part of 'house_page.dart';

// ============================================================
// HOUSE DIALOGS — Dialogs et bottom sheets extraits de house_page
// ============================================================

// ── Dialog modification durée / capacité ─────────────────────────────────────
Future<_ModifResult?> _showModifDialog(
  BuildContext context, {
  required String title,
  required String preview,
  bool hasReservations = false,
  bool isCapacity = false,
  bool todayDone = false,
}) async {
  ModificationType type =
      todayDone ? ModificationType.permanente : ModificationType.ponctuelle;
  return showDialog<_ModifResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),

            if (hasReservations) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _green.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, color: _green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isCapacity
                            ? 'Seules les places libres seront ajustées. '
                                'Les réservations existantes sont préservées, '
                                'vos clients ne sont pas impactés.'
                            : 'Seuls les créneaux libres seront recalculés. '
                                'Les créneaux déjà réservés gardent leur '
                                'heure — vos clients ne sont pas impactés.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2E5E3E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Opacity(
              opacity: todayDone ? 0.4 : 1.0,
              child: RadioListTile<ModificationType>(
                title: const Text("Juste pour aujourd'hui"),
                subtitle: const Text(
                  'Les paramètres reviendront à la normale demain',
                  style: TextStyle(fontSize: 12),
                ),
                value: ModificationType.ponctuelle,
                groupValue: type,
                activeColor: _green,
                contentPadding: EdgeInsets.zero,
                onChanged: todayDone ? null : (v) => setD(() => type = v!),
              ),
            ),
            if (todayDone)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  'Tous les créneaux d\'aujourd\'hui sont terminés',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _ModifResult(type: type)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Confirmer',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Bottom sheet : ajout rapide via FAB — carousel des créneaux disponibles ───
class _QuickAddSheet extends StatefulWidget {
  final _QueueAgenda queue;
  final List<AgendaSlot> availableSlots;
  final DateFormat timeFormat;
  final Future<void> Function(String name, AgendaSlot slot) onConfirm;

  const _QuickAddSheet({
    required this.queue,
    required this.availableSlots,
    required this.timeFormat,
    required this.onConfirm,
  });

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _nameController = TextEditingController();
  late final PageController _pageController;
  int _currentIndex = 0;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  AgendaSlot get _currentSlot => widget.availableSlots[_currentIndex];

  @override
  Widget build(BuildContext context) {
    final total = widget.availableSlots.length;
    final bottomPadding =
        28.0 + MediaQuery.of(context).padding.bottom;

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
            // Titre
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: _green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Ajouter un client',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carousel des créneaux disponibles
            SizedBox(
              height: 76,
              child: PageView.builder(
                controller: _pageController,
                itemCount: total,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) {
                  final slot = widget.availableSlots[index];
                  final remaining = slot.capacity - slot.reserved;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              color: _green, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${widget.timeFormat.format(slot.start)} – ${widget.timeFormat.format(slot.end)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  widget.queue.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$remaining pl.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _green,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Indicateur de position + hint de swipe
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (total > 1)
                  Icon(Icons.swipe_rounded,
                      size: 13, color: Colors.grey.shade400),
                if (total > 1) const SizedBox(width: 4),
                Text(
                  total > 1
                      ? '${_currentIndex + 1} / $total disponibles'
                      : '1 créneau disponible',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            // Champ nom
            TextField(
              controller: _nameController,
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final name = _nameController.text.trim();
                  if (name.isEmpty) {
                    setState(() => _nameError = 'Veuillez entrer un nom');
                    return;
                  }
                  final slot = _currentSlot;
                  Navigator.pop(context);
                  await widget.onConfirm(name, slot);
                },
                icon: const Icon(Icons.check_rounded, color: Colors.white),
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
      ),
    );
  }
}
