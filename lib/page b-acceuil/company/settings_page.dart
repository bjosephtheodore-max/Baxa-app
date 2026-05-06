import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baxa/services/booking_constants.dart';

part 'queue_timeslots_page.dart';
part 'queue_timeslots_dialogs.dart';
part 'queue_timeslots_logic.dart';

// ============================================================
// CONSTANTES PARTAGÉES
// ============================================================
const Color _kGreen = Color.fromARGB(255, 75, 139, 94);
const Color _kLightGreen = Color.fromARGB(255, 178, 211, 194);

// ==================== PAGE PRINCIPALE : LISTE DES FILES ====================
class SettingsPage extends StatefulWidget {
  final bool autoOpenCreateDialog;
  const SettingsPage({super.key, this.autoOpenCreateDialog = false});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _companyId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _companyId = user?.uid;
    setState(() => _isLoading = false);
    if (widget.autoOpenCreateDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCreateQueueDialog();
      });
    }
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
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.black87, size: 20),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('companies')
                  .doc(_companyId)
                  .collection('queues')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur : ${snapshot.error}'));
                }
                final queues = snapshot.data?.docs ?? [];
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateQueueDialog,
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_outlined, size: 80, color: Colors.grey.shade400),
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
            'Créez votre première file pour commencer',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(String queueId, Map<String, dynamic> queueData) {
    final name = queueData['name'] ?? 'File sans nom';
    final weekdays =
        (queueData['weekdays'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [1, 2, 3, 4, 5, 6, 7];
    final isActive = queueData['isActive'] ?? true;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                color: isActive ? _kGreen : Colors.grey.shade300,
              ),
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QueueTimeSlotsPage(
                        companyId: _companyId!,
                        queueId: queueId,
                        queueName: name,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 20, 8, 20),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isActive
                                ? _kGreen.withValues(alpha: 0.1)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.people_alt_rounded,
                            color: isActive ? _kGreen : Colors.grey.shade400,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A1C2E),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!isActive) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Pause',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _formatWeekdays(weekdays),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StreamBuilder<int>(
                          stream: _calculateTotalCapacity(queueId),
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              );
                            }
                            final total = snap.data ?? 0;
                            if (total == 0) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _kGreen.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.groups_rounded,
                                      size: 20, color: _kGreen),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$total',
                                    style: TextStyle(
                                      fontSize: 13,
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
                        GestureDetector(
                          onTap: () => _showQueueActions(queueId, queueData),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.more_vert_rounded,
                              color: Colors.grey.shade500,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueueActions(String queueId, Map<String, dynamic> queueData) {
    final isActive = queueData['isActive'] ?? true;
    final name = queueData['name'] ?? 'File';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1C2E),
              ),
            ),
            const SizedBox(height: 20),
            _actionTile(
              icon: isActive
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              label: isActive
                  ? 'Suspendre les réservations'
                  : 'Réactiver la file',
              color: isActive ? Colors.orange.shade600 : _kGreen,
              onTap: () {
                Navigator.pop(context);
                _toggleQueueActive(queueId, queueData);
              },
            ),
            const SizedBox(height: 10),
            _actionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Supprimer la file',
              color: Colors.red.shade400,
              onTap: () {
                Navigator.pop(context);
                _deleteQueue(queueId);
              },
            ),
          ],
        ),
      ),
    );
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
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleQueueActive(
    String queueId,
    Map<String, dynamic> queueData,
  ) async {
    final isActive = queueData['isActive'] ?? true;
    try {
      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .update({'isActive': !isActive});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive
                ? '🚫 Réservations désactivées'
                : '✅ Réservations réactivées',
          ),
          backgroundColor: isActive ? Colors.orange.shade700 : _kGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _deleteQueue(String queueId) async {
    final reservationsSnap = await _firestore
        .collection('reservations')
        .where('queueId', isEqualTo: queueId)
        .where('status', isEqualTo: 'confirmed')
        .limit(1)
        .get();

    if (!mounted) return;

    if (reservationsSnap.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Cette file contient des réservations'),
          duration: Duration(milliseconds: 1500),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Supprimer cette file ?'),
        content: const Text(
          'Cette action est irréversible. La file et toutes ses plages horaires seront supprimées définitivement.',
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

    if (confirm != true) return;

    try {
      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('🗑️ File supprimée')));
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
    final nameCtrl = TextEditingController();
    List<int> selectedWeekdays = [1, 2, 3, 4, 5];
    int selectedMaxActive = kDefaultMaxActivePerUser;
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
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
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
                        const Text(
                          'Nouvelle file d\'attente',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
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
                            onChanged: (_) {
                              if (nameError != null) {
                                setD(() => nameError = null);
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Ex : Consultation, Caisse principale…',
                              errorText: nameError,
                              hintStyle:
                                  TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(
                                Icons.label_outline_rounded,
                                color: _kGreen,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
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
                              final selected =
                                  selectedWeekdays.contains(day);
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
                          const SizedBox(height: 20),
                          const Text(
                            'Réservations simultanées max par client',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF1A1C2E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nombre de créneaux actifs en même temps dans cet établissement.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: List.generate(5, (i) {
                              final val = i + 1;
                              final isSelected = selectedMaxActive == val;
                              return Expanded(
                                child: Padding(
                                  padding:
                                      EdgeInsets.only(right: i < 4 ? 8 : 0),
                                  child: GestureDetector(
                                    onTap: () =>
                                        setD(() => selectedMaxActive = val),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? _kGreen
                                            : Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected
                                              ? _kGreen
                                              : Colors.grey.shade200,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$val',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.grey.shade500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          if (selectedMaxActive > 1) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      color: Colors.orange.shade600,
                                      size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Les créneaux d\'un même client ne pourront pas se chevaucher.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                if (nameCtrl.text.trim().isEmpty) {
                                  setD(() =>
                                      nameError = 'Veuillez entrer un nom');
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
    if (result != true) return;
    try {
      final docRef = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .add({
            'name': nameCtrl.text.trim(),
            'weekdays': selectedWeekdays,
            'isActive': true,
            'maxActivePerUser': selectedMaxActive,
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('File créée ✅ Ajoutez maintenant une plage horaire'),
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QueueTimeSlotsPage(
            companyId: _companyId!,
            queueId: docRef.id,
            queueName: nameCtrl.text.trim(),
            autoOpenSlotDialog: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
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
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.w400,
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
