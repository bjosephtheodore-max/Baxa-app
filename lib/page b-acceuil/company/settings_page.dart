import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _companyId = user?.uid;
    setState(() => _isLoading = false);
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
        title: const Text(
          'Gestion des files d\'attente',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
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
                    // En-tête avec compteur
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

                    // Liste des files
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
        onPressed: () => _showCreateQueueDialog(),
        backgroundColor: const Color.fromARGB(255, 75, 139, 94),
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

  Widget _buildQueueCard(String queueId, Map<String, dynamic> queueData) {
    final name = queueData['name'] ?? 'File sans nom';
    final weekdays =
        (queueData['weekdays'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [1, 2, 3, 4, 5, 6, 7];

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
              builder: (context) => QueueTimeSlotsPage(
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 178, 211, 194),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.people_outline,
                  color: Color.fromARGB(255, 75, 139, 94),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
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
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatWeekdays(List<int> weekdays) {
    final labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return weekdays.map((d) => labels[d - 1]).join(', ');
  }

  Future<void> _showCreateQueueDialog() async {
    final nameController = TextEditingController();
    List<bool> selectedDays = List.filled(7, true);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Créer une file d\'attente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la file',
                    hintText: 'Ex: Consultation générale',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Jours de fonctionnement',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (i) {
                    final labels = [
                      'Lun',
                      'Mar',
                      'Mer',
                      'Jeu',
                      'Ven',
                      'Sam',
                      'Dim',
                    ];
                    return FilterChip(
                      selected: selectedDays[i],
                      label: Text(labels[i]),
                      onSelected: (v) => setState(() => selectedDays[i] = v),
                      selectedColor: const Color.fromARGB(255, 178, 211, 194),
                    );
                  }),
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
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Veuillez entrer un nom')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 75, 139, 94),
              ),
              child: const Text('Créer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    // Créer la file d'attente
    final weekdays = <int>[];
    for (int i = 0; i < 7; i++) {
      if (selectedDays[i]) weekdays.add(i + 1);
    }

    try {
      final queueRef = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .add({
            'name': nameController.text.trim(),
            'weekdays': weekdays,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      // Naviguer vers la page de gestion des plages horaires
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QueueTimeSlotsPage(
            companyId: _companyId!,
            queueId: queueRef.id,
            queueName: nameController.text.trim(),
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

// ==================== PAGE : GESTION DES PLAGES HORAIRES ====================
class QueueTimeSlotsPage extends StatefulWidget {
  final String companyId;
  final String queueId;
  final String queueName;

  const QueueTimeSlotsPage({
    super.key,
    required this.companyId,
    required this.queueId,
    required this.queueName,
  });

  @override
  State<QueueTimeSlotsPage> createState() => _QueueTimeSlotsPageState();
}

class _QueueTimeSlotsPageState extends State<QueueTimeSlotsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plages horaires',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.queueName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('companies')
            .doc(widget.companyId)
            .collection('queues')
            .doc(widget.queueId)
            .collection('timeSlots')
            .orderBy('startTime')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }

          final slots = snapshot.data?.docs ?? [];

          return slots.isEmpty
              ? _buildEmptySlots()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: slots.length,
                  itemBuilder: (context, index) {
                    final slot = slots[index];
                    final slotData = slot.data() as Map<String, dynamic>;
                    return _buildSlotCard(slot.id, slotData);
                  },
                );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTimeSlotDialog(),
        backgroundColor: const Color.fromARGB(255, 75, 139, 94),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Ajouter une plage',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmptySlots() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_outlined, size: 80, color: Colors.grey.shade400),
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
            'Ajoutez une plage pour générer des créneaux',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(String slotId, Map<String, dynamic> slotData) {
    final startTime = slotData['startTime'] ?? '00:00';
    final endTime = slotData['endTime'] ?? '00:00';
    final duration = slotData['serviceDurationMinutes'] ?? 0;
    final capacity = slotData['capacityPerSlot'] ?? 1;

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
                    color: const Color.fromARGB(255, 178, 211, 194),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.access_time,
                    color: Color.fromARGB(255, 75, 139, 94),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$startTime – $endTime',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      _showTimeSlotDialog(slotId: slotId, slotData: slotData),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  onPressed: () => _deleteSlot(slotId),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip(
                  icon: Icons.timer_outlined,
                  label: '${duration} min',
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  icon: Icons.person_outline,
                  label: '$capacity pers.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
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
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTimeSlotDialog({
    String? slotId,
    Map<String, dynamic>? slotData,
  }) async {
    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 12, minute: 0);
    final durationCtrl = TextEditingController(text: '10');
    final capacityCtrl = TextEditingController(text: '1');
    final maxReservationsCtrl = TextEditingController();
    final deadlineCtrl = TextEditingController(text: '0');
    final advanceCtrl = TextEditingController(text: '7');

    // Charger les données existantes si modification
    if (slotData != null) {
      final start = slotData['startTime']?.split(':') ?? ['8', '0'];
      final end = slotData['endTime']?.split(':') ?? ['12', '0'];
      startTime = TimeOfDay(
        hour: int.tryParse(start[0]) ?? 8,
        minute: int.tryParse(start[1]) ?? 0,
      );
      endTime = TimeOfDay(
        hour: int.tryParse(end[0]) ?? 12,
        minute: int.tryParse(end[1]) ?? 0,
      );
      durationCtrl.text =
          slotData['serviceDurationMinutes']?.toString() ?? '10';
      capacityCtrl.text = slotData['capacityPerSlot']?.toString() ?? '1';
      maxReservationsCtrl.text =
          slotData['maxReservationsPerPerson']?.toString() ?? '';
      deadlineCtrl.text =
          slotData['reservationDeadlineMinutes']?.toString() ?? '0';
      advanceCtrl.text = slotData['maxAdvanceDays']?.toString() ?? '7';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            slotId == null ? 'Ajouter une plage' : 'Modifier la plage',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sélection des heures
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: startTime,
                          );
                          if (t != null) setState(() => startTime = t);
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
                          if (t != null) setState(() => endTime = t);
                        },
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text(_formatTime(endTime)),
                      ),
                    ),
                  ],
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 75, 139, 94),
              ),
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

    // ✅ MODIFICATION : Ajout de reserved, cancelled, et status
    final timeSlotData = {
      'startTime': _formatTime(startTime),
      'endTime': _formatTime(endTime),
      'serviceDurationMinutes': int.tryParse(durationCtrl.text) ?? 10,
      'capacityPerSlot': int.tryParse(capacityCtrl.text) ?? 1,
      'maxReservationsPerPerson': maxReservationsCtrl.text.isNotEmpty
          ? int.tryParse(maxReservationsCtrl.text)
          : null,
      'reservationDeadlineMinutes': int.tryParse(deadlineCtrl.text) ?? 0,
      'maxAdvanceDays': int.tryParse(advanceCtrl.text) ?? 7,
      'reserved': 0, // ← AJOUTÉ
      'cancelled': 0, // ← AJOUTÉ
      'status': 'open', // ← AJOUTÉ
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
        // Générer les créneaux automatiquement
        await _generateSlots(timeSlotData);
      } else {
        await slotsRef.doc(slotId).update(timeSlotData);
        // Régénérer les créneaux
        await _generateSlots(timeSlotData);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plage horaire enregistrée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _generateSlots(Map<String, dynamic> timeSlotData) async {
    // Logique pour générer les créneaux à partir de la plage horaire
    // Cette fonction créera les créneaux individuels dans la collection 'slots'
    // basés sur startTime, endTime et serviceDurationMinutes

    // À implémenter selon votre logique métier
    debugPrint('Génération des créneaux pour la plage horaire');
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
          'Tous les créneaux associés seront également supprimés.',
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
