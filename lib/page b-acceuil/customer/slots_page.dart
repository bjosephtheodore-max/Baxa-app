import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/reservation_rules_service.dart';

/// ============================================================
/// PAGE DES CRÉNEAUX — autonome, dissociée de CompanyQueuePage
/// Appelée depuis CompanyQueuePage via Navigator.push
/// ============================================================
class SlotsPage extends StatefulWidget {
  final String entrepriseId;
  final String queueId;
  final String queueName;
  final Color primaryGreen;
  final Color lightGreen;
  final VoidCallback onReservationSuccess;

  const SlotsPage({
    super.key,
    required this.entrepriseId,
    required this.queueId,
    required this.queueName,
    required this.primaryGreen,
    required this.lightGreen,
    required this.onReservationSuccess,
  });

  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final DateFormat _timeFmt = DateFormat('HH:mm');
  final DateFormat _dateFmtFull = DateFormat('EEEE d MMMM', 'fr_FR');
  final _rulesService = ReservationRulesService();

  DateTime _selectedDate = DateTime.now();

  /// Config de la file (chargée une fois)
  int _maxActivePerUser = kDefaultMaxActivePerUser;
  bool _configLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadQueueConfig();
  }

  Future<void> _loadQueueConfig() async {
    try {
      final doc = await _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .collection('queues')
          .doc(widget.queueId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _maxActivePerUser =
              (data['maxActivePerUser'] as int?) ?? kDefaultMaxActivePerUser;
          _configLoaded = true;
        });
      }
    } catch (_) {
      setState(() => _configLoaded = true);
    }
  }

  // ── Helpers date ─────────────────────────────────────────────

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(DateTime date) {
    final today = _dateOnly(DateTime.now());
    final d = _dateOnly(date);
    if (d == today) return 'Aujourd\'hui';
    if (d == today.add(const Duration(days: 1))) return 'Demain';
    final raw = DateFormat('EEEE d MMMM', 'fr_FR').format(date);
    return raw[0].toUpperCase() + raw.substring(1);
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: _fs
            .collection('companies')
            .doc(widget.entrepriseId)
            .collection('queues')
            .doc(widget.queueId)
            .collection('slots')
            .orderBy('start')
            .snapshots(),
        builder: (context, snapshot) {
          final now = DateTime.now();
          List<QueryDocumentSnapshot> allFutureSlots = [];
          List<DateTime> availableDays = [];

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            // Exclure créneaux déjà commencés ou passés
            allFutureSlots = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final start = (data['start'] as Timestamp).toDate().toLocal();
              return start.isAfter(now);
            }).toList();

            final daySet = <String>{};
            for (final doc in allFutureSlots) {
              final data = doc.data() as Map<String, dynamic>;
              final start = (data['start'] as Timestamp).toDate().toLocal();
              final key = '${start.year}-${start.month}-${start.day}';
              if (daySet.add(key)) availableDays.add(_dateOnly(start));
            }
            availableDays.sort();

            if (availableDays.isNotEmpty &&
                !availableDays.any((d) => _isSameDay(d, _selectedDate))) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted)
                  setState(() => _selectedDate = availableDays.first);
              });
            }
          }

          final dailySlots = allFutureSlots.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final start = (data['start'] as Timestamp).toDate().toLocal();
            return _isSameDay(start, _selectedDate);
          }).toList();

          final currentIdx = availableDays.indexWhere(
            (d) => _isSameDay(d, _selectedDate),
          );
          final hasPrev = currentIdx > 0;
          final hasNext = currentIdx < availableDays.length - 1;

          return NestedScrollView(
            headerSliverBuilder: (ctx, _) => [
              _buildSliverAppBar(hasPrev, hasNext, availableDays, currentIdx),
            ],
            body:
                snapshot.connectionState == ConnectionState.waiting ||
                    !_configLoaded
                ? Center(
                    child: CircularProgressIndicator(
                      color: widget.primaryGreen,
                    ),
                  )
                : allFutureSlots.isEmpty
                ? _buildEmptyState(noSlots: true)
                : dailySlots.isEmpty
                ? _buildEmptyState(noSlots: false)
                : _buildSlotList(dailySlots),
          );
        },
      ),
    );
  }

  // ── SliverAppBar avec navigation jours ───────────────────────

  SliverAppBar _buildSliverAppBar(
    bool hasPrev,
    bool hasNext,
    List<DateTime> availableDays,
    int currentIdx,
  ) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: widget.primaryGreen,
      iconTheme: const IconThemeData(color: Colors.white),
      expandedHeight: 115,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          color: widget.primaryGreen,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                widget.queueName,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 10),
              _buildDayNavigator(hasPrev, hasNext, availableDays, currentIdx),
            ],
          ),
        ),
      ),
      title: const Text(
        'Créneaux disponibles',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDayNavigator(
    bool hasPrev,
    bool hasNext,
    List<DateTime> availableDays,
    int currentIdx,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _navBtn(
            icon: Icons.chevron_left_rounded,
            enabled: hasPrev,
            onTap: () =>
                setState(() => _selectedDate = availableDays[currentIdx - 1]),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _showDayPicker(availableDays),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dayLabel(_selectedDate),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (availableDays.isNotEmpty)
                    Text(
                      '${currentIdx + 1} / ${availableDays.length} jour${availableDays.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _navBtn(
            icon: Icons.chevron_right_rounded,
            enabled: hasNext,
            onTap: () =>
                setState(() => _selectedDate = availableDays[currentIdx + 1]),
          ),
        ],
      ),
    );
  }

  Widget _navBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Icon(
            icon,
            color: enabled ? Colors.white : Colors.white24,
            size: 26,
          ),
        ),
      ),
    );
  }

  void _showDayPicker(List<DateTime> availableDays) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Text(
              'Choisir un jour',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            ...availableDays.map((day) {
              final isSelected = _isSameDay(day, _selectedDate);
              return ListTile(
                onTap: () {
                  setState(() => _selectedDate = day);
                  Navigator.pop(ctx);
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: isSelected
                    ? widget.primaryGreen.withOpacity(0.08)
                    : null,
                leading: Icon(
                  Icons.calendar_today_rounded,
                  color: isSelected ? widget.primaryGreen : Colors.grey,
                  size: 18,
                ),
                title: Text(
                  _dayLabel(day),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? widget.primaryGreen
                        : const Color(0xFF1A1A2E),
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: widget.primaryGreen,
                        size: 20,
                      )
                    : null,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // ── Liste des slots avec séparateurs ─────────────────────────

  Widget _buildSlotList(List<QueryDocumentSnapshot> dailySlots) {
    const int gapThreshold = 60;
    final items = <Widget>[];

    final availableCount = dailySlots.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final cap = (d['capacity'] ?? 1) as int;
      final res = (d['reserved'] ?? 0) as int;
      return (d['status'] ?? 'open') == 'open' && res < cap;
    }).length;

    items.add(_buildDaySummary(dailySlots.length, availableCount));
    items.add(const SizedBox(height: 12));

    for (int i = 0; i < dailySlots.length; i++) {
      if (i > 0) {
        final prevData = dailySlots[i - 1].data() as Map<String, dynamic>;
        final currData = dailySlots[i].data() as Map<String, dynamic>;
        final prevEnd = (prevData['end'] as Timestamp).toDate().toLocal();
        final currStart = (currData['start'] as Timestamp).toDate().toLocal();
        final gap = currStart.difference(prevEnd).inMinutes;
        if (gap >= gapThreshold) {
          items.add(_buildGapSeparator(prevEnd, currStart, gap));
        }
      }
      items.add(_buildSlotCard(dailySlots[i]));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: items,
    );
  }

  Widget _buildDaySummary(int total, int available) {
    final isFull = available == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isFull
            ? Colors.orange.shade50
            : widget.primaryGreen.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFull
              ? Colors.orange.shade200
              : widget.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFull
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
            color: isFull ? Colors.orange.shade700 : widget.primaryGreen,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            isFull
                ? 'Journée complète — aucun créneau libre'
                : '$available créneau${available > 1 ? 'x' : ''} disponible${available > 1 ? 's' : ''} sur $total',
            style: TextStyle(
              color: isFull ? Colors.orange.shade800 : widget.primaryGreen,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGapSeparator(DateTime gapStart, DateTime gapEnd, int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final label = h > 0
        ? (m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h')
        : '${m}min';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.coffee_rounded,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Column(
                  children: [
                    Text(
                      'Pause · $label',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '${_timeFmt.format(gapStart)} → ${_timeFmt.format(gapEnd)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
        ],
      ),
    );
  }

  // ── Carte créneau ─────────────────────────────────────────────

  Widget _buildSlotCard(QueryDocumentSnapshot slotDoc) {
    final data = slotDoc.data() as Map<String, dynamic>;
    final start = (data['start'] as Timestamp).toDate().toLocal();
    final end = (data['end'] as Timestamp).toDate().toLocal();
    final capacity = (data['capacity'] ?? 1) as int;
    final reserved = (data['reserved'] ?? 0) as int;
    final status = (data['status'] ?? 'open') as String;
    final timeSlotId = (data['timeSlotId'] ?? '') as String;
    final maxResPerPerson =
        (data['maxReservationsPerPerson'] as int?) ??
        kDefaultMaxReservationsPerPerson;

    final remaining = capacity - reserved;
    final isFull = remaining <= 0;
    final isAvailable = status == 'open' && remaining > 0;
    final fillRatio = capacity > 0 ? reserved / capacity : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAvailable
              ? widget.primaryGreen.withOpacity(0.25)
              : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isAvailable
              ? () => _onSlotTap(
                  slotDoc: slotDoc,
                  start: start,
                  end: end,
                  timeSlotId: timeSlotId,
                  maxResPerPerson: maxResPerPerson,
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: isAvailable
                            ? widget.lightGreen.withOpacity(0.25)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.schedule_rounded,
                        color: isAvailable
                            ? widget.primaryGreen
                            : Colors.grey.shade400,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.people_alt_rounded,
                                size: 13,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isFull
                                    ? 'Complet ($capacity/$capacity)'
                                    : '$remaining place${remaining > 1 ? 's' : ''} libre${remaining > 1 ? 's' : ''} · $reserved/$capacity',
                                style: TextStyle(
                                  color: isFull
                                      ? Colors.red.shade400
                                      : Colors.grey.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // CTA
                    if (isFull)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          'Complet',
                          style: TextStyle(
                            color: Colors.red.shade500,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (isAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: widget.primaryGreen,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: widget.primaryGreen.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Réserver',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.grey.shade300,
                        size: 20,
                      ),
                  ],
                ),
                if (capacity > 1 && !isFull) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fillRatio,
                      minHeight: 4,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        fillRatio > 0.75
                            ? Colors.orange.shade400
                            : widget.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Logique de tap sur un créneau ─────────────────────────────

  Future<void> _onSlotTap({
    required QueryDocumentSnapshot slotDoc,
    required DateTime start,
    required DateTime end,
    required String timeSlotId,
    required int maxResPerPerson,
  }) async {
    // 1. Vérifier les règles côté UI
    final result = await _rulesService.checkCanReserve(
      companyId: widget.entrepriseId,
      queueId: widget.queueId,
      timeSlotId: timeSlotId,
      slotStart: start,
      slotEnd: end,
      maxActivePerUser: _maxActivePerUser,
      maxReservationsPerPerson: maxResPerPerson,
    );

    if (!mounted) return;

    if (result.canReserve) {
      // Pas de conflit → dialog confirmation standard
      _showConfirmDialog(
        slotDoc: slotDoc,
        start: start,
        end: end,
        timeSlotId: timeSlotId,
      );
      return;
    }

    // Violation détectée
    switch (result.violation!) {
      case RuleViolation.activeInSameQueue:
        // Proposer remplacement
        _showReplaceDialog(
          slotDoc: slotDoc,
          newStart: start,
          newEnd: end,
          timeSlotId: timeSlotId,
          existingRes: result.conflictingReservation!,
        );
        break;

      case RuleViolation.activeInSameCompany:
        // maxActivePerUser = 1 → remplacement aussi
        _showReplaceDialog(
          slotDoc: slotDoc,
          newStart: start,
          newEnd: end,
          timeSlotId: timeSlotId,
          existingRes: result.conflictingReservation!,
        );
        break;

      default:
        // Tous les autres cas → message bloquant
        final message = ReservationRulesService.violationMessage(
          result.violation!,
          conflictData: result.conflictingReservation != null
              ? result.conflictingReservation!.data() as Map<String, dynamic>
              : null,
        );
        _showBlockedSnackbar(message);
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────

  Future<void> _showConfirmDialog({
    required QueryDocumentSnapshot slotDoc,
    required DateTime start,
    required DateTime end,
    required String timeSlotId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // En-tête
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: widget.primaryGreen.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: widget.primaryGreen.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.event_available_rounded,
                      color: widget.primaryGreen,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confirmer la réservation',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _detailRow(Icons.queue_rounded, 'File', widget.queueName),
                  const SizedBox(height: 10),
                  _detailRow(
                    Icons.schedule_rounded,
                    'Heure',
                    '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    Icons.calendar_month_rounded,
                    'Date',
                    _dateFmtFull.format(start),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.blue.shade600,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Vous recevrez des rappels et pourrez annuler depuis vos réservations.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Annuler',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryGreen,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Confirmer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _doReserve(
        slotDoc: slotDoc,
        start: start,
        end: end,
        timeSlotId: timeSlotId,
      );
    }
  }

  Future<void> _showReplaceDialog({
    required QueryDocumentSnapshot slotDoc,
    required DateTime newStart,
    required DateTime newEnd,
    required String timeSlotId,
    required DocumentSnapshot existingRes,
  }) async {
    final existingData = existingRes.data() as Map<String, dynamic>;
    final existingStart = (existingData['slotStart'] as Timestamp)
        .toDate()
        .toLocal();
    final existingEnd = (existingData['slotEnd'] as Timestamp)
        .toDate()
        .toLocal();
    final existingQueue = existingData['queueName'] ?? 'File';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // En-tête orange
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: Colors.orange.shade700,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Remplacer votre créneau ?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Créneau actuel
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_circle_outline_rounded,
                          color: Colors.red.shade400,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Actuel · $existingQueue',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade400,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${_timeFmt.format(existingStart)} – ${_timeFmt.format(existingEnd)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    Icons.arrow_downward_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                  const SizedBox(height: 8),
                  // Nouveau créneau
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.primaryGreen.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: widget.primaryGreen.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: widget.primaryGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nouveau · ${widget.queueName}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${_timeFmt.format(newStart)} – ${_timeFmt.format(newEnd)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Votre réservation actuelle sera annulée automatiquement.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Non', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryGreen,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Confirmer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _doReplace(
        slotDoc: slotDoc,
        newStart: newStart,
        newEnd: newEnd,
        timeSlotId: timeSlotId,
        existingRes: existingRes,
        existingData: existingData,
      );
    }
  }

  // ── Exécution des transactions ────────────────────────────────

  Future<void> _doReserve({
    required QueryDocumentSnapshot slotDoc,
    required DateTime start,
    required DateTime end,
    required String timeSlotId,
  }) async {
    try {
      _showLoadingSnackbar();

      final reservationId = await _rulesService.reserveSlot(
        companyId: widget.entrepriseId,
        queueId: widget.queueId,
        timeSlotId: timeSlotId,
        slotDocId: slotDoc.id,
        slotStart: start,
        slotEnd: end,
        maxActivePerUser: _maxActivePerUser,
        maxReservationsPerPerson: kDefaultMaxReservationsPerPerson,
      );

      await NotificationService().cancelAll();
      await NotificationService().scheduleReservationNotifications(
        waitMinutes: 180,
        slotDurationMinutes: 15,
        reservationId: reservationId,
        companyId: widget.entrepriseId,
        queueId: widget.queueId,
        slotId: slotDoc.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSuccessSnackbar('Réservation confirmée !');
        widget.onReservationSuccess();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showErrorSnackbar('$e');
      }
    }
  }

  Future<void> _doReplace({
    required QueryDocumentSnapshot slotDoc,
    required DateTime newStart,
    required DateTime newEnd,
    required String timeSlotId,
    required DocumentSnapshot existingRes,
    required Map<String, dynamic> existingData,
  }) async {
    try {
      _showLoadingSnackbar();

      final newResId = await _rulesService.replaceReservation(
        oldReservationId: existingRes.id,
        oldCompanyId: existingData['companyId'] as String,
        oldSlotDocId: existingData['slotId'] as String,
        oldQueueId: existingData['queueId'] as String,
        newCompanyId: widget.entrepriseId,
        newQueueId: widget.queueId,
        newTimeSlotId: timeSlotId,
        newSlotDocId: slotDoc.id,
        newSlotStart: newStart,
        newSlotEnd: newEnd,
      );

      await NotificationService().cancelAll();
      await NotificationService().scheduleReservationNotifications(
        waitMinutes: 180,
        slotDurationMinutes: 15,
        reservationId: newResId,
        companyId: widget.entrepriseId,
        queueId: widget.queueId,
        slotId: slotDoc.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSuccessSnackbar('Créneau remplacé avec succès !');
        widget.onReservationSuccess();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showErrorSnackbar('$e');
      }
    }
  }

  // ── Snackbars ─────────────────────────────────────────────────

  void _showLoadingSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Réservation en cours...'),
          ],
        ),
        backgroundColor: widget.primaryGreen,
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: widget.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showBlockedSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur : $message'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Widgets utilitaires ───────────────────────────────────────

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Text(
          '$label : ',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF1A1A2E),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required bool noSlots}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                noSlots
                    ? Icons.event_busy_rounded
                    : Icons.calendar_today_rounded,
                size: 52,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              noSlots ? 'Aucun créneau disponible' : 'Aucun créneau ce jour-là',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              noSlots
                  ? 'Vérifiez plus tard ou contactez l\'établissement'
                  : 'Utilisez les flèches pour naviguer vers un autre jour',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
