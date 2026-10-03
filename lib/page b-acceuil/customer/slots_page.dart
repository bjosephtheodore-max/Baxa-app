import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:baxa/page%20b-acceuil/customer/signine_page.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/favorites_service.dart';
import 'package:baxa/services/reservation_rules_service.dart';

class SlotsPage extends StatefulWidget {
  final String entrepriseId;
  final String entrepriseNom;
  final String queueId;
  final String queueName;
  final Color primaryGreen;
  final Color lightGreen;
  final VoidCallback onReservationSuccess;

  // Config de la file connue de l'écran précédent (il vient de lire le même
  // doc). Quand fournie, la page démarre sans attendre le serveur : bandeau
  // de jours complet dès la 1ʳᵉ image, plus de valeur devinée.
  // (Les jours d'ouverture, eux, viennent des plages — pas du doc file.)
  final int? initialMaxAdvanceDays;
  final int? initialDeadlineMinutes;
  final DateTime? initialCutoffDate;
  final bool? initialAllowMultiplePerPlage;

  const SlotsPage({
    super.key,
    required this.entrepriseId,
    this.entrepriseNom = '',
    required this.queueId,
    required this.queueName,
    required this.primaryGreen,
    required this.lightGreen,
    required this.onReservationSuccess,
    this.initialMaxAdvanceDays,
    this.initialDeadlineMinutes,
    this.initialCutoffDate,
    this.initialAllowMultiplePerPlage,
  });

  // À utiliser quand l'écran appelant a déjà le doc `queues/{id}` en main :
  // la page démarre alors sans attendre le serveur pour sa config.
  factory SlotsPage.fromQueueData({
    Key? key,
    required String companyId,
    required String queueId,
    required Map<String, dynamic> queueData,
    String entrepriseNom = '',
    required Color primaryGreen,
    required Color lightGreen,
    required VoidCallback onReservationSuccess,
  }) {
    return SlotsPage(
      key: key,
      entrepriseId: companyId,
      entrepriseNom: entrepriseNom,
      queueId: queueId,
      queueName: queueData['name'] as String? ?? 'File',
      primaryGreen: primaryGreen,
      lightGreen: lightGreen,
      onReservationSuccess: onReservationSuccess,
      initialMaxAdvanceDays: (queueData['maxAdvanceDays'] as num?)?.toInt() ?? 2,
      initialDeadlineMinutes:
          (queueData['reservationDeadlineMinutes'] as num?)?.toInt() ?? 0,
      initialCutoffDate: (queueData['reservationCutoffDate'] as Timestamp?)
          ?.toDate()
          .toLocal(),
      initialAllowMultiplePerPlage:
          (queueData['allowMultiplePerPlage'] as bool?) ?? false,
    );
  }

  // Préchauffe le cache Firestore (créneaux + plages) — à appeler juste avant
  // de pousser SlotsPage. Les données arrivent souvent avant la fin de la
  // transition de page, la liste s'affiche alors sans attente visible.
  static void prefetch(String companyId, String queueId) {
    final now = DateTime.now();
    final upper = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: _kInitialWindowDays + 1));
    final queue = FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .doc(queueId);
    queue
        .collection('slots')
        .where('start', isLessThan: Timestamp.fromDate(upper))
        .orderBy('start')
        .get()
        .ignore();
    queue.collection('timeSlots').get().ignore();
  }

  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

// Fenêtre (en jours) chargée au premier affichage ; le reste de l'horizon
// d'anticipation est chargé juste après, en arrière-plan.
const int _kInitialWindowDays = 2;

class _SlotsPageState extends State<SlotsPage>
    with SingleTickerProviderStateMixin {
  // Palette unifiée de la page (un seul vert, fond chaud, zéro ombre).
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenTint = Color(0xFFEEF4EF);
  static const Color _greenTintBorder = Color(0xFFD9E6DD);
  static const Color _bg = Color(0xFFFAF9F6);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceMuted = Color(0xFFF6F5F1);
  static const Color _ink = Color(0xFF1F2430);
  static const Color _inkSoft = Color(0xFF6B7280);
  static const Color _inkFaint = Color(0xFF9AA0A8);
  static const Color _hairline = Color(0xFFEAE8E2);

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final DateFormat _timeFmt = DateFormat('HH:mm');
  final DateFormat _dateFmtFull = DateFormat('EEEE d MMMM', 'fr_FR');
  final _rulesService = ReservationRulesService();

  DateTime _selectedDate = DateTime.now();
  bool _showPastSlots = false;
  late final AnimationController _pastSlotsCtrl;

  int _maxAdvanceDays = 2;
  int _reservationDeadlineMinutes = 0;
  bool _allowMultiplePerPlage = false;
  // Nombre de plages actives (hors suppression programmée) de cette file —
  // sert au retour auto conditionnel quand le réglage ci-dessus est activé.
  int _totalActivePlages = 1;
  // Jours où AU MOINS UNE plage de la file travaille (union des `workingDays`
  // de toutes les plages). null = pas encore chargé → on ne déclare aucun
  // jour « fermé » tant qu'on ne sait pas.
  Set<int>? _openWeekdays;
  StreamSubscription<QuerySnapshot>? _timeSlotsSub;
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

  // Créneaux chargés. Fenêtre courante = `_loadedWindowDays` jours à venir ;
  // elle est élargie à tout l'horizon d'anticipation juste après le 1ᵉʳ rendu.
  // On garde `_slots` en mémoire : élargir ne fait pas clignoter la liste.
  List<QueryDocumentSnapshot> _slots = [];
  bool _slotsLoaded = false;
  int _loadedWindowDays = 0;
  StreamSubscription<QuerySnapshot>? _slotsSub;

  // Créneaux de CETTE file déjà réservés par le client (suivis en temps réel) :
  // sert à afficher l'état « Réservé » sur la bonne carte.
  Set<String> _myReservedSlotIds = {};
  StreamSubscription<QuerySnapshot>? _myReservationsSub;

  // Places encore libres par jour (id `AAAA-MM-JJ`), lues sur `dailyStats` —
  // pilote les pastilles vertes du bandeau sans dépendre du chargement complet
  // des créneaux.
  Map<String, int> _dailyAvailable = {};
  StreamSubscription<QuerySnapshot>? _dailyStatsSub;

  @override
  void initState() {
    super.initState();
    _pastSlotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 180),
    );

    // Réveil anticipé de la fonction de réservation : le temps que le
    // client choisisse son créneau, elle est prête à répondre vite.
    _rulesService.warmUp();

    // Config transmise par l'écran précédent → démarrage sans attente serveur.
    if (widget.initialMaxAdvanceDays != null) {
      _maxAdvanceDays = widget.initialMaxAdvanceDays!;
      _reservationDeadlineMinutes = widget.initialDeadlineMinutes ?? 0;
      _reservationCutoffDate = widget.initialCutoffDate;
      _allowMultiplePerPlage = widget.initialAllowMultiplePerPlage ?? false;
      _configLoaded = true;
    }

    _subscribeSlots(
      _maxAdvanceDays < _kInitialWindowDays
          ? _maxAdvanceDays
          : _kInitialWindowDays,
    );
    // Élargir à tout l'horizon d'anticipation juste après la 1ʳᵉ image.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeWidenSlots());

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
    _listenMyReservations();
    _listenDailyStats();
    _listenOpenWeekdays();
    _loadCompanyConfig();
  }

  // Jours d'ouverture réels de la file = union des `workingDays` de ses plages
  // (`timeSlots`). C'est LA source des jours « fermés » côté client — le champ
  // `queue.weekdays` ne reflète plus la réalité depuis que les jours sont
  // réglés par plage.
  void _listenOpenWeekdays() {
    _timeSlotsSub = _fs
        .collection('companies')
        .doc(widget.entrepriseId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('timeSlots')
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final days = <int>{};
            var activePlages = 0;
            for (final d in snap.docs) {
              final data = d.data();
              final wd = data['workingDays'] as List<dynamic>?;
              if (wd != null) {
                days.addAll(wd.map((e) => (e as num).toInt()));
              } else {
                days.addAll(const [1, 2, 3, 4, 5]); // plage legacy sans champ
              }
              // Une plage en cours de suppression programmée ne compte plus
              // pour le retour auto conditionnel (plus de résa possible).
              if (data['deleteAfter'] == null) activePlages++;
            }
            // TODO(diag) retirer une fois le comportement confirmé sur appareil.
            debugPrint('🔎[SLOTS] union workingDays plages = $days');
            setState(() {
              _openWeekdays = days;
              _totalActivePlages = activePlages > 0 ? activePlages : 1;
            });
          },
          onError: (_) {},
        );
  }

  // Abonnement aux créneaux sur une fenêtre de `windowDays` jours à venir.
  // Rappelable pour élargir la fenêtre : l'ancienne liste reste affichée
  // jusqu'à l'arrivée du nouveau snapshot (pas de clignotement).
  void _subscribeSlots(int windowDays) {
    _loadedWindowDays = windowDays;
    _slotsSub?.cancel();
    final now = DateTime.now();
    final upper = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: windowDays + 1));
    _slotsSub = _fs
        .collection('companies')
        .doc(widget.entrepriseId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots')
        .where('start', isLessThan: Timestamp.fromDate(upper))
        .orderBy('start')
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _slots = snap.docs;
              _slotsLoaded = true;
            });
          },
          onError: (_) {
            if (mounted) setState(() => _slotsLoaded = true);
          },
        );
  }

  void _maybeWidenSlots() {
    if (!mounted) return;
    if (_maxAdvanceDays > _loadedWindowDays) {
      _subscribeSlots(_maxAdvanceDays);
    }
  }

  // Résumé « places libres par jour » — maintenu en direct par la génération
  // et les transactions de réservation/annulation.
  void _listenDailyStats() {
    _dailyStatsSub = _fs
        .collection('companies')
        .doc(widget.entrepriseId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('dailyStats')
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _dailyAvailable = {
                for (final d in snap.docs)
                  d.id: (d.data()['available'] as num?)?.toInt() ?? 0,
              };
            });
          },
          onError: (_) {},
        );
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // Réservations confirmées du client dans cette file — pour marquer sa carte.
  void _listenMyReservations() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _myReservationsSub = _fs
        .collection('companies')
        .doc(widget.entrepriseId)
        .collection('reservations')
        .where('customerId', isEqualTo: uid)
        .where('queueId', isEqualTo: widget.queueId)
        .where('status', isEqualTo: 'confirmed')
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _myReservedSlotIds = snap.docs
                  .map((d) => (d.data()['slotId'] as String?) ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet();
            });
          },
          onError: (_) {},
        );
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
    final closureStart = (data['closureStart'] as Timestamp?)?.toDate();
    final closureEnd = (data['closureEnd'] as Timestamp?)?.toDate();
    // TODO(diag) retirer une fois le comportement confirmé sur appareil.
    debugPrint('🔎[SLOTS] queue.weekdays = ${data['weekdays']}');
    setState(() {
      _queueUnavailable = false;
      _queueClosed = isQueueClosedNow(closureStart, closureEnd);
      _queueClosureEnd = closureEnd;
      _liveQueueName = data['name'] as String? ?? _liveQueueName;
      _maxAdvanceDays = (data['maxAdvanceDays'] as int?) ?? 2;
      _reservationDeadlineMinutes =
          (data['reservationDeadlineMinutes'] as int?) ?? 0;
      _reservationCutoffDate = (data['reservationCutoffDate'] as Timestamp?)
          ?.toDate()
          .toLocal();
      _allowMultiplePerPlage = (data['allowMultiplePerPlage'] as bool?) ?? false;
      _configLoaded = true;
    });
    // L'horizon réel a peut-être grandi → élargir la fenêtre chargée.
    _maybeWidenSlots();
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _slotsSub?.cancel();
    _myReservationsSub?.cancel();
    _dailyStatsSub?.cancel();
    _timeSlotsSub?.cancel();
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
    } catch (_) {
      // Doc entreprise illisible (droits, réseau) : on garde l'état courant.
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
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: BackButton(
            color: _ink,
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

    final now = DateTime.now();
    final deadline = Duration(minutes: _reservationDeadlineMinutes);

    final allFutureSlots = _slots.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final start = (data['start'] as Timestamp).toDate().toLocal();
      final end = (data['end'] as Timestamp).toDate().toLocal();
      return end.isAfter(now) && start.isAfter(now.add(deadline));
    }).toList();

    final availableDays = <DateTime>[];
    if (_configLoaded) {
      final today = _dateOnly(now);
      for (int i = 0; i <= _maxAdvanceDays; i++) {
        availableDays.add(today.add(Duration(days: i)));
      }
      if (!availableDays.any((d) => _isSameDay(d, _selectedDate))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedDate = availableDays.first);
        });
      }
    }

    final allDailySlots = _slots.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final start = (data['start'] as Timestamp).toDate().toLocal();
      return _isSameDay(start, _selectedDate);
    }).toList();

    final futureDailySlots = allFutureSlots.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final start = (data['start'] as Timestamp).toDate().toLocal();
      return _isSameDay(start, _selectedDate);
    }).toList();

    // Jour « fermé » = connu ET aucune plage n'y travaille. Tant que les
    // plages ne sont pas chargées, on ne ferme rien.
    final isClosedDay =
        _openWeekdays != null &&
        !_openWeekdays!.contains(_selectedDate.weekday);
    final isCutoffDay =
        _reservationCutoffDate != null &&
        _dateOnly(_selectedDate).isAfter(_dateOnly(_reservationCutoffDate!));
    final selectedDay = _dateOnly(_selectedDate);
    final isClosurePeriodDay =
        _closureStart != null &&
        _closureEnd != null &&
        !selectedDay.isBefore(_dateOnly(_closureStart!)) &&
        !selectedDay.isAfter(_dateOnly(_closureEnd!));

    // Le jour sélectionné est-il encore en cours de chargement (fenêtre pas
    // encore assez large, ou tout premier chargement) ?
    final selectedOffset = _dateOnly(_selectedDate).difference(_dateOnly(now)).inDays;
    final dayLoading = !_slotsLoaded || selectedOffset > _loadedWindowDays;
    final windowComplete = _slotsLoaded && _loadedWindowDays >= _maxAdvanceDays;

    Widget content;
    if (!_configLoaded) {
      // Config pas encore connue (appelant sans `initial*`) : on ne dessine
      // pas le bandeau de jours tant qu'on ignore l'horizon réel.
      content = _slotsLoaded
          ? _buildSlotSkeleton()
          : const Center(child: CircularProgressIndicator(color: _green));
    } else if (isClosurePeriodDay) {
      content = _buildClosurePeriodDayState();
    } else if (isCutoffDay) {
      content = _buildCutoffDayState();
    } else if (isClosedDay) {
      content = _buildClosedDayState();
    } else if (allDailySlots.isEmpty && dayLoading) {
      content = _buildSlotSkeleton();
    } else if (allDailySlots.isEmpty) {
      content = _buildEmptyState(
        noSlots: allFutureSlots.isEmpty && windowComplete,
      );
    } else {
      content = _buildSlotList(allDailySlots);
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildUnifiedHeader(
            availableDays: availableDays,
            isClosurePeriodDay: isClosurePeriodDay,
            isClosedDay: isClosedDay,
            availableCount:
                (!isClosurePeriodDay &&
                    !isCutoffDay &&
                    !isClosedDay &&
                    !dayLoading)
                ? futureDailySlots.length
                : -1,
            totalCount: allDailySlots.length,
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  // Aperçu gris pendant le court instant où les créneaux du jour se chargent
  // (le bandeau de jours, lui, est déjà complet).
  Widget _buildSlotSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
      children: List.generate(5, (_) {
        return Container(
          height: 56,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 118,
                      height: 13,
                      decoration: BoxDecoration(
                        color: _hairline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      width: 56,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _hairline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 82,
                height: 34,
                decoration: BoxDecoration(
                  color: _hairline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── Header unifié (titre + navigateur de jours) ───────────────

  Widget _buildUnifiedHeader({
    required List<DateTime> availableDays,
    required bool isClosurePeriodDay,
    required bool isClosedDay,
    int availableCount = -1,
    int totalCount = 0,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ligne 1 : retour · nom de la file · compteur du jour
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  BackButton(
                    color: _ink,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      _displayQueueName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (availableCount >= 0) ...[
                    const SizedBox(width: 8),
                    _buildSlotBadge(availableCount, totalCount),
                  ],
                ],
              ),
            ),
            // Ligne 2 : bandeau de jours (une ligne + pastille de dispo)
            if (availableDays.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: availableDays.length,
                  itemBuilder: (context, i) {
                    final day = availableDays[i];
                    final isSelected = _isSameDay(day, _selectedDate);
                    final isClosedChip =
                        _openWeekdays != null &&
                        !_openWeekdays!.contains(day.weekday);
                    final hasSlots = (_dailyAvailable[_ymd(day)] ?? 0) > 0;

                    final Color labelColor = isSelected
                        ? Colors.white
                        : isClosedChip
                        ? const Color(0xFFC7C7C2)
                        : _ink;
                    final Color dotColor = isSelected
                        ? Colors.white.withValues(alpha: 0.9)
                        : hasSlots
                        ? _green
                        : Colors.transparent;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDate = day;
                          _showPastSlots = false;
                        });
                        // Jour au-delà de la fenêtre déjà chargée → l'élargir.
                        final off = _dateOnly(
                          day,
                        ).difference(_dateOnly(DateTime.now())).inDays;
                        if (off > _loadedWindowDays) _maybeWidenSlots();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? _green : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isSelected
                                ? _green
                                : isClosedChip
                                ? const Color(0xFFF0EEE9)
                                : _hairline,
                          ),
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
                            const SizedBox(height: 5),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
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

    final deadline = Duration(minutes: _reservationDeadlineMinutes);
    for (final doc in allDailySlots) {
      final data = doc.data() as Map<String, dynamic>;
      final start = (data['start'] as Timestamp).toDate().toLocal();
      if (!start.isAfter(now.add(deadline))) {
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

    // Créneaux à venir groupés par moment de la journée (Matin / Après-midi / Soir).
    int? currentPeriod;
    bool firstLabel = true;
    final periodSlots = <QueryDocumentSnapshot>[];
    void flushPeriod() {
      if (periodSlots.isEmpty) return;
      items.add(_buildPeriodLabel(currentPeriod!, isFirst: firstLabel));
      firstLabel = false;
      _appendSlotsWithGaps(items, List.of(periodSlots));
      periodSlots.clear();
    }

    for (final doc in upcomingSlots) {
      final start =
          ((doc.data() as Map<String, dynamic>)['start'] as Timestamp)
              .toDate()
              .toLocal();
      final p = _periodOf(start);
      if (currentPeriod != null && p != currentPeriod) flushPeriod();
      currentPeriod = p;
      periodSlots.add(doc);
    }
    flushPeriod();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 48),
      children: items,
    );
  }

  int _periodOf(DateTime d) => d.hour < 12 ? 0 : (d.hour < 18 ? 1 : 2);

  Widget _buildPeriodLabel(int period, {required bool isFirst}) {
    const labels = ['Matin', 'Après-midi', 'Soir'];
    return Padding(
      padding: EdgeInsets.fromLTRB(2, isFirst ? 4 : 18, 0, 10),
      child: Text(
        labels[period].toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
          color: _inkFaint,
        ),
      ),
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
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _showPastSlots = !_showPastSlots);
        if (_showPastSlots) {
          _pastSlotsCtrl.forward();
        } else {
          _pastSlotsCtrl.reverse();
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
        child: Row(
          children: [
            Icon(
              _showPastSlots
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: _inkFaint,
            ),
            const SizedBox(width: 6),
            Text(
              _showPastSlots
                  ? 'Masquer les créneaux passés'
                  : '$count créneau${count > 1 ? 'x' : ''} passé${count > 1 ? 's' : ''}',
              style: const TextStyle(
                color: _inkFaint,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotBadge(int available, int total) {
    if (total == 0) return const SizedBox.shrink();

    final isEndOfDay =
        available == 0 && _isSameDay(_selectedDate, DateTime.now());
    final isFull = available == 0 && !isEndOfDay;

    if (isEndOfDay) {
      return const Text(
        'Fin de journée',
        style: TextStyle(
          color: _inkFaint,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (isFull) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _hairline),
        ),
        child: const Text(
          'Complet',
          style: TextStyle(
            color: _inkFaint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: _greenTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$available libre${available > 1 ? 's' : ''}',
        style: const TextStyle(
          color: _green,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildGapSeparator(DateTime gapStart, DateTime gapEnd, int minutes) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: _hairline)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Pause · ${_timeFmt.format(gapStart)} – ${_timeFmt.format(gapEnd)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _inkFaint,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: _hairline)),
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

    final now = DateTime.now();
    final isPast = !start.isAfter(
      now.add(Duration(minutes: _reservationDeadlineMinutes)),
    );
    final isMine = !isPast && _myReservedSlotIds.contains(slotDoc.id);
    final remaining = capacity - reserved;
    final isFull = remaining <= 0;
    final isAvailable =
        status == 'open' && remaining > 0 && !isPast && !isMine;

    final timeLabel =
        '${_timeFmt.format(start)} – ${_timeFmt.format(end)}';

    // Surface + texte selon l'état (2 états réels : disponible / complet,
    // plus « réservé » pour la carte du client et l'atténuation du passé).
    final Color cardBg;
    final Color cardBorder;
    final Color timeColor;
    if (isPast) {
      cardBg = _surface;
      cardBorder = const Color(0xFFEFEDE7);
      timeColor = _inkFaint;
    } else if (isMine) {
      cardBg = _greenTint;
      cardBorder = _greenTintBorder;
      timeColor = _ink;
    } else if (isFull) {
      cardBg = _surfaceMuted;
      cardBorder = _hairline;
      timeColor = _inkFaint;
    } else {
      cardBg = _surface;
      cardBorder = _hairline;
      timeColor = _ink;
    }

    final String caption;
    if (isPast) {
      caption = 'Créneau passé';
    } else if (isMine) {
      caption = 'Vous êtes inscrit';
    } else if (isFull) {
      caption = '$capacity place${capacity > 1 ? 's' : ''}';
    } else {
      caption = '$remaining place${remaining > 1 ? 's' : ''}';
    }

    final Widget trailing;
    if (isMine) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _green),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 15, color: _green),
            SizedBox(width: 4),
            Text(
              'Réservé',
              style: TextStyle(
                color: _green,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (isAvailable) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Réserver',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else if (isFull) {
      trailing = const Text(
        'Complet',
        style: TextStyle(
          color: _inkFaint,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    } else if (isPast) {
      trailing = const Icon(
        Icons.history_rounded,
        size: 18,
        color: Color(0xFFC7C7C2),
      );
    } else {
      trailing = const Icon(
        Icons.lock_outline_rounded,
        size: 18,
        color: Color(0xFFC7C7C2),
      );
    }

    final bool tappable = isAvailable || isMine;

    return Opacity(
      opacity: isPast ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: tappable
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
                vertical: 11,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: timeColor,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          caption,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: _inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailing,
                ],
              ),
            ),
          ),
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
    // Le client tape le créneau qu'il a DÉJÀ réservé : rien à remplacer.
    if (_myReservedSlotIds.contains(slotDoc.id)) {
      _showBlockedSnackbar('Vous avez déjà réservé ce créneau.');
      return;
    }

    final result = await _rulesService.checkCanReserve(
      companyId: widget.entrepriseId,
      queueId: widget.queueId,
      timeSlotId: timeSlotId,
      slotStart: start,
      slotEnd: end,
      maxAdvanceDays: _maxAdvanceDays,
      allowMultiplePerPlage: _allowMultiplePerPlage,
    );

    if (!mounted) return;

    if (result.canReserve) {
      // Autorisé grâce au réglage « plusieurs réservations par jour », mais
      // le client a déjà une résa active ailleurs dans cette file : on le
      // prévient plutôt que de le laisser réserver sans qu'il s'en rende
      // compte.
      if (result.otherActiveInQueue.isNotEmpty) {
        await _showSecondReservationDialog(
          slotDoc: slotDoc,
          start: start,
          end: end,
          timeSlotId: timeSlotId,
          otherActiveInQueue: result.otherActiveInQueue,
        );
        return;
      }
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
        final conflictData = conflict.data() as Map<String, dynamic>;
        final conflictStart =
            (conflictData['slotStart'] as Timestamp).toDate();
        // Filet de sécurité si _myReservedSlotIds n'est pas encore chargé :
        // le créneau visé est exactement celui déjà réservé → aucun sens.
        if (conflictData['slotId'] == slotDoc.id) {
          _showBlockedSnackbar('Vous avez déjà réservé ce créneau.');
          break;
        }
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
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: const BoxDecoration(
                color: _greenTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: _green,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Confirmer la réservation',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 18),
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
                color: _surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _hairline),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    color: _inkFaint,
                    size: 16,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vous recevrez des rappels et pourrez annuler depuis vos réservations.',
                      style: TextStyle(fontSize: 12, color: _inkSoft),
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
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
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
              child: const Text(
                'Annuler',
                style: TextStyle(color: _inkFaint, fontSize: 14),
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

  // Affiché quand la file autorise « plusieurs réservations par jour » et
  // que le client a déjà une résa active ailleurs dans cette même file
  // (plage différente). Prévient plutôt que de réserver en silence.
  Future<void> _showSecondReservationDialog({
    required QueryDocumentSnapshot slotDoc,
    required DateTime start,
    required DateTime end,
    required String timeSlotId,
    required List<QueryDocumentSnapshot> otherActiveInQueue,
  }) async {
    final single = otherActiveInQueue.length == 1;

    Widget existingRow(QueryDocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>;
      final s = (data['slotStart'] as Timestamp).toDate().toLocal();
      final e = (data['slotEnd'] as Timestamp).toDate().toLocal();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, size: 15, color: _inkFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_dayLabel(s)} · ${_timeFmt.format(s)} – ${_timeFmt.format(e)}',
                style: const TextStyle(fontSize: 12.5, color: _inkSoft),
              ),
            ),
          ],
        ),
      );
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: const BoxDecoration(
                color: _greenTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: _green,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              single
                  ? 'Vous avez déjà une réservation dans cette file'
                  : 'Vous avez déjà ${otherActiveInQueue.length} réservations dans cette file',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final doc in otherActiveInQueue) existingRow(doc),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _detailRow(
              Icons.schedule_rounded,
              'Nouveau créneau',
              '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
            ),
            const SizedBox(height: 10),
            _detailRow(
              Icons.calendar_month_rounded,
              'Date',
              _dateFmtFull.format(start),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'confirm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
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
            if (single) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, 'replace'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _inkSoft,
                    side: const BorderSide(color: _hairline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Remplacer ma réservation',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Text(
                'Pour modifier une réservation existante, gérez-la depuis '
                'Mes réservations.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: _inkFaint),
              ),
            ],
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'confirm') {
      await _doReserve(
        slotDoc: slotDoc,
        start: start,
        end: end,
        timeSlotId: timeSlotId,
      );
    } else if (action == 'replace') {
      await _showReplaceDialog(
        slotDoc: slotDoc,
        newStart: start,
        newEnd: end,
        timeSlotId: timeSlotId,
        existingRes: otherActiveInQueue.first,
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
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: _surfaceMuted,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: _greenTint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: _green,
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
                      color: _surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _hairline),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.remove_circle_outline_rounded,
                          color: _inkFaint,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Actuel · $existingQueue',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _inkSoft,
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
                      color: _green.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _green.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: _green,
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
                                  color: _green,
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
                        backgroundColor: _green,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Remplacer',
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

  // File normale (réglage éteint) : retour dès la 1ʳᵉ résa, comme avant.
  // File « plusieurs réservations par jour » : on ne ramène le client que
  // lorsqu'il a désormais une résa active dans TOUTES les plages de la
  // file — sinon il reste sur l'écran pour réserver les plages restantes.
  Future<bool> _shouldReturnAfterReservation() async {
    if (!_allowMultiplePerPlage) return true;
    try {
      final count = await _rulesService.countDistinctActivePlages(
        companyId: widget.entrepriseId,
        queueId: widget.queueId,
      );
      return count >= _totalActivePlages;
    } catch (_) {
      // Repli sûr en cas d'échec de la requête : comportement d'avant.
      return true;
    }
  }

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

        // Le rappel « plus qu'une réservation aujourd'hui » n'est plus un
        // widget local : c'est la Cloud Function `notifyDailyQuotaWarning`
        // qui envoie une notification quand le quota du jour tombe à 1.

        if (mounted && await _shouldReturnAfterReservation() && mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showBookingError(e);
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
        newCompanyId: widget.entrepriseId,
        newQueueId: widget.queueId,
        newTimeSlotId: timeSlotId,
        newSlotDocId: slotDoc.id,
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

        if (mounted && await _shouldReturnAfterReservation() && mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showBookingError(e);
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

      // Écriture réelle du favori + retour visuel — succès ET échec (fini le
      // catch silencieux : si ça rate, l'utilisateur en est informé).
      Future<void> addFavoriteNow() async {
        try {
          await FavoritesService.addFavorite(
            companyId: widget.entrepriseId,
            nom: resolvedNom,
            type: companyType,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.star_rounded, color: Colors.white, size: 16),
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
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Impossible d\'ajouter aux favoris : $e'),
                backgroundColor: Colors.red.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      }

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
              // Widget C : l'utilisateur doit d'abord s'inscrire — même
              // parcours que le favori posé par appui long (search_page) :
              // une fois l'inscription terminée, le favori est ajouté
              // directement, sans que le client ait à refaire le geste.
              if (!mounted) return;
              await showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isDismissible: true,
                builder: (ctx2) => _RegistrationNeededSheet(
                  onRegister: () async {
                    Navigator.pop(ctx2);
                    if (!mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SigninePage()),
                    );
                    if (!mounted) return;
                    final u = FirebaseAuth.instance.currentUser;
                    if (u != null && !u.isAnonymous) {
                      await addFavoriteNow();
                    }
                  },
                  onLater: () => Navigator.pop(ctx2),
                ),
              );
            } else {
              await addFavoriteNow();
            }
          },
          onDismiss: () => Navigator.pop(ctx),
        ),
      );

      // Marquer comme montré (qu'il ait ajouté ou annulé)
      await prefs.setBool(promptedKey, true);
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
            const Text('Confirmation en cours…'),
          ],
        ),
        backgroundColor: widget.primaryGreen,
        // Masquée dès la réponse du serveur ; marge large pour un réseau lent.
        duration: const Duration(seconds: 30),
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

  // Refus du serveur (créneau complet, quota atteint…) : message métier,
  // affiché comme une information. Autre échec (réseau…) : erreur.
  void _showBookingError(Object e) {
    if (e is BookingException && e.reason != null) {
      _showBlockedSnackbar(e.message);
    } else {
      _showErrorSnackbar('$e');
    }
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
