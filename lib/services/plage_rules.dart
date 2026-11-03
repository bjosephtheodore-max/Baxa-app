import 'package:cloud_firestore/cloud_firestore.dart';

// ════════════════════════════════════════════════════════════════════
// Règles partagées autour des plages horaires (timeSlots) et de leurs
// créneaux. Fonctions pures : aucune lecture Firestore, testables seules.
// ════════════════════════════════════════════════════════════════════

/// « HH:mm » → minutes depuis minuit (« 24:00 » → 1440). Une heure absente
/// ou illisible renvoie null.
int? plageTimeToMinutes(String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Trie des plages par heure de début (ordre horaire de la journée).
/// Une plage sans heure de début lisible est rangée en fin de liste (jamais
/// retirée). À égalité, l'ordre d'origine est conservé.
List<T> sortedByPlageStart<T>(
  Iterable<T> items,
  String? Function(T item) startTimeOf,
) {
  final indexed = items.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final ma = plageTimeToMinutes(startTimeOf(a.value));
    final mb = plageTimeToMinutes(startTimeOf(b.value));
    if (ma == null && mb == null) return a.key.compareTo(b.key);
    if (ma == null) return 1;
    if (mb == null) return -1;
    final byTime = ma.compareTo(mb);
    return byTime != 0 ? byTime : a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}

/// Minuit du jour de [d].
DateTime plageDayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Vue minimale d'un créneau, lue depuis un document Firestore.
typedef SlotLite = ({
  String timeSlotId,
  String status,
  DateTime start,
  DateTime end,
  int reserved,
});

/// Convertit les données brutes d'un document créneau. Renvoie null si le
/// document n'a pas d'horaires exploitables.
SlotLite? slotLiteFromData(Map<String, dynamic> d) {
  final s = d['start'];
  final e = d['end'];
  final start = s is Timestamp ? s.toDate() : (s is DateTime ? s : null);
  final end = e is Timestamp ? e.toDate() : (e is DateTime ? e : null);
  if (start == null || end == null) return null;
  return (
    timeSlotId: d['timeSlotId'] as String? ?? '',
    status: d['status'] as String? ?? 'open',
    start: start,
    end: end,
    reserved: (d['reserved'] as num?)?.toInt() ?? 0,
  );
}

/// Un créneau bloqué compte comme « blocage en cours » tant qu'il n'est
/// pas terminé.
bool isActiveBlockedSlot(SlotLite s, DateTime now) =>
    s.status == 'blocked' && s.end.isAfter(now);

/// Jours (à minuit) où la plage [timeSlotId] a encore au moins un créneau
/// bloqué à venir. Ces jours-là, la plage ne reçoit AUCUNE modification
/// (suppression, génération, capacité, durée) : la structure gère un
/// incident, le jour reste tel qu'elle l'a laissé.
Set<DateTime> activeBlockedDays(
  Iterable<SlotLite> slots,
  String timeSlotId,
  DateTime now,
) {
  return {
    for (final s in slots)
      if (s.timeSlotId == timeSlotId && isActiveBlockedSlot(s, now))
        plageDayOf(s.start),
  };
}

/// Espaces libres de [rangeStart, rangeEnd[ une fois retirés les intervalles
/// [occupied] (créneaux conservés). Seuls les intervalles qui touchent la
/// plage comptent ; ils peuvent se recouvrir ou être dans le désordre.
List<({DateTime start, DateTime end})> freeIntervals(
  Iterable<({DateTime start, DateTime end})> occupied,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final busy =
      occupied
          .where((o) => o.start.isBefore(rangeEnd) && o.end.isAfter(rangeStart))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  final spans = <({DateTime start, DateTime end})>[];
  var cursor = rangeStart;
  for (final o in busy) {
    if (cursor.isBefore(o.start)) spans.add((start: cursor, end: o.start));
    if (o.end.isAfter(cursor)) cursor = o.end;
  }
  if (cursor.isBefore(rangeEnd)) spans.add((start: cursor, end: rangeEnd));
  return spans;
}

/// Valeur la plus fréquente de [values] ; à égalité, la plus grande
/// (choix stable). Null si la liste est vide.
int? mostFrequent(Iterable<int> values) {
  final counts = <int, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  int? best;
  var bestCount = 0;
  counts.forEach((v, c) {
    if (c > bestCount || (c == bestCount && best != null && v > best!)) {
      best = v;
      bestCount = c;
    }
  });
  return best;
}
