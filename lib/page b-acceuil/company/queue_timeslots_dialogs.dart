part of 'settings_page.dart';

// Choix proposé quand une modification de plage entre en conflit avec des
// réservations existantes.
enum _ConflictChoice { cancel, scheduleLater, forceNow }

// ============================================================
// DIALOGS — vérification de chevauchement, conflits, plage horaire
// ============================================================
extension _QueueTimeSlotsDialogs on _QueueTimeSlotsPageState {
  // ── Vérification chevauchement ────────────────────────────────
  Future<String?> _checkOverlap({
    required int newStartMin,
    required int newEndMin,
    required List<int> newDays,
    String? excludeSlotId,
  }) async {
    final snap = await _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('timeSlots')
        .get();

    for (final doc in snap.docs) {
      if (doc.id == excludeSlotId) continue;
      final d = doc.data();
      final existingDays =
          (d['workingDays'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          _queueWeekdays;

      final hasCommonDay = newDays.any((day) => existingDays.contains(day));
      if (!hasCommonDay) continue;

      final existStartParts = (d['startTime'] as String? ?? '00:00').split(':');
      final existEndParts = (d['endTime'] as String? ?? '00:00').split(':');
      final existStartMin =
          int.parse(existStartParts[0]) * 60 + int.parse(existStartParts[1]);
      final existEndMin =
          int.parse(existEndParts[0]) * 60 + int.parse(existEndParts[1]);

      if (newStartMin < existEndMin && existStartMin < newEndMin) {
        return '${d['startTime']} – ${d['endTime']}';
      }
    }
    return null;
  }

  // ── Détection des créneaux réservés en conflit ────────────────
  // Un créneau est en conflit si sa plage sort des nouvelles bornes
  // ou si son jour d'ouverture a été retiré.
  //
  // Renvoie aussi [furthestReservedStart] : le début du créneau réservé
  // le plus lointain de cette plage (conflictuel ou non), qui sert à
  // calculer une date d'effet garantie postérieure à toute réservation
  // existante (voir _computeScheduledEffectiveDate). null si aucune
  // réservation.
  Future<
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> conflicts,
        DateTime? furthestReservedStart,
      })>
  _findConflictingReservedSlots({
    required String timeSlotId,
    required int newStartMin,
    required int newEndMin,
    required List<int> newWorkingDays,
  }) async {
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

    final conflicting = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    DateTime? furthestReservedStart;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['timeSlotId'] != timeSlotId) continue;
      final reserved = data['reserved'] as int? ?? 0;
      if (reserved == 0) continue;

      final slotStart = (data['start'] as Timestamp).toDate();
      if (furthestReservedStart == null ||
          slotStart.isAfter(furthestReservedStart)) {
        furthestReservedStart = slotStart;
      }
      final slotEnd = (data['end'] as Timestamp).toDate();
      final slotStartMin = slotStart.hour * 60 + slotStart.minute;
      // Un créneau se terminant à 00:00 du lendemain = minuit (1440 min)
      final slotEndMin = slotEnd.day > slotStart.day
          ? 1440
          : slotEnd.hour * 60 + slotEnd.minute;
      final slotWeekday = slotStart.weekday;

      final outsideTime = slotStartMin < newStartMin || slotEndMin > newEndMin;
      final outsideDay = !newWorkingDays.contains(slotWeekday);

      if (outsideTime || outsideDay) {
        conflicting.add(doc);
      }
    }
    return (
      conflicts: conflicting,
      furthestReservedStart: furthestReservedStart,
    );
  }

  // ── Choix : programmer sans impact, ou appliquer maintenant ─────
  // [isDeletion] : la plage entière est supprimée (pas seulement modifiée).
  // Change le texte et le libellé du bouton rouge.
  Future<_ConflictChoice> _showScheduleOrForceSheet({
    required int reservationCount,
    required bool hasBaxaClients,
    required bool hasManualClients,
    required String formattedDate,
    bool isDeletion = false,
  }) async {
    final message = isDeletion
        ? _buildScheduleOrDeleteMessage(
            hasBaxaClients: hasBaxaClients,
            hasManualClients: hasManualClients,
            formattedDate: formattedDate,
          )
        : _buildScheduleOrForceMessage(
            hasBaxaClients: hasBaxaClients,
            hasManualClients: hasManualClients,
            formattedDate: formattedDate,
          );
    final result = await showModalBottomSheet<_ConflictChoice>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          24, 20, 24, 24 + MediaQuery.of(ctx).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$reservationCount réservation'
                    '${reservationCount > 1 ? 's' : ''} concernée'
                    '${reservationCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () =>
                      Navigator.pop(ctx, _ConflictChoice.cancel),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        color: Colors.grey.shade500, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.pop(ctx, _ConflictChoice.scheduleLater),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Programmer ($formattedDate)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.pop(ctx, _ConflictChoice.forceNow),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  side: BorderSide(color: Colors.red.shade200),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  isDeletion ? 'Supprimer maintenant' : 'Appliquer maintenant',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return result ?? _ConflictChoice.cancel;
  }

  // ── Dialog création / modification de plage horaire ───────────
  Future<void> _showTimeSlotDialog({
    String? slotId,
    Map<String, dynamic>? slotData,
  }) async {
    // Plage en cours de suppression programmée : verrouillée. Il faut
    // d'abord restituer la suppression pour pouvoir la modifier.
    if (slotData != null && slotData['deleteAfter'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cette plage est en cours de suppression. Restituez-la d\'abord '
            'pour la modifier.',
          ),
        ),
      );
      return;
    }

    TimeOfDay startTime = slotData != null
        ? _parseTimeOfDay(slotData['startTime'] ?? '09:00')
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = slotData != null
        ? _parseTimeOfDay(slotData['endTime'] ?? '17:00')
        : const TimeOfDay(hour: 17, minute: 0);

    int selectedDuration = (() {
      final raw = (slotData?['serviceDurationMinutes'] as num?)?.toInt() ?? 15;
      const valid = [5, 10, 15, 20, 25, 30];
      return valid.contains(raw) ? raw : 15;
    })();

    List<int> selectedWorkingDays = slotData?['workingDays'] != null
        ? List<int>.from(slotData!['workingDays'])
        : List<int>.from(_queueWeekdays);

    int selectedCapacity =
        (slotData?['capacityPerSlot'] as num?)?.toInt() ?? 1;
    int selectedDelay =
        (slotData?['reservationDeadlineMinutes'] as num?)?.toInt() ?? 5;
    int selectedAdvanceDays =
        (slotData?['maxAdvanceDays'] as num?)?.toInt() ?? 2;
    bool guideSeen = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final startMin = startTime.hour * 60 + startTime.minute;
          // 00:00 sélectionné comme heure de fin = minuit (24:00 = 1440 min)
          final endMin = (endTime.hour == 0 && endTime.minute == 0)
              ? 1440
              : endTime.hour * 60 + endTime.minute;
          final totalMinutes = endMin - startMin;
          final slotCount = totalMinutes > 0 && selectedDuration > 0
              ? (totalMinutes / selectedDuration).floor()
              : 0;
          final remainder = totalMinutes > 0 && selectedDuration > 0
              ? totalMinutes % selectedDuration
              : 0;
          final dailyCapacity = slotCount * selectedCapacity;

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.93,
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Handle ─────────────────────────────────────────
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── En-tête ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.schedule_rounded,
                          color: _kGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              slotId == null
                                  ? 'Créer une plage horaire'
                                  : 'Modifier la plage',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1C2E),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              slotId == null
                                  ? 'Définissez vos horaires de service'
                                  : widget.queueName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, false),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Corps scrollable ─────────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // ── Chip Guide ───────────────────────────────────
                      Builder(builder: (_) {
                        final pulsing =
                            OnboardingService().step == 5 && !guideSeen;
                        final chip = GestureDetector(
                          onTap: () {
                            if (!guideSeen) setD(() => guideSeen = true);
                            _showSlotHelp(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: pulsing
                                  ? _kLightGreen
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: pulsing
                                    ? _kGreen.withValues(alpha: 0.5)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline,
                                    size: 15, color: _kGreen),
                                const SizedBox(width: 6),
                                Text(
                                  'Guide des paramètres',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: pulsing
                                        ? _kGreen
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward_ios_rounded,
                                    size: 10,
                                    color: pulsing
                                        ? _kGreen
                                        : Colors.grey.shade500),
                              ],
                            ),
                          ),
                        );
                        return pulsing
                            ? PulsingGlow(
                                borderRadius: BorderRadius.circular(20),
                                child: chip,
                              )
                            : chip;
                      }),
                      const SizedBox(height: 16),

                      // ── 1. DURÉE ──────────────────────────────────────
                      _buildSheetCard(
                        icon: Icons.timer_rounded,
                        title: 'Durée par créneau',
                        subtitle: 'Temps par client',
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [5, 10, 15, 20, 25, 30].map((d) {
                              final isSel = selectedDuration == d;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () =>
                                      setD(() => selectedDuration = d),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSel ? _kGreen : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSel
                                            ? _kGreen
                                            : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                      boxShadow: isSel
                                          ? [
                                              BoxShadow(
                                                color: _kGreen.withValues(
                                                    alpha: 0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Text(
                                      '${d}min',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isSel
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── 2. PLAGE HORAIRE ─────────────────────────────
                      _buildSheetCard(
                        icon: Icons.access_time_rounded,
                        title: 'Plage horaire',
                        subtitle: 'Ouverture · Fermeture',
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final t = await showTimePicker(
                                        context: ctx,
                                        initialTime: startTime,
                                      );
                                      if (t != null) setD(() => startTime = t);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            _kGreen.withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              _kGreen.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'DÉBUT',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: _kGreen.withValues(
                                                  alpha: 0.7),
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatTime(startTime),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: _kGreen,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.grey.shade400,
                                    size: 20,
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final t = await showTimePicker(
                                        context: ctx,
                                        initialTime: endTime,
                                      );
                                      if (t != null) setD(() => endTime = t);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'FIN',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            (endTime.hour == 0 &&
                                                    endTime.minute == 0)
                                                ? '24:00'
                                                : _formatTime(endTime),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1A1C2E),
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Aperçu en temps réel
                            if (slotCount > 0) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _kGreen.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        size: 15, color: _kGreen),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$slotCount créneau${slotCount > 1 ? 'x' : ''} · '
                                        '$dailyCapacity personne${dailyCapacity > 1 ? 's' : ''}/jour'
                                        '${remainder > 0 ? ' · ⚠️ ${remainder}min non utilisées' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _kGreen,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (totalMinutes <= 0 && endMin > 0) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber,
                                        size: 15, color: Colors.red.shade700),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'L\'heure de fin doit être après le début',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── 3. JOURS D'OUVERTURE ─────────────────────────
                      _buildSheetCard(
                        icon: Icons.calendar_today_rounded,
                        title: 'Jours d\'ouverture',
                        subtitle: 'Jours actifs',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (index) {
                            final day = index + 1;
                            const labels = [
                              'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim',
                            ];
                            final isSel = selectedWorkingDays.contains(day);
                            return GestureDetector(
                              onTap: () {
                                setD(() {
                                  if (isSel) {
                                    selectedWorkingDays.remove(day);
                                  } else {
                                    selectedWorkingDays.add(day);
                                  }
                                  selectedWorkingDays.sort();
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 9),
                                decoration: BoxDecoration(
                                  color: isSel ? _kGreen : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSel
                                        ? _kGreen
                                        : Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  labels[index],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSel
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── 4. PARAMÈTRES NUMÉRIQUES ─────────────────────
                      _buildSheetCard(
                        icon: Icons.tune_rounded,
                        title: 'Paramètres',
                        subtitle: 'Règles de réservation',
                        child: Column(
                          children: [
                            _buildPickerCard(
                              title: 'Capacité',
                              subtitle: 'Personnes par créneau',
                              child: _NumberPickerDial(
                                min: 1,
                                max: 30,
                                value: selectedCapacity,
                                suffix: 'pers.',
                                onChanged: (v) =>
                                    setD(() => selectedCapacity = v),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildPickerCard(
                                    title: 'Délai min.',
                                    subtitle: 'Avant début du créneau',
                                    child: _NumberPickerDial(
                                      min: 0,
                                      max: 60,
                                      value: selectedDelay,
                                      suffix: 'min',
                                      onChanged: (v) =>
                                          setD(() => selectedDelay = v),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildPickerCard(
                                    title: 'Anticipation',
                                    subtitle: 'Jours à l\'avance max.',
                                    child: _NumberPickerDial(
                                      min: 1,
                                      max: 7,
                                      value: selectedAdvanceDays,
                                      suffix: 'j',
                                      onChanged: (v) =>
                                          setD(() => selectedAdvanceDays = v),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),

                // ── Bouton principal fixe ────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FA),
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          slotId == null ? 'Créer la plage' : 'Enregistrer',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result != true) return;

    // Une modification programmée en attente sur cette plage ? Rouvrir
    // "Modifier" et enregistrer — même sans rien changer — annule toujours
    // cette modification en attente avant toute autre chose (pas de bouton
    // dédié : "enregistrer sans changement" revient à annuler le plan).
    final hasPendingChange =
        slotId != null && slotData != null && slotData['pendingEffectiveDate'] != null;

    // ── Détection absence de changement (mode édition uniquement) ─
    if (!hasPendingChange && slotId != null && slotData != null) {
      final origStart = slotData['startTime'] as String? ?? '09:00';
      final origEnd = slotData['endTime'] as String? ?? '17:00';
      final origDuration =
          (slotData['serviceDurationMinutes'] as num?)?.toInt() ?? 15;
      final origCapacity =
          (slotData['capacityPerSlot'] as num?)?.toInt() ?? 1;
      final origDelay =
          (slotData['reservationDeadlineMinutes'] as num?)?.toInt() ?? 5;
      final origAdvanceDays =
          (slotData['maxAdvanceDays'] as num?)?.toInt() ?? 2;
      final origDays = slotData['workingDays'] != null
          ? List<int>.from(slotData['workingDays'] as List)
          : List<int>.from(_queueWeekdays);

      final newEndStr = (endTime.hour == 0 && endTime.minute == 0)
          ? '24:00'
          : _formatTime(endTime);
      final sortedOrig = (List<int>.from(origDays)..sort()).join(',');
      final sortedNew = (List<int>.from(selectedWorkingDays)..sort()).join(',');

      final unchanged = _formatTime(startTime) == origStart &&
          newEndStr == origEnd &&
          selectedDuration == origDuration &&
          selectedCapacity == origCapacity &&
          selectedDelay == origDelay &&
          selectedAdvanceDays == origAdvanceDays &&
          sortedNew == sortedOrig;

      if (unchanged) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aucune modification détectée'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    final startMin = startTime.hour * 60 + startTime.minute;
    final endMin = (endTime.hour == 0 && endTime.minute == 0)
        ? 1440
        : endTime.hour * 60 + endTime.minute;
    if (endMin <= startMin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ L\'heure de fin doit être après l\'heure de début'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final overlap = await _checkOverlap(
      newStartMin: startMin,
      newEndMin: endMin,
      newDays: selectedWorkingDays,
      excludeSlotId: slotId,
    );
    if (overlap != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Chevauchement avec la plage $overlap. Ajustez les horaires.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFC62828),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // ── Catégorisation des changements (mode édition) ─────────────
    List<QueryDocumentSnapshot<Map<String, dynamic>>> conflictingSlots = [];
    bool isHardChange = false;
    bool needsGeneration = slotId == null; // création → toujours générer
    DateTime? scheduledEffectiveDate; // non-null si "Programmer" est choisi

    if (slotId != null && slotData != null) {
      final origStart = slotData['startTime'] as String? ?? '09:00';
      final origEnd = slotData['endTime'] as String? ?? '17:00';
      final origDuration =
          (slotData['serviceDurationMinutes'] as num?)?.toInt() ?? 15;
      final origAdvanceDays =
          (slotData['maxAdvanceDays'] as num?)?.toInt() ?? 2;
      final origDaySet = slotData['workingDays'] != null
          ? (slotData['workingDays'] as List).map((e) => e as int).toSet()
          : _queueWeekdays.toSet();
      final newDaySet = selectedWorkingDays.toSet();

      final newEndStr = (endTime.hour == 0 && endTime.minute == 0)
          ? '24:00'
          : _formatTime(endTime);
      final timingChanged = _formatTime(startTime) != origStart ||
          newEndStr != origEnd ||
          selectedDuration != origDuration;
      final removedDays = origDaySet.difference(newDaySet);
      final addedDays = newDaySet.difference(origDaySet);

      isHardChange = timingChanged || removedDays.isNotEmpty;
      needsGeneration = isHardChange ||
          addedDays.isNotEmpty ||
          selectedAdvanceDays > origAdvanceDays;

      if (isHardChange) {
        final reservedScan = await _findConflictingReservedSlots(
          timeSlotId: slotId,
          newStartMin: startMin,
          newEndMin: endMin,
          newWorkingDays: selectedWorkingDays,
        );
        conflictingSlots = reservedScan.conflicts;
        if (conflictingSlots.isNotEmpty) {
          if (!mounted) return;
          final n = conflictingSlots.length;
          final origins = await _analyzeReservationOrigins(conflictingSlots);
          if (!mounted) return;
          final effectiveDate = _computeScheduledEffectiveDate(
            newAnticipationDays: selectedAdvanceDays,
            furthestReservedStart: reservedScan.furthestReservedStart,
          );
          final formattedDate =
              DateFormat('EEE d MMM', 'fr_FR').format(effectiveDate);
          final choice = await _showScheduleOrForceSheet(
            reservationCount: n,
            hasBaxaClients: origins.hasBaxaClients,
            hasManualClients: origins.hasManualClients,
            formattedDate: formattedDate,
          );
          if (choice == _ConflictChoice.cancel) return;
          if (choice == _ConflictChoice.scheduleLater) {
            scheduledEffectiveDate = effectiveDate;
          }
        }
      }
    }

    final timeSlotData = {
      'startTime': _formatTime(startTime),
      'endTime': (endTime.hour == 0 && endTime.minute == 0)
          ? '24:00'
          : _formatTime(endTime),
      'serviceDurationMinutes': selectedDuration,
      'capacityPerSlot': selectedCapacity,
      'workingDays': selectedWorkingDays,
      'reservationDeadlineMinutes': selectedDelay,
      'maxAdvanceDays': selectedAdvanceDays,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    var loadingDialogShown = false;
    try {
      if (!mounted) return;
      loadingDialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    slotId != null
                        ? 'Modifications...'
                        : 'Génération des créneaux...',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Une modification programmée traîne encore sur cette plage : on
      // l'annule d'abord (repart d'une base propre) avant d'évaluer quoi
      // que ce soit ci-dessous — que l'utilisateur ait changé quelque
      // chose ou non.
      if (hasPendingChange) {
        await _revertPendingChange(slotId, slotData);
      }

      // ── Cas "Programmer" : la config actuelle n'est jamais touchée ──
      if (scheduledEffectiveDate != null) {
        await _scheduleTimeSlotChange(
          timeSlotId: slotId!,
          effectiveDate: scheduledEffectiveDate,
          startTimeStr: _formatTime(startTime),
          endTimeStr: (endTime.hour == 0 && endTime.minute == 0)
              ? '24:00'
              : _formatTime(endTime),
          duration: selectedDuration,
          capacity: selectedCapacity,
          workingDays: selectedWorkingDays,
          maxAdvanceDays: selectedAdvanceDays,
          reservationDeadlineMinutes: selectedDelay,
        );

        if (!mounted) return;
        Navigator.pop(context);
        loadingDialogShown = false;

        final formattedDate =
            DateFormat('EEE d MMM', 'fr_FR').format(scheduledEffectiveDate);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Modification programmée pour le $formattedDate ✅ — aucune '
              'réservation en cours n\'est impactée.',
            ),
            backgroundColor: _kGreen,
          ),
        );
        return;
      }

      // ── Cas normal (création, édition sans conflit, ou "Appliquer
      // maintenant") : comportement inchangé ────────────────────────
      final timeSlotsRef = _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('queues')
          .doc(widget.queueId)
          .collection('timeSlots');

      final String resolvedSlotId;
      if (slotId == null) {
        final ref = await timeSlotsRef.add(timeSlotData);
        resolvedSlotId = ref.id;
      } else {
        await timeSlotsRef.doc(slotId).update(timeSlotData);
        resolvedSlotId = slotId;
      }

      await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('queues')
          .doc(widget.queueId)
          .update({'maxAdvanceDays': selectedAdvanceDays});

      // ── Nettoyage selon le type de changement ──────────────────
      bool cancelNotifyFailed = false;
      if (slotId != null) {
        if (isHardChange) {
          await _deleteEmptyFutureSlotsForTimeSlot(resolvedSlotId);
          if (conflictingSlots.isNotEmpty) {
            // Isolé dans son propre try/catch : un échec ici (ex. notification
            // au client) ne doit jamais empêcher la régénération des créneaux
            // ci-dessous — sinon la plage se retrouve vidée par le nettoyage
            // ci-dessus sans jamais être reconstruite.
            try {
              await _cancelReservedSlotsAndNotify(conflictingSlots);
            } catch (e) {
              cancelNotifyFailed = true;
              debugPrint('Erreur annulation/notification réservations : $e');
            }
          }
        }
      }

      // ── Génération si nécessaire ───────────────────────────────
      int created = 0;
      if (needsGeneration) {
        created = await _generateSlotsImmediately(
          timeSlotId: resolvedSlotId,
          startTimeStr: _formatTime(startTime),
          endTimeStr: (endTime.hour == 0 && endTime.minute == 0)
              ? '24:00'
              : _formatTime(endTime),
          duration: selectedDuration,
          capacity: selectedCapacity,
          workingDays: selectedWorkingDays,
          maxAdvanceDays: selectedAdvanceDays,
          reservationDeadlineMinutes: selectedDelay,
        );
      }

      // ── Mise à jour des paramètres sur créneaux existants ──────
      int updated = 0;
      if (slotId != null) {
        updated = await _updateSlotParameters(
          timeSlotId: resolvedSlotId,
          capacity: selectedCapacity,
          duration: selectedDuration,
          reservationDeadlineMinutes: selectedDelay,
          maxAdvanceDays: selectedAdvanceDays,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      loadingDialogShown = false;

      final isEdit = slotId != null;
      final wasOnboarding = !isEdit && OnboardingService().step == 5;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'Plage modifiée ✅'
                    '${updated > 0 ? '  ·  $updated créneau${updated > 1 ? 'x' : ''} mis à jour' : ''}'
                    '${created > 0 ? '  ·  $created nouveau${created > 1 ? 'x' : ''}' : ''}'
                    '${cancelNotifyFailed ? '  ·  ⚠️ Annulation des réservations en conflit incomplète, réessaie' : ''}'
                : 'Plage créée ✅  $created créneau${created > 1 ? 'x' : ''} générés',
          ),
          backgroundColor: cancelNotifyFailed ? Colors.orange.shade700 : _kGreen,
        ),
      );

      if (wasOnboarding && mounted) {
        OnboardingService().advance(5); // 5 → 6
        await showOnboardingCelebration(
          context,
          title: 'Tout est en place !',
          body: 'Vos créneaux sont actifs dès maintenant.\n\nRetournez sur l\'accueil pour consulter votre agenda et suivre vos réservations.',
        );
        if (mounted) await OnboardingService().complete();
      }
    } catch (e) {
      if (loadingDialogShown && mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ── Guide des paramètres ──────────────────────────────────────────────────
  void _showSlotHelp(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (helpCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── En-tête vert ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              color: _kGreen,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lightbulb_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guide des paramètres',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '6 paramètres à maîtriser',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(helpCtx),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Liste des paramètres ───────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Column(
                  children: [
                    _helpCard(
                      Icons.timer_rounded,
                      'Durée par créneau',
                      'Temps accordé à chaque client lors de sa venue.',
                      '30 min = 1 client toutes les 30 min',
                    ),
                    _helpCard(
                      Icons.access_time_rounded,
                      'Plage horaire',
                      'Fenêtre d\'accueil pendant laquelle vos créneaux sont ouverts.',
                      '9h–17h → créneaux proposés sur cette tranche',
                    ),
                    _helpCard(
                      Icons.calendar_today_rounded,
                      'Jours d\'ouverture',
                      'Jours de la semaine où cette plage est active.',
                      'Fermé le week-end ? Décochez Sam & Dim',
                    ),
                    _helpCard(
                      Icons.people_rounded,
                      'Capacité',
                      'Nombre de clients accueillis en simultané sur un même créneau.',
                      '2 pers. = 2 clients au même horaire',
                    ),
                    _helpCard(
                      Icons.hourglass_top_rounded,
                      'Délai minimum',
                      'Délai obligatoire entre la réservation et le début du créneau.',
                      '10 min = plus de résa de dernière minute',
                    ),
                    _helpCard(
                      Icons.date_range_rounded,
                      'Anticipation max.',
                      'Horizon maximum auquel un client peut réserver à l\'avance.',
                      '3 j = clients voient les 3 prochains jours',
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

            // ── Bouton ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(helpCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Compris !',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpCard(
      IconData icon, String title, String desc, String example) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _kGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF1A1C2E),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    example,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _kGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
