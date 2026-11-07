import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/agenda_service.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/company_booking_service.dart';
import 'package:baxa/services/company_functions.dart';
import 'package:baxa/services/company_schedule_service.dart';
import 'package:baxa/services/plage_rules.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:baxa/page b-acceuil/company/team_page.dart';
import 'package:baxa/page b-acceuil/company/settings_page.dart'
    show QueueTimeSlotsPage;
import 'package:baxa/main.dart' show routeObserver;
import 'package:baxa/services/onboarding_service.dart';
import 'package:baxa/widgets/onboarding_widgets.dart';
import 'package:baxa/widgets/baxa_date_picker_theme.dart';
import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';
import 'package:baxa/page%20b-acceuil/company/staff_revocation.dart';

part 'house_widgets.dart';
part 'house_dialogs.dart';
part 'house_notifier.dart';

// ── Palette (niveau bibliothèque — accessible dans tous les parts) ────────────
const Color _green = Color.fromARGB(255, 75, 139, 94);
const Color _lightGreen = Color.fromARGB(255, 178, 211, 194);

// Bornes des modifs du jour à l'accueil : les MÊMES que la page des plages
// (durées 5 à 30 min, capacité 1 à 30 pers.). MIROIR de company_schedule.js
// (changeDayDuration / changeDayCapacity), qui refuse au-delà.
const int _kMinDuration = 5;
const int _kMaxDuration = 30;
const int _kMinCapacity = 1;
const int _kMaxCapacity = 30;

// ============================================================
// HOUSE PAGE — AGENDA INTERACTIF DE L'ENTREPRISE
// ============================================================
class HousePage extends StatefulWidget {
  // Renseigné par StaffPage : l'accueil s'ouvre directement en mode staff
  // sur cette entreprise. Absent = accueil de l'admin (uid == companyId).
  final String? staffCompanyId;

  const HousePage({super.key, this.staffCompanyId});
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

  // Fin d'accès staff traitée (message + redirection) : le build peut
  // repasser plusieurs fois par l'état « révoqué », on n'agit qu'une fois.
  bool _revocationHandled = false;

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
    _n = _HouseNotifier(staffCompanyId: widget.staffCompanyId);
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
      // OnboardingService aussi : la carte Bienvenue reste affichée tant que
      // le parcours guidé est en cours, même si une file existe déjà.
      listenable: Listenable.merge([_n, OnboardingService()]),
      builder: (context, _) {
        // Staff retiré de l'équipe (détecté à l'ouverture ou en direct) :
        // déconnexion déjà faite côté notifier. On explique pourquoi (sauf
        // départ volontaire), puis on renvoie vers l'écran de choix en
        // vidant toute la pile de navigation.
        if (_n.revoked) {
          if (!_revocationHandled) {
            _revocationHandled = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _leaveAfterRevocation(),
            );
          }
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator(color: _green)),
          );
        }
        return _buildScaffold();
      },
    );
  }

  Future<void> _leaveAfterRevocation() async {
    if (!mounted) return;
    final msg = StaffRevocation.of(_n.revokedReason, _n.companyName);
    if (msg != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(msg.title),
          content: Text(msg.body),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ChoosePage()),
      (route) => false,
    );
  }

  // ── Bouton « + » : règle unique d'affichage et d'appui ────
  /// Créneaux de [queue] où l'on peut encore inscrire un client : non
  /// bloqués et pas encore commencés (aujourd'hui), ou du jour affiché s'il
  /// est futur. Les créneaux complets en font partie : une place peut se
  /// libérer à tout moment (annulation).
  Iterable<AgendaSlot> _upcomingOpenSlots(_QueueAgenda queue, DateTime now) {
    final today = plageDayOf(now);
    final selectedDay = plageDayOf(_n.selectedDate);
    // Borne basse : "maintenant" seulement si on regarde aujourd'hui (ou un
    // jour passé) — sinon le début du jour affiché.
    final lowerBound = selectedDay.isAfter(today) ? selectedDay : now;
    return queue.slots.where(
      (s) => !s.isBlocked && s.start.isAfter(lowerBound),
    );
  }

  /// Index de la file affichée dans le PageView (0 s'il n'y en a qu'une).
  int _visibleQueueIndex() {
    final count = _n.queues.length;
    if (count <= 1 || !_pageControllerReady || !_pageController.hasClients) {
      return 0;
    }
    return (_pageController.page ?? 0).round().clamp(0, count - 1);
  }

  /// Le « + » a-t-il une raison d'être sur la file affichée ? Non quand il
  /// ne reste aucun créneau à venir et non bloqué : jour passé, journée
  /// terminée, aucun créneau ce jour (jour non travaillé, fermeture), ou
  /// tout ce qui reste est bloqué. File en cours de chargement : visible,
  /// comme avant (évite un clignotement à chaque changement de date).
  bool _quickAddUseful() {
    final queues = _n.queues;
    if (queues.isEmpty) return true;
    final queue = queues[_visibleQueueIndex()];
    if (queue == null) return true;
    return _upcomingOpenSlots(queue, DateTime.now()).isNotEmpty;
  }

  // Carte Bienvenue : aucune file, ou parcours guidé en cours (une file peut
  // déjà exister sans plage — reprise après avoir quitté l'app). Le parcours
  // ne concerne que l'admin, jamais un compte staff.
  bool get _showWelcome =>
      !_n.hasQueues || (!_n.isStaff && OnboardingService().isActive);

  Widget _buildScaffold() {
    final showWelcome = _showWelcome;
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
          : showWelcome
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
      floatingActionButton: !showWelcome && _pageControllerReady
          // Suit la file affichée (défilement entre files) en plus des
          // données : se redessine à chaque changement de page.
          ? AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                // Deux raisons de se cacher, même animation : défilement
                // vers le bas, ou plus aucun créneau où inscrire quelqu'un.
                final show = _fabVisible && _quickAddUseful();
                return AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: show ? Offset.zero : const Offset(0, 1.4),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    scale: show ? 1.0 : 0.4,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: show ? 1.0 : 0.0,
                      child: IgnorePointer(ignoring: !show, child: child),
                    ),
                  ),
                );
              },
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
      // Toujours blanc, même quand la liste défile dessous : sans ça,
      // Material 3 teinte l'en-tête en vert pâle (visible avec une seule
      // file ; avec plusieurs, le défilement est dans un PageView et la
      // teinte ne se déclenchait pas).
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
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

  Widget _buildRetryState() => _RetryState(onRetry: _n.retry);

  Widget _buildEmptyState() => _EmptyState(hasQueue: _n.hasQueues);

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

  // ── File sans plage horaire ───────────────────────────────
  // Distinct de « Aucun créneau pour cette date » : ici il manque la
  // configuration elle-même. Le staff voit le message, sans le bouton.
  Widget _buildNoPlageState(_QueueAgenda queue) {
    final companyId = _n.companyId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.schedule_rounded, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Aucune plage horaire',
            style: GoogleFonts.poppins(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Vos clients ne peuvent pas encore réserver dans cette file.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
          if (!_n.isStaff && companyId != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QueueTimeSlotsPage(
                    companyId: companyId,
                    queueId: queue.id,
                    queueName: queue.name,
                    autoOpenSlotDialog: true,
                  ),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Ajouter une plage'),
              style: TextButton.styleFrom(
                foregroundColor: _green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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

          // File sans AUCUNE plage (même en suppression programmée) : passe
          // avant tous les autres états vides. Dès qu'une plage existe, la
          // logique habituelle ci-dessous reprend sans changement.
          if (slotsForQueue.isEmpty && queue.timeSlotCount == 0)
            _buildNoPlageState(queue)
          else if (slotsForQueue.isEmpty)
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
      // Journée terminée (aujourd'hui, tous les créneaux passés) traitée
      // comme un jour passé : plus rien à modifier ni à bloquer. Le
      // minuteur de fin de créneau du notifier fait la bascule en direct.
      isPastDay:
          selectedDay.isBefore(today) ||
          (queue.weekdays.isNotEmpty &&
              !queue.weekdays.contains(_n.selectedDate.weekday)) ||
          (selectedDay == today &&
              queue.slots.isNotEmpty &&
              queue.slots.every((s) => !s.end.isAfter(now))),
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
        canDeleteClient: _n.canDeleteManual,
        showNameHint: _n.showNameHint,
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
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'ui_interaction',
        parameters: {'widget_name': 'fab_ajouter_client'},
      ),
    );
    // 1. File actuellement affichée (page visible du PageView, ou l'unique
    // file s'il n'y en a qu'une) — le bouton + agit toujours sur ce que
    // l'utilisateur a sous les yeux, jamais sur une autre file. Même index
    // que celui qui décide d'afficher le bouton (_quickAddUseful).
    if (_n.queues.isEmpty) return;
    final bestQueue = _n.queues[_visibleQueueIndex()];
    if (bestQueue == null) return; // file encore en chargement

    // Même règle que l'affichage du bouton (_upcomingOpenSlots), plus une
    // place libre : si tout est complet, le message ci-dessous l'explique.
    final hasCandidate = _upcomingOpenSlots(
      bestQueue,
      DateTime.now(),
    ).any((s) => s.reserved < s.capacity);

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
        showNameHint: _n.showNameHint,
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
      final now = DateTime.now();
      final anyBlockable = timeslots.any(
        (ts) =>
            _plageDayState(ts, queue.slots, now) == _PlageDayState.available,
      );
      if (!anyBlockable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aucune plage à bloquer pour le moment'),
            ),
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
                if (error == null) _logQuickEdit('block');
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
    if (!_liveEditBusyQueueIds.add(queue.id)) return;
    try {
      final result = await _n.unblockPlage(queue.id);
      if (result.success) _logQuickEdit('unblock');
      if (mounted) _snackBar(result);
    } finally {
      _liveEditBusyQueueIds.remove(queue.id);
    }
  }

  // ── Modifs du jour : éléments communs ─────────────────────
  // L'accueil ne modifie que le jour affiché. Les valeurs de départ des
  // boutons +/− sont celles du jour (voir _HouseNotifier.dayValuesFor) ;
  // la plage elle-même se modifie durablement dans la page des plages.

  /// « Pour aujourd'hui uniquement » / « Pour le mardi 4 nov. uniquement ».
  String _modifDayLabel() {
    final now = DateTime.now();
    final sel = _n.selectedDate;
    if (plageDayOf(sel) == plageDayOf(now)) {
      return 'Pour aujourd\'hui uniquement';
    }
    return 'Pour le ${DateFormat('EEEE d MMM', 'fr_FR').format(sel)} '
        'uniquement';
  }

  /// Créneaux à venir de la plage ce jour-là (ceux qu'une modif touche).
  List<AgendaSlot> _upcomingSlotsOf(_QueueAgenda queue, String timeSlotId) {
    final now = DateTime.now();
    return queue.slots
        .where((s) => s.timeSlotId == timeSlotId && s.end.isAfter(now))
        .toList();
  }

  /// Ouvre la page des plages de cette file (modifs durables).
  void _openPlagesPage(_QueueAgenda queue) {
    final companyId = _n.companyId;
    if (companyId == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QueueTimeSlotsPage(
          companyId: companyId,
          queueId: queue.id,
          queueName: queue.name,
        ),
      ),
    );
  }

  // ── Modification durée ────────────────────────────────────
  Future<void> _onDurationChanged(_QueueAgenda queue, int delta) async {
    if (!_liveEditBusyQueueIds.add(queue.id)) return;
    try {
      final tsInfo = await _selectTimeSlot(
        queue,
        forDuration: true,
        delta: delta,
      );
      // La page a pu être quittée pendant le choix de la plage.
      if (tsInfo == null || !mounted) return;

      final current = tsInfo.effectiveDuration;
      final newDuration = (current + delta).clamp(_kMinDuration, _kMaxDuration);
      if (newDuration == current) return;

      final plageStart = _parseTimeString(tsInfo.startTime, _n.selectedDate);
      final plageEnd = _parseTimeString(tsInfo.endTime, _n.selectedDate);

      final confirmed = await _showModifDialog(
        context,
        title: 'Modifier la durée',
        preview: 'Durée : $current min → $newDuration min',
        dayLabel: _modifDayLabel(),
        hasReservations: _n.hasReservationsInSlots(
          _upcomingSlotsOf(queue, tsInfo.id),
        ),
        isCapacity: false,
        onOpenPlages: () => _openPlagesPage(queue),
      );
      if (!confirmed) return;

      _n.setQueueLoading(queue.id);
      final result = await _n.applyDurationChange(
        queue: queue,
        tsInfo: tsInfo,
        plageStart: plageStart,
        plageEnd: plageEnd,
        newDuration: newDuration,
      );
      if (result.success) {
        _logQuickEdit(delta > 0 ? 'duration_increase' : 'duration_decrease');
      }
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
    if (result.success) _logQuickEdit('revert');
    if (mounted) {
      _snackBar(result);
      if (result.success) _n.refreshSilent();
    }
  }

  // ── Modification capacité ─────────────────────────────────
  // Ne jamais bloquer la réduction de capacité au prétexte qu'un créneau est
  // complet : le serveur (changeDayCapacity) clampe déjà, créneau par créneau, la
  // nouvelle capacité au nombre de réservations existantes (un créneau
  // complet garde sa capacité et ses réservations intactes, les autres
  // s'ajustent normalement). Un pré-check bloquant ici serait redondant et,
  // pire, empêcherait un ajustement légitime dès qu'UN SEUL créneau de la
  // plage est complet.
  Future<void> _onCapacityChanged(_QueueAgenda queue, int delta) async {
    if (!_liveEditBusyQueueIds.add(queue.id)) return;
    try {
      final tsInfo = await _selectTimeSlot(
        queue,
        forDuration: false,
        delta: delta,
      );
      // La page a pu être quittée pendant le choix de la plage.
      if (tsInfo == null || !mounted) return;

      final current = tsInfo.effectiveCapacity;
      final newCapacity = (current + delta).clamp(_kMinCapacity, _kMaxCapacity);
      if (newCapacity == current) return;

      final confirmed = await _showModifDialog(
        context,
        title: 'Modifier la capacité',
        preview: 'Capacité : $current pers. → $newCapacity pers.',
        dayLabel: _modifDayLabel(),
        hasReservations: _n.hasReservationsInSlots(
          _upcomingSlotsOf(queue, tsInfo.id),
        ),
        isCapacity: true,
        onOpenPlages: () => _openPlagesPage(queue),
      );
      if (!confirmed) return;

      _n.setQueueLoading(queue.id);
      final result = await _n.changeDayCapacity(
        queueId: queue.id,
        newCapacity: newCapacity,
        timeSlotId: tsInfo.id,
      );
      if (result.success) {
        _logQuickEdit(delta > 0 ? 'capacity_increase' : 'capacity_decrease');
      }
      if (mounted) {
        _snackBar(result);
        _n.refreshSilent();
      }
    } finally {
      _liveEditBusyQueueIds.remove(queue.id);
    }
  }

  // ── Sélecteur de plage horaire (bottom sheet) ────────────
  // Plages triées, avec leurs valeurs DU JOUR. Une plage non modifiable
  // apparaît grisée avec sa raison : bloquée, terminée, suppression
  // programmée, sans créneau ce jour, ou — pour la durée seulement — sans
  // créneau libre à recalculer (tous les créneaux restants sont réservés).
  //
  // [delta] : sens du changement demandé. Une plage déjà à la borne dans ce
  // sens (durée 5 / 30 min, capacité 1 / 30 pers.) est grisée avec la
  // raison, comme les boutons + / − de la carte. Une plage sans créneau ce
  // jour-là est simplement grisée, sans mention (raison vide).
  Future<_TimeSlotInfo?> _selectTimeSlot(
    _QueueAgenda queue, {
    required bool forDuration,
    required int delta,
  }) async {
    final fetched = await _n.fetchTimeSlots(queue.id);
    if (fetched.isEmpty || !mounted) return null;

    final now = DateTime.now();
    final entries = [
      for (final ts in fetched)
        () {
          final info = _n.withDayValues(queue, ts);
          final state = _plageDayState(info, queue.slots, now);
          String? disabledReason = state == _PlageDayState.noSlots
              ? ''
              : _plageDayStateLabel(state, info);
          if (disabledReason == null && forDuration && !info.hasFreeSlot) {
            disabledReason = 'Aucun créneau libre à modifier';
          }
          disabledReason ??= _boundReason(info, forDuration, delta);
          return (ts: info, disabledReason: disabledReason);
        }(),
    ];

    // Une seule plage : choix direct, ou explication si elle n'est pas
    // modifiable (au lieu de ne rien faire).
    if (entries.length == 1) {
      final only = entries.first;
      if (only.disabledReason == null) return only.ts;
      final reason = only.disabledReason!.isEmpty
          ? 'pas de créneau ce jour'
          : only.disabledReason!.toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modification impossible pour le moment : $reason.'),
        ),
      );
      return null;
    }

    return showModalBottomSheet<_TimeSlotInfo>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TimeslotPickerSheet(
        entries: entries,
        title: 'Quelle plage modifier ?',
      ),
    );
  }

  /// Raison de griser une plage déjà à la borne dans le sens demandé, ou
  /// null si le changement est possible.
  String? _boundReason(_TimeSlotInfo ts, bool forDuration, int delta) {
    if (forDuration) {
      final d = ts.effectiveDuration;
      if (delta > 0 && d >= _kMaxDuration) {
        return 'Durée maximale atteinte ($_kMaxDuration min)';
      }
      if (delta < 0 && d <= _kMinDuration) {
        return 'Durée minimale atteinte ($_kMinDuration min)';
      }
    } else {
      final c = ts.effectiveCapacity;
      if (delta > 0 && c >= _kMaxCapacity) {
        return 'Capacité maximale atteinte ($_kMaxCapacity pers.)';
      }
      if (delta < 0 && c <= _kMinCapacity) {
        return 'Capacité minimale atteinte ($_kMinCapacity pers.)';
      }
    }
    return null;
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

  // ── Analytics : modifs rapides & widgets ────────────────────
  void _logQuickEdit(String action) {
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'timeslot_quick_edit',
        parameters: {'action': action},
      ),
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

  /// Droit de supprimer cette inscription (admin : toutes ; staff : les
  /// siennes) — fourni par le notifier.
  final bool Function(CustomerEntry customer) canDeleteClient;

  /// Affiche l'exemple « Ex : Jean Dupont » (5 premières inscriptions).
  final bool showNameHint;

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
    required this.canDeleteClient,
    this.showNameHint = true,
  });

  @override
  State<_SlotDetailDialog> createState() => _SlotDetailDialogState();
}

class _SlotDetailDialogState extends State<_SlotDetailDialog> {
  List<CustomerEntry>? _customers;
  bool _loadingNames = false;
  bool _showAddForm = false;
  final _nameCtrl = TextEditingController();
  final _listCtrl = ScrollController();
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
    _listCtrl.dispose();
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

    final media = MediaQuery.of(context);
    // Hauteur max du panneau : 60 % de l'écran. Clavier ouvert, le panneau
    // remonte au-dessus et se limite encore pour laisser l'App Bar visible
    // en haut — c'est alors la liste des clients qui rétrécit (marge basse
    // réduite au passage : la barre système est sous le clavier).
    final keyboard = media.viewInsets.bottom;
    final bottomPadding = keyboard > 0 ? 16.0 : 28.0 + media.padding.bottom;
    final appBarReserve = media.padding.top + kToolbarHeight;
    final maxSheetHeight = math.min(
      media.size.height * 0.60,
      media.size.height - keyboard - appBarReserve,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
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
                // Seule zone qui défile : l'en-tête au-dessus et le bouton
                // d'ajout en dessous restent toujours visibles. Peu de
                // clients → hauteur naturelle ; au-delà de la hauteur max du
                // panneau, la liste défile.
                Flexible(
                  child: Scrollbar(
                    controller: _listCtrl,
                    child: ListView(
                      controller: _listCtrl,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final c in _customers!) _customerRow(c),
                      ],
                    ),
                  ),
                )
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
                  hintText: widget.showNameHint ? 'Ex : Jean Dupont' : null,
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

  Widget _customerRow(CustomerEntry c) {
    final initial = c.name.isNotEmpty ? c.name.trim()[0].toUpperCase() : '?';
    final circleBg = c.isCompanyManual
        ? Colors.blue.shade50
        : const Color(0xFFE8F5ED);
    final circleText = c.isCompanyManual ? Colors.blue.shade400 : _green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
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
          // Nom sur 2 lignes max, tronqué par « … » quelle que soit sa
          // longueur, sans jamais déplacer la poubelle.
          Expanded(
            child: Text(
              c.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          if (widget.onDeleteClient != null && widget.canDeleteClient(c))
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

  /// Tout ce qui reste à venir ce jour est bloqué (ou, journée terminée :
  /// tous ses créneaux l'ont été). Masque durée/capacité, badge « Bloquée ».
  final bool isBlocked;

  /// Au moins un créneau bloqué n'est pas encore terminé : le bouton de la
  /// carte devient « Débloquer » (qui rouvre tout ce qui est bloqué).
  final bool hasActiveBlock;

  /// Plages bloquées en partie de journée (« 08:00–12:00 »), null si aucune
  /// ou si tout est bloqué.
  final String? blockedPlagesLabel;
  final String? blockReason;
  final QueueStats stats;
  /// Jours où au moins une plage de la file est ouverte (1 = lundi) ; vide
  /// = aucune plage connue (tous les jours traités comme ouvrés).
  final List<int> weekdays;
  final int timeSlotCount;
  final DateTime? closureStart;
  final DateTime? closureEnd;

  _QueueAgenda({
    required this.id,
    required this.name,
    required this.slots,
    this.isBlocked = false,
    this.hasActiveBlock = false,
    this.blockedPlagesLabel,
    this.blockReason,
    required this.stats,
    this.weekdays = const [],
    this.timeSlotCount = 0,
    this.closureStart,
    this.closureEnd,
  });

  /// Même file, créneaux [newSlots] (ou les mêmes) : l'état de blocage et
  /// les stats sont recalculés pour l'instant [now] — ils dépendent de
  /// l'heure (un blocage se termine avec son dernier créneau).
  _QueueAgenda rebuiltAt(
    DateTime now, {
    List<AgendaSlot>? newSlots,
    QueueStats? newStats,
    int? newTimeSlotCount,
    List<int>? newWeekdays,
  }) {
    final s = newSlots ?? slots;
    final block = _blockStateOf(s, now);
    return _QueueAgenda(
      id: id,
      name: name,
      slots: s,
      isBlocked: block.isBlocked,
      hasActiveBlock: block.hasActiveBlock,
      blockedPlagesLabel: block.blockedPlagesLabel,
      blockReason: block.reason,
      stats: newStats ?? AgendaService().computeStats(s, now: now),
      weekdays: newWeekdays ?? weekdays,
      timeSlotCount: newTimeSlotCount ?? timeSlotCount,
      closureStart: closureStart,
      closureEnd: closureEnd,
    );
  }

  bool get isClosedNow => isQueueClosedNow(closureStart, closureEnd);

  /// Fermeture posée mais pas encore active (date de début future).
  DateTime? get closurePlannedFor {
    final cs = closureStart;
    if (cs == null || isClosedNow) return null;
    return cs.isAfter(DateTime.now()) ? cs : null;
  }
}

/// État d'une plage pour la journée affichée, vu des boutons de l'accueil.
enum _PlageDayState {
  /// Modifiable / blocable.
  available,

  /// Tous ses créneaux du jour sont terminés.
  ended,

  /// Bloquée (incident en cours) : aucune modif ce jour-là.
  blocked,

  /// Suppression programmée : verrouillée.
  deferred,

  /// Aucun créneau ce jour (jour non travaillé pour cette plage).
  noSlots,
}

_PlageDayState _plageDayState(
  _TimeSlotInfo ts,
  List<AgendaSlot> daySlots,
  DateTime now,
) {
  if (ts.deleteAfter != null) return _PlageDayState.deferred;
  final plage = daySlots.where((s) => s.timeSlotId == ts.id).toList();
  if (plage.isEmpty) return _PlageDayState.noSlots;
  final remaining = plage.where((s) => s.end.isAfter(now)).toList();
  if (remaining.isEmpty) return _PlageDayState.ended;
  if (remaining.any((s) => s.isBlocked)) return _PlageDayState.blocked;
  return _PlageDayState.available;
}

/// Mention affichée sous / à côté d'une plage non disponible.
String? _plageDayStateLabel(_PlageDayState state, _TimeSlotInfo ts) {
  switch (state) {
    case _PlageDayState.available:
      return null;
    case _PlageDayState.ended:
      return 'Terminée';
    case _PlageDayState.blocked:
      return 'Bloquée';
    case _PlageDayState.deferred:
      return 'Suppression programmée le '
          '${DateFormat('d MMM', 'fr_FR').format(ts.deleteAfter!)}';
    case _PlageDayState.noSlots:
      return 'Pas de créneau ce jour';
  }
}

/// État de blocage d'une file pour la journée affichée, à l'instant [now].
///
/// Un blocage n'est « en cours » que tant qu'un créneau bloqué n'est pas
/// terminé : quand la plage bloquée se termine, la carte repasse sur
/// « Bloquer » (la structure peut bloquer la plage suivante). Les clients
/// de ces créneaux sont prévenus côté serveur à la fin de chaque créneau.
({
  bool isBlocked,
  bool hasActiveBlock,
  String? reason,
  String? blockedPlagesLabel,
})
_blockStateOf(List<AgendaSlot> slots, DateTime now) {
  final remaining = slots.where((s) => s.end.isAfter(now)).toList();
  final activeBlocked = remaining.where((s) => s.isBlocked).toList();
  final hasActiveBlock = activeBlocked.isNotEmpty;

  // Journée terminée : on garde la lecture historique (tout a été bloqué).
  final isBlocked = remaining.isNotEmpty
      ? remaining.every((s) => s.isBlocked)
      : slots.isNotEmpty && slots.every((s) => s.isBlocked);

  final reasonSource = hasActiveBlock
      ? activeBlocked
      : (isBlocked ? slots : const <AgendaSlot>[]);
  String? reason;
  for (final s in reasonSource) {
    final r = s.blockReason?.trim();
    if (r != null && r.isNotEmpty) {
      reason = r;
      break;
    }
  }

  // Blocage partiel : quelles plages ? (bornes de la plage ce jour-là)
  String? label;
  if (hasActiveBlock && !isBlocked) {
    final fmt = DateFormat('HH:mm');
    final ranges = <({DateTime start, DateTime end})>[];
    for (final tsId in activeBlocked.map((s) => s.timeSlotId).toSet()) {
      final plage = slots.where((s) => s.timeSlotId == tsId).toList();
      if (plage.isEmpty) continue;
      var start = plage.first.start;
      var end = plage.first.end;
      for (final s in plage) {
        if (s.start.isBefore(start)) start = s.start;
        if (s.end.isAfter(end)) end = s.end;
      }
      ranges.add((start: start, end: end));
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    // Fin à minuit pile (plage « jusqu'à 24:00 ») : affichée 24:00.
    String endText(DateTime start, DateTime end) =>
        end.day != start.day && end.hour == 0 && end.minute == 0
        ? '24:00'
        : fmt.format(end);
    if (ranges.isNotEmpty) {
      label = ranges
          .map((r) => '${fmt.format(r.start)}–${endText(r.start, r.end)}')
          .join(', ');
    }
  }

  return (
    isBlocked: isBlocked,
    hasActiveBlock: hasActiveBlock,
    reason: reason,
    blockedPlagesLabel: label,
  );
}

class _TimeSlotInfo {
  final String id;
  final String startTime;
  final String endTime;

  /// Valeurs HABITUELLES de la plage (document timeSlot) : ne changent que
  /// par une modif durable, faite dans la page des plages.
  final int capacity;
  final int duration;
  final List<int> workingDays;
  final int maxAdvanceDays;
  final int reservationDeadlineMinutes;

  /// Non-null si une suppression programmée est en cours sur cette plage :
  /// elle est alors verrouillée (aucune modification possible tant que la
  /// suppression n'est pas restituée).
  final DateTime? deleteAfter;

  /// Valeurs RÉELLES du jour affiché, lues sur ses créneaux (elles diffèrent
  /// des habituelles après une modif du jour faite depuis l'accueil). Null
  /// tant qu'elles n'ont pas été calculées, ou faute de créneau à lire.
  final int? dayDuration;
  final int? dayCapacity;

  /// Il reste au moins un créneau à venir, ouvert et sans réservation : la
  /// durée du jour est modifiable (seuls ces créneaux sont recalculés).
  final bool hasFreeSlot;

  _TimeSlotInfo({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.capacity = 1,
    this.duration = 15,
    this.workingDays = const [],
    this.maxAdvanceDays = 3,
    this.reservationDeadlineMinutes = 10,
    this.deleteAfter,
    this.dayDuration,
    this.dayCapacity,
    this.hasFreeSlot = true,
  });

  /// Durée en vigueur ce jour-là (repli : la durée habituelle).
  int get effectiveDuration => dayDuration ?? duration;

  /// Capacité en vigueur ce jour-là (repli : la capacité habituelle).
  int get effectiveCapacity => dayCapacity ?? capacity;

  _TimeSlotInfo withDayValues({
    required int? dayDuration,
    required int? dayCapacity,
    required bool hasFreeSlot,
  }) => _TimeSlotInfo(
    id: id,
    startTime: startTime,
    endTime: endTime,
    capacity: capacity,
    duration: duration,
    workingDays: workingDays,
    maxAdvanceDays: maxAdvanceDays,
    reservationDeadlineMinutes: reservationDeadlineMinutes,
    deleteAfter: deleteAfter,
    dayDuration: dayDuration,
    dayCapacity: dayCapacity,
    hasFreeSlot: hasFreeSlot,
  );
}
