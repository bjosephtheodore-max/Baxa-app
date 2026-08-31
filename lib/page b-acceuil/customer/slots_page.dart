import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:baxa/page%20b-acceuil/customer/signine_page.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/reservation_rules_service.dart';

class SlotsPage extends StatefulWidget {
  final String entrepriseId;
  final String entrepriseNom;
  final String queueId;
  final String queueName;
  final Color primaryGreen;
  final Color lightGreen;
  final VoidCallback onReservationSuccess;

  const SlotsPage({
    super.key,
    required this.entrepriseId,
    this.entrepriseNom = '',
    required this.queueId,
    required this.queueName,
    required this.primaryGreen,
    required this.lightGreen,
    required this.onReservationSuccess,
  });

  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage>
    with SingleTickerProviderStateMixin {
  static const Color _kActiveColor = Color(0xFF16A34A);

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final DateFormat _timeFmt = DateFormat('HH:mm');
  final DateFormat _dateFmtFull = DateFormat('EEEE d MMMM', 'fr_FR');
  final _rulesService = ReservationRulesService();

  DateTime _selectedDate = DateTime.now();
  bool _showPastSlots = false;
  late final AnimationController _pastSlotsCtrl;

  int _maxAdvanceDays = 5;
  List<int> _queueWeekdays = [1, 2, 3, 4, 5, 6, 7];
  DateTime? _reservationCutoffDate;
  DateTime? _closureStart;
  DateTime? _closureEnd;
  bool _configLoaded = false;
  bool _companyDeleted = false;

  // Nom + existence + fermeture de la file : suivis en temps réel (le doc
  // de la file peut être renommé, supprimé ou fermé pendant que le client
  // est sur cette page).
  String? _liveQueueName;
  bool _queueUnavailable = false;
  bool _queueClosed = false;
  DateTime? _queueClosureEnd;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _queueSub;

  String get _displayQueueName => _liveQueueName ?? widget.queueName;

  late Stream<QuerySnapshot> _slotsStream;

  // LOGS TEMPORAIRES DE DIAGNOSTIC — à retirer une fois la cause trouvée.
  late final DateTime _initAt;
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    _initAt = DateTime.now();
    debugPrint(
      '🔎[SLOTS] initState "${widget.entrepriseNom}"/"${widget.queueName}" @ $_initAt',
    );
    _pastSlotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _slotsStream = _buildSlotsStream();
    _queueSub = _fs
        .collection('companies')
        .doc(widget.entrepriseId)
        .collection('queues')
        .doc(widget.queueId)
        .snapshots()
        .listen(
          _onQueueSnapshot,
          onError: (_) {
            if (mounted) setState(() => _configLoaded = true);
          },
        );
    _loadCompanyConfig();
  }

  // ── Suivi temps réel du doc de la file ─────────────────────────
  void _onQueueSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!mounted) return;

    if (!doc.exists) {
      setState(() {
        _queueUnavailable = true;
        _configLoaded = true;
      });
      return;
    }

    final data = doc.data()!;
    final newMaxAdvanceDays = (data['maxAdvanceDays'] as int?) ?? 2;
    final advanceDaysChanged = newMaxAdvanceDays != _maxAdvanceDays;
    final closureStart = (data['closureStart'] as Timestamp?)?.toDate();
    final closureEnd = (data['closureEnd'] as Timestamp?)?.toDate();
    setState(() {
      _queueUnavailable = false;
      _queueClosed = isQueueClosedNow(closureStart, closureEnd);
      _queueClosureEnd = closureEnd;
      _liveQueueName = data['name'] as String? ?? _liveQueueName;
      _maxAdvanceDays = newMaxAdvanceDays;
      _queueWeekdays =
          (data['weekdays'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          [1, 2, 3, 4, 5, 6, 7];
      _reservationCutoffDate = (data['reservationCutoffDate'] as Timestamp?)
          ?.toDate()
          .toLocal();
      _configLoaded = true;
      if (advanceDaysChanged) {
        _slotsStream = _buildSlotsStream();
      }
    });
  }

  // Recréée uniquement quand _maxAdvanceDays change réellement, pour éviter
  // que le StreamBuilder ne se réabonne (et clignote) à chaque setState.
  Stream<QuerySnapshot> _buildSlotsStream() {
    final now = DateTime.now();
    return _fs
        .collection('companies')
        .doc(widget.entrepriseId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots')
        .where(
          'start',
          isLessThan: Timestamp.fromDate(
            DateTime(
              now.year,
              now.month,
              now.day,
            ).add(Duration(days: _maxAdvanceDays + 1)),
          ),
        )
        .orderBy('start')
        .snapshots();
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _pastSlotsCtrl.dispose();
    super.dispose();
  }

  // La config de la file (nom, maxAdvanceDays, weekdays, cutoff…) est suivie
  // en temps réel par _onQueueSnapshot. Ici on ne lit que le doc entreprise
  // (fermetures, statut supprimé).
  Future<void> _loadCompanyConfig() async {
    try {
      final companyDoc = await _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .get();

      if (!mounted) return;

      if (companyDoc.exists) {
        final cd = companyDoc.data()!;
        setState(() {
          _closureStart = (cd['closureStart'] as Timestamp?)
              ?.toDate()
              .toLocal();
          _closureEnd = (cd['closureEnd'] as Timestamp?)?.toDate().toLocal();
          _companyDeleted = cd['status'] == 'deleted';
        });
      }
    } catch (e) {
      debugPrint(
        '🔎[SLOTS] _loadCompanyConfig erreur "${widget.queueName}" après '
        '${DateTime.now().difference(_initAt).inMilliseconds}ms: $e',
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(DateTime date) {
    final today = _dateOnly(DateTime.now());
    final d = _dateOnly(date);
    if (d == today) return "Aujourd'hui";
    if (d == today.add(const Duration(days: 1))) return 'Demain';
    final raw = DateFormat('EEEE d MMMM', 'fr_FR').format(date);
    return raw[0].toUpperCase() + raw.substring(1);
  }

  String _shortDayLabel(DateTime date) {
    final today = _dateOnly(DateTime.now());
    final d = _dateOnly(date);
    if (d == today) return "Auj.";
    if (d == today.add(const Duration(days: 1))) return 'Dem.';
    final raw = DateFormat('EEE', 'fr_FR').format(date);
    return raw[0].toUpperCase() + raw.substring(1);
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    debugPrint(
      '🔎[SLOTS] build() #$_buildCount "${widget.queueName}" @ '
      '+${DateTime.now().difference(_initAt).inMilliseconds}ms',
    );
    if (_companyDeleted || _queueUnavailable || _queueClosed) {
      final String title;
      final String subtitle;
      final IconData icon;
      if (_companyDeleted) {
        icon = Icons.storefront_outlined;
        title = 'Entreprise indisponible';
        subtitle = 'Cette entreprise n\'est plus disponible sur Baxa';
      } else if (_queueUnavailable) {
        icon = Icons.storefront_outlined;
        title = 'File d\'attente indisponible';
        subtitle = 'Cette file d\'attente n\'existe plus.';
      } else {
        icon = Icons.nightlight_round_outlined;
        title = 'Réservations fermées';
        // closureEnd est stocké à la veille de la réouverture (23:59:59).
        final reopen = _queueClosureEnd?.add(const Duration(seconds: 1));
        subtitle = (reopen != null && reopen.isAfter(DateTime.now()))
            ? 'Cette file rouvre le ${_dateFmtFull.format(reopen)}.'
            : 'Cette file ne prend pas de nouvelles réservations pour le moment.';
      }
      return Scaffold(
        backgroundColor: const Color(0xFFF8F7F4),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: BackButton(
            color: const Color(0xFF1A1C2E),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _buildStateView(
          icon: icon,
          iconColor: Colors.grey.shade400,
          bgColor: Colors.grey.shade100,
          title: title,
          subtitle: subtitle,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),
      body: StreamBuilder<QuerySnapshot>(
        stream: _slotsStream,
        builder: (context, snapshot) {
          // LOG TEMPORAIRE DE DIAGNOSTIC — à retirer une fois la cause trouvée.
          if (snapshot.hasData) {
            final changes = snapshot.data!.docChanges;
            debugPrint(
              '🔎[SLOTS-STREAM] "${widget.queueName}" snapshot @ '
              '+${DateTime.now().difference(_initAt).inMilliseconds}ms — '
              'docs=${snapshot.data!.docs.length}, '
              'fromCache=${snapshot.data!.metadata.isFromCache}, '
              'changes=${changes.length}'
              '${changes.isNotEmpty ? ' [${changes.map((c) => '${c.type.name}:${c.doc.id}').join(', ')}]' : ''}',
            );
          }
          final now = DateTime.now();
          List<QueryDocumentSnapshot> allFutureSlots = [];
          List<DateTime> availableDays = [];

          if (snapshot.hasData) {
            allFutureSlots = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final start = (data['start'] as Timestamp).toDate().toLocal();
              final end = (data['end'] as Timestamp).toDate().toLocal();
              final deadlineMinutes =
                  (data['reservationDeadlineMinutes'] as int?) ?? 0;
              return end.isAfter(now) &&
                  start.isAfter(now.add(Duration(minutes: deadlineMinutes)));
            }).toList();
          }

          if (_configLoaded) {
            final today = _dateOnly(now);
            for (int i = 0; i <= _maxAdvanceDays; i++) {
              availableDays.add(today.add(Duration(days: i)));
            }
            if (!availableDays.any((d) => _isSameDay(d, _selectedDate))) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _selectedDate = availableDays.first);
                }
              });
            }
          }

          final allDailySlots = snapshot.hasData
              ? snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final start = (data['start'] as Timestamp).toDate().toLocal();
                  return _isSameDay(start, _selectedDate);
                }).toList()
              : <QueryDocumentSnapshot>[];

          final futureDailySlots = allFutureSlots.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final start = (data['start'] as Timestamp).toDate().toLocal();
            return _isSameDay(start, _selectedDate);
          }).toList();

          final Map<String, int> dayAvailableCounts = {};
          for (final doc in allFutureSlots) {
            final data = doc.data() as Map<String, dynamic>;
            final start = (data['start'] as Timestamp).toDate().toLocal();
            final capacity = (data['capacity'] ?? 1) as int;
            final reserved = (data['reserved'] ?? 0) as int;
            final status = (data['status'] ?? 'open') as String;
            if (status == 'open' && capacity - reserved > 0) {
              final key = _dateOnly(start).toIso8601String();
              dayAvailableCounts[key] = (dayAvailableCounts[key] ?? 0) + 1;
            }
          }

          final isClosedDay = !_queueWeekdays.contains(_selectedDate.weekday);
          final isCutoffDay =
              _reservationCutoffDate != null &&
              _dateOnly(
                _selectedDate,
              ).isAfter(_dateOnly(_reservationCutoffDate!));
          final selectedDay = _dateOnly(_selectedDate);
          final isClosurePeriodDay =
              _closureStart != null &&
              _closureEnd != null &&
              !selectedDay.isBefore(_dateOnly(_closureStart!)) &&
              !selectedDay.isAfter(_dateOnly(_closureEnd!));

          Widget content;
          if (snapshot.connectionState == ConnectionState.waiting ||
              !_configLoaded) {
            content = Center(
              child: CircularProgressIndicator(color: widget.primaryGreen),
            );
          } else if (isClosurePeriodDay) {
            content = _buildClosurePeriodDayState();
          } else if (isCutoffDay) {
            content = _buildCutoffDayState();
          } else if (isClosedDay) {
            content = _buildClosedDayState();
          } else if (allDailySlots.isEmpty) {
            content = _buildEmptyState(noSlots: allFutureSlots.isEmpty);
          } else {
            content = _buildSlotList(allDailySlots);
          }

          return Column(
            children: [
              _buildUnifiedHeader(
                availableDays: availableDays,
                isClosurePeriodDay: isClosurePeriodDay,
                isClosedDay: isClosedDay,
                availableCount:
                    (!isClosurePeriodDay &&
                        !isCutoffDay &&
                        !isClosedDay &&
                        snapshot.hasData)
                    ? futureDailySlots.length
                    : -1,
                totalCount: allDailySlots.length,
                dayAvailableCounts: dayAvailableCounts,
              ),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  // ── Header unifié (titre + navigateur de jours) ───────────────

  Widget _buildUnifiedHeader({
    required List<DateTime> availableDays,
    required bool isClosurePeriodDay,
    required bool isClosedDay,
    int availableCount = -1,
    int totalCount = 0,
    required Map<String, int> dayAvailableCounts,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ligne 1 : retour · nom de la file · badge
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
              child: Row(
                children: [
                  BackButton(
                    color: const Color(0xFF1A1C2E),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _displayQueueName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1C2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.entrepriseNom.isNotEmpty)
                          Text(
                            widget.entrepriseNom,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (availableCount >= 0) ...[
                    const SizedBox(width: 8),
                    _buildSlotBadge(availableCount, totalCount),
                  ],
                ],
              ),
            ),
            // Ligne 2 : carousel de jours
            if (availableDays.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: availableDays.length,
                  itemBuilder: (context, i) {
                    final day = availableDays[i];
                    final isSelected = _isSameDay(day, _selectedDate);
                    final isClosedChip = !_queueWeekdays.contains(day.weekday);
                    final key = _dateOnly(day).toIso8601String();
                    final count = dayAvailableCounts[key] ?? 0;

                    final Color chipBg = isSelected
                        ? _kActiveColor
                        : Colors.transparent;
                    final Color chipBorder = isSelected
                        ? _kActiveColor
                        : Colors.grey.shade200;
                    final Color labelColor = isSelected
                        ? Colors.white
                        : isClosedChip
                        ? Colors.grey.shade300
                        : const Color(0xFF1A1C2E);
                    final Color countColor = isSelected
                        ? Colors.white.withValues(alpha: 0.85)
                        : count > 0
                        ? _kActiveColor
                        : Colors.grey.shade400;

                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedDate = day;
                        _showPastSlots = false;
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: chipBorder),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _shortDayLabel(day),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: labelColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              count > 0 ? '$count dispo' : '·',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: countColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Liste des créneaux ────────────────────────────────────────

  Widget _buildSlotList(List<QueryDocumentSnapshot> allDailySlots) {
    final now = DateTime.now();
    final pastSlots = <QueryDocumentSnapshot>[];
    final upcomingSlots = <QueryDocumentSnapshot>[];

    for (final doc in allDailySlots) {
      final data = doc.data() as Map<String, dynamic>;
      final start = (data['start'] as Timestamp).toDate().toLocal();
      final deadlineMinutes = (data['reservationDeadlineMinutes'] as int?) ?? 0;
      if (!start.isAfter(now.add(Duration(minutes: deadlineMinutes)))) {
        pastSlots.add(doc);
      } else {
        upcomingSlots.add(doc);
      }
    }

    final items = <Widget>[];

    if (pastSlots.isNotEmpty) {
      items.add(_buildPastSlotsToggle(pastSlots.length));

      final pastWidgets = <Widget>[];
      _appendSlotsWithGaps(pastWidgets, pastSlots);
      if (upcomingSlots.isNotEmpty) {
        pastWidgets.add(const SizedBox(height: 4));
      }

      items.add(
        ClipRect(
          child: SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: _pastSlotsCtrl,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            ),
            axisAlignment: -1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: pastWidgets,
            ),
          ),
        ),
      );
    }

    _appendSlotsWithGaps(items, upcomingSlots);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: items,
    );
  }

  void _appendSlotsWithGaps(
    List<Widget> items,
    List<QueryDocumentSnapshot> slots,
  ) {
    const int gapThreshold = 60;
    for (int i = 0; i < slots.length; i++) {
      if (i > 0) {
        final prevData = slots[i - 1].data() as Map<String, dynamic>;
        final currData = slots[i].data() as Map<String, dynamic>;
        final prevEnd = (prevData['end'] as Timestamp).toDate().toLocal();
        final currStart = (currData['start'] as Timestamp).toDate().toLocal();
        final gap = currStart.difference(prevEnd).inMinutes;
        if (gap >= gapThreshold) {
          items.add(_buildGapSeparator(prevEnd, currStart, gap));
        }
      }
      items.add(_buildSlotCard(slots[i]));
    }
  }

  Widget _buildPastSlotsToggle(int count) {
    return GestureDetector(
      onTap: () {
        setState(() => _showPastSlots = !_showPastSlots);
        if (_showPastSlots) {
          _pastSlotsCtrl.forward();
        } else {
          _pastSlotsCtrl.reverse();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(
              _showPastSlots
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Text(
              _showPastSlots
                  ? 'Masquer les créneaux passés'
                  : '$count créneau${count > 1 ? 'x' : ''} passé${count > 1 ? 's' : ''}',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (!_showPastSlots)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotBadge(int available, int total, {bool onColor = false}) {
    if (total == 0) return const SizedBox.shrink();

    final isEndOfDay =
        available == 0 &&
        total > 0 &&
        _isSameDay(_selectedDate, DateTime.now());
    final isFull = available == 0 && !isEndOfDay;

    if (isEndOfDay) {
      return Text(
        'Fin de journée',
        style: TextStyle(
          color: onColor
              ? Colors.white.withValues(alpha: 0.65)
              : Colors.grey.shade400,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (isFull) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: onColor
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6),
          border: onColor
              ? Border.all(color: Colors.white.withValues(alpha: 0.3))
              : Border.all(color: Colors.orange.shade200),
        ),
        child: Text(
          'Complet',
          style: TextStyle(
            color: onColor ? Colors.white : Colors.orange.shade700,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onColor
            ? Colors.white.withValues(alpha: 0.2)
            : _kActiveColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$available libre${available > 1 ? 's' : ''}',
        style: TextStyle(
          color: onColor ? Colors.white : _kActiveColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
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
                  size: 13,
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

    final deadlineMinutes = (data['reservationDeadlineMinutes'] as int?) ?? 0;
    final now = DateTime.now();
    final isPast = !start.isAfter(now.add(Duration(minutes: deadlineMinutes)));
    final remaining = capacity - reserved;
    final isFull = remaining <= 0;
    final isAvailable = status == 'open' && remaining > 0 && !isPast;
    final fillRatio = capacity > 0 ? reserved / capacity : 1.0;

    final Color leftBorderColor = isAvailable
        ? _kActiveColor
        : isPast
        ? Colors.grey.shade200
        : Colors.grey.shade300;

    final Color cardBg = isAvailable
        ? _kActiveColor.withValues(alpha: 0.08)
        : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 7, color: leftBorderColor),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isAvailable
                      ? () => _onSlotTap(
                          slotDoc: slotDoc,
                          start: start,
                          end: end,
                          timeSlotId: timeSlotId,
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: isPast
                                          ? Colors.grey.shade400
                                          : const Color(0xFF1A1A2E),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    isPast
                                        ? 'Créneau passé'
                                        : isFull
                                        ? '$capacity places · Complet'
                                        : '$remaining place${remaining > 1 ? 's' : ''} libre${remaining > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isPast)
                              Icon(
                                Icons.history_rounded,
                                color: Colors.grey.shade300,
                                size: 18,
                              )
                            else if (isFull)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: Text(
                                  'Complet',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else if (isAvailable)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: _kActiveColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Réserver',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.grey.shade300,
                                size: 18,
                              ),
                          ],
                        ),
                        if (capacity > 1 && !isFull && !isPast) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: fillRatio,
                              minHeight: 3,
                              backgroundColor: reserved > 0
                                  ? Colors.grey.shade100
                                  : Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                reserved == 0
                                    ? Colors.transparent
                                    : fillRatio > 0.75
                                    ? Colors.orange.shade400
                                    : _kActiveColor.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                        ],
                      ],
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

  // ── Logique de tap ────────────────────────────────────────────

  Future<void> _onSlotTap({
    required QueryDocumentSnapshot slotDoc,
    required DateTime start,
    required DateTime end,
    required String timeSlotId,
  }) async {
    final result = await _rulesService.checkCanReserve(
      companyId: widget.entrepriseId,
      queueId: widget.queueId,
      timeSlotId: timeSlotId,
      slotStart: start,
      slotEnd: end,
    );

    if (!mounted) return;

    if (result.canReserve) {
      _showConfirmDialog(
        slotDoc: slotDoc,
        start: start,
        end: end,
        timeSlotId: timeSlotId,
      );
      return;
    }

    switch (result.violation!) {
      case RuleViolation.activeInSameQueue:
        final conflict = result.conflictingReservation!;
        final conflictStart =
            ((conflict.data() as Map<String, dynamic>)['slotStart']
                    as Timestamp)
                .toDate();
        // On ne propose "remplacer" que pour un rendez-vous pas encore
        // commencé — remplacer un créneau déjà en cours n'a pas de sens.
        if (conflictStart.isAfter(DateTime.now())) {
          _showReplaceDialog(
            slotDoc: slotDoc,
            newStart: start,
            newEnd: end,
            timeSlotId: timeSlotId,
            existingRes: conflict,
          );
        } else {
          _showBlockedSnackbar(
            'Vous avez déjà un rendez-vous en cours. Attendez qu\'il se '
            'termine avant d\'en réserver un autre.',
          );
        }
        break;
      case RuleViolation.globalLimitReached:
        _showDailyLimitSheet();
        break;
      default:
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

  void _showDailyLimitSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_busy_rounded,
                color: Colors.orange.shade600,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Limite journalière atteinte',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Vous avez effectué vos 5 réservations du jour. Cette limite garantit un accès équitable à tous les utilisateurs de Baxa. Votre quota sera automatiquement rechargé demain.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.lightGreen.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    color: widget.primaryGreen,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Besoin d\'un créneau supplémentaire aujourd\'hui ? Rendez-vous directement sur place — l\'établissement peut vous enregistrer en quelques secondes via son espace Baxa.',
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.primaryGreen,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Compris',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kActiveColor, Color(0xFF0D6B2A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confirmer la réservation',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _detailRow(Icons.queue_rounded, 'File', _displayQueueName),
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
                      color: _kActiveColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _kActiveColor.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          color: _kActiveColor,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Vous recevrez des rappels et pourrez annuler depuis vos réservations.',
                            style: TextStyle(
                              fontSize: 12,
                              color: _kActiveColor.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kActiveColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Confirmer la réservation',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Annuler',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                              const SizedBox(height: 2),
                              Text(
                                _dayLabel(existingStart),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kActiveColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _kActiveColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: _kActiveColor,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nouveau · $_displayQueueName',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _kActiveColor,
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
                              const SizedBox(height: 2),
                              Text(
                                _dayLabel(newStart),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
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
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kActiveColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Confirmer le remplacement',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Annuler',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  // ── Transactions ──────────────────────────────────────────────

  Future<void> _doReserve({
    required QueryDocumentSnapshot slotDoc,
    required DateTime start,
    required DateTime end,
    required String timeSlotId,
  }) async {
    try {
      _showLoadingSnackbar();

      await _rulesService.reserveSlot(
        companyId: widget.entrepriseId,
        queueId: widget.queueId,
        timeSlotId: timeSlotId,
        slotDocId: slotDoc.id,
        slotStart: start,
        slotEnd: end,
        companyName: widget.entrepriseNom,
        queueName: _displayQueueName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSuccessSnackbar('Réservation confirmée !');
        widget.onReservationSuccess();

        // Widget A : invite à l'inscription (utilisateurs anonymes uniquement)
        bool widgetAShown = false;
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null && fbUser.isAnonymous) {
          final result = await _maybeShowProfilePrompt(fbUser.uid);
          if (!mounted) return;
          widgetAShown = result.shown;
          if (result.wantsSignIn) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SigninePage()),
            );
            if (!mounted) return;
          }
        }

        // Widget B : invite aux favoris (différé si Widget A vient d'apparaître)
        if (mounted) {
          await _maybeShowFavoritePrompt(widgetAShown: widgetAShown);
        }

        // Widget D : rappel du quota journalier (à la 4e réservation du jour)
        if (mounted) {
          await _maybeShowDailyLimitPrompt();
        }

        if (mounted) Navigator.pop(context);
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

      await _rulesService.replaceReservation(
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
        companyName: widget.entrepriseNom,
        queueName: _displayQueueName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSuccessSnackbar('Créneau remplacé avec succès !');
        widget.onReservationSuccess();

        // Widget B : invite aux favoris (pas de conflit Widget A ici)
        if (mounted) {
          await _maybeShowFavoritePrompt(widgetAShown: false);
        }

        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showErrorSnackbar('$e');
      }
    }
  }

  // ── Profile prompt ────────────────────────────────────────────

  Future<({bool shown, bool wantsSignIn})> _maybeShowProfilePrompt(
    String uid,
  ) async {
    try {
      final ref = _fs.collection('users').doc(uid);
      await ref.set({
        'totalReservations': FieldValue.increment(1),
      }, SetOptions(merge: true));
      final snap = await ref.get();
      final total = (snap.data()?['totalReservations'] as int?) ?? 1;
      if (!mounted || (total != 1 && total != 3)) {
        return (shown: false, wantsSignIn: false);
      }
      bool wantsSignIn = false;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        builder: (ctx) => _ProfilePromptSheet(
          onSignIn: () {
            wantsSignIn = true;
            Navigator.pop(ctx);
          },
          onLater: () => Navigator.pop(ctx),
        ),
      );
      return (shown: true, wantsSignIn: wantsSignIn);
    } catch (_) {
      return (shown: false, wantsSignIn: false);
    }
  }

  // ── Invite aux favoris (Widget B) ────────────────────────────

  Future<void> _maybeShowFavoritePrompt({required bool widgetAShown}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final countKey = 'company_res_count_${user.uid}_${widget.entrepriseId}';
    final promptedKey = 'fav_prompted_${user.uid}_${widget.entrepriseId}';

    // Toujours incrémenter le compteur (même si on différera l'affichage)
    final count = (prefs.getInt(countKey) ?? 0) + 1;
    await prefs.setInt(countKey, count);

    // Différé : Widget A vient d'apparaître sur cette réservation
    if (widgetAShown) return;
    // Pas encore 3 réservations dans cette structure
    if (count < 3) return;
    // Prompt déjà montré une fois
    if (prefs.getBool(promptedKey) ?? false) return;

    try {
      // Vérifier si déjà en favoris + récupérer données structure
      final results = await Future.wait([
        _fs
            .collection('users')
            .doc(user.uid)
            .collection('favorites')
            .doc(widget.entrepriseId)
            .get(),
        _fs.collection('companies').doc(widget.entrepriseId).get(),
      ]);

      final favDoc = results[0];
      if (favDoc.exists) return; // Déjà en favoris, inutile de proposer

      final companyData = results[1].data();
      final resolvedNom = widget.entrepriseNom.isNotEmpty
          ? widget.entrepriseNom
          : (companyData?['nom'] as String? ?? '');
      final companyType = companyData?['type'] as String? ?? '';

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        builder: (ctx) => _FavoritePromptSheet(
          onAddFavorite: () async {
            Navigator.pop(ctx);
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser == null) return;

            if (currentUser.isAnonymous) {
              // Widget C : l'utilisateur doit d'abord s'inscrire
              if (!mounted) return;
              await showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isDismissible: true,
                builder: (ctx2) => _RegistrationNeededSheet(
                  onRegister: () {
                    Navigator.pop(ctx2);
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SigninePage()),
                      );
                    }
                  },
                  onLater: () => Navigator.pop(ctx2),
                ),
              );
            } else {
              // Ajout réel aux favoris
              try {
                await _fs
                    .collection('users')
                    .doc(currentUser.uid)
                    .collection('favorites')
                    .doc(widget.entrepriseId)
                    .set({
                      'nom': resolvedNom,
                      'type': companyType,
                      'companyId': widget.entrepriseId,
                      'addedAt': FieldValue.serverTimestamp(),
                    });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text('Ajouté aux favoris'),
                        ],
                      ),
                      backgroundColor: widget.primaryGreen,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              } catch (_) {}
            }
          },
          onDismiss: () => Navigator.pop(ctx),
        ),
      );

      // Marquer comme montré (qu'il ait ajouté ou annulé)
      await prefs.setBool(promptedKey, true);
    } catch (_) {}
  }

  // ── Rappel du quota journalier (Widget D) ─────────────────────

  Future<void> _maybeShowDailyLimitPrompt() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final ref = _fs.collection('users').doc(user.uid);
      final snap = await ref.get();
      final data = snap.data() ?? {};

      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final lastDate = data['lastBookingDate'] as String? ?? '';
      final dailyCount = lastDate == todayStr
          ? (data['dailyBookingCount'] as int? ?? 0)
          : 0;

      // Affiché une seule fois, quand il reste exactement 1 réservation
      if (dailyCount != kMaxDailyReservations - 1) return;

      final shownCount = (data['dailyLimitPromptShownCount'] as int?) ?? 0;
      if (shownCount >= 2) return;

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        builder: (ctx) =>
            _DailyLimitPromptSheet(onOk: () => Navigator.pop(ctx)),
      );

      await ref.set({
        'dailyLimitPromptShownCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── Snackbars ─────────────────────────────────────────────────

  void _showLoadingSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
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

  // ── Utilitaires ───────────────────────────────────────────────

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

  // ── États vides ───────────────────────────────────────────────

  Widget _buildClosurePeriodDayState() {
    // _closureEnd est stocké à la veille de la réouverture (23:59:59).
    final end = _closureEnd!.add(const Duration(seconds: 1));
    final dd = end.day.toString().padLeft(2, '0');
    final mm = end.month.toString().padLeft(2, '0');
    return _buildStateView(
      icon: Icons.block_rounded,
      iconColor: Colors.red.shade400,
      bgColor: Colors.red.shade50,
      title: 'Fermeture temporaire',
      subtitle:
          'L\'établissement est fermé ce jour-là.\nRéouverture prévue le $dd/$mm/${end.year}.',
    );
  }

  Widget _buildCutoffDayState() {
    final cutoff = _reservationCutoffDate!;
    final dd = cutoff.day.toString().padLeft(2, '0');
    final mm = cutoff.month.toString().padLeft(2, '0');
    return _buildStateView(
      icon: Icons.event_busy_rounded,
      iconColor: Colors.orange.shade400,
      bgColor: Colors.orange.shade50,
      title: 'Réservations fermées',
      subtitle:
          'Les réservations pour cette file sont\nacceptées jusqu\'au $dd/$mm/${cutoff.year} uniquement.',
    );
  }

  Widget _buildClosedDayState() {
    return _buildStateView(
      icon: Icons.storefront_outlined,
      iconColor: Colors.grey.shade400,
      bgColor: Colors.grey.shade100,
      title: 'Établissement fermé',
      subtitle:
          "L'établissement n'est pas ouvert ce jour-là.\nChoisissez un autre jour.",
    );
  }

  Widget _buildEmptyState({required bool noSlots}) {
    return _buildStateView(
      icon: noSlots ? Icons.event_busy_rounded : Icons.calendar_today_rounded,
      iconColor: Colors.grey.shade400,
      bgColor: Colors.grey.shade100,
      title: noSlots ? 'Aucun créneau disponible' : 'Aucun créneau ce jour-là',
      subtitle: noSlots
          ? 'Vérifiez plus tard ou contactez l\'établissement'
          : 'Utilisez les flèches pour naviguer vers un autre jour',
    );
  }

  Widget _buildStateView({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
              child: Icon(icon, size: 52, color: iconColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet : invitation à créer un compte ───────────────────────────────

class _ProfilePromptSheet extends StatelessWidget {
  final VoidCallback onSignIn;
  final VoidCallback onLater;

  const _ProfilePromptSheet({required this.onSignIn, required this.onLater});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4B8B5E);
    final bottomPadding = 16.0 + MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5ED),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined, color: green, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'Sécurisez vos réservations',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez votre compte gratuit en deux clics\npour ne pas perdre vos réservations.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Créer mon compte',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onLater,
            child: Text(
              'Plus tard',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget B : invite à ajouter la structure aux favoris ─────────────────────

class _FavoritePromptSheet extends StatelessWidget {
  final VoidCallback onAddFavorite;
  final VoidCallback onDismiss;

  const _FavoritePromptSheet({
    required this.onAddFavorite,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4B8B5E);
    final bottomPadding = 16.0 + MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.star_rounded,
              color: Colors.amber.shade500,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Ajoutez à vos favoris !',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez cette structure à vos favoris pour\npouvoir réserver depuis votre page d\'accueil.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDismiss,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Annuler',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onAddFavorite,
                  icon: const Icon(
                    Icons.star_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  label: const Text(
                    'Ajouter',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Widget C : inscription requise pour accéder aux favoris ──────────────────

class _RegistrationNeededSheet extends StatelessWidget {
  final VoidCallback onRegister;
  final VoidCallback onLater;

  const _RegistrationNeededSheet({
    required this.onRegister,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4B8B5E);
    final bottomPadding = 16.0 + MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5ED),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: green,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Terminez votre inscription',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pour ajouter des favoris et réserver\ndepuis votre page d\'accueil, créez\nvotre compte gratuit en deux clics.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Terminer l\'inscription',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onLater,
            child: Text(
              'Plus tard',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget D : rappel du quota journalier ─────────────────────────────────

class _DailyLimitPromptSheet extends StatelessWidget {
  final VoidCallback onOk;

  const _DailyLimitPromptSheet({required this.onOk});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4B8B5E);
    final bottomPadding = 16.0 + MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.info_rounded,
              color: Colors.amber.shade600,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Plus qu\'une réservation aujourd\'hui',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Vous pouvez effectuer jusqu\'à $kMaxDailyReservations réservations par jour. '
            'Vous en avez déjà utilisé ${kMaxDailyReservations - 1} — il ne vous en reste qu\'une.\n\n'
            'Une fois ce quota atteint, vous pourrez toujours vous rendre directement dans l\'établissement pour vous inscrire sur place.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onOk,
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Ok',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
