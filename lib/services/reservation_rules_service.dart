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

  const RuleCheckResult.allowed()
    : canReserve = true,
      violation = null,
      conflictingReservation = null;

  const RuleCheckResult.blocked(this.violation, {this.conflictingReservation})
    : canReserve = false;
}

/// Types de violations possibles
enum RuleViolation {
  /// Max 5 réservations actives atteint sur toute l'app
  globalLimitReached,

  /// Créneau actif dans cette file → proposer remplacement
  activeInSameQueue,

  /// Cooldown 5 min non écoulé après fin de créneau dans cette file
  cooldownNotElapsed,

  /// Max réservations par plage atteint (maxReservationsPerPerson)
  slotRangeLimitReached,

  /// Réservation active dans cette entreprise (maxActivePerUser = 1)
  activeInSameCompany,

  /// Chevauchement horaire avec une réservation dans cette entreprise
  overlapInSameCompany,

  /// Gap 30 min non respecté entre deux entreprises différentes
  gapDifferentCompany,

  /// Créneau déjà commencé ou passé
  slotAlreadyStarted,
}

/// ============================================================
/// SERVICE PRINCIPAL
/// ============================================================
class ReservationRulesService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // ── Helpers ──────────────────────────────────────────────────

  // ignore: unused_element
  bool _isActive(Map<String, dynamic> resData) {
    final end = (resData['slotEnd'] as Timestamp).toDate();
    return end.isAfter(DateTime.now()) && resData['status'] == 'confirmed';
  }

  bool _isExpired(Map<String, dynamic> resData) {
    final end = (resData['slotEnd'] as Timestamp).toDate();
    final cooldownEnd = end.add(Duration(minutes: kCooldownSameQueueMinutes));
    return DateTime.now().isAfter(cooldownEnd);
  }

  /// Vérifie si deux intervalles se chevauchent (avec tolérance de 0 min)
  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  // ── Chargement des réservations actives de l'utilisateur ─────

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
      // ignore: unnecessary_cast
      final data = doc.data() as Map<String, dynamic>;
      final end = (data['slotEnd'] as Timestamp).toDate();
      return end.isAfter(now);
    }).toList();
  }

  // ── VÉRIFICATION PRINCIPALE ───────────────────────────────────

  /// Vérifie toutes les règles avant d'afficher le bouton / lancer la transaction.
  ///
  /// [companyId]   : entreprise du créneau cible
  /// [queueId]     : file du créneau cible
  /// [slotStart]   : début du créneau cible (local)
  /// [slotEnd]     : fin du créneau cible (local)
  /// [timeSlotId]  : id du timeSlot parent (plage horaire)
  /// [maxActivePerUser] : valeur lue depuis queues/{queueId}.maxActivePerUser
  /// [maxReservationsPerPerson] : valeur lue depuis timeSlots/{id}.maxReservationsPerPerson
  Future<RuleCheckResult> checkCanReserve({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required DateTime slotStart,
    required DateTime slotEnd,
    required int maxActivePerUser,
    required int maxReservationsPerPerson,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const RuleCheckResult.allowed();

    // ── Règle 0 : créneau déjà commencé ──────────────────────
    if (slotStart.isBefore(DateTime.now())) {
      return const RuleCheckResult.blocked(RuleViolation.slotAlreadyStarted);
    }

    // ── Charger toutes les réservations actives ───────────────
    final allActive = await _getUserActiveReservations(user.uid);

    // ── Règle 1 : limite globale (5 max toute l'app) ──────────
    if (allActive.length >= kMaxDailyReservations) {
      return const RuleCheckResult.blocked(RuleViolation.globalLimitReached);
    }

    // ── Séparer par entreprise ────────────────────────────────
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

    // ── Règle 3 : même file ───────────────────────────────────
    final sameQueue = sameCompany
        .where((d) => (d.data() as Map)['queueId'] == queueId)
        .toList();

    if (sameQueue.isNotEmpty) {
      final res = sameQueue.first;
      final data = res.data() as Map<String, dynamic>;
      // ignore: unused_local_variable
      final resEnd = (data['slotEnd'] as Timestamp).toDate();

      // Cooldown écoulé ? → peut réserver (après remplacement)
      if (!_isExpired(data)) {
        // Créneau encore actif → proposer remplacement
        return RuleCheckResult.blocked(
          RuleViolation.activeInSameQueue,
          conflictingReservation: res,
        );
      }
      // Cooldown non écoulé
      return RuleCheckResult.blocked(
        RuleViolation.cooldownNotElapsed,
        conflictingReservation: res,
      );
    }

    // ── Règle 4 : même entreprise, files différentes ──────────
    final sameCompanyOtherQueues = sameCompany
        .where((d) => (d.data() as Map)['queueId'] != queueId)
        .toList();

    if (maxActivePerUser == 1) {
      // Défaut : 1 seule résa active dans toute l'entreprise
      if (sameCompanyOtherQueues.isNotEmpty) {
        return RuleCheckResult.blocked(
          RuleViolation.activeInSameCompany,
          conflictingReservation: sameCompanyOtherQueues.first,
        );
      }
    } else {
      // maxActivePerUser > 1 : vérifier les chevauchements
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

        // Gap minimum 5 min entre files même entreprise
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

      // Vérifier que le nombre de résas actives dans cette entreprise
      // ne dépasse pas maxActivePerUser
      if (sameCompanyOtherQueues.length >= maxActivePerUser) {
        return RuleCheckResult.blocked(
          RuleViolation.activeInSameCompany,
          conflictingReservation: sameCompanyOtherQueues.first,
        );
      }
    }

    // ── Règle 5 : max réservations par plage (timeSlot) ───────
    // ⚠️ TODO : activé uniquement si timeSlotId est présent dans les slots.
    // Ajouter 'timeSlotId' dans la Cloud Function qui génère les slots,
    // puis supprimer la condition timeSlotId.isNotEmpty ci-dessous.
    if (timeSlotId.isNotEmpty) {
      final sameTimeSlot = await _fs
          .collection('companies')
          .doc(companyId)
          .collection('reservations')
          .where('customerId', isEqualTo: user.uid)
          .where('timeSlotId', isEqualTo: timeSlotId)
          .where('status', isEqualTo: 'confirmed')
          .get();

      final activeInSlotRange = sameTimeSlot.docs.where((doc) {
        final data = doc.data();
        final end = (data['slotEnd'] as Timestamp).toDate();
        return end.isAfter(DateTime.now());
      }).length;

      if (activeInSlotRange >= maxReservationsPerPerson) {
        return const RuleCheckResult.blocked(
          RuleViolation.slotRangeLimitReached,
        );
      }
    }

    return const RuleCheckResult.allowed();
  }

  // ── MESSAGE UI ────────────────────────────────────────────────

  /// Retourne le message à afficher à l'utilisateur selon la violation
  static String violationMessage(
    RuleViolation violation, {
    Map<String, dynamic>? conflictData,
  }) {
    switch (violation) {
      case RuleViolation.globalLimitReached:
        return 'Vous avez atteint la limite de $kMaxDailyReservations réservations actives. Annulez-en une pour continuer.';

      case RuleViolation.activeInSameQueue:
        return ''; // géré par le dialog de remplacement

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

      case RuleViolation.slotRangeLimitReached:
        return 'Vous avez atteint le nombre maximum de réservations pour cette plage horaire.';

      case RuleViolation.activeInSameCompany:
        return 'Vous avez déjà une réservation active dans cet établissement. Terminez ou annulez-la d\'abord.';

      case RuleViolation.overlapInSameCompany:
        return 'Vous avez déjà un rendez-vous prévu à cet horaire.';

      case RuleViolation.gapDifferentCompany:
        return 'Un délai de $kMinGapDifferentCompanyMinutes minutes est requis entre deux établissements. Choisissez un autre créneau.';

      case RuleViolation.slotAlreadyStarted:
        return 'Ce créneau a déjà commencé et ne peut plus être réservé.';
    }
  }

  // ── TRANSACTION : RÉSERVER ────────────────────────────────────

  /// Réserve un créneau de façon atomique avec toutes les vérifications
  /// en transaction Firestore (double sécurité).
  Future<String> reserveSlot({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required String slotDocId,
    required DateTime slotStart,
    required DateTime slotEnd,
    required int maxActivePerUser,
    required int maxReservationsPerPerson,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    final slotRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .doc(slotDocId);

    final reservationRef = _fs
        .collection('companies')
        .doc(companyId)
        .collection('reservations')
        .doc();

    await _fs.runTransaction((tx) async {
      // Vérification fraîche du slot
      final freshSlot = await tx.get(slotRef);
      if (!freshSlot.exists) throw Exception('Créneau introuvable');

      final freshData = freshSlot.data()!;
      final capacity = (freshData['capacity'] ?? 1) as int;
      final reserved = (freshData['reserved'] ?? 0) as int;
      final status = (freshData['status'] ?? 'open') as String;
      final start = (freshData['start'] as Timestamp).toDate().toUtc();

      if (status != 'open')
        throw Exception('Ce créneau n\'est plus disponible');
      if (reserved >= capacity) throw Exception('Ce créneau est complet');
      if (start.difference(DateTime.now().toUtc()).inMinutes < 1) {
        throw Exception('Ce créneau a déjà commencé');
      }

      tx.set(reservationRef, {
        'companyId': companyId,
        'queueId': queueId,
        'timeSlotId': timeSlotId,
        'slotId': slotDocId,
        'customerId': user.uid,
        'customerEmail': user.email,
        'slotStart': Timestamp.fromDate(slotStart.toUtc()),
        'slotEnd': Timestamp.fromDate(slotEnd.toUtc()),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'confirmed',
      });

      tx.update(slotRef, {'reserved': FieldValue.increment(1)});
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
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

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

    final newSlotRef = _fs
        .collection('companies')
        .doc(newCompanyId)
        .collection('queues')
        .doc(newQueueId)
        .collection('slots')
        .doc(newSlotDocId);

    final newResRef = _fs
        .collection('companies')
        .doc(newCompanyId)
        .collection('reservations')
        .doc();

    await _fs.runTransaction((tx) async {
      final freshNewSlot = await tx.get(newSlotRef);
      if (!freshNewSlot.exists) throw Exception('Nouveau créneau introuvable');

      final newData = freshNewSlot.data()!;
      final capacity = (newData['capacity'] ?? 1) as int;
      final reserved = (newData['reserved'] ?? 0) as int;
      if (reserved >= capacity)
        throw Exception('Ce créneau est maintenant complet');

      // Annuler l'ancienne réservation
      tx.update(oldResRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      tx.update(oldSlotRef, {'reserved': FieldValue.increment(-1)});

      // Créer la nouvelle
      tx.set(newResRef, {
        'companyId': newCompanyId,
        'queueId': newQueueId,
        'timeSlotId': newTimeSlotId,
        'slotId': newSlotDocId,
        'customerId': user.uid,
        'customerEmail': user.email,
        'slotStart': Timestamp.fromDate(newSlotStart.toUtc()),
        'slotEnd': Timestamp.fromDate(newSlotEnd.toUtc()),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'confirmed',
        'replacedReservationId': oldReservationId,
      });
      tx.update(newSlotRef, {'reserved': FieldValue.increment(1)});
    });

    return newResRef.id;
  }

  // ── ANNULATION ────────────────────────────────────────────────

  Future<void> cancelReservation({
    required String companyId,
    required String reservationId,
    required String queueId,
    required String slotDocId,
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

    await _fs.runTransaction((tx) async {
      tx.update(resRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      tx.update(slotRef, {'reserved': FieldValue.increment(-1)});
    });
  }
}
