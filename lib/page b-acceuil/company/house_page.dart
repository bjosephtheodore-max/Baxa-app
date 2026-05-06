import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/agenda_service.dart';
import 'package:baxa/page b-acceuil/company/settings_page.dart';
import 'package:baxa/page b-acceuil/company/team_page.dart';
import 'package:baxa/main.dart' show routeObserver;

part 'house_widgets.dart';
part 'house_dialogs.dart';
part 'house_notifier.dart';

// ── Palette (niveau bibliothèque — accessible dans tous les parts) ────────────
const Color _green = Color.fromARGB(255, 75, 139, 94);
const Color _lightGreen = Color.fromARGB(255, 178, 211, 194);

// ============================================================
// HOUSE PAGE — AGENDA INTERACTIF DE L'ENTREPRISE
// ============================================================
class HousePage extends StatefulWidget {
  const HousePage({super.key});
  @override
  State<HousePage> createState() => _HousePageState();
}

class _HousePageState extends State<HousePage>
    with AutomaticKeepAliveClientMixin, RouteAware {
  // ── Notifier (état + Firestore) ───────────────────────────
  late final _HouseNotifier _n;

  // ── Formatters ────────────────────────────────────────────
  final DateFormat _dateFormat = DateFormat('EEEE d MMM yyyy', 'fr_FR');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  // ── Contrôleurs UI (restent dans le widget) ───────────────
  late PageController _pageController;
  final Map<String, ScrollController> _scrollControllers = {};
  bool _quickAddLoading = false;

  @override
  bool get wantKeepAlive => true;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _n = _HouseNotifier();
    _pageController = PageController(viewportFraction: 0.88);
    _n.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void didPopNext() => _n.refreshSilent();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _n.dispose();
    _pageController.dispose();
    for (final sc in _scrollControllers.values) {
      sc.dispose();
    }
    super.dispose();
  }

  // ── Scroll infini : un controller par file ────────────────
  ScrollController _scrollControllerFor(String queueId) {
    return _scrollControllers.putIfAbsent(queueId, () {
      final sc = ScrollController();
      sc.addListener(() {
        if (sc.position.pixels >= sc.position.maxScrollExtent - 200) {
          _n.loadMoreSlots(queueId);
        }
      });
      return sc;
    });
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: _n,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: _buildAppBar(),
        body: _n.isLoading
            ? const Center(child: CircularProgressIndicator(color: _green))
            : _n.loadFailed
            ? _buildRetryState()
            : !_n.hasQueues
            ? _buildEmptyState()
            : Column(
                children: [
                  _buildDateBar(),
                  Expanded(child: _buildAgendaBody()),
                ],
              ),
        floatingActionButton: _n.hasQueues
            ? FloatingActionButton(
                onPressed: _quickAddLoading ? null : _showQuickAddDialog,
                backgroundColor: _green,
                child: _quickAddLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Icon(Icons.add, color: Colors.white),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      automaticallyImplyLeading: false,
      toolbarHeight: 48,
      title: Row(
        children: [
          Text(
            'Baxa',
            style: GoogleFonts.poppins(
              color: _green,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (_n.companyName.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(width: 1, height: 16, color: Colors.grey.shade300),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _n.companyName,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_n.isStaff)
          IconButton(
            icon: const Icon(Icons.group_rounded, color: _green),
            tooltip: 'Mon équipe',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TeamPage()),
            ),
          ),
      ],
    );
  }

  // ── Barre de date ─────────────────────────────────────────
  Widget _buildDateBar() {
    final now = DateTime.now();
    final isToday = _n.selectedDate.year == now.year &&
        _n.selectedDate.month == now.month &&
        _n.selectedDate.day == now.day;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _n.changeDate(-1),
            icon: const Icon(Icons.chevron_left, color: _green),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isToday ? _green.withValues(alpha: 0.08) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isToday ? _green : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: isToday ? _green : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _dateFormat.format(_n.selectedDate),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isToday ? _green : Colors.black87,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Auj.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _n.changeDate(1),
            icon: const Icon(Icons.chevron_right, color: _green),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── Corps de l'agenda ─────────────────────────────────────
  Widget _buildAgendaBody() {
    if (_n.queues.isEmpty) {
      return Center(
        child: Text(
          'Aucun créneau pour cette date',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    if (_n.queues.length == 1) return _buildQueueOrLoader(0);

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _n.queues.length,
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _buildQueueOrLoader(index),
            ),
          ),
        ),
        _buildPageIndicators(),
      ],
    );
  }

  Widget _buildQueueOrLoader(int index) {
    final queue = index < _n.queues.length ? _n.queues[index] : null;
    return queue == null ? const _QueueSkeleton() : _buildQueueView(queue);
  }

  // AnimatedBuilder sur le PageController : pas de setState pour les dots
  Widget _buildPageIndicators() {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) {
        final current = _pageController.hasClients
            ? (_pageController.page ?? 0).round()
            : 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 24, top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_n.queues.length, (i) {
              final isActive = i == current;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? _green : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildRetryState() => _RetryState(onRetry: _n.refreshSilent);

  Widget _buildEmptyState() => _EmptyState(
    onCreateQueue: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsPage(autoOpenCreateDialog: true),
        ),
      );
      // Le stream détecte la création de file automatiquement.
      // initialize() causerait un double-init avec _isLoading bloqué.
      if (mounted) _n.refreshSilent();
    },
  );

  // ── Vue complète d'une file ───────────────────────────────
  Widget _buildQueueView(_QueueAgenda queue) {
    final slotsForQueue = queue.slots.toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final plageOrder = <String, int>{};
    for (final s in slotsForQueue) {
      if (s.timeSlotId.isNotEmpty && !plageOrder.containsKey(s.timeSlotId)) {
        plageOrder[s.timeSlotId] = plageOrder.length + 1;
      }
    }
    final hasMultiplePlages = plageOrder.length >= 2;

    final slotWidgets = <Widget>[];
    for (int i = 0; i < slotsForQueue.length; i++) {
      final current = slotsForQueue[i];

      if (i > 0 && hasMultiplePlages && current.timeSlotId.isNotEmpty) {
        final prev = slotsForQueue[i - 1];
        if (prev.timeSlotId != current.timeSlotId) {
          slotWidgets.add(
            _PlageSeparator(
              plageNumber: plageOrder[current.timeSlotId]!,
              startTime: current.start,
              timeFormat: _timeFormat,
            ),
          );
        }
      }

      slotWidgets.add(
        _SlotCard(
          slot: current,
          timeFormat: _timeFormat,
          onTap: () => _showSlotDetails(current, queue),
        ),
      );

      if (i < slotsForQueue.length - 1) {
        final next = slotsForQueue[i + 1];
        final sameTimeslot = current.timeSlotId.isNotEmpty &&
            current.timeSlotId == next.timeSlotId;
        if (sameTimeslot) {
          final gap = next.start.difference(current.end);
          if (gap.inMinutes > 0) {
            slotWidgets.add(
              _TimeslotSeparator(
                endTime: current.end,
                startTime: next.start,
                timeFormat: _timeFormat,
              ),
            );
          }
        }
      }
    }

    final isWorkingDay = queue.weekdays.isEmpty ||
        queue.weekdays.contains(_n.selectedDate.weekday);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(
      _n.selectedDate.year,
      _n.selectedDate.month,
      _n.selectedDate.day,
    );
    final isToday = selectedDay == today;
    final isDayOver = isToday && isWorkingDay;
    final isBeyondHorizon = selectedDay.isAfter(today.add(const Duration(days: 7)));
    final isBeforeHistory = selectedDay.isBefore(today.subtract(const Duration(days: 7)));

    return RefreshIndicator(
      onRefresh: () async => _n.refreshSilent(),
      color: _green,
      displacement: 56,
      child: ListView(
        controller: _scrollControllerFor(queue.id),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _buildQueueHeaderCard(queue),
          const SizedBox(height: 12),

          if (slotsForQueue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    isBeyondHorizon
                        ? Icons.hourglass_empty_rounded
                        : isBeforeHistory
                        ? Icons.history_rounded
                        : !isWorkingDay
                        ? Icons.storefront_outlined
                        : isDayOver
                        ? Icons.nightlight_outlined
                        : Icons.calendar_today_outlined,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isBeyondHorizon
                        ? 'Hors horizon de génération'
                        : isBeforeHistory
                        ? 'Historique expiré'
                        : !isWorkingDay
                        ? 'Fermé ce jour-là'
                        : isDayOver
                        ? 'Journée terminée'
                        : 'Aucun créneau pour cette date',
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isBeyondHorizon
                        ? 'Les créneaux sont générés 7 jours à l\'avance'
                        : isBeforeHistory
                        ? 'L\'historique est conservé 7 jours'
                        : !isWorkingDay
                        ? 'Ce jour n\'est pas dans vos jours ouvrés'
                        : isDayOver
                        ? 'Les créneaux d\'aujourd\'hui sont tous passés'
                        : '',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!isBeyondHorizon && !isBeforeHistory)
                    TextButton.icon(
                      onPressed: isDayOver
                          ? () => _n.changeDate(1)
                          : () => _jumpToNextSlotDate(queue.id),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: Text(
                        isDayOver
                            ? 'Voir demain'
                            : 'Voir les prochains créneaux',
                      ),
                      style: TextButton.styleFrom(foregroundColor: _green),
                    ),
                ],
              ),
            )
          else
            ...slotWidgets,

          const SizedBox(height: 8),
          if (_n.isLoadingMore(queue.id))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                ),
              ),
            )
          else if (!_n.hasMore(queue.id) && slotsForQueue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  '✓ Tous les créneaux affichés',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Carte en-tête de file ─────────────────────────────────
  Widget _buildQueueHeaderCard(_QueueAgenda queue) {
    return _QueueHeaderCard(
      queue: queue,
      currentDuration:
          queue.timeSlotCount == 1 ? _n.currentDuration(queue) : null,
      currentCapacity:
          queue.timeSlotCount == 1 ? _n.currentCapacity(queue) : null,
      onDurationChanged: (delta) => _onDurationChanged(queue, delta),
      onCapacityChanged: (delta) => _onCapacityChanged(queue, delta),
      onBlock: () => _onBlockRequest(queue),
      onUnblock: () => _onUnblock(queue),
    );
  }

  // ── Détail d'un créneau (lazy loading noms) ───────────────
  void _showSlotDetails(AgendaSlot slot, _QueueAgenda queue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SlotDetailDialog(
        slot: slot,
        queue: queue,
        timeFormat: _timeFormat,
        agenda: _n.agenda,
        green: _green,
        onAddClient: (name) => _createManualAppointmentForSlot(name, queue, slot),
      ),
    );
  }

  // ── Navigation de date ────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _n.selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr'),
      helpText: 'Créneaux visibles : J-7 → J+7',
    );
    if (picked != null && picked != _n.selectedDate) _n.setDate(picked);
  }

  Future<void> _jumpToNextSlotDate(String queueId) async {
    final date = await _n.findNextSlotDate(queueId);
    if (!mounted) return;
    if (date != null) {
      _n.setDate(date);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun créneau à venir disponible')),
      );
    }
  }

  // ── Ajout rapide (FAB) — carousel des créneaux disponibles ──
  Future<void> _showQuickAddDialog() async {
    final now = DateTime.now();

    // 1. Trouver la file avec le prochain créneau (depuis la mémoire, rapide)
    _QueueAgenda? bestQueue;
    AgendaSlot? bestSlot;
    for (final queue in _n.queues.whereType<_QueueAgenda>()) {
      if (queue.isBlocked) continue;
      final candidates = queue.slots
          .where((s) =>
              !s.isBlocked && s.reserved < s.capacity && s.start.isAfter(now))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (candidates.isNotEmpty &&
          (bestSlot == null ||
              candidates.first.start.isBefore(bestSlot.start))) {
        bestSlot = candidates.first;
        bestQueue = queue;
      }
    }

    if (bestQueue == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aucune place disponible en ce moment.')),
        );
      }
      return;
    }

    // 2. Requête Firestore pour la liste complète et précise
    if (!mounted) return;
    setState(() => _quickAddLoading = true);
    final List<AgendaSlot> available;
    try {
      available = await _n.fetchAvailableSlots(bestQueue.id);
    } finally {
      if (mounted) setState(() => _quickAddLoading = false);
    }

    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aucune place disponible en ce moment.')),
        );
      }
      return;
    }

    if (!mounted) return;
    final queue = bestQueue;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickAddSheet(
        queue: queue,
        availableSlots: available,
        timeFormat: _timeFormat,
        onConfirm: (name, slot) =>
            _createManualAppointmentForSlot(name, queue, slot),
      ),
    );
  }

  Future<void> _createManualAppointmentForSlot(
    String clientName,
    _QueueAgenda queue,
    AgendaSlot slot,
  ) async {
    final error = await _n.createManualAppointment(clientName, queue, slot);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Client ajouté avec succès'),
      backgroundColor: error != null ? Colors.red.shade600 : null,
    ));
    _n.refreshSilent();
  }

  // ── Blocage ───────────────────────────────────────────────
  Future<void> _onBlockRequest(_QueueAgenda queue) async {
    if (_n.companyId == null) return;
    final timeslots = await _n.fetchTimeSlots(queue.id);
    if (timeslots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun créneau à bloquer')),
        );
      }
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BlockSheet(
        timeslots: timeslots,
        onConfirm: ({required String? timeSlotId, required String reason}) async {
          final error = await _n.blockTimeSlot(
            queueId: queue.id,
            timeSlotId: timeSlotId,
            reason: reason,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(error ?? 'Créneaux bloqués ✅'),
              backgroundColor: error != null ? Colors.red.shade600 : null,
            ));
          }
          return null;
        },
      ),
    );
  }

  Future<void> _onUnblock(_QueueAgenda queue) async {
    final result = await _n.unblockPlage(queue.id);
    if (mounted) _snackBar(result);
  }

  // ── Modification durée ────────────────────────────────────
  Future<void> _onDurationChanged(_QueueAgenda queue, int delta) async {
    final tsInfo = await _selectTimeSlot(queue);
    if (tsInfo == null) return;

    final newDuration = (tsInfo.duration + delta).clamp(5, 120);
    if (newDuration == tsInfo.duration) return;

    final plageStart = _parseTimeString(tsInfo.startTime, _n.selectedDate);
    final plageEnd = _parseTimeString(tsInfo.endTime, _n.selectedDate);
    final slotsInRange = queue.slots
        .where((s) =>
            !s.start.isBefore(plageStart) && !s.end.isAfter(plageEnd))
        .toList();

    final res = await _showModifDialog(
      context,
      title: 'Modifier la durée',
      preview: 'Durée : ${tsInfo.duration} min → $newDuration min',
      hasReservations: _n.hasReservationsInSlots(slotsInRange),
      isCapacity: false,
    );
    if (res == null) return;

    _n.setQueueLoading(queue.id);
    final result = await _n.applyDurationChange(
      queue: queue,
      tsInfo: tsInfo,
      plageStart: plageStart,
      plageEnd: plageEnd,
      newDuration: newDuration,
      type: res.type,
    );
    if (mounted) {
      _snackBar(result);
      _n.refreshSilent();
    }
  }

  // ── Modification capacité ─────────────────────────────────
  Future<void> _onCapacityChanged(_QueueAgenda queue, int delta) async {
    final tsInfo = await _selectTimeSlot(queue);
    if (tsInfo == null) return;

    final newCapacity = (tsInfo.capacity + delta).clamp(1, 50);
    if (newCapacity == tsInfo.capacity) return;

    final plageStart = _parseTimeString(tsInfo.startTime, _n.selectedDate);
    final plageEnd = _parseTimeString(tsInfo.endTime, _n.selectedDate);
    final slotsInRange = queue.slots
        .where((s) =>
            !s.start.isBefore(plageStart) && !s.end.isAfter(plageEnd))
        .toList();

    if (delta < 0 && _n.hasReservationsInSlots(slotsInRange)) {
      final maxReserved = slotsInRange
          .map((s) => s.reserved)
          .fold(0, (a, b) => a > b ? a : b);
      if (newCapacity < maxReserved) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              '⚠️ Capacité minimale : $maxReserved '
              '(créneaux avec réservations existantes)',
            ),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 4),
          ));
        }
        return;
      }
    }

    final res = await _showModifDialog(
      context,
      title: 'Modifier la capacité',
      preview: 'Capacité : ${tsInfo.capacity} pers. → $newCapacity pers.',
      hasReservations: _n.hasReservationsInSlots(slotsInRange),
      isCapacity: true,
    );
    if (res == null) return;

    _n.setQueueLoading(queue.id);
    final result = await _n.agenda.modifySlotCapacity(
      queueId: queue.id,
      date: _n.selectedDate,
      newCapacity: newCapacity,
      type: res.type,
      applyToFuture: res.applyToFuture,
      timeSlotId: tsInfo.id,
    );
    if (mounted) {
      _snackBar(result);
      _n.refreshSilent();
    }
  }

  // ── Sélecteur de plage horaire (bottom sheet) ────────────
  Future<_TimeSlotInfo?> _selectTimeSlot(_QueueAgenda queue) async {
    final timeslots = await _n.fetchTimeSlots(queue.id);
    if (timeslots.isEmpty) return null;
    if (timeslots.length == 1) return timeslots.first;
    if (!mounted) return null;
    return showModalBottomSheet<_TimeSlotInfo>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TimeslotPickerSheet(
        timeslots: timeslots,
        title: 'Quelle plage modifier ?',
      ),
    );
  }

  DateTime _parseTimeString(String time, DateTime date) {
    final parts = time.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  void _snackBar(ModificationResult res) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? _green : Colors.red.shade600,
        duration: const Duration(seconds: 3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTTOM SHEET DÉTAIL D'UN CRÉNEAU
// ============================================================
class _SlotDetailDialog extends StatefulWidget {
  final AgendaSlot slot;
  final _QueueAgenda queue;
  final DateFormat timeFormat;
  final AgendaService agenda;
  final Color green;
  final Future<void> Function(String name)? onAddClient;

  const _SlotDetailDialog({
    required this.slot,
    required this.queue,
    required this.timeFormat,
    required this.agenda,
    required this.green,
    this.onAddClient,
  });

  @override
  State<_SlotDetailDialog> createState() => _SlotDetailDialogState();
}

class _SlotDetailDialogState extends State<_SlotDetailDialog> {
  List<String>? _customerNames;
  bool _loadingNames = false;
  bool _showAddForm = false;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.slot.reserved > 0) _loadNames();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    setState(() => _loadingNames = true);
    try {
      final names = await widget.agenda.loadCustomerNames(widget.slot.id);
      if (mounted) setState(() => _customerNames = names);
    } catch (_) {
      if (mounted) setState(() => _customerNames = []);
    } finally {
      if (mounted) setState(() => _loadingNames = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final tf = widget.timeFormat;
    final isFull = slot.reserved >= slot.capacity;
    final isBlocked = slot.isBlocked;
    final canAdd = !isFull && !isBlocked && widget.onAddClient != null;
    final remaining = slot.capacity - slot.reserved;

    final bottomPadding = 28.0 + MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // En-tête : heure + badge statut
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tf.format(slot.start)} – ${tf.format(slot.end)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.queue.name,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusBadge(isBlocked, isFull, remaining),
              ],
            ),

            const SizedBox(height: 12),

            // Chips info
            Row(
              children: [
                _infoChip(Icons.timer_outlined, '${slot.duration} min'),
                const SizedBox(width: 8),
                _infoChip(
                  Icons.people_outline_rounded,
                  '${slot.reserved}/${slot.capacity} places',
                ),
              ],
            ),

            const Divider(height: 28),

            // Section clients
            if (slot.reserved > 0) ...[
              const Text(
                'Clients',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              if (_loadingNames)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Chargement...',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_customerNames != null && _customerNames!.isNotEmpty)
                ..._customerNames!.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5ED),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            size: 14,
                            color: widget.green,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(name, style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  'Aucun nom trouvé',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                  ),
                ),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                'Aucune réservation pour ce créneau',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],

            // Formulaire inline ou bouton
            if (_showAddForm) ...[
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nom du client',
                  hintText: 'Ex : Jean Dupont',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _showAddForm = false;
                      _nameCtrl.clear();
                    }),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final name = _nameCtrl.text.trim().isEmpty
                            ? 'Client'
                            : _nameCtrl.text.trim();
                        Navigator.pop(context);
                        await widget.onAddClient!(name);
                      },
                      icon: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Inscrire',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
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
            ] else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canAdd
                      ? () => setState(() => _showAddForm = true)
                      : null,
                  icon: Icon(
                    Icons.person_add_rounded,
                    color: canAdd ? Colors.white : Colors.grey.shade400,
                  ),
                  label: Text(
                    isBlocked
                        ? 'Créneau bloqué'
                        : isFull
                        ? 'Complet'
                        : 'Ajouter un client',
                    style: TextStyle(
                      color: canAdd ? Colors.white : Colors.grey.shade500,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAdd ? _green : Colors.grey.shade200,
                    disabledBackgroundColor: Colors.grey.shade200,
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
      ),
    );
  }

  Widget _statusBadge(bool isBlocked, bool isFull, int remaining) {
    if (isBlocked) return _badge('Bloqué', Colors.red.shade600);
    if (isFull) return _badge('Complet', Colors.red.shade400);
    if (remaining < widget.slot.capacity) {
      return _badge('$remaining pl.', Colors.orange.shade500);
    }
    return _badge('Libre', _green);
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MODÈLE INTERNE — page de slots paginée
// ============================================================
class _SlotPage {
  final List<AgendaSlot> slots;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;

  _SlotPage({
    required this.slots,
    required this.lastDoc,
    required this.hasMore,
  });
}

// ============================================================
// MODÈLES LOCAUX (UI only)
// ============================================================
class _QueueAgenda {
  final String id;
  final String name;
  final List<AgendaSlot> slots;
  final bool isBlocked;
  final String? blockReason;
  final QueueStats stats;
  final List<int> weekdays;
  final int timeSlotCount;

  _QueueAgenda({
    required this.id,
    required this.name,
    required this.slots,
    this.isBlocked = false,
    this.blockReason,
    required this.stats,
    this.weekdays = const [],
    this.timeSlotCount = 0,
  });
}

class _ModifResult {
  final ModificationType type;
  final bool applyToFuture;
  _ModifResult({required this.type, this.applyToFuture = false});
}

class _TimeSlotInfo {
  final String id;
  final String startTime;
  final String endTime;
  final int capacity;
  final int duration;
  final List<int> workingDays;
  final int maxAdvanceDays;
  final int maxReservationsPerPerson;
  final int reservationDeadlineMinutes;

  _TimeSlotInfo({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.capacity = 1,
    this.duration = 15,
    this.workingDays = const [],
    this.maxAdvanceDays = 5,
    this.maxReservationsPerPerson = 1,
    this.reservationDeadlineMinutes = 10,
  });
}

