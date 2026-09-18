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
      snap = await slotsRef.where('start', isGreaterThanOrEqualTo: today).get();
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

  // ── Origine des clients concernés par une annulation à venir ─────
  // Détermine si les réservations en conflit incluent des clients Baxa
  // (seront notifiés automatiquement par la Cloud Function) et/ou des
  // clients ajoutés manuellement par l'entreprise (pas de compte Baxa,
  // donc aucune notification possible) — utilisé pour adapter le texte
  // d'avertissement avant confirmation.
  Future<({bool hasBaxaClients, bool hasManualClients})>
  _analyzeReservationOrigins(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> slots,
  ) async {
    bool hasBaxaClients = false;
    bool hasManualClients = false;
    for (final slotDoc in slots) {
      final reservationsSnap = await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('reservations')
          .where('slotId', isEqualTo: slotDoc.id)
          .where('status', isEqualTo: 'confirmed')
          .get();
      for (final resDoc in reservationsSnap.docs) {
        final customerId = resDoc.data()['customerId'] as String?;
        if (customerId == 'manual_booking') {
          hasManualClients = true;
        } else if (customerId != null) {
          hasBaxaClients = true;
        }
        if (hasBaxaClients && hasManualClients) {
          return (hasBaxaClients: true, hasManualClients: true);
        }
      }
    }
    return (hasBaxaClients: hasBaxaClients, hasManualClients: hasManualClients);
  }

  // ── Annule les créneaux conflictuels ─────────────────────────────
  // Ne fait QUE marquer les réservations "cancelled" (+ cancellationSource)
  // et supprimer les créneaux — jamais d'écriture de notification ici :
  // c'est la Cloud Function `onReservationCancelledByCompany` qui s'en
  // charge côté serveur en réagissant à ce changement de statut (seule
  // façon fiable de garantir que le texte envoyé au client correspond à
  // une réservation qui appartient réellement à cette entreprise).
  Future<void> _cancelReservedSlotsAndNotify(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> conflictingSlots, {
    String cancellationSource = 'company_edit',
  }) async {
    for (final slotDoc in conflictingSlots) {
      final reservationsSnap = await _firestore
          .collection('companies')
          .doc(widget.companyId)
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
        batch.update(resDoc.reference, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancellationSource': cancellationSource,
        });
        batchCount++;

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
  // Délègue au service partagé `generateSlotsImmediately` (voir
  // lib/services/slot_generation_service.dart), aussi utilisé par la
  // réouverture immédiate d'une file fermée.
  // [maxAdvanceDays] est conservé pour la compatibilité des appels mais
  // n'est pas utilisé : l'horizon de génération immédiate est fixe (7 j).
  Future<int> _generateSlotsImmediately({
    required String timeSlotId,
    required String startTimeStr,
    required String endTimeStr,
    required int duration,
    required int capacity,
    required List<int> workingDays,
    required int maxAdvanceDays,
    required int reservationDeadlineMinutes,
    DateTime? startFrom,
    SlotGenMode mode = SlotGenMode.refresh,
  }) {
    return generateSlotsImmediately(
      firestore: _firestore,
      companyId: widget.companyId,
      queueId: widget.queueId,
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
  }

  // ── Texte du choix "Programmer / Appliquer maintenant" ───────────
  String _buildScheduleOrForceMessage({
    required bool hasBaxaClients,
    required bool hasManualClients,
    required String formattedDate,
  }) {
    final String consequence;
    if (hasManualClients && !hasBaxaClients) {
      consequence =
          'Ces réservations seront annulées, et ces clients — '
          'n\'ayant pas de compte Baxa — ne seront pas prévenus : pensez à '
          'les contacter.';
    } else if (hasManualClients && hasBaxaClients) {
      consequence =
          'Ces réservations seront annulées, et certains de ces '
          'clients — n\'ayant pas de compte Baxa — ne seront pas prévenus : '
          'pensez à les contacter.';
    } else {
      consequence = 'Ces réservations seront annulées et vos clients notifiés.';
    }
    return '$consequence Programmez-la plutôt pour éviter tout désagrément : '
        'elle prendra effet le $formattedDate, sans impact sur les '
        'réservations en cours.';
  }

  // ── Texte du choix "Programmer / Supprimer maintenant" ───────────
  // Variante suppression de plage : programmer n'impacte personne (les
  // réservations en cours sont honorées jusqu'au bout), supprimer maintenant
  // annule et notifie.
  String _buildScheduleOrDeleteMessage({
    required bool hasBaxaClients,
    required bool hasManualClients,
    required String formattedDate,
  }) {
    final String nowConsequence;
    if (hasManualClients && !hasBaxaClients) {
      nowConsequence =
          'Supprimer maintenant annule ces réservations ; ces clients n\'ont '
          'pas de compte Baxa et ne seront pas prévenus — pensez à les contacter.';
    } else if (hasManualClients && hasBaxaClients) {
      nowConsequence =
          'Supprimer maintenant annule ces réservations ; certains de ces '
          'clients n\'ont pas de compte Baxa et ne seront pas prévenus — pensez '
          'à les contacter.';
    } else {
      nowConsequence =
          'Supprimer maintenant annule ces réservations et notifie les clients.';
    }
    return 'Programmer la suppression n\'impacte personne : vos clients gardent '
        'leur créneau, la plage sera supprimée le $formattedDate une fois toutes '
        'les réservations en cours honorées. $nowConsequence';
  }

  // ── Date d'effet d'une modification programmée ───────────────────
  // On ne se fie PAS à un nombre de jours d'anticipation (ni l'ancien ni le
  // nouveau) : si l'entreprise réduit l'anticipation dans le même geste, ou
  // si une réservation manuelle a été posée au-delà de l'horizon, ce nombre
  // ne reflète plus la réalité. On part de la réservation réelle la plus
  // lointaine de la plage ([furthestReservedStart], voir
  // _findConflictingReservedSlots), + 1 jour — avec pour plancher
  // aujourd'hui + nouvelle anticipation + 1 jour (cas sans aucune
  // réservation). La date retournée est ainsi toujours postérieure à toute
  // réservation existante, quel que soit l'historique des éditions.
  DateTime _computeScheduledEffectiveDate({
    required int newAnticipationDays,
    required DateTime? furthestReservedStart,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final floor = today.add(Duration(days: newAnticipationDays + 1));
    if (furthestReservedStart == null) return floor;
    final afterLastReservation = DateTime(
      furthestReservedStart.year,
      furthestReservedStart.month,
      furthestReservedStart.day,
    ).add(const Duration(days: 1));
    return afterLastReservation.isAfter(floor) ? afterLastReservation : floor;
  }

  // ── Programme une modification à une date future sans impact ────
  // Ne touche jamais la config actuelle (currentTimeSlotData) : elle reste
  // en vigueur pour tous les créneaux avant [effectiveDate]. La nouvelle
  // config est écrite en "attente" sur le document, et ses créneaux sont
  // générés immédiatement à partir de [effectiveDate] — pas de fenêtre
  // d'attente pendant laquelle une réservation pourrait s'y glisser.
  Future<void> _scheduleTimeSlotChange({
    required String timeSlotId,
    required DateTime effectiveDate,
    required String startTimeStr,
    required String endTimeStr,
    required int duration,
    required int capacity,
    required List<int> workingDays,
    required int maxAdvanceDays,
    required int reservationDeadlineMinutes,
  }) async {
    final slotsRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots');

    // Vérification de sécurité : garanti vide par construction, mais on
    // vérifie avant d'agir plutôt que de le supposer aveuglément (ex. si un
    // client a réservé entre l'ouverture du formulaire et la confirmation).
    final existingSnap = await slotsRef
        .where('start', isGreaterThanOrEqualTo: effectiveDate)
        .get();
    final relevant = existingSnap.docs
        .where((d) => d.data()['timeSlotId'] == timeSlotId)
        .toList();
    final stillReserved = relevant
        .where((d) => (d.data()['reserved'] as int? ?? 0) > 0)
        .toList();

    if (stillReserved.isNotEmpty) {
      await _cancelReservedSlotsAndNotify(
        stillReserved,
        cancellationSource: 'company_edit',
      );
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    for (final doc in relevant) {
      if ((doc.data()['reserved'] as int? ?? 0) > 0) continue; // déjà traité
      batch.delete(doc.reference);
      batchCount++;
      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();

    await _generateSlotsImmediately(
      timeSlotId: timeSlotId,
      startTimeStr: startTimeStr,
      endTimeStr: endTimeStr,
      duration: duration,
      capacity: capacity,
      workingDays: workingDays,
      maxAdvanceDays: maxAdvanceDays,
      reservationDeadlineMinutes: reservationDeadlineMinutes,
      startFrom: effectiveDate,
    );

    await _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('timeSlots')
        .doc(timeSlotId)
        .update({
          'pendingStartTime': startTimeStr,
          'pendingEndTime': endTimeStr,
          'pendingServiceDurationMinutes': duration,
          'pendingCapacityPerSlot': capacity,
          'pendingWorkingDays': workingDays,
          'pendingMaxAdvanceDays': maxAdvanceDays,
          'pendingReservationDeadlineMinutes': reservationDeadlineMinutes,
          'pendingEffectiveDate': Timestamp.fromDate(effectiveDate),
        });
  }

  // ── Annule une modification programmée pas encore appliquée ─────
  // Déclenché automatiquement en tête de sauvegarde dès qu'une plage a une
  // modification en attente — pas de bouton dédié : rouvrir "Modifier" et
  // enregistrer (avec ou sans changement) revient toujours à repartir d'une
  // base propre. Si des clients ont réservé entre-temps sur la période déjà
  // générée par avance, ces réservations sont annulées et notifiées comme
  // n'importe quel autre conflit.
  Future<void> _revertPendingChange(
    String timeSlotId,
    Map<String, dynamic> slotData,
  ) async {
    final pendingEffectiveDate =
        (slotData['pendingEffectiveDate'] as Timestamp?)?.toDate();
    if (pendingEffectiveDate == null) return;

    final slotsRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots');

    final existingSnap = await slotsRef
        .where('start', isGreaterThanOrEqualTo: pendingEffectiveDate)
        .get();
    final relevant = existingSnap.docs
        .where((d) => d.data()['timeSlotId'] == timeSlotId)
        .toList();
    final stillReserved = relevant
        .where((d) => (d.data()['reserved'] as int? ?? 0) > 0)
        .toList();

    if (stillReserved.isNotEmpty) {
      await _cancelReservedSlotsAndNotify(
        stillReserved,
        cancellationSource: 'company_edit',
      );
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    for (final doc in relevant) {
      if ((doc.data()['reserved'] as int? ?? 0) > 0) continue; // déjà traité
      batch.delete(doc.reference);
      batchCount++;
      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();

    // Régénère cette période sous la config ACTUELLE (celle qui était déjà
    // en vigueur avant la modification programmée — pas les champs "en
    // attente" qu'on est justement en train d'annuler).
    await _generateSlotsImmediately(
      timeSlotId: timeSlotId,
      startTimeStr: slotData['startTime'] as String? ?? '09:00',
      endTimeStr: slotData['endTime'] as String? ?? '17:00',
      duration: (slotData['serviceDurationMinutes'] as num?)?.toInt() ?? 15,
      capacity: (slotData['capacityPerSlot'] as num?)?.toInt() ?? 1,
      workingDays: slotData['workingDays'] != null
          ? List<int>.from(slotData['workingDays'] as List)
          : List<int>.from(_queueWeekdays),
      maxAdvanceDays: (slotData['maxAdvanceDays'] as num?)?.toInt() ?? 2,
      reservationDeadlineMinutes:
          (slotData['reservationDeadlineMinutes'] as num?)?.toInt() ?? 0,
      startFrom: pendingEffectiveDate,
    );

    await _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('timeSlots')
        .doc(timeSlotId)
        .update({
          'pendingStartTime': FieldValue.delete(),
          'pendingEndTime': FieldValue.delete(),
          'pendingServiceDurationMinutes': FieldValue.delete(),
          'pendingCapacityPerSlot': FieldValue.delete(),
          'pendingWorkingDays': FieldValue.delete(),
          'pendingMaxAdvanceDays': FieldValue.delete(),
          'pendingReservationDeadlineMinutes': FieldValue.delete(),
          'pendingEffectiveDate': FieldValue.delete(),
        });
  }

  // ── Mise à jour des paramètres sur les créneaux existants ────────
  // Met à jour capacité, durée, limites sur les créneaux futurs ouverts.
  Future<int> _updateSlotParameters({
    required String timeSlotId,
    required int capacity,
    required int duration,
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

  // ── Recalcule dailyStats après suppression de créneaux ──────────
  // Contrairement au dailyStats écrit après génération, celui-ci réécrit
  // AUSSI les jours qui se retrouvent sans aucun créneau (remise à zéro) —
  // sinon le résumé d'une journée vidée resterait figé sur d'anciens
  // chiffres, jamais recalculé (la CF de nuit ne recalcule que les jours
  // qu'elle regénère).
  Future<void> _recomputeDailyStatsForDays(Iterable<DateTime> days) async {
    final queuePath = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId);
    final slotsRef = queuePath.collection('slots');
    final dailyStatsRef = queuePath.collection('dailyStats');

    final processed = <String>{};
    for (final raw in days) {
      final day = DateTime(raw.year, raw.month, raw.day);
      final dateStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      if (!processed.add(dateStr)) continue;

      try {
        final snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: day)
            .where('start', isLessThan: day.add(const Duration(days: 1)))
            .get();

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

        await dailyStatsRef.doc(dateStr).set({
          'date': dateStr,
          'totalSlots': totalSlots,
          'totalCapacity': totalCapacity,
          'available': totalCapacity - reserved,
          'reserved': reserved,
          'cancelled': cancelled,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // dailyStats non-critiques
      }
    }
  }

  List<DateTime> _generationHorizonDays() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [for (int i = 0; i <= 8; i++) today.add(Duration(days: i))];
  }

  // ── Suppression d'une plage horaire ─────────────────────────────
  // - Aucune réservation à venir → confirmation simple, suppression immédiate.
  // - Des réservations à venir → choix : programmer la suppression (aucun
  //   impact, voir _scheduleTimeSlotDeletion) ou supprimer maintenant
  //   (annulation + notification des clients).
  Future<void> _deleteSlot(String slotId, Map<String, dynamic> slotData) async {
    final now = DateTime.now();
    final slotsRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots');

    // 1. Créneaux futurs RÉSERVÉS de cette plage. Query sur un seul champ
    // range (start) + filtre timeSlotId en mémoire (pas d'index composite).
    List<QueryDocumentSnapshot<Map<String, dynamic>>> futureWithReservations;
    try {
      final futureSnap = await slotsRef
          .where('start', isGreaterThan: now)
          .get();
      futureWithReservations = futureSnap.docs
          .where(
            (doc) =>
                doc.data()['timeSlotId'] == slotId &&
                (doc.data()['reserved'] as int? ?? 0) > 0,
          )
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la vérification : $e')),
      );
      return;
    }

    if (!mounted) return;

    // 2. Aucune réservation → confirmation simple → suppression immédiate.
    if (futureWithReservations.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Supprimer cette plage ?'),
          content: const Text(
            'Les créneaux futurs associés seront supprimés définitivement.',
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
      if (confirm == true) {
        await _performImmediateTimeSlotDeletion(slotId);
      }
      return;
    }

    // 3. Des réservations à venir → choix Programmer / Supprimer maintenant.
    final reservationCount = futureWithReservations.fold<int>(
      0,
      (acc, doc) => acc + (doc.data()['reserved'] as int? ?? 0),
    );
    final origins = await _analyzeReservationOrigins(futureWithReservations);
    if (!mounted) return;

    // Date d'effet = dernier créneau réservé + 1 jour, garantie postérieure
    // à toute réservation en cours (même logique que
    // _computeScheduledEffectiveDate côté modification).
    DateTime furthest =
        (futureWithReservations.first.data()['start'] as Timestamp).toDate();
    for (final doc in futureWithReservations) {
      final s = (doc.data()['start'] as Timestamp).toDate();
      if (s.isAfter(furthest)) furthest = s;
    }
    final effectiveDate = DateTime(
      furthest.year,
      furthest.month,
      furthest.day,
    ).add(const Duration(days: 1));
    final formattedDate = DateFormat(
      'EEE d MMM',
      'fr_FR',
    ).format(effectiveDate);

    final choice = await _showScheduleOrForceSheet(
      reservationCount: reservationCount,
      hasBaxaClients: origins.hasBaxaClients,
      hasManualClients: origins.hasManualClients,
      formattedDate: formattedDate,
      isDeletion: true,
    );

    if (choice == _ConflictChoice.cancel) return;
    if (choice == _ConflictChoice.scheduleLater) {
      await _scheduleTimeSlotDeletion(slotId, slotData, effectiveDate);
      return;
    }
    // _ConflictChoice.forceNow
    await _performImmediateTimeSlotDeletion(
      slotId,
      reservedSlots: futureWithReservations,
    );
  }

  // ── Suppression immédiate et complète d'une plage ──────────────
  Future<void> _performImmediateTimeSlotDeletion(
    String slotId, {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reservedSlots = const [],
  }) async {
    final queuePath = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId);
    final slotsRef = queuePath.collection('slots');

    try {
      // 1. Annuler + notifier les réservations impactées (la Cloud Function
      // onReservationCancelledByCompany se charge du texte envoyé au client).
      if (reservedSlots.isNotEmpty) {
        await _cancelReservedSlotsAndNotify(
          reservedSlots,
          cancellationSource: 'company_delete_timeslot',
        );
      }

      // 2. Supprimer le doc timeSlot.
      await queuePath.collection('timeSlots').doc(slotId).delete();

      // 3. Supprimer les créneaux restants par lots de 400.
      const batchLimit = 400;
      QuerySnapshot snap;
      do {
        snap = await slotsRef
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

      // 4. Recalcul dailyStats des jours impactés + refresh HousePage.
      await _recomputeDailyStatsForDays(_generationHorizonDays());
      await queuePath.update({
        'slotsLastGenerated': FieldValue.serverTimestamp(),
      });

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

  // ── Programme la suppression d'une plage sans impacter les clients ──
  // Dès maintenant : plus aucune nouvelle réservation possible (tous les
  // créneaux vides futurs sont retirés). Les réservations en cours sont
  // honorées. La Cloud Function de nuit supprimera définitivement la plage
  // une fois [effectiveDate] atteinte. Aucune notification : personne n'est
  // impacté. Le champ `deleteAfter` sert de verrou (UI + générateurs) et de
  // déclencheur pour la Cloud Function.
  Future<void> _scheduleTimeSlotDeletion(
    String timeSlotId,
    Map<String, dynamic> slotData,
    DateTime effectiveDate,
  ) async {
    final queuePath = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId);

    try {
      // 0. Une modification programmée traîne encore sur cette plage : on
      // repart d'une base propre avant de programmer la suppression.
      if (slotData['pendingEffectiveDate'] != null) {
        await _revertPendingChange(timeSlotId, slotData);
      }

      // 1. Retirer tous les créneaux vides futurs.
      await _deleteEmptyFutureSlotsForTimeSlot(timeSlotId);

      // 2. Poser le marqueur de sursis.
      await queuePath.collection('timeSlots').doc(timeSlotId).update({
        'deleteAfter': Timestamp.fromDate(effectiveDate),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Recalcul dailyStats + refresh HousePage.
      await _recomputeDailyStatsForDays(_generationHorizonDays());
      await queuePath.update({
        'slotsLastGenerated': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      final f = DateFormat('EEE d MMM', 'fr_FR').format(effectiveDate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Suppression programmée pour le $f ✅ — vos clients gardent leur '
            'créneau, personne n\'est prévenu.',
          ),
          backgroundColor: _kGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ── Annule une suppression programmée pas encore appliquée ──────
  // Efface le marqueur et régénère les créneaux des 7 jours à venir sous la
  // config actuelle de la plage.
  Future<void> _restorePendingDeletion(
    String timeSlotId,
    Map<String, dynamic> slotData,
  ) async {
    final queuePath = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId);

    try {
      await queuePath.collection('timeSlots').doc(timeSlotId).update({
        'deleteAfter': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // La file avait peut-être une suppression programmée basée sur « toutes
      // les plages en sursis » — ce n'est plus le cas.
      await queuePath.update({'deleteAfter': FieldValue.delete()});

      await _generateSlotsImmediately(
        timeSlotId: timeSlotId,
        startTimeStr: slotData['startTime'] as String? ?? '09:00',
        endTimeStr: slotData['endTime'] as String? ?? '17:00',
        duration: (slotData['serviceDurationMinutes'] as num?)?.toInt() ?? 15,
        capacity: (slotData['capacityPerSlot'] as num?)?.toInt() ?? 1,
        workingDays: slotData['workingDays'] != null
            ? List<int>.from(slotData['workingDays'] as List)
            : List<int>.from(_queueWeekdays),
        maxAdvanceDays: (slotData['maxAdvanceDays'] as num?)?.toInt() ?? 2,
        reservationDeadlineMinutes:
            (slotData['reservationDeadlineMinutes'] as num?)?.toInt() ?? 0,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Suppression annulée — la plage est de nouveau active.',
          ),
          backgroundColor: _kGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }
}
