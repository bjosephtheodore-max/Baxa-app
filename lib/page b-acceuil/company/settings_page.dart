import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baxa/services/booking_constants.dart';

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
    // ── Auto-ouvre le dialog de création si demandé depuis house_page
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'Gestion des files d\'attente',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
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
                return Column(
                  children: [
                    // En-tête compteur
                    Container(
                      width: double.infinity,
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
                      child: Text(
                        '${queues.length} file(s) d\'attente',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: queues.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: queues.length,
                              itemBuilder: (context, index) {
                                final queue = queues[index];
                                final queueData =
                                    queue.data() as Map<String, dynamic>;
                                return _buildQueueCard(queue.id, queueData);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateQueueDialog,
        backgroundColor: _kGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Créer une file',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

  // ==============================================================
  // CARTE D'UNE FILE — avec menu ⋮ (toggle + supprimer)
  // ==============================================================
  Widget _buildQueueCard(String queueId, Map<String, dynamic> queueData) {
    final name = queueData['name'] ?? 'File sans nom';
    final weekdays =
        (queueData['weekdays'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [1, 2, 3, 4, 5, 6, 7];
    final isActive = queueData['isActive'] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icône file
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive ? _kLightGreen : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.people_outline,
                  color: isActive ? _kGreen : Colors.grey.shade500,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Nom + jours + badge inactif
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
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
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Désactivée',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatWeekdays(weekdays),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // Badge capacité
              StreamBuilder<int>(
                stream: _calculateTotalCapacity(queueId),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.grey.shade400,
                        ),
                      ),
                    );
                  }
                  final total = snap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: total > 0
                          ? _kGreen.withOpacity(0.1)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: total > 0 ? _kGreen : Colors.grey.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.groups,
                          size: 16,
                          color: total > 0 ? _kGreen : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          total.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: total > 0 ? _kGreen : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),

              // ✅ MODIFICATION 5 — Menu ⋮ (remplace la flèche →)
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
                onSelected: (value) {
                  if (value == 'toggle') {
                    _toggleQueueActive(queueId, queueData);
                  } else if (value == 'delete') {
                    _deleteQueue(queueId);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          isActive ? Icons.block : Icons.check_circle,
                          size: 20,
                          color: isActive ? Colors.orange.shade700 : _kGreen,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isActive
                              ? 'Cesser réservations'
                              : 'Activer réservations',
                          style: TextStyle(
                            color: isActive ? Colors.orange.shade700 : _kGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: const [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Supprimer', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==============================================================
  // TOGGLE ACTIF / INACTIF
  // ==============================================================
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

  // ==============================================================
  // SUPPRIMER UNE FILE — vérifie les réservations avant
  // ==============================================================
  Future<void> _deleteQueue(String queueId) async {
    // Vérifier s'il existe des réservations confirmées
    final reservationsSnap = await _firestore
        .collection('reservations')
        .where('queueId', isEqualTo: queueId)
        .where('status', isEqualTo: 'confirmed')
        .limit(1)
        .get();

    if (!mounted) return;

    if (reservationsSnap.docs.isNotEmpty) {
      // Toast rouge 1.5s — impossible de supprimer
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Cette file contient des réservations'),
          duration: Duration(milliseconds: 1500),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Confirmation avant suppression
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

  // ==============================================================
  // CAPACITÉ TOTALE (pour le badge sur la carte)
  // Utilise timeSlots (config) plutôt que les slots générés
  // ==============================================================
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

  // ==============================================================
  // DIALOG CRÉER UNE FILE
  // ==============================================================
  Future<void> _showCreateQueueDialog() async {
    final nameCtrl = TextEditingController();
    List<int> selectedWeekdays = [1, 2, 3, 4, 5];
    int selectedMaxActive = kDefaultMaxActivePerUser; // défaut = 1

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Créer une file d\'attente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la file',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Jours de la semaine',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (index) {
                    final day = index + 1;
                    const labels = [
                      'Lun',
                      'Mar',
                      'Mer',
                      'Jeu',
                      'Ven',
                      'Sam',
                      'Dim',
                    ];
                    return FilterChip(
                      label: Text(labels[index]),
                      selected: selectedWeekdays.contains(day),
                      selectedColor: _kLightGreen,
                      checkmarkColor: _kGreen,
                      onSelected: (selected) {
                        setD(() {
                          if (selected) {
                            selectedWeekdays.add(day);
                          } else {
                            selectedWeekdays.remove(day);
                          }
                          selectedWeekdays.sort();
                        });
                      },
                    );
                  }),
                ),

                const SizedBox(height: 20),

                // ── Réservations actives max par client ──────────
                const Text(
                  'Réservations actives max par client',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nombre de créneaux actifs simultanés autorisés par personne dans cette file.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(5, (i) {
                      final val = i + 1;
                      final isSelected = selectedMaxActive == val;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setD(() => selectedMaxActive = val),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _kGreen
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? _kGreen
                                    : Colors.grey.shade300,
                                width: 1.5,
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
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                if (selectedMaxActive > 1) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.orange.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Les créneaux de ce client ne devront pas se chevaucher.',
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || selectedWeekdays.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Remplissez tous les champs')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
              child: const Text('Créer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
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
          content: Text('File créée ✅ Ajoutez maintenant une plage horaire'),
        ),
      );
      // ── Enchaînement automatique → page plages avec dialog auto-ouvert
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QueueTimeSlotsPage(
            companyId: _companyId!,
            queueId: docRef.id,
            queueName: nameCtrl.text.trim(),
            autoOpenSlotDialog: true, // ← ouvre le dialog automatiquement
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

class _QueueTimeSlotsPageState extends State<QueueTimeSlotsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Jours par défaut de la file parente (chargés une fois)
  List<int> _queueWeekdays = [1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    _loadQueueWeekdays();
    // ── Auto-ouvre le dialog de création de plage si demandé
    if (widget.autoOpenSlotDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showTimeSlotDialog();
      });
    }
  }

  Future<void> _loadQueueWeekdays() async {
    try {
      final doc = await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('queues')
          .doc(widget.queueId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final days = (data['weekdays'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList();
        if (days != null && mounted) {
          setState(() => _queueWeekdays = days);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kGreen,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plages horaires',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              widget.queueName,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ✅ MODIFICATION 3 — Bannière capacité groupée par jour
          StreamBuilder<List<_DayCapacity>>(
            stream: _calculateCapacityByDay(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }
              final days = snapshot.data ?? [];
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _kLightGreen.withOpacity(0.3),
                      _kLightGreen.withOpacity(0.1),
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kGreen.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.groups, color: _kGreen, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Capacité d\'accueil journalière',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (days.isEmpty)
                            Text(
                              'Aucune plage configurée',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                              ),
                            )
                          else
                            ...days.map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  d.capacity > 0
                                      ? '• ${d.label} : ${d.capacity} personnes'
                                      : '• ${d.label} : Fermé',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: d.capacity > 0
                                        ? _kGreen
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (days.isEmpty || days.every((d) => d.capacity == 0))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Créer des plages',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // Liste des plages horaires
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('companies')
                  .doc(widget.companyId)
                  .collection('queues')
                  .doc(widget.queueId)
                  .collection('timeSlots')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final timeSlots = snapshot.data?.docs ?? [];
                if (timeSlots.isEmpty) return _buildEmptyState();
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: timeSlots.length,
                  itemBuilder: (context, index) {
                    final slot = timeSlots[index];
                    final slotData = slot.data() as Map<String, dynamic>;
                    return _buildTimeSlotCard(slot.id, slotData);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showTimeSlotDialog,
        backgroundColor: _kGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Ajouter une plage',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  // ==============================================================
  // MODIFICATION 3 — CAPACITÉ GROUPÉE PAR JOUR
  // Calcul fait une seule fois à partir des timeSlots (config)
  // ==============================================================
  Stream<List<_DayCapacity>> _calculateCapacityByDay() {
    return _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('timeSlots')
        .snapshots()
        .map((snapshot) {
          // Capacité totale par numéro de jour (1=Lun … 7=Dim)
          final Map<int, int> capacityPerDay = {
            1: 0,
            2: 0,
            3: 0,
            4: 0,
            5: 0,
            6: 0,
            7: 0,
          };

          for (final doc in snapshot.docs) {
            final d = doc.data();
            final workingDays =
                (d['workingDays'] as List<dynamic>?)
                    ?.map((e) => e as int)
                    .toList() ??
                _queueWeekdays; // hérite des jours de la file
            final start = d['startTime'] as String? ?? '00:00';
            final end = d['endTime'] as String? ?? '00:00';
            final duration =
                (d['serviceDurationMinutes'] as num?)?.toInt() ?? 0;
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

  /// Groupe les jours consécutifs ayant la même capacité
  /// Ex: Lun=332, Mar=332, Mer=332, Jeu=220 → ["Lun–Mer: 332", "Jeu: 220"]
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

  // ==============================================================
  // MODIFICATION 2 — CARTE PLAGE HORAIRE simplifiée
  // Affiche uniquement la capacité totale (Z) pas X × Y = Z
  // ==============================================================
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

    // ✅ MODIFICATION 2 — uniquement la capacité totale
    final slotsCount = _countSlots(startTime, endTime, duration);
    final totalCapacity = slotsCount * capacity;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kLightGreen.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.access_time,
                    color: _kGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$startTime - $endTime',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // ✅ MODIFICATION 2 — juste "X pers." pas "A × B = X pers."
                      Text(
                        '$totalCapacity pers.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showTimeSlotDialog(slotId: slotId, slotData: slotData);
                    } else if (value == 'delete') {
                      _deleteSlot(slotId);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 12),
                          Text('Modifier'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 12),
                          Text(
                            'Supprimer',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildInfoChip(Icons.timer, '$duration min/créneau'),
                _buildInfoChip(Icons.people, '$capacity pers./créneau'),
                // ✅ Afficher les jours de cette plage
                _buildInfoChip(
                  Icons.calendar_today,
                  _formatWeekdays(workingDays),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatWeekdays(List<int> weekdays) {
    const labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    if (weekdays.length == 7) return 'Tous les jours';
    return weekdays.map((i) => labels[i - 1]).join(', ');
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

  // ==============================================================
  // MODIFICATION 1 + 4 — DIALOG PLAGE HORAIRE
  // • _generateSlots() supprimé → Cloud Function prend le relais
  // • Ajout du sélecteur de jours ouvrés par plage
  // ==============================================================
  Future<void> _showTimeSlotDialog({
    String? slotId,
    Map<String, dynamic>? slotData,
  }) async {
    TimeOfDay startTime = slotData != null
        ? _parseTimeOfDay(slotData['startTime'] ?? '09:00')
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = slotData != null
        ? _parseTimeOfDay(slotData['endTime'] ?? '17:00')
        : const TimeOfDay(hour: 17, minute: 0);

    final durationCtrl = TextEditingController(
      text: slotData?['serviceDurationMinutes']?.toString() ?? '15',
    );
    final capacityCtrl = TextEditingController(
      text: slotData?['capacityPerSlot']?.toString() ?? '1',
    );
    final maxReservationsCtrl = TextEditingController(
      text:
          slotData?['maxReservationsPerPerson']?.toString() ??
          '$kDefaultMaxReservationsPerPerson',
    );
    final deadlineCtrl = TextEditingController(
      text: slotData?['reservationDeadlineMinutes']?.toString() ?? '10',
    );
    final advanceCtrl = TextEditingController(
      text: slotData?['maxAdvanceDays']?.toString() ?? '7',
    );

    // ✅ MODIFICATION 4 — jours ouvrés par plage, hérite de la file
    List<int> selectedWorkingDays = slotData?['workingDays'] != null
        ? List<int>.from(slotData!['workingDays'])
        : List<int>.from(_queueWeekdays);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            slotId == null ? 'Créer une plage horaire' : 'Modifier la plage',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sélection heures
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: startTime,
                          );
                          if (t != null) setD(() => startTime = t);
                        },
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text(_formatTime(startTime)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('–'),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: endTime,
                          );
                          if (t != null) setD(() => endTime = t);
                        },
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text(_formatTime(endTime)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ✅ MODIFICATION 4 — sélecteur jours ouvrés pour cette plage
                const Text(
                  'Jours d\'ouverture de cette plage',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Par défaut : hérite des jours de la file',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (index) {
                    final day = index + 1;
                    const labels = [
                      'Lun',
                      'Mar',
                      'Mer',
                      'Jeu',
                      'Ven',
                      'Sam',
                      'Dim',
                    ];
                    return FilterChip(
                      label: Text(labels[index]),
                      selected: selectedWorkingDays.contains(day),
                      selectedColor: _kLightGreen,
                      checkmarkColor: _kGreen,
                      onSelected: (selected) {
                        setD(() {
                          if (selected) {
                            selectedWorkingDays.add(day);
                          } else {
                            selectedWorkingDays.remove(day);
                          }
                          selectedWorkingDays.sort();
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Durée par créneau (minutes)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: capacityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Capacité par créneau',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.people),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxReservationsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max réservations/personne (optionnel)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_pin),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deadlineCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Délai minimum (minutes)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.schedule),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: advanceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Anticipation max (jours)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
              child: Text(
                slotId == null ? 'Créer' : 'Modifier',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    // ✅ MODIFICATION 1 — plus de _generateSlots()
    // La Cloud Function génère automatiquement chaque nuit à 2h30
    final timeSlotData = {
      'startTime': _formatTime(startTime),
      'endTime': _formatTime(endTime),
      'serviceDurationMinutes': int.tryParse(durationCtrl.text) ?? 10,
      'capacityPerSlot': int.tryParse(capacityCtrl.text) ?? 1,
      'workingDays': selectedWorkingDays, // ✅ MODIFICATION 4
      'maxReservationsPerPerson':
          int.tryParse(maxReservationsCtrl.text) ??
          kDefaultMaxReservationsPerPerson,
      'reservationDeadlineMinutes': int.tryParse(deadlineCtrl.text) ?? 0,
      'maxAdvanceDays': int.tryParse(advanceCtrl.text) ?? 7,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final slotsRef = _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('queues')
          .doc(widget.queueId)
          .collection('timeSlots');

      if (slotId == null) {
        await slotsRef.add(timeSlotData);
      } else {
        await slotsRef.doc(slotId).update(timeSlotData);
      }

      // ✅ MODIFICATION 1 — Créneaux générés automatiquement par
      // la Cloud Function (quotidienne à 2h30)

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plage horaire enregistrée ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  TimeOfDay _parseTimeOfDay(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteSlot(String slotId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette plage ?'),
        content: const Text(
          'Les créneaux futurs associés seront supprimés automatiquement par la Cloud Function.',
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
          .doc(widget.companyId)
          .collection('queues')
          .doc(widget.queueId)
          .collection('timeSlots')
          .doc(slotId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Plage horaire supprimée')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }
}

// ============================================================
// MODÈLE INTERNE — un groupe de jours avec leur capacité
// ============================================================
class _DayCapacity {
  final String label; // ex: "Lun–Mer" ou "Jeu"
  final int capacity; // ex: 332 ou 0

  const _DayCapacity({required this.label, required this.capacity});
}
