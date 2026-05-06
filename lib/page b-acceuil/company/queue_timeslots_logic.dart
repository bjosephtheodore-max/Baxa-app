part of 'settings_page.dart';

extension _QueueTimeSlotsLogic on _QueueTimeSlotsPageState {
  // ── Petits helpers ──────────────────────────────────────────────
  TimeOfDay _parseTimeOfDay(String time) {
    if (time == '24:00') return const TimeOfDay(hour: 0, minute: 0);
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // ── Supprime les créneaux vides au-delà d'un horizon ───────────
  // Utilisé quand maxAdvanceDays diminue — les réservations existantes
  // au-delà de l'horizon sont conservées (changement de politique, pas de fermeture).
  Future<void> _deleteEmptyFutureSlotsForTimeSlotBeyondHorizon(
    String timeSlotId,
    int maxAdvanceDays,
  ) async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final horizon = today.add(const Duration(days: 8));
    final slotsRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots');

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await slotsRef
          .where('start', isGreaterThanOrEqualTo: horizon)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: horizon)
            .get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['timeSlotId'] != timeSlotId) continue;
      if ((data['reserved'] as int? ?? 0) > 0) continue;

      batch.delete(doc.reference);
      batchCount++;

      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();
  }

  // ── Supprime les créneaux vides futurs d'une plage ──────────────
  Future<void> _deleteEmptyFutureSlotsForTimeSlot(String timeSlotId) async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final slotsRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots');

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await slotsRef
          .where('start', isGreaterThanOrEqualTo: today)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: today)
            .get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['timeSlotId'] != timeSlotId) continue;
      if ((data['reserved'] as int? ?? 0) > 0) continue;

      batch.delete(doc.reference);
      batchCount++;

      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();
  }

  // ── Annule les créneaux conflictuels et notifie les clients ─────
  Future<void> _cancelReservedSlotsAndNotify(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> conflictingSlots,
  ) async {
    for (final slotDoc in conflictingSlots) {
      final slotData = slotDoc.data();
      final slotStart = (slotData['start'] as Timestamp).toDate().toLocal();
      final formattedDate =
          '${slotStart.day.toString().padLeft(2, '0')}/${slotStart.month.toString().padLeft(2, '0')}/${slotStart.year}';
      final formattedTime =
          '${slotStart.hour.toString().padLeft(2, '0')}h${slotStart.minute.toString().padLeft(2, '0')}';

      final reservationsSnap = await _firestore
          .collection('reservations')
          .where('slotId', isEqualTo: slotDoc.id)
          .where('status', isEqualTo: 'confirmed')
          .get();

      if (reservationsSnap.docs.isEmpty) {
        await slotDoc.reference.delete();
        continue;
      }

      WriteBatch batch = _firestore.batch();
      int batchCount = 0;

      for (final resDoc in reservationsSnap.docs) {
        final resData = resDoc.data();
        final customerId = resData['customerId'] as String?;

        batch.update(resDoc.reference, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancellationSource': 'company_edit',
        });
        batchCount++;

        if (customerId != null) {
          final notifRef = _firestore
              .collection('customers')
              .doc(customerId)
              .collection('notifications')
              .doc();
          batch.set(notifRef, {
            'title': 'Réservation annulée',
            'body':
                'Votre réservation du $formattedDate à $formattedTime chez ${widget.queueName} '
                'a été annulée suite à une modification des horaires.',
            'createdAt': FieldValue.serverTimestamp(),
            'type': 'cancellation_by_company',
            'payload': null,
          });
          batchCount++;
        }

        if (batchCount >= 380) {
          await batch.commit();
          batch = _firestore.batch();
          batchCount = 0;
        }
      }

      batch.delete(slotDoc.reference);
      batchCount++;

      if (batchCount > 0) await batch.commit();
    }
  }

  // ── Génération immédiate des créneaux ────────────────────────────
  // Appelée après chaque création/modification de plage horaire.
  // Génère les créneaux pour aujourd'hui + 7 jours (fixe)
  // sans attendre la Cloud Function de 2h du matin.
  Future<int> _generateSlotsImmediately({
    required String timeSlotId,
    required String startTimeStr,
    required String endTimeStr,
    required int duration,
    required int capacity,
    required List<int> workingDays,
    required int maxAdvanceDays,
    required int maxReservationsPerPerson,
    required int reservationDeadlineMinutes,
  }) async {
    final today = DateTime.now();
    final queuePath = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId);
    final slotsRef = queuePath.collection('slots');
    final dailyStatsRef = queuePath.collection('dailyStats');

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    int created = 0;
    final processedDays = <DateTime>[];

    final startParts = startTimeStr.split(':');
    final endParts = endTimeStr.split(':');

    for (int i = 0; i <= 7; i++) {
      final date = DateTime(today.year, today.month, today.day)
          .add(Duration(days: i));

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
          : DateTime(date.year, date.month, date.day, int.parse(endParts[0]), int.parse(endParts[1]));

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
            'maxReservationsPerPerson': maxReservationsPerPerson,
            'reservationDeadlineMinutes': reservationDeadlineMinutes,
          });
          batchCount++;
          created++;

          if (batchCount >= 400) {
            await batch.commit();
            batch = _firestore.batch();
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

  // ── Mise à jour des paramètres sur les créneaux existants ────────
  // Met à jour capacité, durée, limites sur les créneaux futurs ouverts.
  Future<int> _updateSlotParameters({
    required String timeSlotId,
    required int capacity,
    required int duration,
    required int maxReservationsPerPerson,
    required int reservationDeadlineMinutes,
    required int maxAdvanceDays,
  }) async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final maxDate = today.add(const Duration(days: 8));

    final slotsRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots');

    // Requête sur un seul champ range — pas d'index composite requis.
    // Filtre timeSlotId et status en mémoire.
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await slotsRef
          .where('start', isGreaterThanOrEqualTo: today)
          .where('start', isLessThan: maxDate)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: today)
            .where('start', isLessThan: maxDate)
            .get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    int updated = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['timeSlotId'] != timeSlotId) continue;
      if (data['status'] != 'open') continue;

      // Ne jamais réduire la capacité sous les réservations existantes
      final reserved = data['reserved'] as int? ?? 0;
      final safeCapacity = capacity < reserved ? reserved : capacity;

      batch.update(doc.reference, {
        'capacity': safeCapacity,
        'duration': duration,
        'maxReservationsPerPerson': maxReservationsPerPerson,
        'reservationDeadlineMinutes': reservationDeadlineMinutes,
      });
      batchCount++;
      updated++;

      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) await batch.commit();
    return updated;
  }

  // ── Suppression d'une plage horaire ─────────────────────────────
  Future<void> _deleteSlot(String slotId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette plage ?'),
        content: const Text(
          'Les créneaux futurs associés seront supprimés automatiquement par la Cloud Function.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final queuePath = _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('queues')
          .doc(widget.queueId);

      // 1. Supprimer le doc timeSlot
      await queuePath.collection('timeSlots').doc(slotId).delete();

      // 2. Supprimer tous les slots générés liés à cette plage par lots de 400
      const batchLimit = 400;
      QuerySnapshot snap;
      do {
        snap = await queuePath
            .collection('slots')
            .where('timeSlotId', isEqualTo: slotId)
            .limit(batchLimit)
            .get();
        if (snap.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (snap.docs.length == batchLimit);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plage et créneaux associés supprimés')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }
}
