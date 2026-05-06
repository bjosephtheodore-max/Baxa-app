part of 'settings_page.dart';

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
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
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
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['timeSlotId'] != timeSlotId) continue;
      final reserved = data['reserved'] as int? ?? 0;
      if (reserved == 0) continue;

      final slotStart = (data['start'] as Timestamp).toDate();
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
    return conflicting;
  }

  // ── Avertissement générique réservations impactées ───────────
  Future<bool> _showDestructiveWarning(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Réservations impactées',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text(
              'Confirmer',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Dialog création / modification de plage horaire ───────────
  Future<void> _showTimeSlotDialog({
    String? slotId,
    Map<String, dynamic>? slotData,
  }) async {
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
    int selectedMaxReservations =
        (slotData?['maxReservationsPerPerson'] as num?)?.toInt() ??
        kDefaultMaxReservationsPerPerson;
    int selectedDelay =
        (slotData?['reservationDeadlineMinutes'] as num?)?.toInt() ?? 10;
    int selectedAdvanceDays =
        (slotData?['maxAdvanceDays'] as num?)?.toInt() ?? 5;

    final result = await showDialog<bool>(
      context: context,
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

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── En-tête coloré ──────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
                  decoration: BoxDecoration(
                    color: _kGreen,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          slotId == null
                              ? 'Créer une plage horaire'
                              : 'Modifier la plage',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // ── Corps scrollable ─────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. DURÉE (en premier)
                        _buildSectionLabel(
                          'Durée par créneau',
                          icon: Icons.timer,
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
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
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? _kGreen
                                          : Colors.grey.shade100,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSel
                                            ? _kGreen
                                            : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
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

                        const SizedBox(height: 20),

                        // 2. PLAGE HORAIRE
                        _buildSectionLabel(
                          'Plage horaire',
                          icon: Icons.access_time,
                        ),
                        const SizedBox(height: 10),
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
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'DÉBUT',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatTime(startTime),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Icon(
                                Icons.arrow_forward,
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
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
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
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (endTime.hour == 0 && endTime.minute == 0)
                                            ? '24:00'
                                            : _formatTime(endTime),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
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
                        const SizedBox(height: 10),
                        if (slotCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _kLightGreen.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _kGreen.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 15,
                                  color: _kGreen,
                                ),
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
                          )
                        else if (totalMinutes <= 0 && endMin > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 15,
                                  color: Colors.red.shade700,
                                ),
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

                        const SizedBox(height: 20),

                        // 3. JOURS D'OUVERTURE
                        _buildSectionLabel(
                          'Jours d\'ouverture',
                          icon: Icons.calendar_today,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hérite des jours de la file par défaut',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: List.generate(7, (index) {
                            final day = index + 1;
                            const labels = [
                              'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim',
                            ];
                            return FilterChip(
                              label: Text(labels[index]),
                              selected: selectedWorkingDays.contains(day),
                              selectedColor: _kLightGreen,
                              checkmarkColor: _kGreen,
                              onSelected: (selected) {
                                setD(() {
                                  if (selected) {
                                    selectedWorkingDays.add(day);
                                  } else {
                                    selectedWorkingDays.remove(day);
                                  }
                                  selectedWorkingDays.sort();
                                });
                              },
                            );
                          }),
                        ),

                        const SizedBox(height: 24),

                        // 4. PARAMÈTRES NUMÉRIQUES (2 × 2)
                        _buildSectionLabel('Paramètres', icon: Icons.tune),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPickerCard(
                                title: 'Capacité',
                                subtitle: 'par créneau',
                                child: _NumberPickerDial(
                                  min: 1,
                                  max: 30,
                                  value: selectedCapacity,
                                  suffix: 'pers.',
                                  onChanged: (v) =>
                                      setD(() => selectedCapacity = v),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildPickerCard(
                                title: 'Max réserv.',
                                subtitle: 'par personne',
                                child: _NumberPickerDial(
                                  min: 1,
                                  max: 5,
                                  value: selectedMaxReservations,
                                  suffix: '/pers.',
                                  onChanged: (v) =>
                                      setD(() => selectedMaxReservations = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPickerCard(
                                title: 'Délai min.',
                                subtitle: 'avant réserv.',
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
                                subtitle: 'maximum',
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

                        const SizedBox(height: 24),

                        // Bouton principal
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              slotId == null ? 'Créer la plage' : 'Enregistrer',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
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

    // ── Détection absence de changement (mode édition uniquement) ─
    if (slotId != null && slotData != null) {
      final origStart = slotData['startTime'] as String? ?? '09:00';
      final origEnd = slotData['endTime'] as String? ?? '17:00';
      final origDuration =
          (slotData['serviceDurationMinutes'] as num?)?.toInt() ?? 15;
      final origCapacity =
          (slotData['capacityPerSlot'] as num?)?.toInt() ?? 1;
      final origMaxRes =
          (slotData['maxReservationsPerPerson'] as num?)?.toInt() ??
          kDefaultMaxReservationsPerPerson;
      final origDelay =
          (slotData['reservationDeadlineMinutes'] as num?)?.toInt() ?? 10;
      final origAdvanceDays =
          (slotData['maxAdvanceDays'] as num?)?.toInt() ?? 5;
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
          selectedMaxReservations == origMaxRes &&
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

    if (slotId != null && slotData != null) {
      final origStart = slotData['startTime'] as String? ?? '09:00';
      final origEnd = slotData['endTime'] as String? ?? '17:00';
      final origDuration =
          (slotData['serviceDurationMinutes'] as num?)?.toInt() ?? 15;
      final origAdvanceDays =
          (slotData['maxAdvanceDays'] as num?)?.toInt() ?? 5;
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
        conflictingSlots = await _findConflictingReservedSlots(
          timeSlotId: slotId,
          newStartMin: startMin,
          newEndMin: endMin,
          newWorkingDays: selectedWorkingDays,
        );
        if (conflictingSlots.isNotEmpty) {
          if (!mounted) return;
          final n = conflictingSlots.length;
          final confirmed = await _showDestructiveWarning(
            '$n réservation${n > 1 ? 's' : ''} '
            'ser${n > 1 ? 'ont' : 'a'} annulée${n > 1 ? 's' : ''} '
            'et les clients notifiés.',
          );
          if (!confirmed) return;
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
      'maxReservationsPerPerson': selectedMaxReservations,
      'reservationDeadlineMinutes': selectedDelay,
      'maxAdvanceDays': selectedAdvanceDays,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
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

      if (!mounted) return;

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

      // ── Nettoyage selon le type de changement ──────────────────
      if (slotId != null) {
        if (isHardChange) {
          await _deleteEmptyFutureSlotsForTimeSlot(resolvedSlotId);
          if (conflictingSlots.isNotEmpty) {
            await _cancelReservedSlotsAndNotify(conflictingSlots);
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
          maxReservationsPerPerson: selectedMaxReservations,
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
          maxReservationsPerPerson: selectedMaxReservations,
          reservationDeadlineMinutes: selectedDelay,
          maxAdvanceDays: selectedAdvanceDays,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);

      final isEdit = slotId != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'Plage modifiée ✅'
                    '${updated > 0 ? '  ·  $updated créneau${updated > 1 ? 'x' : ''} mis à jour' : ''}'
                    '${created > 0 ? '  ·  $created nouveau${created > 1 ? 'x' : ''}' : ''}'
                : 'Plage créée ✅  $created créneau${created > 1 ? 'x' : ''} générés',
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
