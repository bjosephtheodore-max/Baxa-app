part of 'settings_page.dart';

// ==================== ÉTAT DE LA PAGE PLAGES HORAIRES ====================
class _QueueTimeSlotsPageState extends State<QueueTimeSlotsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<int> _queueWeekdays = [1, 2, 3, 4, 5];

  // Streams stockés en instance — évite la réinscription à chaque rebuild.
  late final Stream<QuerySnapshot> _slotsStream;
  late final Stream<List<_DayCapacity>> _capacityStream;

  @override
  void initState() {
    super.initState();
    final queueRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId);
    _slotsStream = queueRef.collection('timeSlots').snapshots();
    _capacityStream = _buildCapacityStream(queueRef);
    _loadQueueWeekdays();
    if (widget.autoOpenSlotDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showTimeSlotDialog();
      });
    }
  }

  Stream<List<_DayCapacity>> _buildCapacityStream(
    DocumentReference<Map<String, dynamic>> queueRef,
  ) {
    return queueRef.collection('timeSlots').snapshots().map((snapshot) {
      final Map<int, int> capacityPerDay = {for (int d = 1; d <= 7; d++) d: 0};
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final workingDays =
            (d['workingDays'] as List<dynamic>?)?.map((e) => e as int).toList()
            ?? _queueWeekdays;
        final start = d['startTime'] as String? ?? '00:00';
        final end = d['endTime'] as String? ?? '00:00';
        final duration = (d['serviceDurationMinutes'] as num?)?.toInt() ?? 0;
        final capacity = (d['capacityPerSlot'] as num?)?.toInt() ?? 0;
        if (duration <= 0) continue;
        final slotsCount = _countSlots(start, end, duration);
        final slotCapacity = slotsCount * capacity;
        for (final day in workingDays) {
          if (capacityPerDay.containsKey(day)) {
            capacityPerDay[day] = capacityPerDay[day]! + slotCapacity;
          }
        }
      }
      return _groupDaysByCapacity(capacityPerDay);
    });
  }

  Future<void> _loadQueueWeekdays() async {
    try {
      final doc = await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('queues')
          .doc(widget.queueId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final days =
            (data['weekdays'] as List<dynamic>?)?.map((e) => e as int).toList();
        if (days != null) {
          // Mise à jour sans setState — le stream capturera la nouvelle valeur
          // lors de sa prochaine émission Firestore.
          _queueWeekdays = days;
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kGreen),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plages horaires',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.queueName,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Bannière capacité groupée par jour
          StreamBuilder<List<_DayCapacity>>(
            stream: _capacityStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }
              final days = snapshot.data ?? [];
              final isEmpty =
                  days.isEmpty || days.every((d) => d.capacity == 0);
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 4,
                        decoration: const BoxDecoration(
                          color: _kGreen,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _kGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.groups,
                            color: _kGreen,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Capacité d\'accueil',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (isEmpty)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber,
                                      size: 14,
                                      color: Colors.orange.shade600,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Aucune plage configurée',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: days.map((d) {
                                    final isOpen = d.capacity > 0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isOpen
                                            ? _kGreen.withValues(alpha: 0.1)
                                            : Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            isOpen
                                                ? '${d.label} · ${d.capacity} '
                                                : '${d.label} · Fermé',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isOpen
                                                  ? _kGreen
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                          if (isOpen)
                                            Icon(
                                              Icons.group,
                                              size: 13,
                                              color: _kGreen,
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Liste des plages horaires
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _slotsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final timeSlots = snapshot.data?.docs ?? [];
                if (timeSlots.isEmpty) return _buildEmptyState();
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: timeSlots.length,
                  itemBuilder: (context, index) {
                    final slot = timeSlots[index];
                    final slotData = slot.data() as Map<String, dynamic>;
                    return _buildTimeSlotCard(slot.id, slotData);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showTimeSlotDialog,
        backgroundColor: _kGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Ajouter une plage',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

// ==================== UI HELPERS ====================
extension _QueueTimeSlotsUI on _QueueTimeSlotsPageState {
  List<_DayCapacity> _groupDaysByCapacity(Map<int, int> perDay) {
    const dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final result = <_DayCapacity>[];

    int? groupStart;
    int? groupEnd;
    int? groupCapacity;

    void flush() {
      if (groupStart == null) return;
      final label = groupStart == groupEnd
          ? dayLabels[groupStart! - 1]
          : '${dayLabels[groupStart! - 1]}–${dayLabels[groupEnd! - 1]}';
      result.add(_DayCapacity(label: label, capacity: groupCapacity!));
      groupStart = null;
      groupEnd = null;
      groupCapacity = null;
    }

    for (int day = 1; day <= 7; day++) {
      final cap = perDay[day] ?? 0;
      if (groupStart == null) {
        groupStart = day;
        groupEnd = day;
        groupCapacity = cap;
      } else if (cap == groupCapacity) {
        groupEnd = day;
      } else {
        flush();
        groupStart = day;
        groupEnd = day;
        groupCapacity = cap;
      }
    }
    flush();

    return result;
  }

  int _countSlots(String start, String end, int duration) {
    try {
      final sp = start.split(':');
      final ep = end.split(':');
      final startMin = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final endMin = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      if (duration <= 0) return 0;
      return ((endMin - startMin) / duration).floor();
    } catch (_) {
      return 0;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 24),
          const Text(
            'Aucune plage horaire',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez votre première plage horaire',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotCard(String slotId, Map<String, dynamic> slotData) {
    final startTime = slotData['startTime'] ?? '00:00';
    final endTime = slotData['endTime'] ?? '00:00';
    final duration = slotData['serviceDurationMinutes'] ?? 0;
    final capacity = slotData['capacityPerSlot'] ?? 0;
    final workingDays =
        (slotData['workingDays'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        _queueWeekdays;

    final slotsCount = _countSlots(startTime, endTime, duration);
    final totalCapacity = slotsCount * capacity;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Bloc horaire vert à gauche ──────────────────────
              Container(
                width: 76,
                color: _kGreen,
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      startTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 1,
                      height: 14,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      endTime,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Contenu ─────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (totalCapacity > 0) ...[
                              Text(
                                '$totalCapacity pers./jour',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _buildInfoChip(Icons.timer, '$duration min'),
                                _buildInfoChip(
                                  Icons.people,
                                  '$capacity pers./crén.',
                                ),
                                _buildInfoChip(
                                  Icons.calendar_today,
                                  _formatWeekdays(workingDays),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: Material(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showSlotActions(slotId, slotData),
                            child: const Icon(
                              Icons.more_vert,
                              size: 18,
                              color: Colors.black54,
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
        ),
      ),
    );
  }

  void _showSlotActions(String slotId, Map<String, dynamic> slotData) {
    final start = slotData['startTime'] ?? '??:??';
    final end = slotData['endTime'] ?? '??:??';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                '$start – $end',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              _slotActionTile(
                icon: Icons.edit_outlined,
                label: 'Modifier',
                bgColor: Colors.grey.shade50,
                fgColor: Colors.black87,
                onTap: () {
                  Navigator.pop(ctx);
                  _showTimeSlotDialog(slotId: slotId, slotData: slotData);
                },
              ),
              const SizedBox(height: 8),
              _slotActionTile(
                icon: Icons.delete_outline,
                label: 'Supprimer',
                bgColor: Colors.red.shade50,
                fgColor: Colors.red.shade700,
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteSlot(slotId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slotActionTile({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fgColor),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatWeekdays(List<int> weekdays) {
    if (weekdays.isEmpty) return '–';
    if (weekdays.length == 7) return 'Tous les jours';
    const labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final sorted = List<int>.from(weekdays)..sort();
    final groups = <String>[];
    int start = sorted[0];
    int end = sorted[0];
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == end + 1) {
        end = sorted[i];
      } else {
        groups.add(end > start
            ? '${labels[start - 1]}–${labels[end - 1]}'
            : labels[start - 1]);
        start = sorted[i];
        end = sorted[i];
      }
    }
    groups.add(end > start
        ? '${labels[start - 1]}–${labels[end - 1]}'
        : labels[start - 1]);
    return groups.join(', ');
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title, {required IconData icon}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _kGreen),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildPickerCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade50,
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
