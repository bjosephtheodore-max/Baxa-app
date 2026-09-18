import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/agenda_service.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/page b-acceuil/company/team_page.dart';
import 'package:baxa/main.dart' show routeObserver;
import 'package:baxa/services/onboarding_service.dart';
import 'package:baxa/widgets/onboarding_widgets.dart';
import 'package:baxa/widgets/baxa_date_picker_theme.dart';
import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';

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
  bool _pageControllerReady = false;
  final Map<String, ScrollController> _scrollControllers = {};
  bool _quickAddLoading = false;
  final Map<String, bool> _pastExpanded = {};
  final Map<String, bool> _headerExpanded = {};

  // Anti-double-tap : les boutons +/- et « Bloquer la plage » ouvrent des
  // bottom sheets/dialogs asynchrones (_selectTimeSlot, _showModifDialog…)
  // AVANT le verrou Firestore (_busyTimeSlotIds) — un double-tap rapide
  // relance donc le handler une 2e fois pendant que le 1er dialog s'ouvre
  // encore, et on se retrouve avec 2 dialogs superposés. Un verrou par file,
  // posé dès l'entrée du handler, empêche ça.
  final Set<String> _liveEditBusyQueueIds = {};

  // Bouton « + » : se range vers la barre du bas quand on défile vers le bas
  // (l'utilisateur cherche un créneau plus loin), revient quand on défile
  // vers le haut. Purement visuel — aucun impact sur l'ajout de client.
  bool _fabVisible = true;

  bool _handleUserScroll(UserScrollNotification n) {
    // Le défilement horizontal du PageView (entre files) ne compte pas.
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.reverse && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if (n.direction == ScrollDirection.forward && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
    return false;
  }

  // ── Barre de date : repli continu lié au défilement ───────
  // 0 = pleinement dépliée, 1 = pleinement repliée dans l'en-tête. Un
  // ValueNotifier (pas setState) : la valeur change à chaque pixel défilé,
  // seuls la barre de date et le petit bouton calendrier de l'AppBar
  // doivent se redessiner, jamais toute la page.
  static const double _dateBarCollapseDistance = 70;
  final ValueNotifier<double> _dateBarCollapse = ValueNotifier(0);

  bool _handleDateBarScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final progress = (n.metrics.pixels / _dateBarCollapseDistance).clamp(
      0.0,
      1.0,
    );
    _dateBarCollapse.value = progress;
    return false;
  }

  @override
  bool get wantKeepAlive => true;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _n = _HouseNotifier();
    _n.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
    _configurePageController();
  }

  // ── Largeur des créneaux (multi-files) ────────────────────
  // Réglage indépendant de la barre de navigation — c'est ICI qu'il faut
  // changer le chiffre pour resserrer/élargir les créneaux quand il y a
  // plusieurs files. Espace
  // visible mais discret sur les côtés, adapté en fraction de la largeur
  // d'écran (jamais une taille figée). Réparti en deux pour qu'on ne perde
  // pas le petit espace entre deux files voisines : une partie sert
  // d'aperçu de la file suivante (viewportFraction), l'autre reste comme
  // gouttière entre les cartes elles-mêmes (le padding de la ListView,
  // `_queueCardGutter`).
  static const double _queueSideMargin = 18;
  static const double _queueCardGutter = 6;

  void _configurePageController() {
    final width = MediaQuery.of(context).size.width;
    if (width <= 0) return;
    final outsideGap = _queueSideMargin - _queueCardGutter;
    final fraction = (1 - (2 * outsideGap / width)).clamp(0.85, 0.99);
    if (_pageControllerReady &&
        (fraction - _pageController.viewportFraction).abs() < 0.01) {
      return; // rien de notable n'a changé, on garde le controller (et sa position)
    }
    final keepPage = _pageControllerReady && _pageController.hasClients
        ? _pageController.page?.round()
        : null;
    if (_pageControllerReady) _pageController.dispose();
    _pageController = PageController(
      viewportFraction: fraction,
      initialPage: keepPage ?? 0,
    );
    _pageControllerReady = true;
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _n.dispose();
    _dateBarCollapse.dispose();
    if (_pageControllerReady) _pageController.dispose();
    for (final sc in _scrollControllers.values) {
      sc.dispose();
    }
    super.dispose();
  }

  // ── Scroll infini : un controller par file ────────────────
  // Seuil de scroll (px) au-delà duquel le panneau "Modifier" de l'en-tête
  // se replie automatiquement — évite de le refermer sur un micro-mouvement.
  static const double _autoCollapseScrollThreshold = 30;

  ScrollController _scrollControllerFor(String queueId) {
    return _scrollControllers.putIfAbsent(queueId, () {
      final sc = ScrollController();
      sc.addListener(() {
        if (sc.position.pixels >= sc.position.maxScrollExtent - 200) {
          _n.loadMoreSlots(queueId);
        }
        // Repli auto du panneau "Modifier" dès qu'on scrolle vers le bas —
        // même état que le bouton "Masquer", donc même animation fluide.
        if ((_headerExpanded[queueId] ?? false) &&
            sc.position.pixels > _autoCollapseScrollThreshold) {
          setState(() => _headerExpanded[queueId] = false);
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
      builder: (context, _) {
        // Staff retiré de l'équipe (détecté à l'ouverture ou en direct) :
        // déconnexion déjà faite côté notifier, il ne reste qu'à renvoyer
        // vers l'écran de choix, en vidant toute la pile de navigation.
        if (_n.revoked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ChoosePage()),
              (route) => false,
            );
          });
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator(color: _green)),
          );
        }
        return _buildScaffold();
      },
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      // Tout en blanc (comme WhatsApp) : l'AppBar, la barre de date et la
      // barre du bas sont déjà blanches — plus de "marche" verdâtre entre
      // l'en-tête et le contenu. La séparation en-tête/contenu passe par un
      // fin trait (voir plus bas), pas par un fond de couleur différente.
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _n.isLoading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _n.loadFailed
          ? _buildRetryState()
          : !_n.hasQueues
          ? _buildEmptyState()
          : NotificationListener<ScrollNotification>(
              onNotification: _handleDateBarScroll,
              child: NotificationListener<UserScrollNotification>(
                onNotification: _handleUserScroll,
                child: Column(
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: _dateBarCollapse,
                      builder: (_, collapse, child) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: 1 - collapse,
                              child: Opacity(
                                opacity: 1 - collapse,
                                child: child,
                              ),
                            ),
                          ),
                          // Limite en-tête / contenu : un fin trait, toujours
                          // présent — il se retrouve sous la barre de date
                          // quand elle est ouverte, sous l'AppBar quand elle
                          // est repliée. Remplace l'ombre d'avant, qui faisait
                          // une "marche" sur fond blanc.
                          Container(
                            height: 1,
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                        ],
                      ),
                      child: _buildDateBar(),
                    ),
                    Expanded(child: _buildAgendaBody()),
                  ],
                ),
              ),
            ),
      floatingActionButton: _n.hasQueues
          ? AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: _fabVisible ? Offset.zero : const Offset(0, 1.4),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                scale: _fabVisible ? 1.0 : 0.4,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: _fabVisible ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_fabVisible,
                    child: FloatingActionButton(
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
                    ),
                  ),
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
      toolbarHeight: 48,
      title: Text(
        'Baxa',
        style: GoogleFonts.poppins(
          color: _green,
          fontSize: 25,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        // Icône calendrier : n'apparaît que dans le dernier tiers du repli
        // de la barre de date (pas dès le premier pixel défilé), et ouvre
        // le même sélecteur qu'un appui sur la barre elle-même.
        ValueListenableBuilder<double>(
          valueListenable: _dateBarCollapse,
          builder: (_, collapse, __) {
            final iconOpacity = ((collapse - 0.7) / 0.3).clamp(0.0, 1.0);
            if (iconOpacity == 0) return const SizedBox.shrink();
            return Opacity(
              opacity: iconOpacity,
              child: IgnorePointer(
                ignoring: iconOpacity < 0.4,
                child: IconButton(
                  icon: const Icon(Icons.calendar_month_rounded, color: _green),
                  tooltip: 'Changer la date',
                  onPressed: _pickDate,
                ),
              ),
            );
          },
        ),
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
    final isToday =
        _n.selectedDate.year == now.year &&
        _n.selectedDate.month == now.month &&
        _n.selectedDate.day == now.day;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isToday
                      ? _green.withValues(alpha: 0.08)
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
                    Flexible(
                      child: Text(
                        _dateFormat.format(_n.selectedDate),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isToday ? _green : Colors.black87,
                        ),
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // Aucun padding ici : la marge visible vient uniquement du
        // `viewportFraction` du PageView, calculé dans
        // `_configurePageController` à partir de `_queueSideMargin`.
        PageView.builder(
          controller: _pageController,
          itemCount: _n.queues.length,
          itemBuilder: (_, index) => _buildQueueOrLoader(index),
        ),
        // Indicateurs de file, en légère surimpression en bas de l'agenda
        // (pas de bande opaque qui réserverait de la place et cacherait la
        // carte suivante).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(child: _buildPageIndicators()),
        ),
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
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_n.queues.length, (i) {
            final isActive = i == current;
            final closed = _n.queues[i]?.isClosedNow ?? false;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: closed
                    ? const Color(0xFFD64545)
                    : (isActive ? _green : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildRetryState() => _RetryState(onRetry: _n.refreshSilent);

  Widget _buildEmptyState() => const _EmptyState();

  // ── Vue complète d'une file ───────────────────────────────
  // Construit la liste de widgets (cartes + séparateurs) pour un groupe de créneaux.
  List<Widget> _buildSlotWidgetList(
    List<AgendaSlot> slots,
    Map<String, int> plageOrder,
    bool hasMultiplePlages,
    _QueueAgenda queue,
  ) {
    final widgets = <Widget>[];
    for (int i = 0; i < slots.length; i++) {
      final current = slots[i];

      if (i > 0 && hasMultiplePlages && current.timeSlotId.isNotEmpty) {
        final prev = slots[i - 1];
        if (prev.timeSlotId != current.timeSlotId) {
          widgets.add(
            _PlageSeparator(
              plageNumber: plageOrder[current.timeSlotId]!,
              startTime: current.start,
              timeFormat: _timeFormat,
            ),
          );
        }
      }

      widgets.add(
        _SlotCard(
          slot: current,
          timeFormat: _timeFormat,
          isPast: _isPastSlot(current),
          onTap: () => _showSlotDetails(current, queue),
        ),
      );

      if (i < slots.length - 1) {
        final next = slots[i + 1];
        final sameTimeslot =
            current.timeSlotId.isNotEmpty &&
            current.timeSlotId == next.timeSlotId;
        if (sameTimeslot) {
          final gap = next.start.difference(current.end);
          if (gap.inMinutes > 0) {
            widgets.add(
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
    return widgets;
  }

  Widget _buildQueueView(_QueueAgenda queue) {
    // Plusieurs files : la carte de la file affichée occupe toute la largeur
    // de son "slot" dans le PageView (la marge visible vient uniquement du
    // viewportFraction, déjà égale à celle de la barre de navigation) — pas
    // de padding en plus ici. Une seule file : padding habituel, inchangé.
    final isMultiQueue = _n.queues.length > 1;
    final slotsForQueue = queue.slots.toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final plageOrder = <String, int>{};
    for (final s in slotsForQueue) {
      if (s.timeSlotId.isNotEmpty && !plageOrder.containsKey(s.timeSlotId)) {
        plageOrder[s.timeSlotId] = plageOrder.length + 1;
      }
    }
    final hasMultiplePlages = plageOrder.length >= 2;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(
      _n.selectedDate.year,
      _n.selectedDate.month,
      _n.selectedDate.day,
    );
    final isToday = selectedDay == today;
    final isWorkingDay =
        queue.weekdays.isEmpty ||
        queue.weekdays.contains(_n.selectedDate.weekday);
    final isDayOver = isToday && isWorkingDay;
    final isBeyondHorizon = selectedDay.isAfter(
      today.add(const Duration(days: 7)),
    );
    final isBeforeHistory = selectedDay.isBefore(
      today.subtract(const Duration(days: 7)),
    );

    // Séparation passé / à venir uniquement pour aujourd'hui.
    final pastSlots = isToday
        ? slotsForQueue.where((s) => s.end.isBefore(now)).toList()
        : <AgendaSlot>[];
    final upcomingSlots = isToday
        ? slotsForQueue.where((s) => !s.end.isBefore(now)).toList()
        : slotsForQueue;

    final pastWidgets = _buildSlotWidgetList(
      pastSlots,
      plageOrder,
      hasMultiplePlages,
      queue,
    );
    final upcomingWidgets = _buildSlotWidgetList(
      upcomingSlots,
      plageOrder,
      hasMultiplePlages,
      queue,
    );

    final isExpanded = _pastExpanded[queue.id] ?? false;

    return RefreshIndicator(
      onRefresh: () async => _n.refreshSilent(),
      color: _green,
      displacement: 56,
      child: ListView(
        controller: _scrollControllerFor(queue.id),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isMultiQueue ? _queueCardGutter : 12,
          vertical: 8,
        ),
        children: [
          _buildQueueHeaderCard(queue),
          if (queue.isClosedNow || queue.closurePlannedFor != null) ...[
            const SizedBox(height: 12),
            _buildClosureBanner(queue),
          ],
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
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
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
          else ...[
            // ── Créneaux dépassés (aujourd'hui uniquement) ──────────────
            if (isToday && pastSlots.isNotEmpty) ...[
              _PastSlotsToggle(
                count: pastSlots.length,
                isCountApproximate:
                    upcomingSlots.isEmpty && _n.hasMore(queue.id),
                isExpanded: isExpanded,
                onTap: () =>
                    setState(() => _pastExpanded[queue.id] = !isExpanded),
              ),
              _PastSlotsSection(isExpanded: isExpanded, children: pastWidgets),
            ],

            // ── Créneaux à venir ─────────────────────────────────────────
            ...upcomingWidgets,
          ],

          const SizedBox(height: 8),
          if (_n.isLoadingMore(queue.id))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _green,
                  ),
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

  // ── Bandeau de fermeture ──────────────────────────────────
  // Fermeture active → rouge doux · fermeture seulement programmée → ambre.
  Widget _buildClosureBanner(_QueueAgenda queue) {
    final planned = queue.closurePlannedFor;
    final active = queue.isClosedNow;

    final String title;
    final String subtitle;
    final IconData icon;
    final Color base;

    if (active) {
      base = const Color(0xFFD64545);
      icon = Icons.lock_outline_rounded;
      title = 'Réservations fermées';
      final end = queue.closureEnd;
      subtitle = (end != null && end.isAfter(DateTime.now()))
          ? 'Rouvre le ${DateFormat('d MMMM', 'fr_FR').format(end)}. '
                'Les clients déjà réservés restent à honorer.'
          : 'Jusqu\'à nouvel ordre. Les clients déjà réservés restent à honorer.';
    } else {
      base = const Color(0xFFB26B00);
      icon = Icons.event_busy_rounded;
      title = 'Fermeture prévue';
      subtitle =
          'À partir du ${DateFormat('d MMMM', 'fr_FR').format(planned!)}. '
          'Les réservations restent ouvertes d\'ici là.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: base.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: base.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: base),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: base,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Carte en-tête de file ─────────────────────────────────
  Widget _buildQueueHeaderCard(_QueueAgenda queue) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = _n.selectedDate;
    final selectedDay = DateTime(sel.year, sel.month, sel.day);
    final isExpanded = _headerExpanded[queue.id] ?? false;
    final pendingRevert = _n.mostRecentPendingRevert(queue);

    return _QueueHeaderCard(
      queue: queue,
      currentDuration: queue.timeSlotCount == 1
          ? _n.currentDuration(queue)
          : null,
      currentCapacity: queue.timeSlotCount == 1
          ? _n.currentCapacity(queue)
          : null,
      onDurationChanged: (delta) => _onDurationChanged(queue, delta),
      onCapacityChanged: (delta) => _onCapacityChanged(queue, delta),
      onBlock: () => _onBlockRequest(queue),
      onUnblock: () => _onUnblock(queue),
      isPastDay:
          selectedDay.isBefore(today) ||
          (queue.weekdays.isNotEmpty &&
              !queue.weekdays.contains(_n.selectedDate.weekday)),
      isExpanded: isExpanded,
      onToggle: () => setState(() => _headerExpanded[queue.id] = !isExpanded),
      readOnly: _n.isStaff,
      onRevertDuration: pendingRevert != null
          ? () => _onRevertDuration(pendingRevert.tsInfo.id)
          : null,
    );
  }

  bool _isPastSlot(AgendaSlot slot) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = _n.selectedDate;
    final selectedDay = DateTime(sel.year, sel.month, sel.day);

    if (selectedDay.isBefore(today)) return true;
    if (selectedDay.isAfter(today)) return false;
    return slot.end.isBefore(now);
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
        companyId: _n.companyId ?? '',
        green: _green,
        isPast: _isPastSlot(slot),
        onAddClient: (name) =>
            _createManualAppointmentForSlot(name, queue, slot),
        onDeleteClient: (customer) =>
            _deleteManualClientForSlot(customer, queue, slot),
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
      builder: (context, child) =>
          Theme(data: baxaDatePickerTheme(context, _green), child: child!),
    );
    // Comparaison sur le jour seul : le calendrier renvoie toujours minuit,
    // alors que `_n.selectedDate` garde l'heure de sa dernière sélection —
    // une comparaison stricte les verrait "différents" même en rappuyant
    // sur OK sur le jour déjà affiché, et déclencherait un rafraîchissement
    // pour rien.
    final sameDay =
        picked != null &&
        picked.year == _n.selectedDate.year &&
        picked.month == _n.selectedDate.month &&
        picked.day == _n.selectedDate.day;
    if (picked != null && !sameDay) _n.setDate(picked);
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
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(
      _n.selectedDate.year,
      _n.selectedDate.month,
      _n.selectedDate.day,
    );
    // Borne basse : "maintenant" seulement si on regarde aujourd'hui
    // (exclut les créneaux déjà passés) — sinon le début du jour affiché,
    // pour ne jamais proposer un créneau d'un autre jour que celui-ci.
    final lowerBound = selectedDay.isAfter(today) ? selectedDay : now;

    // 1. File actuellement affichée (page visible du PageView, ou l'unique
    // file s'il n'y en a qu'une) — le bouton + agit toujours sur ce que
    // l'utilisateur a sous les yeux, jamais sur une autre file.
    final queues = _n.queues.whereType<_QueueAgenda>().toList();
    if (queues.isEmpty) return;
    var currentIndex = 0;
    if (queues.length > 1 && _pageController.hasClients) {
      currentIndex = (_pageController.page ?? 0).round().clamp(
        0,
        queues.length - 1,
      );
    }
    final bestQueue = queues[currentIndex];

    final hasCandidate =
        !bestQueue.isBlocked &&
        bestQueue.slots.any(
          (s) =>
              !s.isBlocked &&
              s.reserved < s.capacity &&
              s.start.isAfter(lowerBound),
        );

    if (!hasCandidate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.event_busy_rounded,
                    color: Colors.orange.shade700,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Aucune place disponible en ce moment.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1A1C2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
            elevation: 4,
            duration: const Duration(seconds: 3),
          ),
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
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.event_busy_rounded,
                    color: Colors.orange.shade700,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Aucune place disponible en ce moment.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1A1C2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
            elevation: 4,
            duration: const Duration(seconds: 3),
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: error != null
                    ? Colors.red.shade100
                    : const Color(0xFFE8F5ED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                error != null
                    ? Icons.error_rounded
                    : Icons.check_circle_rounded,
                color: error != null ? Colors.red.shade600 : _green,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error ?? 'Client ajouté avec succès',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A1C2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        elevation: 4,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _deleteManualClientForSlot(
    CustomerEntry customer,
    _QueueAgenda queue,
    AgendaSlot slot,
  ) async {
    final error = await _n.deleteManualReservation(
      reservationId: customer.id,
      queue: queue,
      slot: slot,
    );
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: error != null
                    ? Colors.red.shade100
                    : const Color(0xFFE8F5ED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                error != null
                    ? Icons.error_rounded
                    : Icons.check_circle_rounded,
                color: error != null ? Colors.red.shade600 : _green,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error ?? 'Client retiré du créneau',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A1C2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        elevation: 4,
        duration: const Duration(seconds: 3),
      ),
    );
    return error == null;
  }

  // ── Blocage ───────────────────────────────────────────────
  Future<void> _onBlockRequest(_QueueAgenda queue) async {
    if (!_liveEditBusyQueueIds.add(queue.id)) return;
    try {
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
          daySlots: queue.slots,
          onConfirm:
              ({required String? timeSlotId, required String reason}) async {
                final error = await _n.blockTimeSlot(
                  queueId: queue.id,
                  timeSlotId: timeSlotId,
                  reason: reason,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(error ?? 'Créneaux bloqués ✅'),
                      backgroundColor: error != null
                          ? Colors.red.shade600
                          : null,
                    ),
                  );
                }
                return null;
              },
        ),
      );
    } finally {
      _liveEditBusyQueueIds.remove(queue.id);
    }
  }

  Future<void> _onUnblock(_QueueAgenda queue) async {
    final result = await _n.unblockPlage(queue.id);
    if (mounted) _snackBar(result);
  }

  // ── Modification durée ────────────────────────────────────
  Future<void> _onDurationChanged(_QueueAgenda queue, int delta) async {
    if (!_liveEditBusyQueueIds.add(queue.id)) return;
    try {
      final tsInfo = await _selectTimeSlot(queue);
      if (tsInfo == null) return;

      final newDuration = (tsInfo.duration + delta).clamp(5, 120);
      if (newDuration == tsInfo.duration) return;

      final plageStart = _parseTimeString(tsInfo.startTime, _n.selectedDate);
      final plageEnd = _parseTimeString(tsInfo.endTime, _n.selectedDate);
      final slotsInRange = queue.slots
          .where(
            (s) => !s.start.isBefore(plageStart) && !s.end.isAfter(plageEnd),
          )
          .toList();

      final now = DateTime.now();
      final isViewingToday =
          _n.selectedDate.year == now.year &&
          _n.selectedDate.month == now.month &&
          _n.selectedDate.day == now.day;
      final todayDone =
          isViewingToday &&
          (slotsInRange.isEmpty ||
              slotsInRange.every((s) => s.end.isBefore(now)));

      final res = await _showModifDialog(
        context,
        title: 'Modifier la durée',
        preview: 'Durée : ${tsInfo.duration} min → $newDuration min',
        hasReservations: _n.hasReservationsInSlots(slotsInRange),
        isCapacity: false,
        todayDone: todayDone,
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
        // Cette modification vient de créer une trace de révocation — si
        // c'est la 1ère fois que l'icône de retour apparaît pour cette
        // entreprise, on le signale une seule fois.
        if (result.success) {
          final seen = await _n.hasSeenRevertHint();
          if (!seen && mounted) {
            await showIconDiscoverySpotlight(
              context,
              mockIcon: Icons.timer,
              badgeIcon: Icons.undo_rounded,
              title: 'Nouveau : bouton retour',
              body:
                  'Cette icône apparaît après une modification de durée en '
                  'direct. Vous avez 5 minutes pour l\'annuler en appuyant '
                  'simplement dessus.',
            );
            if (mounted) await _n.markRevertHintSeen();
          }
        }
      }
    } finally {
      _liveEditBusyQueueIds.remove(queue.id);
    }
  }

  // ── Révocation durée (undo 5 min) ──────────────────────────
  Future<void> _onRevertDuration(String timeSlotId) async {
    final result = await _n.revertDurationChange(timeSlotId);
    if (mounted) {
      _snackBar(result);
      if (result.success) _n.refreshSilent();
    }
  }

  // ── Modification capacité ─────────────────────────────────
  // Ne jamais bloquer la réduction de capacité au prétexte qu'un créneau est
  // complet : `modifySlotCapacity` clampe déjà, créneau par créneau, la
  // nouvelle capacité au nombre de réservations existantes (un créneau
  // complet garde sa capacité et ses réservations intactes, les autres
  // s'ajustent normalement). Un pré-check bloquant ici serait redondant et,
  // pire, empêcherait un ajustement légitime dès qu'UN SEUL créneau de la
  // plage est complet.
  Future<void> _onCapacityChanged(_QueueAgenda queue, int delta) async {
    if (!_liveEditBusyQueueIds.add(queue.id)) return;
    try {
      final tsInfo = await _selectTimeSlot(queue);
      if (tsInfo == null) return;

      final newCapacity = (tsInfo.capacity + delta).clamp(1, 50);
      if (newCapacity == tsInfo.capacity) return;

      final plageStart = _parseTimeString(tsInfo.startTime, _n.selectedDate);
      final plageEnd = _parseTimeString(tsInfo.endTime, _n.selectedDate);
      final slotsInRange = queue.slots
          .where(
            (s) => !s.start.isBefore(plageStart) && !s.end.isAfter(plageEnd),
          )
          .toList();

      final now = DateTime.now();
      final isViewingToday =
          _n.selectedDate.year == now.year &&
          _n.selectedDate.month == now.month &&
          _n.selectedDate.day == now.day;
      final todayDone =
          isViewingToday &&
          (slotsInRange.isEmpty ||
              slotsInRange.every((s) => s.end.isBefore(now)));

      final res = await _showModifDialog(
        context,
        title: 'Modifier la capacité',
        preview: 'Capacité : ${tsInfo.capacity} pers. → $newCapacity pers.',
        hasReservations: _n.hasReservationsInSlots(slotsInRange),
        isCapacity: true,
        todayDone: todayDone,
      );
      if (res == null) return;

      _n.setQueueLoading(queue.id);
      final result = await _n.agenda.modifySlotCapacity(
        queueId: queue.id,
        date: _n.selectedDate,
        newCapacity: newCapacity,
        type: res.type,
        timeSlotId: tsInfo.id,
      );
      if (mounted) {
        _snackBar(result);
        _n.refreshSilent();
      }
    } finally {
      _liveEditBusyQueueIds.remove(queue.id);
    }
  }

  // ── Sélecteur de plage horaire (bottom sheet) ────────────
  Future<_TimeSlotInfo?> _selectTimeSlot(_QueueAgenda queue) async {
    final timeslots = await _n.fetchTimeSlots(queue.id);
    if (timeslots.isEmpty) return null;

    // Les plages en cours de suppression programmée ne sont pas modifiables.
    final editable = timeslots.where((ts) => ts.deleteAfter == null).toList();
    if (editable.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Toutes les plages de cette file sont en cours de suppression.',
            ),
          ),
        );
      }
      return null;
    }
    // Sélection directe uniquement si la file n'a qu'une plage (et qu'elle
    // est modifiable) ; sinon on montre le sélecteur, où les plages en
    // suppression apparaissent grisées.
    if (timeslots.length == 1) return editable.first;
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
  final String companyId;
  final Color green;
  final bool isPast;
  final Future<void> Function(String name)? onAddClient;
  final Future<bool> Function(CustomerEntry customer)? onDeleteClient;

  const _SlotDetailDialog({
    required this.slot,
    required this.queue,
    required this.timeFormat,
    required this.agenda,
    required this.companyId,
    required this.green,
    this.isPast = false,
    this.onAddClient,
    this.onDeleteClient,
  });

  @override
  State<_SlotDetailDialog> createState() => _SlotDetailDialogState();
}

class _SlotDetailDialogState extends State<_SlotDetailDialog> {
  List<CustomerEntry>? _customers;
  bool _loadingNames = false;
  bool _showAddForm = false;
  final _nameCtrl = TextEditingController();
  String? _nameError;
  late int _reservedCount;

  @override
  void initState() {
    super.initState();
    _reservedCount = widget.slot.reserved;
    if (_reservedCount > 0) _loadNames();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteCustomer(CustomerEntry customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce client ?'),
        content: Text(
          '${customer.name} sera retiré de ce créneau. Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || widget.onDeleteClient == null) return;

    final ok = await widget.onDeleteClient!(customer);
    if (!mounted || !ok) return;
    setState(() {
      _customers?.removeWhere((c) => c.id == customer.id);
      _reservedCount--;
    });
  }

  Future<void> _loadNames() async {
    setState(() => _loadingNames = true);
    try {
      final customers = await widget.agenda.loadCustomers(
        widget.slot.id,
        companyId: widget.companyId,
      );
      if (mounted) setState(() => _customers = customers);
    } catch (_) {
      if (mounted) setState(() => _customers = []);
    } finally {
      if (mounted) setState(() => _loadingNames = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final tf = widget.timeFormat;
    final isFull = _reservedCount >= slot.capacity;
    final isBlocked = slot.isBlocked;
    final canAdd =
        !isFull && !isBlocked && !widget.isPast && widget.onAddClient != null;
    final remaining = slot.capacity - _reservedCount;

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
                  '$_reservedCount/${slot.capacity} places',
                ),
              ],
            ),

            const Divider(height: 28),

            // Section clients
            if (_reservedCount > 0) ...[
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
              else if (_customers != null && _customers!.isNotEmpty)
                ..._customers!.asMap().entries.map((entry) {
                  final c = entry.value;
                  final initial = c.name.isNotEmpty
                      ? c.name.trim()[0].toUpperCase()
                      : '?';
                  final circleBg = c.isCompanyManual
                      ? Colors.blue.shade50
                      : const Color(0xFFE8F5ED);
                  final circleText = c.isCompanyManual
                      ? Colors.blue.shade400
                      : _green;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: circleBg,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initial,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: circleText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (c.isCompanyManual && widget.onDeleteClient != null)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red.shade400,
                              size: 20,
                            ),
                            tooltip: 'Supprimer',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                            onPressed: () => _confirmDeleteCustomer(c),
                          ),
                      ],
                    ),
                  );
                })
              else
                Text(
                  'Aucun nom trouvé',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
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
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Nom du client',
                  hintText: 'Ex : Jean Dupont',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  errorText: _nameError,
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
                      _nameError = null;
                    }),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final name = _nameCtrl.text.trim();
                        if (name.isEmpty) {
                          setState(() => _nameError = 'Veuillez entrer un nom');
                          return;
                        }
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
    if (isFull) return _badge('Complet', _green);
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
  final DateTime? closureStart;
  final DateTime? closureEnd;

  _QueueAgenda({
    required this.id,
    required this.name,
    required this.slots,
    this.isBlocked = false,
    this.blockReason,
    required this.stats,
    this.weekdays = const [],
    this.timeSlotCount = 0,
    this.closureStart,
    this.closureEnd,
  });

  bool get isClosedNow => isQueueClosedNow(closureStart, closureEnd);

  /// Fermeture posée mais pas encore active (date de début future).
  DateTime? get closurePlannedFor {
    final cs = closureStart;
    if (cs == null || isClosedNow) return null;
    return cs.isAfter(DateTime.now()) ? cs : null;
  }
}

class _ModifResult {
  final ModificationType type;
  _ModifResult({required this.type});
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

  /// Non-null si une suppression programmée est en cours sur cette plage :
  /// elle est alors verrouillée (aucune modification possible tant que la
  /// suppression n'est pas restituée).
  final DateTime? deleteAfter;

  _TimeSlotInfo({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.capacity = 1,
    this.duration = 15,
    this.workingDays = const [],
    this.maxAdvanceDays = 3,
    this.maxReservationsPerPerson = 1,
    this.reservationDeadlineMinutes = 10,
    this.deleteAfter,
  });
}
