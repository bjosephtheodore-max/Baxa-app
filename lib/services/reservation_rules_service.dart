import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'booking_constants.dart';

/// ============================================================
/// RÉSULTAT D'UNE VÉRIFICATION DE RÈGLE
/// ============================================================
class RuleCheckResult {
  final bool canReserve;
  final RuleViolation? violation;
  final DocumentSnapshot? conflictingReservation;

  /// Autres réservations actives du client dans CETTE file (plages
  /// différentes) — renseigné uniquement quand la résa est autorisée grâce
  /// au réglage « plusieurs réservations par jour » de la file, pour que
  /// l'écran de confirmation puisse prévenir le client. Vide sinon.
  final List<QueryDocumentSnapshot> otherActiveInQueue;

  const RuleCheckResult.allowed({this.otherActiveInQueue = const []})
    : canReserve = true,
      violation = null,
      conflictingReservation = null;

  const RuleCheckResult.blocked(this.violation, {this.conflictingReservation})
    : canReserve = false,
      otherActiveInQueue = const [];
}

/// Types de violations possibles
enum RuleViolation {
  /// Limite de 5 réservations créées aujourd'hui atteinte (recharge à minuit)
  globalLimitReached,

  /// Créneau actif dans cette file → proposer remplacement
  activeInSameQueue,

  /// Cooldown 5 min non écoulé après fin de créneau dans cette file
  cooldownNotElapsed,

  /// Chevauchement horaire avec une réservation dans cette entreprise
  overlapInSameCompany,

  /// Gap 30 min non respecté entre deux entreprises différentes
  gapDifferentCompany,

  /// Créneau déjà commencé ou passé
  slotAlreadyStarted,

  /// Créneau au-delà de l'anticipation maximale configurée par l'entreprise
  tooFarInAdvance,
}

/// ============================================================
/// SERVICE PRINCIPAL
/// ============================================================
class ReservationRulesService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // ── Helpers ──────────────────────────────────────────────────

  bool _isExpired(Map<String, dynamic> resData) {
    final end = (resData['slotEnd'] as Timestamp).toDate();
    final cooldownEnd = end.add(Duration(minutes: kCooldownSameQueueMinutes));
    return DateTime.now().isAfter(cooldownEnd);
  }

  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Concatène prénom + nom depuis un document `users/{uid}`.
  /// Retourne null si aucun des deux n'est renseigné.
  String? _fullName(Map<String, dynamic> userData) {
    final prenom = (userData['prenom'] as String?)?.trim() ?? '';
    final nom = (userData['nom'] as String?)?.trim() ?? '';
    final full = [prenom, nom].where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty ? null : full;
  }

  // ── Quota journalier (pré-vérification) ──────────────────────

  Future<int> _getDailyBookingCount(String userId) async {
    final doc = await _fs.collection('users').doc(userId).get();
    if (!doc.exists) return 0;
    final data = doc.data()!;
    final lastDate = data['lastBookingDate'] as String? ?? '';
    if (lastDate != _todayStr()) return 0;
    return (data['dailyBookingCount'] as int?) ?? 0;
  }

  // ── Réservations futures actives (pour règles 2-4) ───────────

  Future<List<QueryDocumentSnapshot>> _getUserActiveReservations(
    String userId,
  ) async {
    final snap = await _fs
        .collectionGroup('reservations')
        .where('customerId', isEqualTo: userId)
        .where('status', isEqualTo: 'confirmed')
        .get();

    final now = DateTime.now();
    return snap.docs.where((doc) {
      final data = doc.data();
      final end = (data['slotEnd'] as Timestamp).toDate();
      return end.isAfter(now);
    }).toList();
  }

  // ── Plages couvertes par des résa actives (pour le retour auto) ──

  /// Nombre de plages DISTINCTES de [queueId] (chez [companyId]) où le
  /// client connecté a actuellement une réservation active. Utilisé après
  /// une réservation/un remplacement pour savoir si, sur une file où le
  /// réglage « plusieurs réservations par jour » est activé, le client a
  /// désormais couvert toutes les plages — auquel cas on le ramène à
  /// l'écran précédent, sinon on le laisse réserver les plages restantes.
  Future<int> countDistinctActivePlages({
    required String companyId,
    required String queueId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final active = await _getUserActiveReservations(user.uid);
    final plages = <String>{};
    for (final doc in active) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['companyId'] != companyId || data['queueId'] != queueId) {
        continue;
      }
      final tsId = data['timeSlotId'] as String?;
      if (tsId != null) plages.add(tsId);
    }
    return plages.length;
  }

  // ── VÉRIFICATION PRINCIPALE ───────────────────────────────────

  Future<RuleCheckResult> checkCanReserve({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required DateTime slotStart,
    required DateTime slotEnd,
    int maxAdvanceDays = 365,
    // Réglage de la file : quand true, un client peut avoir une résa active
    // par plage (timeSlotId) au lieu d'une seule pour toute la file.
    bool allowMultiplePerPlage = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const RuleCheckResult.allowed();

    // ── Règle 0a : créneau déjà commencé ─────────────────────
    if (slotStart.isBefore(DateTime.now())) {
      return const RuleCheckResult.blocked(RuleViolation.slotAlreadyStarted);
    }

    // ── Règle 0b : anticipation maximale ─────────────────────
    final today = DateTime.now();
    final maxDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: maxAdvanceDays + 1));
    if (slotStart.isAfter(maxDate)) {
      return const RuleCheckResult.blocked(RuleViolation.tooFarInAdvance);
    }

    // ── Règle 1 : quota journalier (5 réservations créées aujourd'hui max) ──
    final dailyCount = await _getDailyBookingCount(user.uid);
    if (dailyCount >= kMaxDailyReservations) {
      return const RuleCheckResult.blocked(RuleViolation.globalLimitReached);
    }

    // ── Charger les réservations futures actives (règles 2-4) ────
    final allActive = await _getUserActiveReservations(user.uid);

    final sameCompany = allActive
        .where((d) => (d.data() as Map)['companyId'] == companyId)
        .toList();
    final otherCompanies = allActive
        .where((d) => (d.data() as Map)['companyId'] != companyId)
        .toList();

    // ── Règle 2 : gap 30 min entre entreprises différentes ────
    for (final res in otherCompanies) {
      final data = res.data() as Map<String, dynamic>;
      final resEnd = (data['slotEnd'] as Timestamp).toDate();
      final resStart = (data['slotStart'] as Timestamp).toDate();

      final gapAfter = slotStart.difference(resEnd).inMinutes;
      final gapBefore = resStart.difference(slotEnd).inMinutes;

      if (gapAfter < kMinGapDifferentCompanyMinutes &&
          gapBefore < kMinGapDifferentCompanyMinutes) {
        return RuleCheckResult.blocked(
          RuleViolation.gapDifferentCompany,
          conflictingReservation: res,
        );
      }
    }

    // ── Règle 4 : même entreprise, files différentes ──────────
    // Vérifiée AVANT la règle 3 : sinon, un conflit « même file » (qui
    // propose un remplacement) court-circuitait la fonction et empêchait
    // de jamais détecter qu'un remplacement pouvait entrer en collision
    // avec une résa active dans une AUTRE file de la même entreprise (bug
    // constaté : deux résa au même horaire dans deux files différentes,
    // obtenues via un remplacement).
    // Le client peut réserver dans plusieurs files de l'entreprise, du
    // moment que les créneaux ne se chevauchent pas (+ 5 min d'écart).
    // Le nombre total est déjà plafonné par la règle 1
    // (kMaxDailyReservations par jour, toutes entreprises confondues).
    final sameCompanyOtherQueues = sameCompany
        .where((d) => (d.data() as Map)['queueId'] != queueId)
        .toList();

    for (final res in sameCompanyOtherQueues) {
      final data = res.data() as Map<String, dynamic>;
      final resStart = (data['slotStart'] as Timestamp).toDate();
      final resEnd = (data['slotEnd'] as Timestamp).toDate();

      if (_overlaps(slotStart, slotEnd, resStart, resEnd)) {
        return RuleCheckResult.blocked(
          RuleViolation.overlapInSameCompany,
          conflictingReservation: res,
        );
      }

      final gapAfter = slotStart.difference(resEnd).inMinutes;
      final gapBefore = resStart.difference(slotEnd).inMinutes;
      if (gapAfter < kMinGapSameCompanyMinutes &&
          gapBefore < kMinGapSameCompanyMinutes) {
        return RuleCheckResult.blocked(
          RuleViolation.overlapInSameCompany,
          conflictingReservation: res,
        );
      }
    }

    // ── Règle 3 : même file ───────────────────────────────────
    final sameQueue = sameCompany
        .where((d) => (d.data() as Map)['queueId'] == queueId)
        .toList();

    if (sameQueue.isNotEmpty) {
      // Sans le réglage « plusieurs réservations par jour » de la file :
      // une seule résa active pour toute la file, peu importe la plage —
      // comportement historique. Avec le réglage : une résa par plage,
      // donc le conflit ne porte que sur LA MÊME plage (même timeSlotId).
      final blocking = allowMultiplePerPlage
          ? sameQueue
                .where((d) => (d.data() as Map)['timeSlotId'] == timeSlotId)
                .toList()
          : sameQueue;

      if (blocking.isNotEmpty) {
        final res = blocking.first;
        final data = res.data() as Map<String, dynamic>;

        if (!_isExpired(data)) {
          return RuleCheckResult.blocked(
            RuleViolation.activeInSameQueue,
            conflictingReservation: res,
          );
        }
        return RuleCheckResult.blocked(
          RuleViolation.cooldownNotElapsed,
          conflictingReservation: res,
        );
      }
      // Réglage activé, plage différente : autorisé, mais on remonte les
      // autres résa actives de cette file pour que l'écran de confirmation
      // prévienne le client (il ne le devine pas tout seul).
    }

    // `sameQueue` n'arrive ici non vide que si le réglage est activé et
    // qu'aucune de ces résa n'est sur la même plage (sinon on aurait déjà
    // renvoyé un blocage plus haut) — donc toujours sûr à remonter tel quel.
    return RuleCheckResult.allowed(otherActiveInQueue: sameQueue);
  }

  // ── MESSAGE UI ────────────────────────────────────────────────

  static String violationMessage(
    RuleViolation violation, {
    Map<String, dynamic>? conflictData,
  }) {
    switch (violation) {
      case RuleViolation.globalLimitReached:
        return 'Vous avez atteint votre limite de $kMaxDailyReservations réservations pour aujourd\'hui. Revenez demain pour réserver à nouveau.';

      case RuleViolation.activeInSameQueue:
        return '';

      case RuleViolation.cooldownNotElapsed:
        if (conflictData != null) {
          final end = (conflictData['slotEnd'] as Timestamp).toDate();
          final available = end.add(
            Duration(minutes: kCooldownSameQueueMinutes),
          );
          final h = available.hour.toString().padLeft(2, '0');
          final m = available.minute.toString().padLeft(2, '0');
          return 'Vous pourrez réserver à nouveau dans cette file à partir de $h:$m.';
        }
        return 'Veuillez attendre la fin de votre créneau actuel avant de réserver à nouveau.';

      case RuleViolation.overlapInSameCompany:
        return 'Vous avez déjà un rendez-vous prévu à cet horaire.';

      case RuleViolation.gapDifferentCompany:
        return 'Un délai de $kMinGapDifferentCompanyMinutes minutes est requis entre deux établissements. Choisissez un autre créneau.';

      case RuleViolation.slotAlreadyStarted:
        return 'Ce créneau a déjà commencé et ne peut plus être réservé.';

      case RuleViolation.tooFarInAdvance:
        return 'Ce créneau dépasse le délai de réservation autorisé par cet établissement.';
    }
  }

  // ── TRANSACTION : RÉSERVER ────────────────────────────────────

  Future<String> reserveSlot({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required String slotDocId,
    required DateTime slotStart,
    required DateTime slotEnd,
    String? companyName,
    String? queueName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    final queueRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .doc(queueId);

    final slotRef = queueRef.collection('slots').doc(slotDocId);

    final reservationRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('reservations')
        .doc();

    final dateStr =
        '${slotStart.year}-'
        '${slotStart.month.toString().padLeft(2, '0')}-'
        '${slotStart.day.toString().padLeft(2, '0')}';
    final dailyStatsRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .doc(queueId)
        .collection('dailyStats')
        .doc(dateStr);

    final userRef = _fs.collection('users').doc(user.uid);
    final timeSlotRef = queueRef.collection('timeSlots').doc(timeSlotId);

    await _fs.runTransaction((tx) async {
      // Reads d'abord (obligation Firestore)
      final freshSlot = await tx.get(slotRef);
      final freshUser = await tx.get(userRef);
      final freshQueue = await tx.get(queueRef);
      final freshTimeSlot = await tx.get(timeSlotRef);

      if (!freshSlot.exists) throw Exception('Créneau introuvable');

      // File fermée par l'entreprise (fermeture planifiée ou immédiate) :
      // aucune nouvelle réservation possible, même depuis une page déjà
      // ouverte ou un client de mauvaise foi.
      final qd = freshQueue.data();
      if (isQueueClosedNow(
        (qd?['closureStart'] as Timestamp?)?.toDate(),
        (qd?['closureEnd'] as Timestamp?)?.toDate(),
      )) {
        throw Exception(
          'Les réservations pour cette file sont fermées pour le moment.',
        );
      }

      // Plage en cours de suppression programmée : plus aucune nouvelle
      // réservation, y compris sur un créneau déjà partiellement rempli.
      if (freshTimeSlot.data()?['deleteAfter'] != null) {
        throw Exception(
          'Cette plage horaire n\'accepte plus de nouvelles réservations.',
        );
      }

      final freshData = freshSlot.data()!;
      final capacity = (freshData['capacity'] ?? 1) as int;
      final reserved = (freshData['reserved'] ?? 0) as int;
      final status = (freshData['status'] ?? 'open') as String;
      final start = (freshData['start'] as Timestamp).toDate().toUtc();

      if (status != 'open') {
        throw Exception('Ce créneau n\'est plus disponible');
      }
      if (reserved >= capacity) throw Exception('Ce créneau est complet');
      if (start.difference(DateTime.now().toUtc()).inMinutes < 1) {
        throw Exception('Ce créneau a déjà commencé');
      }

      // Filet serveur : l'anticipation max et le délai min de la file ne sont
      // que des filtres d'affichage côté client. On les fait respecter ici
      // aussi, pour qu'une liste périmée / une course / un client modifié ne
      // puisse pas réserver hors de la fenêtre voulue. Ne touche ni la
      // génération des créneaux ni ce que voit l'entreprise.
      final maxAdvanceDays = (qd?['maxAdvanceDays'] as num?)?.toInt();
      if (maxAdvanceDays != null) {
        // Même borne que le pré-check (Règle 0b) : autorisé jusqu'à la fin
        // du jour « aujourd'hui + maxAdvanceDays ».
        final n = DateTime.now();
        final lastDay = DateTime(n.year, n.month, n.day)
            .add(Duration(days: maxAdvanceDays + 1));
        if (start.toLocal().isAfter(lastDay)) {
          throw Exception(
            'Ce créneau est trop loin dans le temps pour être réservé.',
          );
        }
      }
      final deadlineMin =
          (freshData['reservationDeadlineMinutes'] as num?)?.toInt() ?? 0;
      if (deadlineMin > 0 &&
          start.difference(DateTime.now().toUtc()).inMinutes < deadlineMin) {
        throw Exception('Il est trop tard pour réserver ce créneau.');
      }

      // Double vérification atomique du quota journalier
      final userData = freshUser.data() ?? {};
      final today = _todayStr();
      final lastDate = userData['lastBookingDate'] as String? ?? '';
      final dailyCount = lastDate == today
          ? (userData['dailyBookingCount'] as int? ?? 0)
          : 0;
      if (dailyCount >= kMaxDailyReservations) {
        throw Exception(
          'Limite de $kMaxDailyReservations réservations atteinte pour aujourd\'hui',
        );
      }

      final customerName = _fullName(userData);

      // Writes
      tx.set(reservationRef, {
        'companyId': companyId,
        'queueId': queueId,
        'timeSlotId': timeSlotId,
        'slotId': slotDocId,
        'customerId': user.uid,
        'customerEmail': user.email,
        if (customerName != null) 'customerName': customerName,
        'slotStart': Timestamp.fromDate(slotStart.toUtc()),
        'slotEnd': Timestamp.fromDate(slotEnd.toUtc()),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'confirmed',
        if (companyName != null && companyName.isNotEmpty)
          'companyName': companyName,
        if (queueName != null && queueName.isNotEmpty) 'queueName': queueName,
      });

      tx.update(slotRef, {'reserved': FieldValue.increment(1)});

      tx.set(dailyStatsRef, {
        'reserved': FieldValue.increment(1),
        'available': FieldValue.increment(-1),
      }, SetOptions(merge: true));

      // Incrémenter le quota journalier (les annulations ne restituent pas)
      tx.set(userRef, {
        'lastBookingDate': today,
        'dailyBookingCount': lastDate == today ? FieldValue.increment(1) : 1,
      }, SetOptions(merge: true));
    });

    return reservationRef.id;
  }

  // ── TRANSACTION : REMPLACER ───────────────────────────────────

  /// Annule l'ancienne réservation et crée la nouvelle — atomique.
  Future<String> replaceReservation({
    required String oldReservationId,
    required String oldCompanyId,
    required String oldSlotDocId,
    required String oldQueueId,
    required String newCompanyId,
    required String newQueueId,
    required String newTimeSlotId,
    required String newSlotDocId,
    required DateTime newSlotStart,
    required DateTime newSlotEnd,
    String? companyName,
    String? queueName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    // Filet de sécurité : remplacer un créneau par lui-même n'a aucun sens
    // (annulerait puis recréerait la même réservation à l'identique).
    if (oldCompanyId == newCompanyId &&
        oldQueueId == newQueueId &&
        oldSlotDocId == newSlotDocId) {
      throw Exception('Vous avez déjà réservé ce créneau.');
    }

    final oldResRef = _fs
        .collection('companies')
        .doc(oldCompanyId)
        .collection('reservations')
        .doc(oldReservationId);

    final oldSlotRef = _fs
        .collection('companies')
        .doc(oldCompanyId)
        .collection('queues')
        .doc(oldQueueId)
        .collection('slots')
        .doc(oldSlotDocId);

    final newQueueRef = _fs
        .collection('companies')
        .doc(newCompanyId)
        .collection('queues')
        .doc(newQueueId);

    final newSlotRef = newQueueRef.collection('slots').doc(newSlotDocId);

    final newResRef = _fs
        .collection('companies')
        .doc(newCompanyId)
        .collection('reservations')
        .doc();

    final oldDateStr =
        '${newSlotStart.year}-'
        '${newSlotStart.month.toString().padLeft(2, '0')}-'
        '${newSlotStart.day.toString().padLeft(2, '0')}';
    // oldSlot date — lire depuis oldSlotDocId n'est pas disponible ici,
    // on suppose que le remplacement reste sur le même jour (cas standard)
    final newDateStr =
        '${newSlotStart.year}-'
        '${newSlotStart.month.toString().padLeft(2, '0')}-'
        '${newSlotStart.day.toString().padLeft(2, '0')}';
    final oldDailyStatsRef = _fs
        .collection('companies')
        .doc(oldCompanyId)
        .collection('queues')
        .doc(oldQueueId)
        .collection('dailyStats')
        .doc(oldDateStr);
    final newDailyStatsRef = _fs
        .collection('companies')
        .doc(newCompanyId)
        .collection('queues')
        .doc(newQueueId)
        .collection('dailyStats')
        .doc(newDateStr);

    final userRef = _fs.collection('users').doc(user.uid);

    await _fs.runTransaction((tx) async {
      // Reads d'abord (obligation Firestore)
      final freshNewSlot = await tx.get(newSlotRef);
      final freshUser = await tx.get(userRef);
      final freshNewQueue = await tx.get(newQueueRef);
      if (!freshNewSlot.exists) throw Exception('Nouveau créneau introuvable');

      final nq = freshNewQueue.data();
      if (isQueueClosedNow(
        (nq?['closureStart'] as Timestamp?)?.toDate(),
        (nq?['closureEnd'] as Timestamp?)?.toDate(),
      )) {
        throw Exception(
          'Les réservations pour cette file sont fermées pour le moment.',
        );
      }

      // Plage en cours de suppression programmée : plus de réservation.
      final newTsId = freshNewSlot.data()?['timeSlotId'] as String?;
      if (newTsId != null && newTsId.isNotEmpty) {
        final freshNewTs = await tx.get(
          newQueueRef.collection('timeSlots').doc(newTsId),
        );
        if (freshNewTs.data()?['deleteAfter'] != null) {
          throw Exception(
            'Cette plage horaire n\'accepte plus de nouvelles réservations.',
          );
        }
      }

      final newData = freshNewSlot.data()!;
      final capacity = (newData['capacity'] ?? 1) as int;
      final reserved = (newData['reserved'] ?? 0) as int;
      final newStatus = (newData['status'] ?? 'open') as String;
      if (newStatus != 'open') {
        throw Exception('Ce créneau n\'est plus disponible');
      }
      if (reserved >= capacity) {
        throw Exception('Ce créneau est maintenant complet');
      }

      // Filet serveur — mêmes garde-fous que reserveSlot : l'anticipation max
      // et le délai min de la file sont aussi vérifiés ici (ce ne sont que des
      // filtres d'affichage côté client), pour qu'un remplacement ne vise pas
      // un créneau hors de la fenêtre voulue.
      final newStart = (newData['start'] as Timestamp).toDate();
      final maxAdvanceDays = (nq?['maxAdvanceDays'] as num?)?.toInt();
      if (maxAdvanceDays != null) {
        final n = DateTime.now();
        final lastDay = DateTime(n.year, n.month, n.day)
            .add(Duration(days: maxAdvanceDays + 1));
        if (newStart.toLocal().isAfter(lastDay)) {
          throw Exception(
            'Ce créneau est trop loin dans le temps pour être réservé.',
          );
        }
      }
      final deadlineMin =
          (newData['reservationDeadlineMinutes'] as num?)?.toInt() ?? 0;
      if (deadlineMin > 0 &&
          newStart.toUtc().difference(DateTime.now().toUtc()).inMinutes <
              deadlineMin) {
        throw Exception('Il est trop tard pour réserver ce créneau.');
      }

      final customerName = _fullName(freshUser.data() ?? {});

      // Annuler l'ancienne réservation
      tx.update(oldResRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      tx.update(oldSlotRef, {'reserved': FieldValue.increment(-1)});
      tx.set(oldDailyStatsRef, {
        'reserved': FieldValue.increment(-1),
        'available': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // Créer la nouvelle
      tx.set(newResRef, {
        'companyId': newCompanyId,
        'queueId': newQueueId,
        'timeSlotId': newTimeSlotId,
        'slotId': newSlotDocId,
        'customerId': user.uid,
        'customerEmail': user.email,
        if (customerName != null) 'customerName': customerName,
        'slotStart': Timestamp.fromDate(newSlotStart.toUtc()),
        'slotEnd': Timestamp.fromDate(newSlotEnd.toUtc()),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'confirmed',
        'replacedReservationId': oldReservationId,
        if (companyName != null && companyName.isNotEmpty)
          'companyName': companyName,
        if (queueName != null && queueName.isNotEmpty) 'queueName': queueName,
      });
      tx.update(newSlotRef, {'reserved': FieldValue.increment(1)});
      tx.set(newDailyStatsRef, {
        'reserved': FieldValue.increment(1),
        'available': FieldValue.increment(-1),
      }, SetOptions(merge: true));
    });

    return newResRef.id;
  }

  // ── ANNULATION ────────────────────────────────────────────────

  Future<void> cancelReservation({
    required String companyId,
    required String reservationId,
    required String queueId,
    required String slotDocId,
    required DateTime slotStart,
  }) async {
    final resRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('reservations')
        .doc(reservationId);

    final slotRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .doc(slotDocId);

    final dateStr =
        '${slotStart.year}-'
        '${slotStart.month.toString().padLeft(2, '0')}-'
        '${slotStart.day.toString().padLeft(2, '0')}';
    final dailyStatsRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .doc(queueId)
        .collection('dailyStats')
        .doc(dateStr);

    await _fs.runTransaction((tx) async {
      tx.update(resRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      tx.update(slotRef, {
        'reserved': FieldValue.increment(-1),
        'cancelled': FieldValue.increment(1),
      });
      tx.set(dailyStatsRef, {
        'reserved': FieldValue.increment(-1),
        'available': FieldValue.increment(1),
        'cancelled': FieldValue.increment(1),
      }, SetOptions(merge: true));
    });
  }
}
