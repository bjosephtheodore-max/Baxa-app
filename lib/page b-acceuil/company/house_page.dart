import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/agenda_service.dart';
import 'package:baxa/page b-acceuil/company/settings_page.dart';

// ============================================================
// HOUSE PAGE — AGENDA INTERACTIF DE L'ENTREPRISE
// ============================================================
class HousePage extends StatefulWidget {
  const HousePage({super.key});
  @override
  State<HousePage> createState() => _HousePageState();
}

class _HousePageState extends State<HousePage>
    with AutomaticKeepAliveClientMixin {
  // ── Services ──────────────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AgendaService _agenda = AgendaService();
  final DateFormat _dateFormat = DateFormat('EEEE d MMM yyyy', 'fr_FR');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  // ── State ─────────────────────────────────────────────────
  String? _companyId;
  String _companyName = '';
  DateTime _selectedDate = DateTime.now();

  // FIX #5 — chaque file a son propre état de chargement
  // _queues peut être partiellement rempli pendant le chargement
  List<_QueueAgenda?> _queues = []; // null = en cours de chargement
  int _totalQueues = 0;
  bool _isLoading = true;
  bool _hasQueues = false;

  // ── Carousel ─────────────────────────────────────────────
  int _currentPageIndex = 0;
  late PageController _pageController;

  // ── Palette ───────────────────────────────────────────────
  static const Color _green = Color.fromARGB(255, 75, 139, 94);
  static const Color _lightGreen = Color.fromARGB(255, 178, 211, 194);

  // ── KeepAlive ─────────────────────────────────────────────
  @override
  bool get wantKeepAlive => true;

  // ── Pagination slots ──────────────────────────────────────
  static const int _pageSize = 15;
  final Map<String, DocumentSnapshot?> _lastSlotDoc = {};
  final Map<String, bool> _hasMoreSlots = {};
  final Map<String, bool> _isLoadingMore = {};
  final Map<String, ScrollController> _scrollControllers = {};

  // ----------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _agenda.initialize();
    _pageController = PageController(viewportFraction: 0.88);
    _loadCompanyData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final sc in _scrollControllers.values) {
      sc.dispose();
    }
    super.dispose();
  }

  // ==============================================================
  // SCROLL CONTROLLER PAR FILE
  // ==============================================================
  ScrollController _scrollControllerFor(String queueId) {
    if (!_scrollControllers.containsKey(queueId)) {
      final sc = ScrollController();
      sc.addListener(() {
        if (sc.position.pixels >= sc.position.maxScrollExtent - 200) {
          _loadMoreSlots(queueId);
        }
      });
      _scrollControllers[queueId] = sc;
    }
    return _scrollControllers[queueId]!;
  }

  // ==============================================================
  // CHARGEMENT INITIAL
  // ==============================================================
  Future<void> _loadCompanyData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _companyId = user.uid;
      _isLoading = true;
    });
    try {
      // Charger infos entreprise + vérifier existence des files en parallèle
      final results = await Future.wait([
        _firestore.collection('Entreprises').doc(_companyId).get(),
        _firestore
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .limit(1) // juste pour vérifier qu'il y en a
            .get(),
      ]);

      final companyDoc = results[0] as DocumentSnapshot;
      final queuesCheck = results[1] as QuerySnapshot;

      if (companyDoc.exists) {
        _companyName =
            (companyDoc.data() as Map<String, dynamic>?)?['nom'] ?? 'Baxa';
      }

      if (queuesCheck.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _hasQueues = false;
            _isLoading = false;
          });
        }
        return;
      }

      _hasQueues = true;
      await _refreshAgenda();
    } catch (e) {
      debugPrint('Erreur chargement données: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==============================================================
  // FIX #2 + #4 + #5 — RAFRAÎCHIR L'AGENDA
  // Requêtes parallèles + pagination queues + UI progressive
  // ==============================================================
  Future<void> _refreshAgenda() async {
    if (_companyId == null || !mounted) return;

    // Reset
    _lastSlotDoc.clear();
    _hasMoreSlots.clear();
    _isLoadingMore.clear();

    setState(() => _isLoading = true);

    try {
      // FIX #4 — pagination des queues (limit 10)
      final queuesSnap = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .limit(10)
          .get();

      if (queuesSnap.docs.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // FIX #5 — Pré-remplir avec des placeholders null (lazy UI)
      // L'UI s'affiche immédiatement avec un loader par file
      if (mounted) {
        setState(() {
          _totalQueues = queuesSnap.docs.length;
          _queues = List.filled(_totalQueues, null);
          _isLoading = false; // on libère le loader global
        });
      }

      // FIX #2 — charger toutes les files EN PARALLÈLE avec Future.wait
      final futures = queuesSnap.docs.asMap().entries.map((entry) async {
        final index = entry.key;
        final qDoc = entry.value;
        final qData = qDoc.data();

        try {
          // FIX #3 — une seule requête Firestore directe (plus de double appel)
          final firstPage = await _loadSlotPage(qDoc.id, startAfter: null);

          _lastSlotDoc[qDoc.id] = firstPage.lastDoc;
          _hasMoreSlots[qDoc.id] = firstPage.hasMore;
          _isLoadingMore[qDoc.id] = false;

          final isBlocked = await _agenda.isPlageBlocked(
            qDoc.id,
            _selectedDate,
          );
          final blockReason = isBlocked
              ? await _agenda.getBlockReason(qDoc.id, _selectedDate)
              : null;

          final queueData = _QueueAgenda(
            id: qDoc.id,
            name: qData['name'] ?? 'File sans nom',
            slots: firstPage.slots,
            isBlocked: isBlocked,
            blockReason: blockReason,
            stats: _agenda.computeStats(firstPage.slots),
          );

          // FIX #5 — mettre à jour cette file dès qu'elle est prête
          // sans attendre les autres
          if (mounted) {
            setState(() {
              _queues[index] = queueData;
            });
          }
        } catch (e) {
          debugPrint('Erreur chargement file ${qDoc.id}: $e');
        }
      });

      // Lancer tout en parallèle
      await Future.wait(futures);
    } catch (e) {
      debugPrint('Erreur rafraîchissement: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==============================================================
  // FIX #3 — UNE SEULE REQUÊTE FIRESTORE PAR PAGE
  // Plus de double appel loadSlotsForDate + snap.docs
  // ==============================================================
  Future<_SlotPage> _loadSlotPage(
    String queueId, {
    required DocumentSnapshot? startAfter,
  }) async {
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Construction de la query paginée
    Query query = _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('start', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('start')
        .limit(_pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();

    // Conversion directe depuis les docs — une seule requête, pas deux
    final slots = snap.docs
        .map((doc) => _agenda.slotFromDoc(doc, queueId: queueId))
        .toList();

    return _SlotPage(
      slots: slots,
      lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
      hasMore: snap.docs.length >= _pageSize,
    );
  }

  // ==============================================================
  // SCROLL INFINI — CHARGER LA PAGE SUIVANTE
  // FIX #1 conservé : toujours pas de loadCustomerNames ici
  // ==============================================================
  Future<void> _loadMoreSlots(String queueId) async {
    if (_isLoadingMore[queueId] == true) return;
    if (_hasMoreSlots[queueId] != true) return;

    setState(() => _isLoadingMore[queueId] = true);

    try {
      final page = await _loadSlotPage(
        queueId,
        startAfter: _lastSlotDoc[queueId],
      );

      _lastSlotDoc[queueId] = page.lastDoc;
      _hasMoreSlots[queueId] = page.hasMore;

      if (mounted) {
        setState(() {
          final qIndex = _queues.indexWhere(
            (q) => q != null && q.id == queueId,
          );
          if (qIndex != -1) {
            final q = _queues[qIndex]!;
            final updatedSlots = [...q.slots, ...page.slots];
            _queues[qIndex] = _QueueAgenda(
              id: q.id,
              name: q.name,
              slots: updatedSlots,
              isBlocked: q.isBlocked,
              blockReason: q.blockReason,
              stats: _agenda.computeStats(updatedSlots),
            );
          }
          _isLoadingMore[queueId] = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur page suivante: $e');
      if (mounted) setState(() => _isLoadingMore[queueId] = false);
    }
  }

  // ==============================================================
  // NAVIGATION DE DATE
  // ==============================================================
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      await _refreshAgenda();
    }
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _refreshAgenda();
  }

  // ==============================================================
  // BUILD
  // ==============================================================
  @override
  Widget build(BuildContext context) {
    super.build(context); // requis par AutomaticKeepAliveClientMixin
    // Queues réellement chargées (non-null)
    // ignore: unused_local_variable
    final loadedQueues = _queues.whereType<_QueueAgenda>().toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : !_hasQueues
          ? _buildEmptyState()
          : Column(
              children: [
                _buildDateBar(),
                Expanded(child: _buildAgendaBody()),
              ],
            ),
      floatingActionButton: _hasQueues
          ? FloatingActionButton.extended(
              onPressed: _showNewAppointmentDialog,
              backgroundColor: _green,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Nouveau RDV',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ── AppBar ────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '🏛️ Baxa',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _companyName,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: const [],
    );
  }

  // ── Barre date ────────────────────────────────────────────
  Widget _buildDateBar() {
    final now = DateTime.now();
    final isToday =
        _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    return Container(
      padding: const EdgeInsets.all(16),
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
            onPressed: () => _changeDate(-1),
            icon: const Icon(Icons.chevron_left, color: _green),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isToday
                      ? _green.withOpacity(0.08)
                      : Colors.grey.shade50,
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
                      _dateFormat.format(_selectedDate),
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
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _changeDate(1),
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
    if (_queues.isEmpty) {
      return Center(
        child: Text(
          'Aucun créneau pour cette date',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    if (_queues.length == 1) {
      return _buildQueueOrLoader(0);
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _queues.length,
            onPageChanged: (i) => setState(() => _currentPageIndex = i),
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

  // FIX #5 — afficher un loader élégant tant que la file n'est pas prête
  Widget _buildQueueOrLoader(int index) {
    final queue = index < _queues.length ? _queues[index] : null;
    if (queue == null) {
      return _buildQueueSkeleton();
    }
    return _buildQueueView(queue);
  }

  // ── Skeleton loader par file ──────────────────────────────
  Widget _buildQueueSkeleton() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        // Skeleton de la carte en-tête
        Container(
          height: 200,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: _green, strokeWidth: 2),
          ),
        ),
        // Skeleton de quelques créneaux
        ...List.generate(
          4,
          (i) => Container(
            height: 72,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageIndicators() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_queues.length, (i) {
          final isActive = i == _currentPageIndex;
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
  }

  // ── Vue complète d'une file ───────────────────────────────
  // BUG FIX — réintégration de _buildQueueHeaderCard en tête de liste
  Widget _buildQueueView(_QueueAgenda queue) {
    final slotsForQueue = queue.slots.toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final slotWidgets = <Widget>[];
    for (int i = 0; i < slotsForQueue.length; i++) {
      final current = slotsForQueue[i];
      slotWidgets.add(_buildSlotCard(current));
      if (i < slotsForQueue.length - 1) {
        final next = slotsForQueue[i + 1];
        final gap = next.start.difference(current.end);
        if (gap.inMinutes > 60) {
          slotWidgets.add(_buildTimeslotSeparator(current.end, next.start));
        }
      }
    }

    final isLoadingMore = _isLoadingMore[queue.id] == true;
    final hasMore = _hasMoreSlots[queue.id] == true;

    return ListView(
      controller: _scrollControllerFor(queue.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        // ✅ BUG FIX — Widget en-tête avec stats + contrôles + bouton blocage
        _buildQueueHeaderCard(queue),
        const SizedBox(height: 12),

        // Liste des créneaux
        if (slotsForQueue.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Aucun créneau pour cette date',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          ...slotWidgets,

        // Footer scroll infini
        const SizedBox(height: 8),
        if (isLoadingMore)
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
        else if (!hasMore && slotsForQueue.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '✓ Tous les créneaux affichés',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
            ),
          ),
        const SizedBox(height: 80), // espace FAB
      ],
    );
  }

  // ==============================================================
  // CARTE EN-TÊTE DE FILE — stats + contrôles durée/capacité + blocage
  // ==============================================================
  Widget _buildQueueHeaderCard(_QueueAgenda queue) {
    final nonLegacy = queue.slots.where((s) => !s.isLegacy).toList();
    final currentDuration = nonLegacy.isNotEmpty
        ? nonLegacy.first.duration
        : (queue.slots.isNotEmpty ? queue.slots.first.duration : 15);
    final currentCapacity = nonLegacy.isNotEmpty
        ? nonLegacy.first.capacity
        : (queue.slots.isNotEmpty ? queue.slots.first.capacity : 1);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nom + badge statut
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  queue.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: queue.isBlocked
                        ? Colors.red.shade100
                        : _lightGreen.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    queue.isBlocked ? '🔒 Bloquée' : '✅ Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: queue.isBlocked ? Colors.red.shade700 : _green,
                    ),
                  ),
                ),
              ],
            ),

            // Raison du blocage
            if (queue.isBlocked && queue.blockReason != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        queue.blockReason!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Ligne de 3 stats
            _buildStatsRow(queue.stats),

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Contrôles durée + capacité (cachés si bloquée)
            if (!queue.isBlocked) ...[
              _buildControl(
                label: 'Durée',
                icon: Icons.timer,
                value: currentDuration,
                unit: 'min',
                min: 5,
                max: 120,
                step: 5,
                onChanged: (v) => _onDurationChanged(queue, v),
              ),
              const SizedBox(height: 12),
              _buildControl(
                label: 'Capacité',
                icon: Icons.people,
                value: currentCapacity,
                unit: 'pers.',
                min: 1,
                max: 50,
                step: 1,
                onChanged: (v) => _onCapacityChanged(queue, v),
              ),
              const SizedBox(height: 16),
            ],

            // Bouton Bloquer / Débloquer
            SizedBox(
              width: double.infinity,
              child: queue.isBlocked
                  ? ElevatedButton.icon(
                      onPressed: () => _onUnblock(queue),
                      icon: const Icon(Icons.lock_open, color: Colors.white),
                      label: const Text(
                        'Débloquer la plage',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _onBlockRequest(queue),
                      icon: const Icon(Icons.lock, color: Colors.white),
                      label: const Text(
                        'Bloquer la plage',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contrôle ⊖ valeur ⊕ ──────────────────────────────────
  Widget _buildControl({
    required String label,
    required IconData icon,
    required int value,
    required String unit,
    required int min,
    required int max,
    required int step,
    required void Function(int) onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _green),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        _plusMinusBtn(Icons.remove, value > min, () => onChanged(value - step)),
        const SizedBox(width: 14),
        Text(
          '$value $unit',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 14),
        _plusMinusBtn(Icons.add, value < max, () => onChanged(value + step)),
      ],
    );
  }

  Widget _plusMinusBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? _green.withOpacity(0.1) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? _green : Colors.grey.shade300),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 18,
            color: enabled ? _green : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  // ── Ligne de 3 stats ──────────────────────────────────────
  Widget _buildStatsRow(QueueStats stats) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statItem(
              emoji: '🟢',
              value: stats.placesRestantes.toString(),
              label: 'Restantes',
              color: stats.placesRestantes == 0 ? Colors.red.shade600 : _green,
            ),
          ),
          Container(width: 1, height: 44, color: Colors.grey.shade200),
          Expanded(
            child: _statItem(
              emoji: '📌',
              value: stats.placesReservees.toString(),
              label: 'Réservées',
              color: Colors.blue.shade600,
            ),
          ),
          Container(width: 1, height: 44, color: Colors.grey.shade200),
          Expanded(
            child: _statItem(
              emoji: '👥',
              value: stats.personnesEnAttente.toString(),
              label: 'En attente',
              color: stats.personnesEnAttente > 0
                  ? Colors.orange.shade700
                  : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem({
    required String emoji,
    required String value,
    required String label,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // CARTE D'UN CRÉNEAU
  // FIX #1 — plus de customerNames en subtitle au démarrage
  // Les noms sont chargés au clic dans _showSlotDetails
  // ==============================================================
  Widget _buildSlotCard(AgendaSlot slot) {
    final isBlocked = slot.isBlocked;
    final isFull = slot.isFull;
    final isLegacy = slot.isLegacy;

    Color border, bg;
    if (isBlocked) {
      border = Colors.red.shade400;
      bg = Colors.red.shade50;
    } else if (isFull) {
      border = _green;
      bg = _lightGreen.withOpacity(0.25);
    } else if (isLegacy) {
      border = Colors.orange.shade400;
      bg = Colors.orange.shade50;
    } else {
      border = Colors.grey.shade300;
      bg = Colors.white;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isBlocked
                ? Colors.red.shade200
                : isFull
                ? _green
                : _lightGreen.withOpacity(0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(
              isBlocked
                  ? Icons.lock
                  : isFull
                  ? Icons.people
                  : Icons.event_available,
              color: isBlocked || isFull ? Colors.white : _green,
              size: 20,
            ),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_timeFormat.format(slot.start)} – ${_timeFormat.format(slot.end)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isBlocked
                    ? Colors.red.shade600
                    : isFull
                    ? _green
                    : Colors.orange.shade500,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isBlocked ? 'Bloqué' : '${slot.reserved}/${slot.capacity}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              // FIX #1 — subtitle simplifié, pas besoin de customerNames
              _slotSubtitle(slot),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (isLegacy) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Ancien format',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        onTap: () => _showSlotDetails(slot),
      ),
    );
  }

  Widget _buildTimeslotSeparator(DateTime endTime, DateTime startTime) {
    final endFormatted = _timeFormat.format(endTime);
    final startFormatted = _timeFormat.format(startTime);
    final durationMinutes = startTime.difference(endTime).inMinutes;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: Colors.grey.shade600, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pause — $endFormatted à $startFormatted',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Prochaine plage dans ${durationMinutes}min',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // FIX #1 — subtitle sans customerNames (chargés uniquement au clic)
  String _slotSubtitle(AgendaSlot slot) {
    if (slot.isBlocked) return 'Bloqué';
    if (slot.reserved == 0) return 'Disponible';
    return '${slot.reserved} personne(s) réservée(s)';
  }

  // ==============================================================
  // FIX #1 — LAZY LOADING des noms clients (seulement au clic)
  // ==============================================================
  void _showSlotDetails(AgendaSlot slot) {
    showDialog(
      context: context,
      builder: (ctx) => _SlotDetailDialog(
        slot: slot,
        timeFormat: _timeFormat,
        agenda: _agenda,
        green: _green,
      ),
    );
  }

  // ignore: unused_element
  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // EMPTY STATE
  // ==============================================================
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _lightGreen.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.queue_outlined, size: 72, color: _green),
            ),
            const SizedBox(height: 28),
            const Text(
              'Bienvenue sur Baxa ! 🎉',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E2D23),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Créez votre première file d\'attente pour commencer à recevoir des réservations.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            // Bouton principal onboarding
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(autoOpenCreateDialog: true),
                    ),
                  );
                  // Rafraîchit après retour
                  if (mounted) _loadCompanyData();
                },
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text(
                  'Créer ma première file',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Indication visuelle des étapes
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _lightGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _lightGreen.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  _buildOnboardingStep(
                    number: '1',
                    text: 'Créez une file d\'attente',
                    done: false,
                  ),
                  const SizedBox(height: 8),
                  _buildOnboardingStep(
                    number: '2',
                    text: 'Ajoutez une plage horaire',
                    done: false,
                  ),
                  const SizedBox(height: 8),
                  _buildOnboardingStep(
                    number: '3',
                    text: 'Vos clients peuvent réserver !',
                    done: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingStep({
    required String number,
    required String text,
    required bool done,
  }) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: done ? _green : _green.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : Text(
                    number,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ==================== CRÉER RDV MANUEL ====================
  Future<void> _showNewAppointmentDialog() async {
    final nameController = TextEditingController();
    final loadedQueues = _queues.whereType<_QueueAgenda>().toList();
    final availableQueues = loadedQueues
        .where((q) => q.stats.placesRestantes > 0)
        .toList();

    if (availableQueues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune file disponible avec des places restantes'),
        ),
      );
      return;
    }
    _QueueAgenda? selectedQueue = availableQueues.first;
    AgendaSlot? selectedSlot;
    List<AgendaSlot> availableSlots =
        selectedQueue.slots
            .where((s) => s.status == 'open' && s.reserved < s.capacity)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    if (availableSlots.isNotEmpty) selectedSlot = availableSlots.first;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Nouveau rendez-vous'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du client',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                    hintText: 'Ex: Jean Dupont',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<_QueueAgenda>(
                  value: selectedQueue,
                  decoration: const InputDecoration(
                    labelText: 'File d\'attente',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.queue),
                  ),
                  items: availableQueues.map((q) {
                    return DropdownMenuItem(
                      value: q,
                      child: Text(
                        '${q.name} (${q.stats.placesRestantes} places)',
                      ),
                    );
                  }).toList(),
                  onChanged: (q) {
                    setS(() {
                      selectedQueue = q;
                      availableSlots =
                          q!.slots
                              .where(
                                (s) =>
                                    s.status == 'open' &&
                                    s.reserved < s.capacity,
                              )
                              .toList()
                            ..sort((a, b) => a.start.compareTo(b.start));
                      selectedSlot = availableSlots.isNotEmpty
                          ? availableSlots.first
                          : null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (availableSlots.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Aucun créneau disponible pour cette file',
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                else
                  DropdownButtonFormField<AgendaSlot>(
                    value: selectedSlot,
                    decoration: const InputDecoration(
                      labelText: 'Créneau horaire',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.schedule),
                    ),
                    items: availableSlots.map((s) {
                      final time = _timeFormat.format(s.start);
                      final av = s.capacity - s.reserved;
                      return DropdownMenuItem(
                        value: s,
                        child: Text('$time ($av/${s.capacity} places)'),
                      );
                    }).toList(),
                    onChanged: (s) => setS(() => selectedSlot = s),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: selectedSlot == null
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Veuillez entrer un nom'),
                          ),
                        );
                        return;
                      }
                      await _createManualAppointment(
                        nameController.text.trim(),
                        selectedQueue!,
                        selectedSlot!,
                      );
                      Navigator.pop(ctx);
                    },
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child: const Text('Créer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createManualAppointment(
    String clientName,
    _QueueAgenda queue,
    AgendaSlot slot,
  ) async {
    if (_companyId == null) return;
    try {
      await _firestore.collection('reservations').add({
        'customerId': 'manual_booking',
        'customerName': clientName,
        'companyId': _companyId,
        'queueId': queue.id,
        'queueName': queue.name,
        'slotStart': slot.start,
        'slotEnd': slot.end,
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'company_manual',
      });
      final slotsRef = _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id)
          .collection('slots');
      final matchingSlots = await slotsRef
          .where('start', isEqualTo: slot.start)
          .where('end', isEqualTo: slot.end)
          .limit(1)
          .get();
      if (matchingSlots.docs.isNotEmpty) {
        await matchingSlots.docs.first.reference.update({
          'reserved': FieldValue.increment(1),
        });
      }
      await _refreshAgenda();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rendez-vous créé avec succès')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  // ==================== BLOCAGE ====================
  Map<String, List<AgendaSlot>> _detectTimeslots(List<AgendaSlot> slots) {
    if (slots.isEmpty) return {};
    final sorted = List<AgendaSlot>.from(slots)
      ..sort((a, b) => a.start.compareTo(b.start));
    final Map<String, List<AgendaSlot>> timeslots = {};
    List<AgendaSlot> currentGroup = [sorted.first];
    for (int i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];
      if (curr.start.difference(prev.end).inMinutes > 60) {
        final s = _timeFormat.format(currentGroup.first.start);
        final e = _timeFormat.format(currentGroup.last.end);
        timeslots['$s — $e'] = List.from(currentGroup);
        currentGroup = [curr];
      } else {
        currentGroup.add(curr);
      }
    }
    if (currentGroup.isNotEmpty) {
      final s = _timeFormat.format(currentGroup.first.start);
      final e = _timeFormat.format(currentGroup.last.end);
      timeslots['$s — $e'] = currentGroup;
    }
    return timeslots;
  }

  Future<void> _blockSlots(
    List<AgendaSlot> slots,
    String reason,
    _QueueAgenda queue,
  ) async {
    if (_companyId == null) return;
    try {
      final batch = _firestore.batch();
      for (final slot in slots) {
        final q = await _firestore
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .doc(queue.id)
            .collection('slots')
            .where('start', isEqualTo: slot.start)
            .where('end', isEqualTo: slot.end)
            .limit(1)
            .get();
        if (q.docs.isEmpty) continue;
        batch.update(q.docs.first.reference, {
          'status': 'blocked',
          'blockReason': reason,
          'blockedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      await _refreshAgenda();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${slots.length} créneau(x) bloqué(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  Future<void> _onBlockRequest(_QueueAgenda queue) async {
    if (_companyId == null) return;
    final daySlots = queue.slots;
    if (daySlots.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucun créneau à bloquer')));
      return;
    }
    final timeslots = _detectTimeslots(daySlots);
    String? selectedRange;
    if (timeslots.length > 1) {
      selectedRange = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Quelle plage bloquer ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...timeslots.entries.map(
                (e) => RadioListTile<String>(
                  title: Text(e.key),
                  subtitle: Text('${e.value.length} créneaux'),
                  value: e.key,
                  groupValue: selectedRange,
                  onChanged: (v) => Navigator.pop(ctx, v),
                ),
              ),
              const Divider(),
              RadioListTile<String>(
                title: const Text('Toutes les plages'),
                subtitle: Text('${daySlots.length} créneaux au total'),
                value: 'ALL',
                groupValue: selectedRange,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
          ],
        ),
      );
      if (selectedRange == null) return;
    } else {
      selectedRange = 'ALL';
    }
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Raison du blocage'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Raison',
            hintText: 'Ex: Pause déjeuner, Réunion...',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bloquer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    final slotsToBlock = selectedRange == 'ALL'
        ? daySlots
        : timeslots[selectedRange]!;
    await _blockSlots(slotsToBlock, reason, queue);
  }

  Future<void> _onUnblock(_QueueAgenda queue) async {
    setState(() {
      final i = _queues.indexWhere((q) => q?.id == queue.id);
      if (i != -1) _queues[i] = null; // affiche skeleton pendant opération
    });
    final result = await _agenda.unblockPlage(
      queueId: queue.id,
      date: _selectedDate,
    );
    if (mounted) {
      _snackBar(result);
      await _refreshAgenda();
    }
  }

  Future<void> _onDurationChanged(_QueueAgenda queue, int newDuration) async {
    final res = await _showModifDialog(
      title: 'Modifier la durée',
      preview: 'Durée : ${_currentDuration(queue)} min → $newDuration min',
    );
    if (res == null) return;
    // Affiche skeleton pendant l'opération
    setState(() {
      final i = _queues.indexWhere((q) => q?.id == queue.id);
      if (i != -1) _queues[i] = null;
    });
    final result = await _agenda.modifySlotDuration(
      queueId: queue.id,
      date: _selectedDate,
      newDuration: newDuration,
      type: res.type,
      applyToFuture: res.applyToFuture,
    );
    if (mounted) {
      _snackBar(result);
      await _refreshAgenda();
    }
  }

  Future<void> _onCapacityChanged(_QueueAgenda queue, int newCapacity) async {
    final res = await _showModifDialog(
      title: 'Modifier la capacité',
      preview:
          'Capacité : ${_currentCapacity(queue)} pers. → $newCapacity pers.',
    );
    if (res == null) return;
    setState(() {
      final i = _queues.indexWhere((q) => q?.id == queue.id);
      if (i != -1) _queues[i] = null;
    });
    final result = await _agenda.modifySlotCapacity(
      queueId: queue.id,
      date: _selectedDate,
      newCapacity: newCapacity,
      type: res.type,
      applyToFuture: res.applyToFuture,
    );
    if (mounted) {
      _snackBar(result);
      await _refreshAgenda();
    }
  }

  // ==============================================================
  // DIALOGS
  // ==============================================================
  Future<_ModifResult?> _showModifDialog({
    required String title,
    required String preview,
  }) async {
    ModificationType type = ModificationType.ponctuelle;
    bool applyToFuture = false;
    return showDialog<_ModifResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _green.withOpacity(0.3)),
                ),
                child: Text(
                  preview,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RadioListTile<ModificationType>(
                title: const Text("Juste pour aujourd'hui"),
                subtitle: const Text(
                  'Les paramètres reviendront à la normale demain',
                  style: TextStyle(fontSize: 12),
                ),
                value: ModificationType.ponctuelle,
                groupValue: type,
                activeColor: _green,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setD(() {
                  type = v!;
                  applyToFuture = false;
                }),
              ),
              RadioListTile<ModificationType>(
                title: const Text('Permanente'),
                subtitle: const Text(
                  'Met à jour les paramètres globaux de la file',
                  style: TextStyle(fontSize: 12),
                ),
                value: ModificationType.permanente,
                groupValue: type,
                activeColor: _green,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setD(() => type = v!),
              ),
              if (type == ModificationType.permanente) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: CheckboxListTile(
                    title: const Text(
                      'Appliquer aux plages futures',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Régénère les créneaux futurs libres avec ces nouveaux paramètres',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: applyToFuture,
                    activeColor: _green,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    onChanged: (v) => setD(() => applyToFuture = v!),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                ctx,
                _ModifResult(type: type, applyToFuture: applyToFuture),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Confirmer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // HELPERS
  // ==============================================================
  int _currentDuration(_QueueAgenda q) {
    final nl = q.slots.where((s) => !s.isLegacy).toList();
    return nl.isNotEmpty
        ? nl.first.duration
        : (q.slots.isNotEmpty ? q.slots.first.duration : 15);
  }

  int _currentCapacity(_QueueAgenda q) {
    final nl = q.slots.where((s) => !s.isLegacy).toList();
    return nl.isNotEmpty
        ? nl.first.capacity
        : (q.slots.isNotEmpty ? q.slots.first.capacity : 1);
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
// FIX #1 — DIALOG DÉTAIL AVEC LAZY LOADING DES NOMS CLIENTS
// Les noms ne sont chargés QUE quand l'utilisateur ouvre ce dialog
// ============================================================
class _SlotDetailDialog extends StatefulWidget {
  final AgendaSlot slot;
  final DateFormat timeFormat;
  final AgendaService agenda;
  final Color green;

  const _SlotDetailDialog({
    required this.slot,
    required this.timeFormat,
    required this.agenda,
    required this.green,
  });

  @override
  State<_SlotDetailDialog> createState() => _SlotDetailDialogState();
}

class _SlotDetailDialogState extends State<_SlotDetailDialog> {
  List<String>? _customerNames;
  bool _loadingNames = false;

  @override
  void initState() {
    super.initState();
    // Chargement lazy : déclenché seulement à l'ouverture du dialog
    if (widget.slot.reserved > 0) {
      _loadNames();
    }
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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('${tf.format(slot.start)} – ${tf.format(slot.end)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rowItem('Statut', slot.isBlocked ? '🔒 Bloqué' : '✅ Ouvert'),
          _rowItem('Durée', '${slot.duration} min'),
          _rowItem('Places', '${slot.reserved} / ${slot.capacity}'),
          if (slot.isLegacy) _rowItem('Format', 'Ancien (legacy)'),
          const SizedBox(height: 12),

          // Section clients — chargée en lazy
          if (slot.reserved > 0) ...[
            const Text(
              'Clients :',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
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
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 16, color: widget.green),
                      const SizedBox(width: 8),
                      Text(name, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              )
            else
              Text(
                'Aucun nom trouvé',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
          ] else
            Text(
              'Aucune réservation',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  Widget _rowItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

  _QueueAgenda({
    required this.id,
    required this.name,
    required this.slots,
    this.isBlocked = false,
    this.blockReason,
    required this.stats,
  });
}

class _ModifResult {
  final ModificationType type;
  final bool applyToFuture;
  _ModifResult({required this.type, this.applyToFuture = false});
}
