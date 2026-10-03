// Fermeture d'une file : `isQueueClosedNow` est LE point unique qui décide
// si une file accepte encore des réservations (lib/services/booking_constants.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/services/booking_constants.dart';

void main() {
  final now = DateTime(2026, 9, 26, 10, 0);

  group('Fermeture d\'une file', () {
    test('aucune fermeture → ouverte', () {
      expect(isQueueClosedNow(null, null, now: now), isFalse);
    });

    test('fermeture planifiée plus tard → encore ouverte', () {
      final start = now.add(const Duration(hours: 2));
      expect(isQueueClosedNow(start, null, now: now), isFalse);
    });

    test('fermeture commencée, sans date de fin → fermée', () {
      final start = now.subtract(const Duration(days: 1));
      expect(isQueueClosedNow(start, null, now: now), isTrue);
    });

    test('pendant la période de fermeture → fermée', () {
      final start = now.subtract(const Duration(days: 1));
      final end = now.add(const Duration(days: 1));
      expect(isQueueClosedNow(start, end, now: now), isTrue);
    });

    test('fermeture terminée → rouverte', () {
      final start = now.subtract(const Duration(days: 3));
      final end = now.subtract(const Duration(days: 1));
      expect(isQueueClosedNow(start, end, now: now), isFalse);
    });

    test('pile à l\'heure de début → fermée', () {
      expect(isQueueClosedNow(now, null, now: now), isTrue);
    });

    test('pile à l\'heure de fin → encore fermée', () {
      final start = now.subtract(const Duration(days: 1));
      expect(isQueueClosedNow(start, now, now: now), isTrue);
    });
  });
}
