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

// ── Empty state (onboarding première file) ────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateQueue;
  const _EmptyState({required this.onCreateQueue});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCreateQueue,
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _lightGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _lightGreen.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  _OnboardingStep(number: '1', text: 'Créez une file d\'attente'),
                  const SizedBox(height: 8),
                  _OnboardingStep(number: '2', text: 'Ajoutez une plage horaire'),
                  const SizedBox(height: 8),
                  _OnboardingStep(
                    number: '3',
                    text: 'Vos clients peuvent réserver !',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  final String number;
  final String text;
  const _OnboardingStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _green.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
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
}

// ── Ligne de 3 stats ──────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final QueueStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              emoji: '🟢',
              value: stats.placesRestantes.toString(),
              label: 'Disponibles',
              color: stats.placesRestantes == 0
                  ? Colors.red.shade600
                  : _green,
            ),
          ),
          Container(width: 1, height: 50, color: Colors.grey.shade200),
          Expanded(
            child: _StatItem(
              emoji: '📌',
              value: stats.placesReservees.toString(),
              label: 'Réservées',
              color: Colors.blue.shade600,
            ),
          ),
          Container(width: 1, height: 50, color: Colors.grey.shade200),
          Expanded(
            child: _StatItem(
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
}

class _StatItem extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  const _StatItem({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte en-tête de file ─────────────────────────────────────────────────────
class _QueueHeaderCard extends StatelessWidget {
  final _QueueAgenda queue;
  final int? currentDuration; // null quand plusieurs plages (valeurs hétérogènes)
  final int? currentCapacity;
  final void Function(int delta) onDurationChanged; // reçoit +step ou -step
  final void Function(int delta) onCapacityChanged;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;

  const _QueueHeaderCard({
    required this.queue,
    required this.currentDuration,
    required this.currentCapacity,
    required this.onDurationChanged,
    required this.onCapacityChanged,
    required this.onBlock,
    required this.onUnblock,
  });

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
            // Nom + badge statut
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  queue.name,
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
                    color: queue.isBlocked
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
                          color: queue.isBlocked
                              ? Colors.grey.shade500
                              : _green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        queue.isBlocked ? 'Bloquée' : 'Active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: queue.isBlocked
                              ? Colors.grey.shade600
                              : _green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Raison du blocage
            if (queue.isBlocked && queue.blockReason != null) ...[
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
                            queue.blockReason!,
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

            const SizedBox(height: 14),
            _StatsRow(stats: queue.stats),
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 14),

            // Contrôles durée + capacité (cachés si bloquée ou aucun créneau chargé)
            if (!queue.isBlocked && queue.slots.isNotEmpty) ...[
              _ControlRow(
                label: 'Durée',
                icon: Icons.timer,
                value: currentDuration,
                unit: 'min',
                min: 5,
                max: 120,
                step: 5,
                onChanged: onDurationChanged,
              ),
              const SizedBox(height: 12),
              _ControlRow(
                label: 'Capacité',
                icon: Icons.people,
                value: currentCapacity,
                unit: 'pers.',
                min: 1,
                max: 50,
                step: 1,
                onChanged: onCapacityChanged,
              ),
              const SizedBox(height: 16),
            ],

            // Bouton Bloquer / Débloquer
            SizedBox(
              width: double.infinity,
              child: queue.isBlocked
                  ? ElevatedButton.icon(
                      onPressed: onUnblock,
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text(
                        'Débloquer la plage',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: onBlock,
                      icon: Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                      label: Text(
                        'Bloquer la plage',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
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

  const _ControlRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canDecrease = value == null || value! > min;
    final canIncrease = value == null || value! < max;
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
        _PlusMinusBtn(
          icon: Icons.remove,
          enabled: canDecrease,
          onTap: () => onChanged(-step),
        ),
        const SizedBox(width: 14),
        Text(
          value != null ? '$value $unit' : '—',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 14),
        _PlusMinusBtn(
          icon: Icons.add,
          enabled: canIncrease,
          onTap: () => onChanged(step),
        ),
      ],
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
          border: Border.all(
            color: enabled ? _green : Colors.grey.shade300,
          ),
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

  const _SlotCard({
    required this.slot,
    required this.timeFormat,
    required this.onTap,
  });

  String _subtitle() {
    if (slot.isBlocked) return 'Bloqué';
    if (slot.reserved == 0) return 'Disponible';
    return '${slot.reserved} personne(s) réservée(s)';
  }

  Widget _statusBadge(bool isBlocked, bool isFull) {
    if (isBlocked) {
      return _solidBadge('Bloqué', Colors.red.shade600);
    }
    if (isFull) {
      return _solidBadge('Complet', Colors.red.shade400);
    }
    final remaining = slot.capacity - slot.reserved;
    if (slot.reserved > 0) {
      return _solidBadge(
        '$remaining pl.',
        Colors.orange.shade500,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.35)),
      ),
      child: Text(
        'Libre',
        style: TextStyle(
          color: _green,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
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
              '${timeFormat.format(slot.start)} – ${timeFormat.format(slot.end)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            _statusBadge(isBlocked, isFull),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              _subtitle(),
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

  const _TimeslotPickerSheet({
    required this.timeslots,
    required this.title,
  });

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
                child: const Icon(Icons.schedule_rounded,
                    color: _green, size: 20),
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
          ...timeslots.map(
            (ts) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.access_time_rounded,
                        color: _green, size: 20),
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
                  '${ts.duration} min · ${ts.capacity} pers./créneau',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: _green),
                onTap: () => Navigator.pop(context, ts),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Annuler',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.grey.shade600, fontSize: 15),
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
  final Future<String?> Function({
    required String? timeSlotId,
    required String reason,
  }) onConfirm;

  const _BlockSheet({
    required this.timeslots,
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

  @override
  void initState() {
    super.initState();
    if (widget.timeslots.length == 1) {
      _selectedId = widget.timeslots.first.id;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.timeslots.length > 1;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
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
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.lock_outline_rounded,
                      color: Colors.red.shade600, size: 20),
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ...widget.timeslots.map(
                    (ts) => ChoiceChip(
                      label: Text('${ts.startTime}–${ts.endTime}'),
                      selected: _selectedId == ts.id,
                      onSelected: (_) =>
                          setState(() => _selectedId = ts.id),
                      selectedColor: _green.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: _selectedId == ts.id
                            ? _green
                            : Colors.grey.shade700,
                        fontWeight: _selectedId == ts.id
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Toutes'),
                    selected: _selectedId == null,
                    onSelected: (_) =>
                        setState(() => _selectedId = null),
                    selectedColor: Colors.red.shade50,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: _selectedId == null
                          ? Colors.red.shade700
                          : Colors.grey.shade700,
                      fontWeight: _selectedId == null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Raison du blocage',
                hintText: 'Ex : Pause déjeuner, Réunion...',
                prefixIcon:
                    const Icon(Icons.info_outline_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading
                    ? null
                    : () async {
                        final reason =
                            _reasonController.text.trim();
                        if (reason.isEmpty) return;
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
                    : const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 18),
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
                  disabledBackgroundColor:
                      Colors.red.shade200,
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
}
