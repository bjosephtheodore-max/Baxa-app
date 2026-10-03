// Règles de réservation côté client (lib/services/reservation_rules_service.dart)
// testées sur une base Firestore SIMULÉE en mémoire (fake_cloud_firestore) :
// aucune donnée réelle n'est touchée.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/reservation_rules_service.dart';

const client = 'cust1';

String ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  late FakeFirebaseFirestore db;
  late ReservationRulesService rules;

  // Demain à 10h : un créneau futur de référence, loin de « maintenant ».
  final now = DateTime.now();
  final tomorrow10 = DateTime(now.year, now.month, now.day + 1, 10);

  setUp(() {
    db = FakeFirebaseFirestore();
    rules = ReservationRulesService(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: client),
      ),
    );
  });

  /// Réservation existante du client.
  Future<void> reservation({
    required DateTime start,
    int minutes = 30,
    String company = 'compA',
    String queue = 'q1',
    String plage = 't1',
    String status = 'confirmed',
  }) {
    return db.collection('companies').doc(company).collection('reservations')
        .add({
          'customerId': client,
          'status': status,
          'companyId': company,
          'queueId': queue,
          'timeSlotId': plage,
          'slotStart': Timestamp.fromDate(start),
          'slotEnd': Timestamp.fromDate(start.add(Duration(minutes: minutes))),
        });
  }

  /// Tentative de réservation d'un créneau de 30 min.
  Future<RuleCheckResult> check(
    DateTime start, {
    String company = 'compA',
    String queue = 'q1',
    String plage = 't1',
    int maxAdvanceDays = 365,
    bool allowMultiplePerPlage = false,
  }) {
    return rules.checkCanReserve(
      companyId: company,
      queueId: queue,
      timeSlotId: plage,
      slotStart: start,
      slotEnd: start.add(const Duration(minutes: 30)),
      maxAdvanceDays: maxAdvanceDays,
      allowMultiplePerPlage: allowMultiplePerPlage,
    );
  }

  void expectAllowed(RuleCheckResult r) =>
      expect(r.canReserve, isTrue, reason: 'bloqué par ${r.violation}');
  void expectBlocked(RuleCheckResult r, RuleViolation v) {
    expect(r.canReserve, isFalse);
    expect(r.violation, v);
  }

  group('Cas de base', () {
    test('aucune réservation existante → autorisé', () async {
      expectAllowed(await check(tomorrow10));
    });

    test('créneau déjà commencé → refusé', () async {
      expectBlocked(
        await check(now.subtract(const Duration(minutes: 5))),
        RuleViolation.slotAlreadyStarted,
      );
    });
  });

  group('Anticipation maximale (réglage de l\'entreprise)', () {
    final today = DateTime(now.year, now.month, now.day);

    test('dernier jour autorisé, en fin de journée → autorisé', () async {
      final lastDay = today.add(const Duration(days: 3, hours: 22));
      expectAllowed(await check(lastDay, maxAdvanceDays: 3));
    });

    test('le lendemain du dernier jour → refusé', () async {
      final tooFar = today.add(const Duration(days: 4, minutes: 30));
      expectBlocked(
        await check(tooFar, maxAdvanceDays: 3),
        RuleViolation.tooFarInAdvance,
      );
    });
  });

  group('Limite de $kMaxDailyReservations réservations par jour', () {
    Future<void> quota(int count, String date) => db
        .collection('users')
        .doc(client)
        .set({'dailyBookingCount': count, 'lastBookingDate': date});

    test('limite atteinte aujourd\'hui → refusé', () async {
      await quota(kMaxDailyReservations, ymd(now));
      expectBlocked(
        await check(tomorrow10),
        RuleViolation.globalLimitReached,
      );
    });

    test('une réservation sous la limite → autorisé', () async {
      await quota(kMaxDailyReservations - 1, ymd(now));
      expectAllowed(await check(tomorrow10));
    });

    test('le compteur repart à zéro le lendemain', () async {
      final yesterday = now.subtract(const Duration(days: 1));
      await quota(kMaxDailyReservations, ymd(yesterday));
      expectAllowed(await check(tomorrow10));
    });
  });

  group('Écart de $kMinGapDifferentCompanyMinutes min entre deux entreprises', () {
    test('20 min après un RDV ailleurs → refusé', () async {
      await reservation(start: tomorrow10, company: 'compB');
      expectBlocked(
        await check(tomorrow10.add(const Duration(minutes: 50))),
        RuleViolation.gapDifferentCompany,
      );
    });

    test('30 min après un RDV ailleurs → autorisé', () async {
      await reservation(start: tomorrow10, company: 'compB');
      expectAllowed(await check(tomorrow10.add(const Duration(minutes: 60))));
    });

    test('se terminant 20 min avant un RDV ailleurs → refusé', () async {
      await reservation(start: tomorrow10, company: 'compB');
      expectBlocked(
        await check(tomorrow10.subtract(const Duration(minutes: 50))),
        RuleViolation.gapDifferentCompany,
      );
    });

    test('même horaire qu\'un RDV ailleurs → refusé', () async {
      await reservation(start: tomorrow10, company: 'compB');
      expectBlocked(
        await check(tomorrow10),
        RuleViolation.gapDifferentCompany,
      );
    });
  });

  group('Même entreprise, autre file', () {
    test('horaires qui se chevauchent → refusé', () async {
      await reservation(start: tomorrow10, queue: 'q2');
      expectBlocked(
        await check(tomorrow10.add(const Duration(minutes: 15))),
        RuleViolation.overlapInSameCompany,
      );
    });

    test('moins de $kMinGapSameCompanyMinutes min d\'écart → refusé', () async {
      await reservation(start: tomorrow10, queue: 'q2');
      expectBlocked(
        await check(tomorrow10.add(const Duration(minutes: 33))),
        RuleViolation.overlapInSameCompany,
      );
    });

    test('$kMinGapSameCompanyMinutes min d\'écart → autorisé', () async {
      await reservation(start: tomorrow10, queue: 'q2');
      expectAllowed(await check(tomorrow10.add(const Duration(minutes: 35))));
    });
  });

  group('Même file', () {
    test('une réservation active dans la file → refusé (remplacement '
        'proposé)', () async {
      await reservation(start: tomorrow10);
      final r = await check(tomorrow10.add(const Duration(hours: 3)));
      expectBlocked(r, RuleViolation.activeInSameQueue);
      expect(r.conflictingReservation, isNotNull);
    });

    test('une réservation annulée ne bloque pas', () async {
      await reservation(start: tomorrow10, status: 'cancelled');
      expectAllowed(await check(tomorrow10.add(const Duration(hours: 3))));
    });

    test('une réservation passée (hier) ne bloque pas', () async {
      await reservation(start: tomorrow10.subtract(const Duration(days: 2)));
      expectAllowed(await check(tomorrow10));
    });

    test('réglage « plusieurs par jour » : autre plage → autorisé, avec '
        'avertissement', () async {
      await reservation(start: tomorrow10, plage: 't1');
      final r = await check(
        tomorrow10.add(const Duration(hours: 4)),
        plage: 't2',
        allowMultiplePerPlage: true,
      );
      expectAllowed(r);
      expect(r.otherActiveInQueue, hasLength(1));
    });

    test('réglage « plusieurs par jour » : même plage → refusé', () async {
      await reservation(start: tomorrow10, plage: 't1');
      expectBlocked(
        await check(
          tomorrow10.add(const Duration(hours: 1)),
          plage: 't1',
          allowMultiplePerPlage: true,
        ),
        RuleViolation.activeInSameQueue,
      );
    });

    test('un créneau terminé à l\'instant ne bloque plus (règle des 5 min '
        'd\'attente supprimée)', () async {
      await reservation(
        start: now.subtract(const Duration(minutes: 32)),
      );
      expectAllowed(await check(tomorrow10));
    });
  });

  group('Messages affichés au client', () {
    test('limite atteinte : le chiffre de la limite apparaît', () {
      expect(
        ReservationRulesService.violationMessage(
          RuleViolation.globalLimitReached,
        ),
        contains('$kMaxDailyReservations réservations'),
      );
    });

    test('écart entre entreprises : la durée requise apparaît', () {
      expect(
        ReservationRulesService.violationMessage(
          RuleViolation.gapDifferentCompany,
        ),
        contains('$kMinGapDifferentCompanyMinutes minutes'),
      );
    });
  });
}
