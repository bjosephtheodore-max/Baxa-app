part of 'settings_page.dart';

// ==================== ÉTAT DE LA PAGE PLAGES HORAIRES ====================
class _QueueTimeSlotsPageState extends State<QueueTimeSlotsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Jours cochés par défaut à la création d'une plage (lundi → vendredi).
  // Chaque plage porte ensuite ses propres `workingDays` ; il n'y a plus de
  // réglage « jours d'ouverture » au niveau de la file — donc cette valeur
  // ne change jamais.
  final List<int> _queueWeekdays = const [1, 2, 3, 4, 5];

  // Streams stockés en instance — évite la réinscription à chaque rebuild.
  late final Stream<QuerySnapshot> _slotsStream;
  late final Stream<List<_DayCapacity>> _capacityStream;
  // Document de la file : lu pour le réglage « Réservations simultanées ».
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _queueStream;

  bool _guideDismissed = false;
  bool _hasSlots = false;

  void _dismissGuide() => setState(() => _guideDismissed = true);

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
    _queueStream = queueRef.snapshots();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Blanc uni (comme l'accueil company) — plus de fond teinté.
      backgroundColor: Colors.white,
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.black.withValues(alpha: 0.06),
            height: 1,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: OnboardingService(),
        builder: (context, child) {
          // Le Stack existe toujours — seule la présence du voile varie.
          // Changer la structure elle-même (avec/sans Stack) forcerait Flutter
          // à détruire et recréer `child` (donc son StreamBuilder Firestore,
          // qui repartirait de zéro) à chaque changement d'étape d'onboarding.
          final showOverlay = OnboardingService().step == 5 && _guideDismissed;
          return Stack(
            children: [
              child!,
              if (showOverlay)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.58),
                    ),
                  ),
                ),
            ],
          );
        },
        child: StreamBuilder<QuerySnapshot>(
          stream: _slotsStream,
          builder: (context, snapshot) {
            final slots = snapshot.data?.docs ?? [];
            final hasSlots = slots.isNotEmpty;
            if (_hasSlots != hasSlots) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _hasSlots = hasSlots);
              });
            }
            // Guide éducatif avant la première plage (onboarding uniquement)
            if (!hasSlots && !_guideDismissed && OnboardingService().isActive) return _buildTimeSlotsGuide();
            // Contenu normal : bannière capacité + liste
            return Column(
              children: [
                StreamBuilder<List<_DayCapacity>>(
                  stream: _capacityStream,
                  builder: (context, capSnapshot) {
                    if (capSnapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }
                    final days = capSnapshot.data ?? [];
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
                                padding:
                                    const EdgeInsets.fromLTRB(0, 12, 14, 12),
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
                                          const Icon(
                                            Icons.touch_app_rounded,
                                            size: 14,
                                            color: _kGreen,
                                          ),
                                          const SizedBox(width: 6),
                                          const Flexible(
                                            child: Text(
                                              'Appuyez sur « Ajouter une plage » pour configurer vos horaires',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _kGreen,
                                                fontWeight: FontWeight.w600,
                                              ),
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
                                                  ? _kGreen.withValues(
                                                      alpha: 0.1)
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
                                    if (slots.length == 1)
                                      _buildSecondPlageHint(),
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
                Expanded(
                  child: !hasSlots
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: slots.length,
                          itemBuilder: (context, index) {
                            final slot = slots[index];
                            return _buildTimeSlotCard(
                              slot.id,
                              slot.data() as Map<String, dynamic>,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: (_guideDismissed || _hasSlots || !OnboardingService().isActive)
          ? ListenableBuilder(
              listenable: OnboardingService(),
              builder: (_, child) {
                final active = OnboardingService().step == 5;
                return active ? PulsingGlow(child: child!) : child!;
              },
              child: FloatingActionButton.extended(
                onPressed: _showTimeSlotDialog,
                backgroundColor: _kGreen,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Ajouter une plage',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            )
          : null,
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

  // Rappel discret : « Réservations simultanées » n'a d'effet qu'à partir de
  // 2 plages (une réservation active par plage). Affiché seulement quand la
  // file n'en a qu'une — l'appelant le garantit — et hors parcours guidé
  // (sinon il surgirait en même temps que la célébration de la 1re plage).
  Widget _buildSecondPlageHint() {
    return ListenableBuilder(
      listenable: OnboardingService(),
      builder: (context, _) {
        if (OnboardingService().isActive) return const SizedBox.shrink();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _queueStream,
          builder: (context, snap) {
            final allow =
                snap.data?.data()?['allowMultiplePerPlage'] as bool? ?? false;
            if (!allow) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: _kGreen,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Réservations simultanées : ajoutez une 2e plage pour en profiter.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimeSlotsGuide() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icône
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.tips_and_updates_rounded,
                        size: 38,
                        color: _kGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Titre
                  const Center(
                    child: Text(
                      'Configurez vos plages\nintelligemment',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1C2E),
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Une plage est un horaire découpé en créneaux.\nVoici les 3 réglages à connaître.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Les 3 paramètres
                  _buildGuideParam(
                    Icons.schedule_rounded,
                    'La plage horaire',
                    'La période où vous recevez vos clients',
                    'ex : 8h–12h ou 14h–17h',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideParam(
                    Icons.timer_rounded,
                    'La durée par créneau',
                    'La plage est découpée en créneaux de durée fixe',
                    'ex : 15 min → 8h00, 8h15, 8h30…',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideParam(
                    Icons.people_rounded,
                    'La capacité du créneau',
                    'Nombre de clients reçus en même temps',
                    'ex : 1, 2 ou 5 personnes',
                  ),
                  const SizedBox(height: 16),
                  // Mini-calcul : relie les 3 réglages à la capacité affichée
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate_rounded,
                            color: _kGreen, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                              children: const [
                                TextSpan(
                                    text:
                                        '8h–12h · créneaux de 15 min · 2 pers. = '),
                                TextSpan(
                                  text: '32 clients',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _kGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Encart clé
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _kGreen.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _kGreen.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.layers_rounded,
                            color: _kGreen, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Créez plusieurs plages dans une même file pour adapter vos réglages à chaque moment de la journée.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1C2E),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Exemple comparatif
                  Text(
                    'EXEMPLE · Banque avec affluence en fin de journée',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildExampleRow(
                    isGood: false,
                    label: '8h–20h · 15 min · 1 pers./créneau',
                    note: 'File longue toute la journée, attente imprévisible',
                  ),
                  const SizedBox(height: 8),
                  _buildExampleRow(
                    isGood: true,
                    label: '8h–12h · 20 min · 1 pers./créneau',
                    note: 'Matinée calme — service fluide',
                  ),
                  const SizedBox(height: 6),
                  _buildExampleRow(
                    isGood: true,
                    label: '17h–20h · 10 min · 2 pers./créneau',
                    note: 'Heure de pointe : double capacité, créneau court',
                  ),
                  const SizedBox(height: 28),
                  // Phrase de réflexion
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      '💭  Prenez un moment pour réfléchir à vos pics d\'affluence et à vos heures de pause. C\'est cette réflexion qui fera toute la différence pour vos clients.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.55,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
          // Bouton fixe en bas
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _dismissGuide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'C\'est compris !',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideParam(
      IconData icon, String title, String subtitle, String example) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _kGreen, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                example,
                style: const TextStyle(
                  fontSize: 11,
                  color: _kGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExampleRow(
      {required bool isGood, required String label, required String note}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isGood
            ? _kGreen.withValues(alpha: 0.06)
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isGood
              ? _kGreen.withValues(alpha: 0.2)
              : Colors.red.shade100,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isGood ? '✅' : '❌',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isGood
                        ? const Color(0xFF1A1C2E)
                        : Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 11,
                    color: isGood
                        ? Colors.grey.shade600
                        : Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final pendingEffectiveDate =
        (slotData['pendingEffectiveDate'] as Timestamp?)?.toDate();
    final deleteAfter = (slotData['deleteAfter'] as Timestamp?)?.toDate();

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
      child: Column(
        children: [
          ClipRRect(
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
          if (pendingEffectiveDate != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: _kGreen),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Modification programmée pour le '
                      '${DateFormat('EEE d MMM', 'fr_FR').format(pendingEffectiveDate)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (deleteAfter != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_delete_outlined,
                      size: 14, color: Colors.red.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Suppression programmée le '
                      '${DateFormat('EEE d MMM', 'fr_FR').format(deleteAfter)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade400,
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
              if (slotData['deleteAfter'] == null) ...[
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
                    _deleteSlot(slotId, slotData);
                  },
                ),
              ] else
                _slotActionTile(
                  icon: Icons.restore_from_trash_outlined,
                  label: 'Restituer la suppression',
                  bgColor: _kGreen.withValues(alpha: 0.08),
                  fgColor: _kGreen,
                  onTap: () {
                    Navigator.pop(ctx);
                    _restorePendingDeletion(slotId, slotData);
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

  // [fullBleed] : le contenu va d'un bord à l'autre de la carte (rangées qui
  // défilent horizontalement), seul l'en-tête garde la marge intérieure.
  Widget _buildSheetCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    bool fullBleed = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: fullBleed ? 0 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: fullBleed ? 16 : 0),
            child: Row(
              children: [
                Icon(icon, size: 15, color: _kSheetGreen),
                const SizedBox(width: 7),
                // Expanded absorbe tout l'espace libre : le titre reste collé
                // à gauche et le sous-titre reste collé à droite, exactement
                // comme avec Spacer() — mais le titre s'ellipse au lieu de
                // déborder si l'espace vient à manquer (grande police système).
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _kSheetDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A938D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
