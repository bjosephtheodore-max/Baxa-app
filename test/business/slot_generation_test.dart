// Génération des créneaux d'une plage horaire (lib/services/slot_generation_service.dart)
// testée sur une base Firestore SIMULÉE en mémoire.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/services/slot_generation_service.dart';

void main() {
  late FakeFirebaseFirestore db;

  // Prochain lundi (toujours dans le futur) : la fenêtre générée couvre
  // ce lundi + 7 jours, soit du lundi au lundi suivant inclus.
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day + (8 - now.weekday));

  CollectionReference<Map<String, dynamic>> col(String name) => db
      .collection('companies')
      .doc('compA')
      .collection('queues')
      .doc('q1')
      .collection(name);

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db
        .collection('companies')
        .doc('compA')
        .collection('queues')
        .doc('q1')
        .set({'nom': 'Coiffure'});
  });

  Future<int> generate({
    String start = '09:00',
    String end = '12:00',
    int duration = 30,
    int capacity = 2,
    List<int> days = const [1, 2, 3, 4, 5],
    SlotGenMode mode = SlotGenMode.create,
  }) {
    return generateSlotsCore(
      firestore: db,
      companyId: 'compA',
      queueId: 'q1',
      timeSlotId: 't1',
      startTimeStr: start,
      endTimeStr: end,
      duration: duration,
      capacity: capacity,
      workingDays: days,
      reservationDeadlineMinutes: 10,
      startFrom: monday,
      mode: mode,
    );
  }

  Future<List<DateTime>> slotStarts() async {
    final snap = await col('slots').get();
    return snap.docs
        .map((d) => (d.data()['start'] as Timestamp).toDate())
        .toList()
      ..sort();
  }

  test('la date de départ des tests est bien un lundi futur', () {
    expect(monday.weekday, DateTime.monday);
    expect(monday.isAfter(now), isTrue);
  });

  group('Créneaux créés', () {
    test('9h-12h par 30 min, du lundi au vendredi : 6 créneaux x 6 jours '
        '(lundi suivant inclus)', () async {
      expect(await generate(), 36);
      expect(await slotStarts(), hasLength(36));
    });

    test('les créneaux d\'une journée se suivent sans trou', () async {
      await generate(days: const [1]);
      final mondaySlots = (await slotStarts())
          .where((s) => s.day == monday.day && s.month == monday.month)
          .toList();
      expect(mondaySlots, [
        for (var m = 0; m < 180; m += 30)
          monday.add(Duration(hours: 9, minutes: m)),
      ]);
    });

    test('les jours non ouvrés n\'ont aucun créneau', () async {
      await generate(days: const [6, 7]); // samedi, dimanche
      final days = (await slotStarts()).map((s) => s.weekday).toSet();
      expect(days, {DateTime.saturday, DateTime.sunday});
    });

    test('un créneau qui dépasserait la fin de plage n\'est pas créé', () async {
      // 9h-10h par 25 min : 9h00, 9h25 ; 9h50 finirait à 10h15.
      await generate(end: '10:00', duration: 25, days: const [1]);
      final first = (await slotStarts()).take(3).toList();
      expect(first, [
        monday.add(const Duration(hours: 9)),
        monday.add(const Duration(hours: 9, minutes: 25)),
        monday.add(const Duration(days: 7, hours: 9)),
      ]);
    });

    test('une plage jusqu\'à minuit (24:00) est acceptée', () async {
      await generate(start: '22:00', end: '24:00', duration: 60,
          days: const [1]);
      final starts = await slotStarts();
      expect(starts.first, monday.add(const Duration(hours: 22)));
      expect(starts[1], monday.add(const Duration(hours: 23)));
    });

    test('chaque créneau porte la bonne configuration', () async {
      await generate(capacity: 4, days: const [1]);
      final data = (await col('slots').get()).docs.first.data();
      expect(data['capacity'], 4);
      expect(data['reserved'], 0);
      expect(data['status'], 'open');
      expect(data['timeSlotId'], 't1');
      expect(data['duration'], 30);
    });

    test('aucun jour ouvré → aucun créneau', () async {
      expect(await generate(days: const []), 0);
      expect(await slotStarts(), isEmpty);
    });
  });

  group('Places par jour (dailyStats)', () {
    test('créées avec les créneaux, pour chaque jour ouvré', () async {
      await generate(capacity: 2, days: const [1]);
      final stats = await col('dailyStats').get();
      expect(stats.docs, hasLength(2)); // ce lundi + le suivant
      final d = stats.docs.first.data();
      expect(d['totalSlots'], 6);
      expect(d['totalCapacity'], 12);
      expect(d['available'], 12);
    });
  });

  group('Pas de doublons', () {
    test('relancer la génération ne recrée pas les créneaux existants',
        () async {
      await generate(days: const [1]);
      expect(await generate(days: const [1], mode: SlotGenMode.refresh), 0);
      expect(await slotStarts(), hasLength(12));
    });

    test('après un recalcul, les places par jour restent justes', () async {
      await generate(capacity: 2, days: const [1]);
      await generate(capacity: 2, days: const [1], mode: SlotGenMode.refresh);
      final d = (await col('dailyStats').get()).docs.first.data();
      expect(d['totalSlots'], 6);
      expect(d['available'], 12);
    });
  });
}
