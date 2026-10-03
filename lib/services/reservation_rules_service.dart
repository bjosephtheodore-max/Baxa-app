import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  /// Région de la fonction `booking` : à côté de la base Firestore
  /// (Johannesburg), voir functions/booking.js.
  static const String bookingRegion = 'africa-south1';

  // Injectables pour les tests (base et session simulées) ; l'app utilise
  // toujours les instances Firebase réelles.
  ReservationRulesService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _fs = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _fs;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;

  // Obtenu au premier appel seulement : les vérifications (checkCanReserve)
  // restent ainsi testables sans initialiser Firebase.
  late final FirebaseFunctions _functions =
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: bookingRegion);

  // ── Helpers ──────────────────────────────────────────────────

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
    final user = _auth.currentUser;
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
    final user = _auth.currentUser;
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
        return RuleCheckResult.blocked(
          RuleViolation.activeInSameQueue,
          conflictingReservation: blocking.first,
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

  static String violationMessage(RuleViolation violation) {
    switch (violation) {
      case RuleViolation.globalLimitReached:
        return 'Vous avez atteint votre limite de $kMaxDailyReservations réservations pour aujourd\'hui. Revenez demain pour réserver à nouveau.';

      case RuleViolation.activeInSameQueue:
        return '';

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

  // ── ÉCRITURES : via la Cloud Function `booking` ───────────────
  //
  // Le client ne peut plus écrire lui-même réservations, compteurs ni quota
  // (firestore.rules) : réserver / remplacer / annuler passent par le
  // serveur, qui refait toutes les vérifications puis écrit en une seule
  // transaction. Les règles de checkCanReserve ci-dessus restent ici pour
  // les messages immédiats ; le serveur a le dernier mot.

  /// Réveille la fonction de réservation (page créneaux ouverte) pour que
  /// le premier appui sur « Réserver » ne subisse pas le démarrage à froid.
  /// Sans effet visible ; toute erreur est ignorée.
  void warmUp() {
    unawaited(
      _callBooking({'action': 'warmup'}).then<void>((_) {}, onError: (_) {}),
    );
  }

  Future<Map<String, dynamic>> _callBooking(Map<String, dynamic> data) async {
    try {
      final res = await _functions.httpsCallable('booking').call(data);
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      throw BookingException(
        e.message?.isNotEmpty == true
            ? e.message!
            : 'La réservation n\'a pas pu aboutir. Réessayez.',
        reason: details is Map ? details['reason'] as String? : null,
      );
    } catch (e) {
      if (e is BookingException) rethrow;
      throw const BookingException(
        'Connexion impossible. Vérifiez votre réseau et réessayez.',
      );
    }
  }

  // ── RÉSERVER ──────────────────────────────────────────────────

  Future<String> reserveSlot({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required String slotDocId,
    String? companyName,
    String? queueName,
  }) async {
    if (_auth.currentUser == null) {
      throw const BookingException('Utilisateur non connecté');
    }
    final result = await _callBooking({
      'action': 'reserve',
      'companyId': companyId,
      'queueId': queueId,
      'slotId': slotDocId,
      'timeSlotId': timeSlotId,
      if (companyName != null && companyName.isNotEmpty)
        'companyName': companyName,
      if (queueName != null && queueName.isNotEmpty) 'queueName': queueName,
    });

    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'booking_created',
        parameters: {
          'company_id': companyId,
          'queue_id': queueId,
          'time_slot_id': timeSlotId,
        },
      ),
    );

    return result['reservationId'] as String;
  }

  // ── REMPLACER ─────────────────────────────────────────────────

  /// Annule l'ancienne réservation et crée la nouvelle — atomique, côté
  /// serveur.
  Future<String> replaceReservation({
    required String oldReservationId,
    required String oldCompanyId,
    required String newCompanyId,
    required String newQueueId,
    required String newTimeSlotId,
    required String newSlotDocId,
    String? companyName,
    String? queueName,
  }) async {
    if (_auth.currentUser == null) {
      throw const BookingException('Utilisateur non connecté');
    }
    final result = await _callBooking({
      'action': 'replace',
      'oldCompanyId': oldCompanyId,
      'oldReservationId': oldReservationId,
      'companyId': newCompanyId,
      'queueId': newQueueId,
      'slotId': newSlotDocId,
      'timeSlotId': newTimeSlotId,
      if (companyName != null && companyName.isNotEmpty)
        'companyName': companyName,
      if (queueName != null && queueName.isNotEmpty) 'queueName': queueName,
    });
    return result['reservationId'] as String;
  }

  // ── ANNULER ───────────────────────────────────────────────────

  /// Point UNIQUE d'annulation par le client (accueil, « Mes
  /// réservations », notification). [fromNotification] trace l'origine.
  Future<void> cancelReservation({
    required String companyId,
    required String reservationId,
    bool fromNotification = false,
  }) async {
    await _callBooking({
      'action': 'cancel',
      'companyId': companyId,
      'reservationId': reservationId,
      if (fromNotification) 'source': 'notification',
    });
  }
}

/// Refus ou échec renvoyé par la fonction de réservation. [toString] donne
/// directement le message à afficher (les écrans font `'$e'`).
class BookingException implements Exception {
  final String message;

  /// Motif technique du refus (ex. `slotFull`, `globalLimitReached`).
  final String? reason;

  const BookingException(this.message, {this.reason});

  @override
  String toString() => message;
}
