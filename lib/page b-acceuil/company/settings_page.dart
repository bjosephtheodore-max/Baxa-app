import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/slot_generation_service.dart';
import 'package:baxa/services/onboarding_service.dart';
import 'package:baxa/widgets/onboarding_widgets.dart';

part 'queue_timeslots_page.dart';
part 'queue_timeslots_dialogs.dart';
part 'queue_timeslots_logic.dart';

// ============================================================
// CONSTANTES PARTAGÉES
// ============================================================
const Color _kGreen = Color.fromARGB(255, 75, 139, 94);
const Color _kLightGreen = Color.fromARGB(255, 178, 211, 194);

// ============================================================
// Suppression d'une file : efface ses sous-collections (Firestore ne
// cascade pas) puis le doc file. N'est appelé que sur une file sans plage
// et sans réservation à venir — le balayage récupère d'éventuels restes
// d'anciennes suppressions.
// ============================================================
Future<void> _sweepAndDeleteQueue(
  FirebaseFirestore fs,
  String companyId,
  String queueId,
) async {
  final queueRef = fs
      .collection('companies')
      .doc(companyId)
      .collection('queues')
      .doc(queueId);
  for (final sub in const ['slots', 'timeSlots', 'dailyStats']) {
    QuerySnapshot<Map<String, dynamic>> snap;
    do {
      snap = await queueRef.collection(sub).limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = fs.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snap.docs.length == 400);
  }
  await queueRef.delete();
}

// ==================== PAGE PRINCIPALE : LISTE DES FILES ====================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _companyId;
  bool _isLoading = true;
  int _queueCount = 0;
  bool _isCreatingQueue = false;
  late final Stream<QuerySnapshot> _queuesStream;
  final Map<String, Stream<int>> _capacityStreams = {};

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _companyId = user?.uid;
    _queuesStream = _companyId != null
        ? _firestore
              .collection('companies')
              .doc(_companyId)
              .collection('queues')
              .snapshots()
        : const Stream.empty();
    _isLoading = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_companyId == null) {
      return const Scaffold(
        body: Center(child: Text('Erreur : utilisateur non connecté')),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.black87,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'Files d\'attente',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade100, height: 1),
        ),
      ),
      body: ListenableBuilder(
        listenable: OnboardingService(),
        builder: (context, child) {
          if (OnboardingService().step != 3) return child!;
          return Stack(
            children: [
              child!,
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(color: Colors.black.withValues(alpha: 0.58)),
                ),
              ),
            ],
          );
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<QuerySnapshot>(
                stream: _queuesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Erreur : ${snapshot.error}'));
                  }
                  final queues = snapshot.data?.docs ?? [];
                  _queueCount = queues.length;
                  if (queues.isEmpty) return _buildEmptyState();
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                    itemCount: queues.length,
                    itemBuilder: (context, index) {
                      final queue = queues[index];
                      final queueData = queue.data() as Map<String, dynamic>;
                      return _buildQueueCard(queue.id, queueData);
                    },
                  );
                },
              ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: OnboardingService(),
        builder: (_, child) {
          final active = OnboardingService().step == 3;
          return active ? PulsingGlow(child: child!) : child!;
        },
        child: FloatingActionButton.extended(
          onPressed: _isCreatingQueue ? null : _showCreateQueueDialog,
          backgroundColor: _kGreen,
          elevation: 3,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text(
            'Nouvelle file',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.queue_outlined,
              size: 64,
              color: _kGreen.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Aucune file d\'attente',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Appuyez sur le bouton ci-dessous\npour créer votre première file',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          Icon(
            Icons.arrow_downward_rounded,
            size: 28,
            color: _kGreen.withValues(alpha: 0.65),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(String queueId, Map<String, dynamic> queueData) {
    final name = queueData['name'] as String? ?? 'File sans nom';
    final weekdays =
        (queueData['weekdays'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [1, 2, 3, 4, 5, 6, 7];
    final closureStart = (queueData['closureStart'] as Timestamp?)?.toDate();
    final closureEnd = (queueData['closureEnd'] as Timestamp?)?.toDate();
    final closedNow = isQueueClosedNow(closureStart, closureEnd);
    final closurePlannedFor =
        (closureStart != null && closureStart.isAfter(DateTime.now()))
        ? closureStart
        : null;
    final deleteAfter = (queueData['deleteAfter'] as Timestamp?)?.toDate();

    final card = _AnimatedQueueCard(
      name: name,
      weekdays: _formatWeekdays(weekdays),
      open: !closedNow,
      closurePlannedFor: closurePlannedFor,
      deleteAfter: deleteAfter,
      capacityStream: _capacityStreams.putIfAbsent(
        queueId,
        () => _calculateTotalCapacity(queueId),
      ),
      onTap: () {
        if (OnboardingService().step == 4) {
          OnboardingService().advance(4); // 4 → 5
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QueueTimeSlotsPage(
              companyId: _companyId!,
              queueId: queueId,
              queueName: name,
            ),
          ),
        );
      },
      onMoreTap: () => _showQueueActions(queueId, queueData),
    );

    return ListenableBuilder(
      listenable: OnboardingService(),
      builder: (_, child) {
        if (OnboardingService().step == 4) {
          return PulsingGlow(
            borderRadius: BorderRadius.circular(14),
            child: child!,
          );
        }
        return child!;
      },
      child: card,
    );
  }

  void _showQueueActions(String queueId, Map<String, dynamic> queueData) {
    final name = queueData['name'] ?? 'File';
    final closedNow = isQueueClosedNow(
      (queueData['closureStart'] as Timestamp?)?.toDate(),
      (queueData['closureEnd'] as Timestamp?)?.toDate(),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.of(sheetCtx).padding.bottom,
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1C2E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _renameQueue(queueId, name);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!closedNow)
              _actionTile(
                icon: Icons.pause_circle_outline_rounded,
                label: 'Stopper les réservations',
                color: Colors.orange.shade700,
                onTap: () {
                  Navigator.pop(context);
                  _confirmStopReservations(queueId, queueData);
                },
              )
            else
              _actionTile(
                icon: Icons.play_circle_outline_rounded,
                label: 'Rouvrir immédiatement',
                color: _kGreen,
                onTap: () {
                  Navigator.pop(context);
                  _reopenQueue(queueId);
                },
              ),
            const SizedBox(height: 10),
            if (queueData['deleteAfter'] == null)
              _actionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Supprimer la file',
                color: Colors.red.shade400,
                onTap: () {
                  Navigator.pop(context);
                  _deleteQueue(queueId, name, queueData);
                },
              )
            else
              _actionTile(
                icon: Icons.restore_from_trash_outlined,
                label: 'Restituer la file',
                color: _kGreen,
                onTap: () {
                  Navigator.pop(context);
                  _restoreQueueDeletion(queueId);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameQueue(String queueId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    String? errorText;

    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: _kGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Renommer la file',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1C2E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: true,
                  onChanged: (_) {
                    if (errorText != null) {
                      setSheet(() => errorText = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Nom de la file',
                    errorText: errorText,
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(
                      Icons.label_outline_rounded,
                      color: _kGreen,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kGreen, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isEmpty) {
                        setSheet(() => errorText = 'Veuillez entrer un nom');
                        return;
                      }
                      Navigator.pop(ctx, value);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Enregistrer',
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
          ),
        ),
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName) {
      return;
    }

    try {
      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .update({'name': newName});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File renommée')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rouvrir une file fermée, immédiatement ─────────────────────
  Future<void> _reopenQueue(String queueId) async {
    final companyId = _companyId;
    if (companyId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Rouvrir immédiatement ?'),
        content: const Text(
          'Les réservations rouvrent tout de suite et les créneaux sont '
          'régénérés. Toute date de réouverture prévue est annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rouvrir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('queues')
          .doc(queueId)
          .update({
            'closureStart': FieldValue.delete(),
            'closureEnd': FieldValue.delete(),
          });

      try {
        await regenerateSlotsForQueue(
          firestore: _firestore,
          companyId: companyId,
          queueId: queueId,
        );
      } catch (_) {
        // La CF de nuit rattrapera si la régénération immédiate échoue.
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Réservations rouvertes'),
          backgroundColor: _kGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ── Confirmation « Stopper les réservations » ───────────────────
  // Raccourci de la fermeture : cette file, dès maintenant, sans date de
  // fin, sans annuler les réservations en cours (on reste ouvert pour les
  // clients déjà réservés, on bloque seulement les nouvelles).
  Future<void> _confirmStopReservations(
    String queueId,
    Map<String, dynamic> queueData,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Stopper les réservations ?'),
        content: const Text(
          'Dès maintenant, vos clients ne pourront plus prendre de nouvelle '
          'réservation sur cette file.\n\n'
          'Les réservations déjà confirmées ne sont pas touchées : vos clients '
          'gardent leur créneau.\n\n'
          'C\'est réversible à tout moment : « Rouvrir les réservations ».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text(
              'Oui, stopper',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .update({
            'closureStart': Timestamp.fromDate(DateTime.now()),
            'closureEnd': FieldValue.delete(),
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🚫 Réservations stoppées'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ── Suppression d'une file ──────────────────────────────────────
  // Une file ne se supprime que lorsqu'elle n'a plus AUCUNE plage (donc
  // plus aucune réservation possible). Tant qu'il reste des plages, on
  // renvoie l'entreprise vers la page des plages — où elle découvre
  // « Programmer la suppression », qui retire une plage sans casser les
  // réservations en cours.
  Future<void> _deleteQueue(
    String queueId,
    String queueName,
    Map<String, dynamic> queueData,
  ) async {
    // Une file en cours de suppression programmée est gérée par le bouton
    // « Restituer la file » du menu — pas ici.
    if (queueData['deleteAfter'] != null) return;

    // ── État des plages de la file ────────────────────────────────
    List<QueryDocumentSnapshot<Map<String, dynamic>>> timeSlots;
    try {
      final snap = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .collection('timeSlots')
          .get();
      timeSlots = snap.docs;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la vérification : $e')),
      );
      return;
    }
    if (!mounted) return;

    // ── Cas 1 : aucune plage → suppression directe ────────────────
    if (timeSlots.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Supprimer cette file ?'),
          content: Text(
            'La file « $queueName » sera supprimée définitivement.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Supprimer',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (confirm == true) await _performQueueDeletion(queueId, queueName);
      return;
    }

    // ── Cas 2/3 : des plages existent ────────────────────────────
    final deferredDates = timeSlots
        .where((d) => d.data()['deleteAfter'] != null)
        .map((d) => (d.data()['deleteAfter'] as Timestamp).toDate())
        .toList();
    final n = timeSlots.length;
    final allDeferred = deferredDates.length == n;

    // ── Cas 2 : au moins une plage encore active → rediriger ──────
    if (!allDeferred) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Supprimez d\'abord les plages'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cette file contient $n plage${n > 1 ? 's' : ''} horaire'
                '${n > 1 ? 's' : ''}. Supprimez-${n > 1 ? 'les' : 'la'} '
                'd\'abord pour pouvoir supprimer la file.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: Colors.blue.shade600,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sur chaque plage, « Programmer la suppression » la '
                        'retire sans annuler les réservations en cours de vos '
                        'clients.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
              child: const Text(
                'Voir les plages',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QueueTimeSlotsPage(
              companyId: _companyId!,
              queueId: queueId,
              queueName: queueName,
            ),
          ),
        );
      }
      return;
    }

    // ── Cas 3 : toutes les plages sont programmées pour suppression ─
    deferredDates.sort();
    final lastDate = deferredDates.last;
    final f = DateFormat('EEE d MMM', 'fr_FR').format(lastDate);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer aussi la file ?'),
        content: Text(
          'Toutes les plages de cette file sont programmées pour suppression '
          '(dernière le $f). Voulez-vous que la file elle-même soit supprimée '
          'automatiquement à cette date, une fois la dernière plage partie ?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
            child: Text(
              'Oui, le $f',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .update({'deleteAfter': Timestamp.fromDate(lastDate)});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression de la file programmée pour le $f.'),
          backgroundColor: _kGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ── Exécution de la suppression d'une file (coquille vide) ──────
  Future<void> _performQueueDeletion(String queueId, String queueName) async {
    try {
      await _sweepAndDeleteQueue(_firestore, _companyId!, queueId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ File « $queueName » supprimée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ── Restituer une suppression de file programmée ────────────────
  // N'efface QUE le marqueur de la file ; les plages qui ont leur propre
  // suppression programmée la gardent (leur restitution, elle, lève aussi
  // celle de la file — voir _restorePendingDeletion).
  Future<void> _restoreQueueDeletion(String queueId) async {
    try {
      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .update({'deleteAfter': FieldValue.delete()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression de la file annulée.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Stream<int> _calculateTotalCapacity(String queueId) {
    return _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('timeSlots')
        .snapshots()
        .map((snapshot) {
          int total = 0;
          for (final doc in snapshot.docs) {
            final d = doc.data();
            final start = d['startTime'] as String? ?? '00:00';
            final end = d['endTime'] as String? ?? '00:00';
            final duration =
                (d['serviceDurationMinutes'] as num?)?.toInt() ?? 0;
            final capacity = (d['capacityPerSlot'] as num?)?.toInt() ?? 0;
            if (duration > 0) {
              final slotsCount = _countSlots(start, end, duration);
              total += slotsCount * capacity;
            }
          }
          return total;
        });
  }

  String _formatWeekdays(List<int> weekdays) {
    final labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    if (weekdays.length == 7) return 'Tous les jours';
    return weekdays.map((i) => labels[i - 1]).join(', ');
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

  Future<void> _showCreateQueueDialog() async {
    if (_isCreatingQueue) return;
    setState(() => _isCreatingQueue = true);
    if (_queueCount >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum 5 files d\'attente atteint'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isCreatingQueue = false);
      return;
    }

    final nameCtrl = TextEditingController();
    List<int> selectedWeekdays = [1, 2, 3, 4, 5];
    String? nameError;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          const dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
          return Padding(
            padding: EdgeInsets.only(
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kGreen,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.people_alt_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Nom de la file d\'attente',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: nameCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            autofocus: true,
                            onChanged: (_) {
                              if (nameError != null) {
                                setD(() => nameError = null);
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Ex : Consultation, Caisse principale…',
                              errorText: nameError,
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(
                                Icons.label_outline_rounded,
                                color: _kGreen,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: _kGreen,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Jours d\'ouverture',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF1A1C2E),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(7, (index) {
                              final day = index + 1;
                              final selected = selectedWeekdays.contains(day);
                              return GestureDetector(
                                onTap: () => setD(() {
                                  if (selected) {
                                    selectedWeekdays.remove(day);
                                  } else {
                                    selectedWeekdays.add(day);
                                  }
                                  selectedWeekdays.sort();
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _kGreen
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected
                                          ? _kGreen
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    dayLabels[index],
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                if (nameCtrl.text.trim().isEmpty) {
                                  setD(
                                    () => nameError = 'Veuillez entrer un nom',
                                  );
                                  return;
                                }
                                if (selectedWeekdays.isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Sélectionnez au moins un jour',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx, true);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kGreen,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Créer la file',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
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
    );
    if (result != true) {
      if (mounted) setState(() => _isCreatingQueue = false);
      return;
    }
    try {
      final docRef = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .add({
            'name': nameCtrl.text.trim(),
            'weekdays': selectedWeekdays,
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;

      final inOnboarding = OnboardingService().step == 3;
      if (inOnboarding) {
        OnboardingService().advance(3); // 3 → 4
        await showOnboardingCelebration(
          context,
          title: 'File d\'attente créée !',
          body:
              'Super ! Votre file "${nameCtrl.text.trim()}" est prête.\n\nAppuyez sur la file pour configurer vos plages horaires.',
        );
        // Step 4 : l'utilisateur doit taper la carte de file pour continuer.
        // La navigation vers QueueTimeSlotsPage se fait via le tap de la carte.
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File créée ✅ Ajoutez maintenant une plage horaire'),
          ),
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QueueTimeSlotsPage(
              companyId: _companyId!,
              queueId: docRef.id,
              queueName: nameCtrl.text.trim(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _isCreatingQueue = false);
    }
  }
}

// ============================================================
// CARTE FILE D'ATTENTE — avec animation "push" au press
// ============================================================
class _AnimatedQueueCard extends StatefulWidget {
  final String name;
  final String weekdays;
  final bool open; // false = fermée aux nouvelles réservations maintenant
  final DateTime? closurePlannedFor; // fermeture planifiée, pas encore active
  final Stream<int> capacityStream;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;
  final DateTime? deleteAfter;

  const _AnimatedQueueCard({
    required this.name,
    required this.weekdays,
    required this.open,
    this.closurePlannedFor,
    required this.capacityStream,
    required this.onTap,
    required this.onMoreTap,
    this.deleteAfter,
  });

  @override
  State<_AnimatedQueueCard> createState() => _AnimatedQueueCardState();
}

class _AnimatedQueueCardState extends State<_AnimatedQueueCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _pressed ? 0.03 : 0.08),
                blurRadius: _pressed ? 3 : 10,
                offset: Offset(0, _pressed ? 1 : 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: _pressed ? const Color(0xFFF4FAF6) : Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Barre accent gauche ──────────────────
                        Container(
                          width: 5,
                          color: widget.open ? _kGreen : Colors.grey.shade300,
                        ),

                        // ── Contenu principal ────────────────────
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
                            child: Row(
                              children: [
                                // Icône circulaire
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: widget.open
                                        ? _kGreen.withValues(alpha: 0.1)
                                        : Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.people_alt_rounded,
                                    color: widget.open
                                        ? _kGreen
                                        : Colors.grey.shade400,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Nom + jours
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              widget.name,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1A1C2E),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!widget.open) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Fermée',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.orange.shade700,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        widget.weekdays,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Capacité totale
                                StreamBuilder<int>(
                                  stream: widget.capacityStream,
                                  builder: (context, snap) {
                                    if (snap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      );
                                    }
                                    final total = snap.data ?? 0;
                                    if (total == 0) {
                                      return const SizedBox.shrink();
                                    }
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _kGreen.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.groups_rounded,
                                            size: 14,
                                            color: _kGreen,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '$total',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _kGreen,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 6),

                                // Chevron vert — signal de navigation
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: _kGreen,
                                  size: 26,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Séparateur vertical ──────────────────
                        Container(width: 1, color: Colors.grey.shade100),

                        // ── Bouton ⋮ isolé ───────────────────────
                        // Material + InkWell : toute la colonne (largeur × hauteur
                        // de la carte) est une cible de tap, avec un retour visuel.
                        // Sans ça, seul le glyphe de l'icône captait le tap et le
                        // reste ouvrait la page des plages par erreur.
                        SizedBox(
                          width: 54,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: widget.onMoreTap,
                              child: Center(
                                child: Icon(
                                  Icons.more_vert_rounded,
                                  color: Colors.grey.shade400,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.deleteAfter != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      color: Colors.red.shade50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_delete_outlined,
                            size: 13,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Suppression de la file programmée le '
                              '${DateFormat('d MMM', 'fr_FR').format(widget.deleteAfter!)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (widget.closurePlannedFor != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      color: Colors.indigo.shade50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.nightlight_round_outlined,
                            size: 13,
                            color: Colors.indigo.shade400,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Fermeture prévue le '
                              '${DateFormat('d MMM', 'fr_FR').format(widget.closurePlannedFor!)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== PAGE DES PLAGES HORAIRES ====================
class QueueTimeSlotsPage extends StatefulWidget {
  final String companyId;
  final String queueId;
  final String queueName;
  final bool autoOpenSlotDialog;

  const QueueTimeSlotsPage({
    super.key,
    required this.companyId,
    required this.queueId,
    required this.queueName,
    this.autoOpenSlotDialog = false,
  });

  @override
  State<QueueTimeSlotsPage> createState() => _QueueTimeSlotsPageState();
}

// ============================================================
// MODÈLE INTERNE — un groupe de jours avec leur capacité
// ============================================================
class _DayCapacity {
  final String label;
  final int capacity;

  const _DayCapacity({required this.label, required this.capacity});
}

// ============================================================
// WIDGET DÉFILANT POUR SÉLECTION NUMÉRIQUE
// ============================================================
class _NumberPickerDial extends StatefulWidget {
  final int min;
  final int max;
  final int value;
  final String suffix;
  final ValueChanged<int> onChanged;

  const _NumberPickerDial({
    required this.min,
    required this.max,
    required this.value,
    required this.suffix,
    required this.onChanged,
  });

  @override
  State<_NumberPickerDial> createState() => _NumberPickerDialState();
}

class _NumberPickerDialState extends State<_NumberPickerDial> {
  late FixedExtentScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = FixedExtentScrollController(
      initialItem: (widget.value - widget.min).clamp(
        0,
        widget.max - widget.min,
      ),
    );
  }

  @override
  void didUpdateWidget(_NumberPickerDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _ctrl.animateToItem(
        (widget.value - widget.min).clamp(0, widget.max - widget.min),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListWheelScrollView.useDelegate(
        controller: _ctrl,
        itemExtent: 36,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.003,
        onSelectedItemChanged: (i) => widget.onChanged(i + widget.min),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.max - widget.min + 1,
          builder: (context, index) {
            final val = index + widget.min;
            final isSelected = val == widget.value;
            return Center(
              child: Text(
                '$val ${widget.suffix}',
                style: TextStyle(
                  fontSize: isSelected ? 18 : 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                  color: isSelected ? _kGreen : Colors.grey.shade400,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
