import 'package:cloud_firestore/cloud_firestore.dart';

// ════════════════════════════════════════════════════════════════════
// Génération immédiate des créneaux — côté app, sans attendre la Cloud
// Function de nuit.
//
// Utilisée :
//  • à la création / modification d'une plage horaire (settings_page) ;
//  • à la réouverture immédiate d'une file fermée (bouton « Rouvrir
//    immédiatement » de company_settings_page / settings_page).
//
// Génère les créneaux pour [startFrom] (par défaut aujourd'hui) + 7 jours
// (horizon fixe). La Cloud Function `generateSlots` prend le relais chaque
// nuit pour prolonger l'horizon et nettoyer les vieux créneaux.
// ════════════════════════════════════════════════════════════════════

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
}) async {
  final today = startFrom ?? DateTime.now();
  final queuePath = firestore
      .collection('companies')
      .doc(companyId)
      .collection('queues')
      .doc(queueId);
  final slotsRef = queuePath.collection('slots');
  final dailyStatsRef = queuePath.collection('dailyStats');

  WriteBatch batch = firestore.batch();
  int batchCount = 0;
  int created = 0;
  final processedDays = <DateTime>[];

  final startParts = startTimeStr.split(':');
  final endParts = endTimeStr.split(':');

  for (int i = 0; i <= 7; i++) {
    final date = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: i));

    if (!workingDays.contains(date.weekday)) continue;
    processedDays.add(date);

    // Récupérer les starts existants (éviter doublons).
    // Fallback sur cache si réseau indisponible.
    final startOfDay = date;
    final endOfDay = date.add(const Duration(days: 1));
    Set<DateTime> existingStarts = {};
    try {
      final existingSnap = await slotsRef
          .where('start', isGreaterThanOrEqualTo: startOfDay)
          .where('start', isLessThan: endOfDay)
          .get(const GetOptions(source: Source.cache));
      existingStarts = existingSnap.docs
          .map((d) => d.data()['start'] as Timestamp)
          .map((ts) => ts.toDate())
          .toSet();
    } catch (_) {
      // Cache vide ou inaccessible → génère tout (sans dédup)
    }

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

    // Aujourd'hui : sauter les créneaux déjà commencés
    if (i == 0) {
      final now = DateTime.now();
      while (cursor.isBefore(now) &&
          cursor.add(Duration(minutes: duration)).compareTo(plageEnd) <= 0) {
        cursor = cursor.add(Duration(minutes: duration));
      }
    }

    while (cursor.add(Duration(minutes: duration)).compareTo(plageEnd) <= 0) {
      final slotEnd = cursor.add(Duration(minutes: duration));

      if (!existingStarts.contains(cursor)) {
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

        if (batchCount >= 400) {
          await batch.commit();
          batch = firestore.batch();
          batchCount = 0;
        }
      }

      cursor = slotEnd;
    }
  }

  if (batchCount > 0) await batch.commit();

  // Toujours déclencher le refresh de HousePage — même si tous les créneaux
  // existaient déjà (dedup cache), house_page doit se rafraîchir.
  await queuePath.update({'slotsLastGenerated': FieldValue.serverTimestamp()});

  // Écrire dailyStats — non-critique, erreurs réseau ignorées.
  // Lire depuis le cache local (inclut les pending writes du batch ci-dessus).
  try {
    for (final date in processedDays) {
      final startOfDay = date;
      final endOfDay = date.add(const Duration(days: 1));
      final snap = await slotsRef
          .where('start', isGreaterThanOrEqualTo: startOfDay)
          .where('start', isLessThan: endOfDay)
          .get(const GetOptions(source: Source.cache));

      if (snap.docs.isEmpty) continue;

      int totalSlots = 0;
      int totalCapacity = 0;
      int reserved = 0;
      int cancelled = 0;

      for (final doc in snap.docs) {
        final d = doc.data();
        totalSlots++;
        totalCapacity += (d['capacity'] as int? ?? 0);
        reserved += (d['reserved'] as int? ?? 0);
        cancelled += (d['cancelled'] as int? ?? 0);
      }

      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await dailyStatsRef.doc(dateStr).set({
        'date': dateStr,
        'totalSlots': totalSlots,
        'totalCapacity': totalCapacity,
        'available': totalCapacity - reserved,
        'reserved': reserved,
        'cancelled': cancelled,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  } catch (_) {
    // dailyStats non-critiques — les créneaux ont bien été créés
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
          (data['reservationDeadlineMinutes'] as num?)?.toInt() ?? 5,
    );
  }
  return total;
}
