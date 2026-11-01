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

  // Fermeture PROGRAMMÉE : un créneau qui tombe dans la période est refusé
  // même si la file est encore ouverte aujourd'hui (miroir de booking.js).
  group('Créneau dans une fermeture', () {
    final start = DateTime(2026, 10, 25);
    final end = DateTime(2026, 10, 27, 23, 59, 59); // veille de réouverture

    test('aucune fermeture → créneau autorisé', () {
      expect(isSlotInClosure(null, null, DateTime(2026, 10, 26, 9)), isFalse);
    });

    test('créneau avant le début → autorisé', () {
      expect(isSlotInClosure(start, end, DateTime(2026, 10, 24, 15)), isFalse);
    });

    test('créneau dans la période → refusé', () {
      expect(isSlotInClosure(start, end, DateTime(2026, 10, 25)), isTrue);
      expect(isSlotInClosure(start, end, DateTime(2026, 10, 27, 18)), isTrue);
    });

    test('jour de réouverture → autorisé', () {
      expect(isSlotInClosure(start, end, DateTime(2026, 10, 28, 8)), isFalse);
    });

    test('fermeture sans fin → tout créneau après le début est refusé', () {
      expect(isSlotInClosure(start, null, DateTime(2027, 3, 1, 8)), isTrue);
    });
  });

  // Une seule fermeture par file : tant qu'elle en porte une (en cours ou à
  // venir), on ne peut pas lui en planifier une autre.
  group('File déjà prise par une fermeture', () {
    test('aucune fermeture → libre', () {
      expect(hasClosureScheduled(null, null, now: now), isFalse);
    });

    test('fermeture à venir → prise', () {
      final start = now.add(const Duration(days: 5));
      final end = now.add(const Duration(days: 8));
      expect(hasClosureScheduled(start, end, now: now), isTrue);
    });

    test('« Stopper les réservations » (sans fin) → prise', () {
      expect(hasClosureScheduled(now, null, now: now), isTrue);
    });

    test('fermeture en cours → prise', () {
      final start = now.subtract(const Duration(days: 1));
      final end = now.add(const Duration(days: 1));
      expect(hasClosureScheduled(start, end, now: now), isTrue);
    });

    test('fermeture terminée → libre à nouveau', () {
      final start = now.subtract(const Duration(days: 3));
      final end = now.subtract(const Duration(seconds: 1));
      expect(hasClosureScheduled(start, end, now: now), isFalse);
    });
  });
}
