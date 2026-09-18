import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_performance/firebase_performance.dart';

// ════════════════════════════════════════════════════════════════════
// Génération immédiate des créneaux — côté app, sans attendre la Cloud
// Function de nuit.
//
// Utilisée :
//  • à la création / modification d'une plage horaire (settings_page) ;
//  • à la réouverture immédiate d'une file fermée (« Rouvrir
//    immédiatement » / « Revenir sur Baxa »).
//
// Génère les créneaux pour [startFrom] (par défaut aujourd'hui) + 7 jours
// (horizon fixe). La Cloud Function `generateSlots` prolonge l'horizon
// chaque nuit, nettoie les vieux créneaux et recompte les `dailyStats`
// depuis les vrais créneaux (filet de sécurité contre toute dérive).
// ════════════════════════════════════════════════════════════════════

/// Contexte d'appel — détermine la stratégie anti-doublon et le calcul des
/// stats journalières.
enum SlotGenMode {
  /// Nouvelle plage : aucun créneau préexistant.
  /// → dédup lue en cache (instantané), stats ajoutées en incrément dans le
  ///   même paquet atomique que les créneaux.
  create,

  /// Modification d'une plage / réouverture d'une file : des créneaux
  /// peuvent déjà exister (voire venir d'être supprimés juste avant).
  /// → dédup lue au serveur (fiable), stats recalculées depuis les vrais
  ///   créneaux.
  refresh,
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Enveloppe [_generateSlotsImmediatelyImpl] d'une trace Performance
/// Monitoring, pour suivre en conditions réelles la durée de l'opération
/// déjà optimisée manuellement (~5s → quasi-instant).
Future<int> generateSlotsImmediately({
  required FirebaseFirestore firestore,
  required String companyId,
  required String queueId,
  required String timeSlotId,
  required String startTimeStr,
  required String endTimeStr,
  required int duration,
  required int capacity,
  required List<int> workingDays,
  required int reservationDeadlineMinutes,
  DateTime? startFrom,
  SlotGenMode mode = SlotGenMode.refresh,
}) async {
  final trace = FirebasePerformance.instance.newTrace('slot_generation');
  await trace.start();
  trace.putAttribute('mode', mode.name);
  try {
    final created = await _generateSlotsImmediatelyImpl(
      firestore: firestore,
      companyId: companyId,
      queueId: queueId,
      timeSlotId: timeSlotId,
      startTimeStr: startTimeStr,
      endTimeStr: endTimeStr,
      duration: duration,
      capacity: capacity,
      workingDays: workingDays,
      reservationDeadlineMinutes: reservationDeadlineMinutes,
      startFrom: startFrom,
      mode: mode,
    );
    trace.setMetric('slots_created', created);
    return created;
  } finally {
    await trace.stop();
  }
}

Future<int> _generateSlotsImmediatelyImpl({
  required FirebaseFirestore firestore,
  required String companyId,
  required String queueId,
  required String timeSlotId,
  required String startTimeStr,
  required String endTimeStr,
  required int duration,
  required int capacity,
  required List<int> workingDays,
  required int reservationDeadlineMinutes,
  DateTime? startFrom,
  SlotGenMode mode = SlotGenMode.refresh,
}) async {
  final today = startFrom ?? DateTime.now();
  final todayMidnight = DateTime(today.year, today.month, today.day);
  final queuePath = firestore
      .collection('companies')
      .doc(companyId)
      .collection('queues')
      .doc(queueId);
  final slotsRef = queuePath.collection('slots');
  final dailyStatsRef = queuePath.collection('dailyStats');

  final startParts = startTimeStr.split(':');
  final endParts = endTimeStr.split(':');

  // ── 1. Jours ouvrés dans la fenêtre de 7 jours ─────────────────────
  final workDates = <DateTime>[];
  for (int i = 0; i <= 7; i++) {
    final date = todayMidnight.add(Duration(days: i));
    if (workingDays.contains(date.weekday)) workDates.add(date);
  }
  if (workDates.isEmpty) {
    await queuePath.update({
      'slotsLastGenerated': FieldValue.serverTimestamp(),
    });
    return 0;
  }

  // ── 2. Dédup : créneaux déjà présents pour chaque jour, EN PARALLÈLE ─
  //   create  → cache (une plage neuve n'a rien ; le cache suffit et évite
  //             ~6 allers-retours réseau).
  //   refresh → serveur (le cache peut être froid/périmé après une
  //             suppression — c'est ce qui causait des doublons).
  final dedupSource =
      mode == SlotGenMode.create ? Source.cache : Source.serverAndCache;

  final dedupResults = await Future.wait(
    workDates.map((date) async {
      final endOfDay = date.add(const Duration(days: 1));
      try {
        final snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: date)
            .where('start', isLessThan: endOfDay)
            .get(GetOptions(source: dedupSource));
        return MapEntry(
          date,
          snap.docs
              .map((d) => (d.data()['start'] as Timestamp).toDate())
              .toSet(),
        );
      } catch (_) {
        if (mode == SlotGenMode.create) {
          // Cache froid/vide → on considère « rien » : aucun risque de
          // doublon sur une plage qu'on vient de créer.
          return MapEntry(date, <DateTime>{});
        }
        // refresh : on préfère échouer proprement (l'appelant réessaie)
        // que risquer un doublon.
        rethrow;
      }
    }),
  );
  final existingByDate = {for (final e in dedupResults) e.key: e.value};

  // ── 3. Construire les créneaux + accumuler le delta de stats par jour ─
  WriteBatch batch = firestore.batch();
  int batchCount = 0;
  int created = 0;
  final dayDelta = <DateTime, ({int slots, int capacity})>{};

  for (final date in workDates) {
    final existing = existingByDate[date] ?? <DateTime>{};

    final plageStart = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(startParts[0]),
      int.parse(startParts[1]),
    );
    final plageEnd = endTimeStr == '24:00'
        ? DateTime(date.year, date.month, date.day).add(const Duration(days: 1))
        : DateTime(
            date.year,
            date.month,
            date.day,
            int.parse(endParts[0]),
            int.parse(endParts[1]),
          );

    DateTime cursor = plageStart;

    // Aujourd'hui : sauter les créneaux déjà commencés.
    if (date == todayMidnight) {
      final now = DateTime.now();
      while (cursor.isBefore(now) &&
          cursor.add(Duration(minutes: duration)).compareTo(plageEnd) <= 0) {
        cursor = cursor.add(Duration(minutes: duration));
      }
    }

    int daySlots = 0;
    int dayCap = 0;
    while (cursor.add(Duration(minutes: duration)).compareTo(plageEnd) <= 0) {
      final slotEnd = cursor.add(Duration(minutes: duration));
      if (!existing.contains(cursor)) {
        batch.set(slotsRef.doc(), {
          'start': cursor,
          'end': slotEnd,
          'capacity': capacity,
          'reserved': 0,
          'cancelled': 0,
          'status': 'open',
          'duration': duration,
          'isLegacy': false,
          'timeSlotId': timeSlotId,
          'reservationDeadlineMinutes': reservationDeadlineMinutes,
        });
        batchCount++;
        created++;
        daySlots++;
        dayCap += capacity;
        if (batchCount >= 400) {
          await batch.commit();
          batch = firestore.batch();
          batchCount = 0;
        }
      }
      cursor = slotEnd;
    }
    if (daySlots > 0) {
      dayDelta[date] = (slots: daySlots, capacity: dayCap);
    }
  }

  // ── 4. Stats journalières ─────────────────────────────────────────
  if (mode == SlotGenMode.create) {
    // Incrément atomique : on ajoute EXACTEMENT ce qu'on vient de créer,
    // dans le même paquet que les créneaux. Tout-ou-rien : si ça rate, rien
    // n'est écrit et l'appelant réessaie.
    dayDelta.forEach((date, d) {
      final dateStr = _ymd(date);
      batch.set(dailyStatsRef.doc(dateStr), {
        'date': dateStr,
        'totalSlots': FieldValue.increment(d.slots),
        'totalCapacity': FieldValue.increment(d.capacity),
        'available': FieldValue.increment(d.capacity),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batchCount++;
    });
    batch.update(queuePath, {
      'slotsLastGenerated': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  } else {
    // refresh : des créneaux ont pu être supprimés juste avant → un incrément
    // serait faux. On recompte chaque jour depuis les vrais créneaux, EN
    // PARALLÈLE, puis un seul paquet. Non-critique : rattrapé par la CF de
    // nuit si ça échoue.
    if (batchCount > 0) await batch.commit();
    await queuePath.update({
      'slotsLastGenerated': FieldValue.serverTimestamp(),
    });

    try {
      final statSnaps = await Future.wait(
        workDates.map((date) async {
          final endOfDay = date.add(const Duration(days: 1));
          final snap = await slotsRef
              .where('start', isGreaterThanOrEqualTo: date)
              .where('start', isLessThan: endOfDay)
              .get();
          return MapEntry(date, snap.docs);
        }),
      );

      final statBatch = firestore.batch();
      var wrote = false;
      for (final e in statSnaps) {
        int totalSlots = 0;
        int totalCapacity = 0;
        int reserved = 0;
        int cancelled = 0;
        for (final doc in e.value) {
          final d = doc.data();
          totalSlots++;
          totalCapacity += (d['capacity'] as int? ?? 0);
          reserved += (d['reserved'] as int? ?? 0);
          cancelled += (d['cancelled'] as int? ?? 0);
        }
        if (totalSlots == 0) continue;
        final dateStr = _ymd(e.key);
        statBatch.set(dailyStatsRef.doc(dateStr), {
          'date': dateStr,
          'totalSlots': totalSlots,
          'totalCapacity': totalCapacity,
          'available': totalCapacity - reserved,
          'reserved': reserved,
          'cancelled': cancelled,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        wrote = true;
      }
      if (wrote) await statBatch.commit();
    } catch (_) {
      // dailyStats non-critiques — les créneaux sont créés ; la CF de nuit
      // recompte tout.
    }
  }

  return created;
}

// ────────────────────────────────────────────────────────────────────
// Régénère les créneaux de TOUTES les plages d'une file — appelée quand
// une file fermée est rouverte immédiatement. Les plages dont la
// suppression est programmée (`deleteAfter`) sont ignorées.
// ────────────────────────────────────────────────────────────────────
Future<int> regenerateSlotsForQueue({
  required FirebaseFirestore firestore,
  required String companyId,
  required String queueId,
}) async {
  final queueRef = firestore
      .collection('companies')
      .doc(companyId)
      .collection('queues')
      .doc(queueId);

  final queueDoc = await queueRef.get();
  final queueData = queueDoc.data() ?? {};
  final List<int> defaultDays = queueData['weekdays'] != null
      ? List<int>.from(queueData['weekdays'] as List)
      : queueData['defaultWorkingDays'] != null
      ? List<int>.from(queueData['defaultWorkingDays'] as List)
      : const [1, 2, 3, 4, 5];

  final timeSlotsSnap = await queueRef.collection('timeSlots').get();

  int total = 0;
  for (final ts in timeSlotsSnap.docs) {
    final data = ts.data();
    if (data['deleteAfter'] != null) continue; // suppression programmée

    total += await generateSlotsImmediately(
      firestore: firestore,
      companyId: companyId,
      queueId: queueId,
      timeSlotId: ts.id,
      startTimeStr: data['startTime'] as String? ?? '09:00',
      endTimeStr: data['endTime'] as String? ?? '17:00',
      duration: (data['serviceDurationMinutes'] as num?)?.toInt() ?? 15,
      capacity: (data['capacityPerSlot'] as num?)?.toInt() ?? 1,
      workingDays: data['workingDays'] != null
          ? List<int>.from(data['workingDays'] as List)
          : defaultDays,
      reservationDeadlineMinutes:
          (data['reservationDeadlineMinutes'] as num?)?.toInt() ?? 0,
      mode: SlotGenMode.refresh,
    );
  }
  return total;
}
