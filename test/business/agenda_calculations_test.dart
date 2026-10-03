// Calculs de l'agenda entreprise (lib/services/agenda_service.dart) :
// indicateurs d'une file, espaces libres pour recréer des créneaux, arrondi
// de l'heure au multiple de 5 minutes.
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/services/agenda_service.dart';

AgendaSlot slot(
  int startHour,
  int startMin, {
  int duration = 30,
  int capacity = 2,
  int reserved = 0,
  String status = 'open',
}) {
  final start = DateTime(2026, 9, 26, startHour, startMin);
  return AgendaSlot(
    id: 's$startHour$startMin',
    queueId: 'q1',
    start: start,
    end: start.add(Duration(minutes: duration)),
    capacity: capacity,
    reserved: reserved,
    cancelled: 0,
    status: status,
    duration: duration,
  );
}

DateTime at(int h, int m) => DateTime(2026, 9, 26, h, m);

void main() {
  final agenda = AgendaService();

  group('Indicateurs d\'une file (computeStats)', () {
    test('aucun créneau → tout à zéro', () {
      final s = agenda.computeStats([]);
      expect(s.placesRestantes, 0);
      expect(s.placesReservees, 0);
      expect(s.personnesEnAttente, 0);
    });

    test('places restantes et réservées sur les créneaux ouverts', () {
      final s = agenda.computeStats([
        slot(9, 0, capacity: 3, reserved: 1),
        slot(9, 30, capacity: 3, reserved: 3),
      ], now: at(8, 0));
      expect(s.placesRestantes, 2);
      expect(s.placesReservees, 4);
      expect(s.totalCreneaux, 2);
      expect(s.estBloquee, isFalse);
    });

    test('les personnes en attente excluent les créneaux passés', () {
      final s = agenda.computeStats([
        slot(9, 0, reserved: 2), // terminé à 9h30
        slot(11, 0, reserved: 1),
      ], now: at(10, 0));
      expect(s.personnesEnAttente, 1);
    });

    test('un créneau bloqué ne compte pas dans les places restantes', () {
      final s = agenda.computeStats([
        slot(9, 0, capacity: 2),
        slot(9, 30, capacity: 5, status: 'blocked'),
      ], now: at(8, 0));
      expect(s.placesRestantes, 2);
      expect(s.totalCreneaux, 1);
    });

    test('un client réservé sur un créneau bloqué reste « en attente »', () {
      final s = agenda.computeStats([
        slot(9, 0, reserved: 1, status: 'blocked'),
      ], now: at(8, 0));
      expect(s.personnesEnAttente, 1);
    });

    test('tous les créneaux bloqués → file bloquée, 0 place', () {
      final s = agenda.computeStats([
        slot(9, 0, reserved: 1, status: 'blocked'),
        slot(9, 30, status: 'blocked'),
      ], now: at(8, 0));
      expect(s.estBloquee, isTrue);
      expect(s.placesRestantes, 0);
      expect(s.placesReservees, 0);
    });

    test('un créneau en surréservation ne rend pas les places négatives', () {
      final s = agenda.computeStats([
        slot(9, 0, capacity: 2, reserved: 3),
        slot(9, 30, capacity: 2),
      ], now: at(8, 0));
      expect(s.placesRestantes, 2);
    });
  });

  group('Espaces libres pour recréer des créneaux (freeSpans)', () {
    test('aucune réservation → toute la plage est libre', () {
      final spans = agenda.freeSpans([slot(9, 0)], at(9, 0), at(12, 0));
      expect(spans, [(start: at(9, 0), end: at(12, 0))]);
    });

    test('une réservation au milieu coupe la plage en deux', () {
      final spans = agenda.freeSpans(
        [slot(10, 0, reserved: 1)],
        at(9, 0),
        at(12, 0),
      );
      expect(spans, [
        (start: at(9, 0), end: at(10, 0)),
        (start: at(10, 30), end: at(12, 0)),
      ]);
    });

    test('réservations collées → pas d\'espace vide entre elles', () {
      final spans = agenda.freeSpans(
        [slot(9, 30, reserved: 1), slot(9, 0, reserved: 1)],
        at(9, 0),
        at(10, 0),
      );
      expect(spans, isEmpty);
    });

    test('les créneaux vides existants sont ignorés', () {
      final spans = agenda.freeSpans(
        [slot(9, 0), slot(9, 30)],
        at(9, 0),
        at(10, 0),
      );
      expect(spans, [(start: at(9, 0), end: at(10, 0))]);
    });

    test('une réservation hors de la plage n\'élargit pas la plage', () {
      final spans = agenda.freeSpans(
        [slot(14, 0, reserved: 1)],
        at(9, 0),
        at(12, 0),
      );
      expect(spans, [(start: at(9, 0), end: at(12, 0))]);
    });

    test('une réservation qui déborde de la plage la coupe sans l\'élargir',
        () {
      // Réservé 11h45-12h15 sur une plage 9h-12h.
      final spans = agenda.freeSpans(
        [slot(11, 45, reserved: 1)],
        at(9, 0),
        at(12, 0),
      );
      expect(spans, [(start: at(9, 0), end: at(11, 45))]);
    });
  });

  group('Arrondi au multiple de 5 minutes', () {
    test('déjà sur un multiple → inchangé', () {
      expect(agenda.roundUpToNext5Minutes(at(10, 5)), at(10, 5));
    });

    test('arrondi vers l\'avant', () {
      expect(agenda.roundUpToNext5Minutes(at(10, 7)), at(10, 10));
    });

    test('des secondes suffisent à passer au multiple suivant', () {
      final t = DateTime(2026, 9, 26, 10, 5, 30);
      expect(agenda.roundUpToNext5Minutes(t), at(10, 10));
    });

    test('passage à l\'heure suivante', () {
      expect(agenda.roundUpToNext5Minutes(at(12, 58)), at(13, 0));
    });

    test('passage au jour suivant', () {
      expect(
        agenda.roundUpToNext5Minutes(DateTime(2026, 9, 26, 23, 57)),
        DateTime(2026, 9, 27, 0, 0),
      );
    });
  });
}
