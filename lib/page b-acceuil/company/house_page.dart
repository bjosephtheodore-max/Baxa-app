import 'package:baxa/page%20b-acceuil/company/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class HousePage extends StatefulWidget {
  const HousePage({super.key});

  @override
  State<HousePage> createState() => _HousePageState();
}

class _HousePageState extends State<HousePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFormat = DateFormat('EEEE d MMM yyyy', 'fr_FR');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  String? _companyId;
  String _companyName = "";
  DateTime _selectedDate = DateTime.now();

  List<Queue> _queues = [];
  bool _isLoading = true;
  bool _hasQueues = false;

  @override
  void initState() {
    super.initState();
    _loadCompanyData();
  }

  Future<void> _loadCompanyData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _companyId = user.uid;
      _isLoading = true;
    });

    try {
      // Charger les infos de l'entreprise
      final companyDoc = await _firestore
          .collection('Entreprises')
          .doc(_companyId)
          .get();

      if (companyDoc.exists) {
        _companyName = companyDoc.data()?['nom'] ?? 'Baxa';
      }

      // Charger les files d'attente
      final queuesSnapshot = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .get();

      if (queuesSnapshot.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _hasQueues = false;
            _isLoading = false;
          });
        }
        return;
      }

      _hasQueues = true;
      await _loadSlotsForDate(_selectedDate);
    } catch (e) {
      debugPrint('Erreur chargement données: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSlotsForDate(DateTime date) async {
    if (_companyId == null || !mounted) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Charger toutes les queues
      final queuesSnap = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .get();

      List<Queue> queues = [];

      for (final queueDoc in queuesSnap.docs) {
        final queueData = queueDoc.data();
        final queueId = queueDoc.id;
        final queueName = queueData['name'] ?? 'File sans nom';

        // Charger les créneaux de cette queue pour la date sélectionnée
        final slotsSnap = await _firestore
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .doc(queueId)
            .collection('slots')
            .where('start', isGreaterThanOrEqualTo: startOfDay)
            .where('start', isLessThan: endOfDay)
            .orderBy('start')
            .get();

        List<TimeSlot> slots = [];

        for (final slotDoc in slotsSnap.docs) {
          final slotData = slotDoc.data();
          final slot = TimeSlot(
            id: slotDoc.id,
            queueId: queueId,
            start: (slotData['start'] as Timestamp).toDate(),
            end: (slotData['end'] as Timestamp).toDate(),
            capacity: slotData['capacity'] ?? 1,
            reserved: slotData['reserved'] ?? 0,
            status: slotData['status'] ?? 'open',
            customerNames: await _getCustomerNames(slotDoc.id),
          );
          slots.add(slot);
        }

        queues.add(Queue(id: queueId, name: queueName, slots: slots));
      }

      if (mounted) {
        setState(() {
          _queues = queues;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement créneaux: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<String>> _getCustomerNames(String slotId) async {
    try {
      final reservationsSnap = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('reservations')
          .where('slotId', isEqualTo: slotId)
          .where('status', isEqualTo: 'confirmed')
          .get();

      List<String> names = [];
      for (final resDoc in reservationsSnap.docs) {
        final name = resDoc.data()['customerName'] ?? 'Client';
        names.add(name);
      }
      return names;
    } catch (e) {
      return [];
    }
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr'),
    );

    if (picked != null && picked != _selectedDate) {
      if (mounted) {
        setState(() => _selectedDate = picked);
      }
      _loadSlotsForDate(picked);
    }
  }

  String _calculateFillRate() {
    int totalCapacity = 0;
    int totalReserved = 0;

    for (var queue in _queues) {
      for (var slot in queue.slots) {
        totalCapacity += slot.capacity;
        totalReserved += slot.reserved;
      }
    }

    if (totalCapacity == 0) return '0%';
    final percentage = ((totalReserved / totalCapacity) * 100).round();
    return '$percentage% ($totalReserved/$totalCapacity)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 75, 139, 94),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '🏥 Baxa',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _companyName,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () {
              // Navigation vers aide/support
            },
            icon: const Icon(Icons.help_outline, color: Colors.black54),
          ),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasQueues
          ? _buildEmptyState()
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildAgendaView()),
              ],
            ),

      floatingActionButton: _hasQueues
          ? FloatingActionButton.extended(
              onPressed: () {
                // Navigation vers création de RDV
              },
              backgroundColor: const Color.fromARGB(255, 75, 139, 94),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Nouveau RDV',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 24),
          const Text(
            'Aucune file d\'attente configurée',
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
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              // Navigation vers settings_page.dart
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 75, 139, 94),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            label: const Text(
              'Créer une file d\'attente',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sélecteur de date
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _dateFormat.format(_selectedDate),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),

          // Taux de remplissage
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 178, 211, 194).withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.pie_chart_outline,
                  size: 20,
                  color: Color.fromARGB(255, 75, 139, 94),
                ),
                const SizedBox(width: 8),
                Text(
                  _calculateFillRate(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color.fromARGB(255, 75, 139, 94),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaView() {
    if (_queues.isEmpty) {
      return Center(
        child: Text(
          'Aucun créneau pour cette date',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      scrollDirection: _queues.length > 1 ? Axis.horizontal : Axis.vertical,
      itemCount: _queues.length,
      itemBuilder: (context, index) {
        final queue = _queues[index];
        return _buildQueueColumn(queue);
      },
    );
  }

  Widget _buildQueueColumn(Queue queue) {
    return Container(
      width: _queues.length > 1 ? 350 : double.infinity,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nom de la file
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              queue.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),

          // Liste des créneaux
          Expanded(
            child: queue.slots.isEmpty
                ? Center(
                    child: Text(
                      'Aucun créneau',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    itemCount: queue.slots.length,
                    itemBuilder: (context, index) {
                      return _buildSlotCard(queue.slots[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(TimeSlot slot) {
    final isFull = slot.reserved >= slot.capacity;
    final isAvailable = slot.reserved == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isFull
            ? const Color.fromARGB(255, 178, 211, 194).withOpacity(0.4)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFull
              ? const Color.fromARGB(255, 75, 139, 94)
              : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isFull
                ? const Color.fromARGB(255, 75, 139, 94)
                : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isAvailable ? Icons.event_available : Icons.people,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          '${_timeFormat.format(slot.start)} - ${_timeFormat.format(slot.end)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          _getSlotDisplayText(slot),
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isFull ? Colors.green : Colors.orange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${slot.reserved}/${slot.capacity}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        onTap: () => _showSlotDetails(slot),
      ),
    );
  }

  String _getSlotDisplayText(TimeSlot slot) {
    if (slot.reserved == 0) return 'DISPONIBLE';
    if (slot.capacity == 1 && slot.customerNames.isNotEmpty) {
      return slot.customerNames.first;
    }
    if (slot.reserved > 1) {
      return '${slot.reserved} personnes';
    }
    return 'Réservé';
  }

  void _showSlotDetails(TimeSlot slot) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${_timeFormat.format(slot.start)} - ${_timeFormat.format(slot.end)}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statut: ${slot.status}'),
            const SizedBox(height: 8),
            Text('Places: ${slot.reserved}/${slot.capacity}'),
            const SizedBox(height: 16),
            if (slot.customerNames.isNotEmpty) ...[
              const Text(
                'Clients:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...slot.customerNames.map((name) => Text('• $name')),
            ] else
              const Text('Aucune réservation'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

// Modèles de données
class Queue {
  final String id;
  final String name;
  final List<TimeSlot> slots;

  Queue({required this.id, required this.name, required this.slots});
}

class TimeSlot {
  final String id;
  final String queueId;
  final DateTime start;
  final DateTime end;
  final int capacity;
  final int reserved;
  final String status;
  final List<String> customerNames;

  TimeSlot({
    required this.id,
    required this.queueId,
    required this.start,
    required this.end,
    required this.capacity,
    required this.reserved,
    required this.status,
    this.customerNames = const [],
  });
}
