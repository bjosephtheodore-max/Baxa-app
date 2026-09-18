part of 'house_page.dart';

// ============================================================
// HOUSE WIDGETS — StatelessWidgets extraits de house_page
// ============================================================

// ── Skeleton loader par file ──────────────────────────────────────────────────
class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
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
}

// ── Retry state (erreur réseau) ───────────────────────────────────────────────
class _RetryState extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: Colors.orange.shade400,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connexion indisponible',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vérifiez votre connexion et réessayez.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text(
                'Réessayer',
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
}

// ── Empty state (accueil sans files) ─────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OnboardingService(),
      builder: (context, _) {
        final isOnboarding = OnboardingService().isActive;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: _lightGreen.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOnboarding
                        ? Icons.waving_hand_rounded
                        : Icons.queue_outlined,
                    size: 64,
                    color: _green,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isOnboarding ? 'Bienvenue sur Baxa !' : 'Aucune file active',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E2D23),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isOnboarding
                      ? 'Suivez ces étapes pour recevoir vos premières réservations.'
                      : 'Créez une file d\'attente dans l\'onglet Réglages pour commencer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    height: 1.5,
                  ),
                ),
                if (isOnboarding) ...[
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _lightGreen.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _lightGreen.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        _OnboardingStep(
                          number: '1',
                          icon: Icons.settings_rounded,
                          text: 'Appuyez sur "Réglages" en bas',
                          done: OnboardingService().step > 1,
                        ),
                        const SizedBox(height: 12),
                        _OnboardingStep(
                          number: '2',
                          icon: Icons.people_outline_rounded,
                          text: 'Ouvrez "Gérer les files d\'attente"',
                          done: OnboardingService().step > 2,
                        ),
                        const SizedBox(height: 12),
                        _OnboardingStep(
                          number: '3',
                          icon: Icons.add_circle_outline_rounded,
                          text: 'Créez votre première file',
                          done: OnboardingService().step > 4,
                        ),
                        const SizedBox(height: 12),
                        _OnboardingStep(
                          number: '4',
                          icon: Icons.schedule_rounded,
                          text: 'Ajoutez une plage horaire',
                          done: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  final String number;
  final String text;
  final IconData? icon;
  final bool done;

  const _OnboardingStep({
    required this.number,
    required this.text,
    this.icon,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: done ? _green : _green.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text(
                    number,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        if (icon != null) ...[
          Icon(icon, size: 15, color: _green.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: done ? Colors.grey.shade400 : Colors.grey.shade700,
              fontWeight: FontWeight.w500,
              decoration: done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Ligne de 3 stats ──────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final QueueStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            value: stats.placesReservees.toString(),
            label: 'Réservées',
            color: Colors.blue.shade600,
            bgColor: Colors.blue.shade50,
            icon: Icons.bookmark_outline_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            value: stats.personnesEnAttente.toString(),
            label: 'En attente',
            color: stats.personnesEnAttente > 0
                ? Colors.orange.shade700
                : Colors.grey.shade500,
            bgColor: stats.personnesEnAttente > 0
                ? Colors.orange.shade50
                : Colors.grey.shade100,
            icon: Icons.hourglass_empty_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            value: stats.placesRestantes.toString(),
            label: 'Disponibles',
            color: stats.placesRestantes == 0 ? Colors.red.shade600 : _green,
            bgColor: stats.placesRestantes == 0
                ? Colors.red.shade50
                : const Color(0xFFECF7F0),
            icon: Icons.check_circle_outline_rounded,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _StatChip({
    required this.value,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte en-tête de file ─────────────────────────────────────────────────────
class _QueueHeaderCard extends StatefulWidget {
  final _QueueAgenda queue;
  final int? currentDuration;
  final int? currentCapacity;
  final void Function(int delta) onDurationChanged;
  final void Function(int delta) onCapacityChanged;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  final bool isPastDay;
  final bool isExpanded;
  final VoidCallback onToggle;
  final bool readOnly;
  final VoidCallback? onRevertDuration;

  const _QueueHeaderCard({
    required this.queue,
    required this.currentDuration,
    required this.currentCapacity,
    required this.onDurationChanged,
    required this.onCapacityChanged,
    required this.onBlock,
    required this.onUnblock,
    required this.isPastDay,
    required this.isExpanded,
    required this.onToggle,
    this.readOnly = false,
    this.onRevertDuration,
  });

  @override
  State<_QueueHeaderCard> createState() => _QueueHeaderCardState();
}

class _QueueHeaderCardState extends State<_QueueHeaderCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _sizeAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _sizeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _fadeAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_QueueHeaderCard old) {
    super.didUpdateWidget(old);
    if (widget.isExpanded != old.isExpanded) {
      widget.isExpanded ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Nom + badge statut ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.queue.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.queue.isBlocked
                        ? Colors.grey.shade100
                        : const Color(0xFFE8F5ED),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: widget.queue.isBlocked
                              ? Colors.grey.shade500
                              : _green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.queue.isBlocked ? 'Bloquée' : 'Active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.queue.isBlocked
                              ? Colors.grey.shade600
                              : _green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Raison du blocage ───────────────────────────────────
            if (widget.queue.isBlocked && widget.queue.blockReason != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.pause_circle_outline_rounded,
                        color: Colors.orange.shade700,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Réservations suspendues',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.queue.blockReason!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Stats ───────────────────────────────────────────────
            const SizedBox(height: 14),
            _StatsRow(stats: widget.queue.stats),

            // ── Toggle Modifier / Masquer (jours non passés, admin/staff seulement) ────
            if (!widget.isPastDay && !widget.readOnly) ...[
              GestureDetector(
                onTap: widget.onToggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.isExpanded ? 'Masquer' : 'Modifier',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 3),
                      AnimatedRotation(
                        turns: widget.isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Contrôles expandables ───────────────────────────
              SizeTransition(
                sizeFactor: _sizeAnim,
                axisAlignment: -1.0,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      const SizedBox(height: 14),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 14),

                      if (!widget.queue.isBlocked &&
                          widget.queue.slots.isNotEmpty) ...[
                        _ControlRow(
                          label: 'Durée',
                          icon: Icons.timer,
                          value: widget.currentDuration,
                          unit: 'min',
                          min: 5,
                          max: 120,
                          step: 5,
                          onChanged: widget.onDurationChanged,
                          onRevert: widget.onRevertDuration,
                        ),
                        Divider(height: 1, color: Colors.grey.shade200),
                        _ControlRow(
                          label: 'Capacité',
                          icon: Icons.people,
                          value: widget.currentCapacity,
                          unit: 'pers.',
                          min: 1,
                          max: 50,
                          step: 1,
                          onChanged: widget.onCapacityChanged,
                        ),
                        const SizedBox(height: 20),
                      ],

                      GestureDetector(
                        onTap: widget.queue.isBlocked
                            ? widget.onUnblock
                            : widget.onBlock,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 11,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: widget.queue.isBlocked
                                  ? _green
                                  : Colors.red.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.queue.isBlocked
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_outline_rounded,
                                size: 16,
                                color: widget.queue.isBlocked
                                    ? _green
                                    : Colors.red.shade400,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.queue.isBlocked
                                    ? 'Débloquer la plage'
                                    : 'Bloquer la plage',
                                style: TextStyle(
                                  color: widget.queue.isBlocked
                                      ? _green
                                      : Colors.red.shade600,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
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
            ],
          ],
        ),
      ),
    );
  }
}

// ── Contrôle ⊖ valeur ⊕ ──────────────────────────────────────────────────────
// onChanged reçoit un delta (+step ou -step), jamais une valeur absolue.
// value == null → plusieurs plages avec des valeurs hétérogènes (affiche "—").
class _ControlRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? value;
  final String unit;
  final int min;
  final int max;
  final int step;
  final void Function(int delta) onChanged;
  final VoidCallback? onRevert;

  const _ControlRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final canDecrease = value == null || value! > min;
    final canIncrease = value == null || value! < max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildLeadingIcon(),
          const SizedBox(width: 8),
          // Expanded (et non un Text à largeur fixe + Spacer séparé) :
          // le libellé rétrécit avec "..." si l'écran est trop étroit pour
          // tout afficher, au lieu de forcer un débordement de la Row.
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _PlusMinusBtn(
            icon: Icons.remove,
            enabled: canDecrease,
            onTap: () => onChanged(-step),
          ),
          const SizedBox(width: 8),
          Text(
            value != null ? '$value $unit' : '—',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          _PlusMinusBtn(
            icon: Icons.add,
            enabled: canIncrease,
            onTap: () => onChanged(step),
          ),
        ],
      ),
    );
  }

  // ── Icône de tête, avec badge ↺ superposé si un retour est disponible ────
  // Pas de bouton séparé dans la ligne : ça éviterait de désaligner la
  // grille ⊖/⊕ entre "Durée" et "Capacité" dès que l'un des deux affiche
  // le badge et pas l'autre. Le badge se pose sur l'icône existante à
  // gauche, sans consommer d'espace supplémentaire dans la ligne.
  Widget _buildLeadingIcon() {
    final plainIcon = Icon(icon, size: 18, color: _green);
    if (onRevert == null) return plainIcon;
    return GestureDetector(
      onTap: onRevert,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Pastille de fond : signale "ceci est un bouton" au premier
            // coup d'œil, même sans avoir vu le tutoriel de découverte.
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
            plainIcon,
            Positioned(
              right: 0,
              top: 2,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: Colors.orange.shade600,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.undo_rounded,
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlusMinusBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PlusMinusBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
}

// ── Carte d'un créneau ────────────────────────────────────────────────────────
class _SlotCard extends StatelessWidget {
  final AgendaSlot slot;
  final DateFormat timeFormat;
  final VoidCallback onTap;
  final bool isPast;

  const _SlotCard({
    required this.slot,
    required this.timeFormat,
    required this.onTap,
    this.isPast = false,
  });

  String _subtitle() {
    // Créneaux passés : seule l'étiquette parle (voir _statusBadge).
    if (isPast) return '';
    if (slot.isBlocked) return '';
    if (slot.reserved == 0) return 'Disponible';
    return '${slot.reserved} résa';
  }

  // Retourne null quand il n'y a rien à signaler : un créneau libre ou
  // partiellement réservé n'affiche aucune étiquette, la carte reste calme.
  Widget? _statusBadge(bool isBlocked, bool isFull) {
    if (isPast) {
      return _solidBadge(
        slot.reserved > 0 ? '${slot.reserved} résa' : 'Passé',
        Colors.grey.shade500,
      );
    }
    if (isBlocked) {
      return _solidBadge('Bloqué', Colors.red.shade600);
    }
    if (isFull) {
      return _completeBadge();
    }
    return null;
  }

  // Créneau plein — bonne nouvelle côté entreprise : vert plein + coche,
  // seul moment « récompense » de la carte.
  Widget _completeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 13, color: Colors.white),
          SizedBox(width: 3),
          Text(
            'Complet',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _solidBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
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

  @override
  Widget build(BuildContext context) {
    final isBlocked = slot.isBlocked;
    final isFull = slot.isFull;
    final isLegacy = slot.isLegacy;
    final badge = _statusBadge(isBlocked, isFull);
    final subtitle = _subtitle();
    // Créneau à venir qui a déjà des réservations : sous-titre « X résa »
    // dans un vert éteint plutôt que le gris de « Disponible » — juste
    // assez pour dire « il y a du monde ici », sans taper à l'œil.
    final subtitleHasBookings = !isPast && !isBlocked && slot.reserved > 0;

    BoxDecoration deco;
    if (isPast) {
      deco = BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      );
    } else if (isBlocked) {
      deco = BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade400, width: 1.5),
      );
    } else if (isFull) {
      // Créneau plein : posé et discret — pas de contour dur, une ombre
      // douce et un fond à peine teinté. Le vert qui compte est sur l'icône
      // et la pastille « ✓ Complet ».
      deco = BoxDecoration(
        color: const Color(0xFFF4FAF6),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: 0.13),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      );
    } else if (isLegacy) {
      deco = BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade400, width: 1.5),
      );
    } else {
      deco = BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: deco,
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
              '${timeFormat.format(slot.start)} – ${timeFormat.format(slot.end)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            if (badge != null) badge,
          ],
        ),
        subtitle: (subtitle.isEmpty && !isLegacy)
            ? null
            : Row(
                children: [
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: subtitleHasBookings
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: subtitleHasBookings
                            ? const Color(0xFF5E8B72)
                            : Colors.grey.shade600,
                      ),
                    ),
                  if (isLegacy) ...[
                    if (subtitle.isNotEmpty) const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
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
        onTap: onTap,
      ),
    );
  }
}

// ── Séparateur de plage horaire ───────────────────────────────────────────────
class _PlageSeparator extends StatelessWidget {
  final int plageNumber;
  final DateTime startTime;
  final DateFormat timeFormat;

  const _PlageSeparator({
    required this.plageNumber,
    required this.startTime,
    required this.timeFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _lightGreen.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule_rounded, size: 13, color: _green),
                const SizedBox(width: 6),
                Text(
                  'Plage $plageNumber — ${timeFormat.format(startTime)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _green,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        ],
      ),
    );
  }
}

// ── Séparateur de pause (au sein d'une même plage) ────────────────────────────
class _TimeslotSeparator extends StatelessWidget {
  final DateTime endTime;
  final DateTime startTime;
  final DateFormat timeFormat;

  const _TimeslotSeparator({
    required this.endTime,
    required this.startTime,
    required this.timeFormat,
  });

  @override
  Widget build(BuildContext context) {
    final endFormatted = timeFormat.format(endTime);
    final startFormatted = timeFormat.format(startTime);
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
}

// ── Sélecteur de plage horaire (bottom sheet) ─────────────────────────────────
class _TimeslotPickerSheet extends StatelessWidget {
  final List<_TimeSlotInfo> timeslots;
  final String title;

  const _TimeslotPickerSheet({required this.timeslots, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: _green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...timeslots.map((ts) {
            final deferred = ts.deleteAfter != null;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: deferred
                    ? Colors.grey.shade100
                    : const Color(0xFFE8F5ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: deferred
                      ? Colors.grey.shade300
                      : _green.withValues(alpha: 0.3),
                ),
              ),
              child: ListTile(
                enabled: !deferred,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: deferred
                        ? Colors.grey.shade300
                        : _green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(
                      deferred
                          ? Icons.auto_delete_outlined
                          : Icons.access_time_rounded,
                      color: deferred ? Colors.grey.shade500 : _green,
                      size: 20,
                    ),
                  ),
                ),
                title: Text(
                  '${ts.startTime} – ${ts.endTime}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  deferred
                      ? 'Suppression programmée le '
                            '${DateFormat('d MMM', 'fr_FR').format(ts.deleteAfter!)}'
                      : '${ts.duration} min · ${ts.capacity} pers./créneau',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: deferred
                    ? null
                    : const Icon(Icons.chevron_right_rounded, color: _green),
                onTap: deferred ? null : () => Navigator.pop(context, ts),
              ),
            );
          }),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Annuler',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet de blocage ───────────────────────────────────────────────────
class _BlockSheet extends StatefulWidget {
  final List<_TimeSlotInfo> timeslots;
  // Créneaux du jour sélectionné, utilisés pour savoir si la cible du
  // blocage (une plage précise, ou "Toutes") a des réservations en cours.
  final List<AgendaSlot> daySlots;
  final Future<String?> Function({
    required String? timeSlotId,
    required String reason,
  })
  onConfirm;

  const _BlockSheet({
    required this.timeslots,
    required this.daySlots,
    required this.onConfirm,
  });

  @override
  State<_BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<_BlockSheet> {
  final _reasonController = TextEditingController();
  // null = toutes les plages; sinon = id de la plage sélectionnée
  String? _selectedId;
  bool _loading = false;
  bool _showReasonError = false;

  // La cible sélectionnée a-t-elle des réservations aujourd'hui ?
  // "Toutes" (_selectedId == null) : dès qu'une seule plage a des
  // réservations, la raison devient obligatoire (pas de cas mixte).
  bool get _reasonRequired => _selectedId == null
      ? widget.daySlots.any((s) => s.reserved > 0)
      : widget.daySlots.any(
          (s) => s.timeSlotId == _selectedId && s.reserved > 0,
        );

  @override
  void initState() {
    super.initState();
    // Ne pas présélectionner une plage en cours de suppression programmée.
    if (widget.timeslots.length == 1 &&
        widget.timeslots.first.deleteAfter == null) {
      _selectedId = widget.timeslots.first.id;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // Puce de sélection : contraste net sélectionné / non sélectionné
  // (rempli rouge + coche vs bordure grise), pour qu'on voie d'un coup
  // d'œil ce qui est ciblé.
  Widget _selectChip({
    required String label,
    required bool selected,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    final Color bg;
    final Color fg;
    final Color border;
    if (disabled) {
      bg = Colors.grey.shade100;
      fg = Colors.grey.shade400;
      border = Colors.grey.shade200;
    } else if (selected) {
      bg = Colors.red.shade600;
      fg = Colors.white;
      border = Colors.red.shade600;
    } else {
      bg = Colors.white;
      fg = Colors.grey.shade800;
      border = Colors.grey.shade300;
    }
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: fg,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.timeslots.length > 1;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        28 +
            MediaQuery.of(context).padding.bottom +
            MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.red.shade600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Bloquer les créneaux',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          if (hasMultiple) ...[
            const SizedBox(height: 16),
            Text(
              'Quelle plage ?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...widget.timeslots.map((ts) {
                  final deferred = ts.deleteAfter != null;
                  return _selectChip(
                    label: deferred
                        ? '${ts.startTime}–${ts.endTime} · suppr. programmée'
                        : '${ts.startTime}–${ts.endTime}',
                    selected: _selectedId == ts.id,
                    disabled: deferred,
                    onTap: () => setState(() {
                      _selectedId = ts.id;
                      _showReasonError = false;
                    }),
                  );
                }),
                _selectChip(
                  label: 'Toutes les plages',
                  selected: _selectedId == null,
                  disabled: false,
                  onTap: () => setState(() {
                    _selectedId = null;
                    _showReasonError = false;
                  }),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            // Autofocus seulement s'il n'y a pas de créneau à choisir
            // avant : sinon le clavier masquerait les puces de sélection.
            autofocus: !hasMultiple,
            onChanged: (_) {
              if (_showReasonError) {
                setState(() => _showReasonError = false);
              }
            },
            decoration: InputDecoration(
              labelText: _reasonRequired
                  ? 'Raison (visible par les clients)'
                  : 'Raison (optionnel)',
              hintText: 'Ex : Panne technique, urgence, personnel absent…',
              prefixIcon: const Icon(Icons.info_outline_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.shade400),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.shade400, width: 2),
              ),
              errorText: _showReasonError
                  ? 'Raison requise — des réservations sont en cours sur ce créneau'
                  : null,
              errorMaxLines: 2,
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            maxLines: 2,
            // La raison part telle quelle dans la notification client.
            maxLength: 120,
          ),
          if (_reasonRequired) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 15,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Les clients ayant réservé via l\'app seront prévenus que '
                    'le service est suspendu. Ceux venus réserver sur place ne '
                    'recevront rien — pensez à les prévenir.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      final reason = _reasonController.text.trim();
                      if (reason.isEmpty && _reasonRequired) {
                        setState(() => _showReasonError = true);
                        return;
                      }
                      setState(() => _loading = true);
                      Navigator.pop(context);
                      await widget.onConfirm(
                        timeSlotId: _selectedId,
                        reason: reason,
                      );
                    },
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
              label: const Text(
                'Bloquer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                disabledBackgroundColor: Colors.red.shade200,
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
    );
  }
}

// ── Section créneaux dépassés avec animation expand/collapse ─────────────────
class _PastSlotsSection extends StatefulWidget {
  final bool isExpanded;
  final List<Widget> children;

  const _PastSlotsSection({required this.isExpanded, required this.children});

  @override
  State<_PastSlotsSection> createState() => _PastSlotsSectionState();
}

class _PastSlotsSectionState extends State<_PastSlotsSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // Chaque carte démarre 35 ms après la précédente (fraction sur 500 ms = 0.07).
  // Les 6 premières cartes sont staggerées ; les suivantes partagent le même décalage.
  static const int _maxStagger = 6;
  static const double _staggerStep = 0.07;
  static const double _cardSpan = 0.56; // durée d'animation de chaque carte

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.isExpanded ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_PastSlotsSection old) {
    super.didUpdateWidget(old);
    if (widget.isExpanded != old.isExpanded) {
      widget.isExpanded ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Animation<double> _cardAnim(int index) {
    final i = index.clamp(0, _maxStagger);
    final start = i * _staggerStep;
    final end = (start + _cardSpan).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      axisAlignment: -1.0,
      child: Column(
        children: widget.children.asMap().entries.map((entry) {
          final anim = _cardAnim(entry.key);
          return AnimatedBuilder(
            animation: anim,
            builder: (_, child) => Opacity(
              opacity: anim.value,
              child: Transform.translate(
                offset: Offset(0, (1.0 - anim.value) * -14),
                child: child,
              ),
            ),
            child: entry.value,
          );
        }).toList(),
      ),
    );
  }
}

// ── Bouton toggle "N créneaux dépassés / Masquer" ─────────────────────────────
class _PastSlotsToggle extends StatelessWidget {
  final int count;
  final bool isCountApproximate;
  final bool isExpanded;
  final VoidCallback onTap;

  const _PastSlotsToggle({
    required this.count,
    required this.isCountApproximate,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isCountApproximate ? '$count+' : '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                isExpanded
                    ? 'Masquer les créneaux dépassés'
                    : 'créneaux dépassés',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
