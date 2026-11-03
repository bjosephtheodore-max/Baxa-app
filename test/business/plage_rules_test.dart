// Règles partagées des plages horaires (lib/services/plage_rules.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/services/plage_rules.dart';

void main() {
  group('Tri des plages par heure de début', () {
    test('ordre horaire, même si créées dans le désordre', () {
      final sorted = sortedByPlageStart(['20:00', '08:00', '15:00'], (s) => s);
      expect(sorted, ['08:00', '15:00', '20:00']);
    });

    test(
      'une plage sans heure lisible va en fin de liste, sans disparaître',
      () {
        final sorted = sortedByPlageStart(<String?>[
          '15:00',
          null,
          '08:00',
          'xx',
        ], (s) => s);
        expect(sorted, ['08:00', '15:00', null, 'xx']);
      },
    );

    test('« 24:00 » et les minutes sont lues correctement', () {
      expect(plageTimeToMinutes('24:00'), 1440);
      expect(plageTimeToMinutes('08:30'), 510);
      expect(plageTimeToMinutes(null), isNull);
    });
  });

  group('Jours bloqués', () {
    final now = DateTime(2026, 11, 2, 14);
    SlotLite slot(
      int day,
      int hour, {
      String ts = 't1',
      String status = 'blocked',
    }) => (
      timeSlotId: ts,
      status: status,
      start: DateTime(2026, 11, day, hour),
      end: DateTime(2026, 11, day, hour, 30),
      reserved: 0,
    );

    test('un créneau bloqué à venir rend le jour bloqué pour sa plage', () {
      expect(activeBlockedDays([slot(2, 15), slot(3, 9)], 't1', now), {
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 3),
      });
    });

    test('un blocage terminé ne compte plus', () {
      expect(activeBlockedDays([slot(2, 9)], 't1', now), isEmpty);
    });

    test('seule la plage concernée est bloquée', () {
      expect(activeBlockedDays([slot(2, 15, ts: 'autre')], 't1', now), isEmpty);
      expect(
        activeBlockedDays([slot(2, 15, status: 'open')], 't1', now),
        isEmpty,
      );
    });
  });

  group('Espaces libres', () {
    DateTime h(int hour, [int min = 0]) => DateTime(2026, 11, 2, hour, min);

    test('sans créneau occupé : la plage entière', () {
      expect(freeIntervals(const [], h(8), h(12)), [(start: h(8), end: h(12))]);
    });

    test('autour des créneaux occupés, même dans le désordre', () {
      final spans = freeIntervals(
        [(start: h(10), end: h(10, 30)), (start: h(8, 10), end: h(8, 20))],
        h(8),
        h(12),
      );
      expect(spans, [
        (start: h(8), end: h(8, 10)),
        (start: h(8, 20), end: h(10)),
        (start: h(10, 30), end: h(12)),
      ]);
    });

    test('un créneau hors plage est ignoré', () {
      expect(freeIntervals([(start: h(13), end: h(14))], h(8), h(12)), [
        (start: h(8), end: h(12)),
      ]);
    });
  });

  group('Valeur la plus fréquente', () {
    test('majorité, égalité → la plus grande, vide → null', () {
      expect(mostFrequent([10, 15, 15]), 15);
      expect(mostFrequent([10, 15]), 15);
      expect(mostFrequent(const []), isNull);
    });
  });
}
