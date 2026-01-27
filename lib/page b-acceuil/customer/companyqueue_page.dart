import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:baxa/page%20b-acceuil/customer/my_reservations_page.dart';

class CompanyQueuePage extends StatefulWidget {
  final String entrepriseId;
  final String entrepriseNom;

  const CompanyQueuePage({
    super.key,
    required this.entrepriseId,
    required this.entrepriseNom,
  });

  @override
  State<CompanyQueuePage> createState() => _CompanyQueuePageState();
}

class _CompanyQueuePageState extends State<CompanyQueuePage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  // ignore: unused_field
  final DateFormat _dateFmt = DateFormat('EEEE d MMMM', 'fr_FR');
  // ignore: unused_field
  final DateFormat _timeFmt = DateFormat('HH:mm');

  final Color _primaryGreen = const Color.fromARGB(255, 75, 139, 94);
  final Color _lightGreen = const Color.fromARGB(255, 178, 211, 194);

  // ignore: unused_field
  bool _loading = false;
  // ignore: unused_field
  String? _selectedQueueId;
  int _activeReservationsCount = 0; // Compteur de réservations actives

  @override
  void initState() {
    super.initState();
    _loadActiveReservationsCount();
  }

  // Charger le nombre de réservations actives de l'utilisateur
  Future<void> _loadActiveReservationsCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _fs
          .collectionGroup('reservations')
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'confirmed')
          .get();

      // Compter seulement les réservations futures
      final now = DateTime.now();
      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final slotStart = (data['slotStart'] as Timestamp).toDate();
        if (slotStart.isAfter(now)) {
          count++;
        }
      }

      setState(() {
        _activeReservationsCount = count;
      });
    } catch (e) {
      debugPrint('Erreur chargement réservations: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _primaryGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Réserver',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              widget.entrepriseNom,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        actions: [
          // Bouton "Mes réservations" avec badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.event_note, color: Colors.white),
                tooltip: 'Mes réservations',
                onPressed: () async {
                  // Navigation vers la page des réservations
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MyReservationsPage(),
                    ),
                  );

                  // Recharger le compteur au retour
                  if (result == true || result == null) {
                    _loadActiveReservationsCount();
                  }
                },
              ),
              // Badge de notification
              if (_activeReservationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: _primaryGreen, width: 2),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _activeReservationsCount > 9
                          ? '9+'
                          : '$_activeReservationsCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _fs
            .collection('companies')
            .doc(widget.entrepriseId)
            .collection('queues')
            .orderBy('createdAt')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _primaryGreen),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final queues = snapshot.data!.docs;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _lightGreen.withOpacity(0.3),
                        _lightGreen.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _primaryGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.event_available,
                          color: _primaryGreen,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choisissez votre créneau',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sélectionnez une file d\'attente ci-dessous',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Titre section
                const Text(
                  'Files d\'attente disponibles',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 12),

                // Liste des files
                ...queues.map((queueDoc) {
                  final queueData = queueDoc.data() as Map<String, dynamic>;
                  final queueId = queueDoc.id;
                  final queueName = queueData['name'] ?? 'File';

                  return _buildQueueCard(
                    queueId: queueId,
                    queueName: queueName,
                    queueData: queueData,
                  );
                }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueueCard({
    required String queueId,
    required String queueName,
    required Map<String, dynamic> queueData,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showSlotsPage(queueId, queueName),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _lightGreen.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.people_outline,
                    color: _primaryGreen,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        queueName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Voir les créneaux disponibles',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSlotsPage(String queueId, String queueName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _SlotsPage(
          entrepriseId: widget.entrepriseId,
          queueId: queueId,
          queueName: queueName,
          primaryGreen: _primaryGreen,
          lightGreen: _lightGreen,
          onReservationSuccess: () {
            // Recharger le compteur après une réservation réussie
            _loadActiveReservationsCount();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _lightGreen.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_busy,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aucune file disponible',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cette entreprise n\'a pas encore créé de files d\'attente',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PAGE DES CRÉNEAUX (Slots)
// ============================================================================

class _SlotsPage extends StatefulWidget {
  final String entrepriseId;
  final String queueId;
  final String queueName;
  final Color primaryGreen;
  final Color lightGreen;
  final VoidCallback onReservationSuccess;

  const _SlotsPage({
    required this.entrepriseId,
    required this.queueId,
    required this.queueName,
    required this.primaryGreen,
    required this.lightGreen,
    required this.onReservationSuccess,
  });

  @override
  State<_SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<_SlotsPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('EEEE d MMMM', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  // ignore: unused_field
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: widget.primaryGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Créneaux disponibles',
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
      body: StreamBuilder<QuerySnapshot>(
        stream: _fs
            .collection('companies')
            .doc(widget.entrepriseId)
            .collection('queues')
            .doc(widget.queueId)
            .collection('slots')
            .orderBy('start')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: widget.primaryGreen),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final slots = snapshot.data!.docs;
          final now = DateTime.now().toUtc();

          // Filtrer les créneaux futurs
          final futureSlots = slots.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final start = (data['start'] as Timestamp).toDate().toUtc();
            return start.isAfter(now);
          }).toList();

          if (futureSlots.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: futureSlots.length,
            itemBuilder: (context, index) {
              return _buildSlotCard(futureSlots[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildSlotCard(QueryDocumentSnapshot slotDoc) {
    final data = slotDoc.data() as Map<String, dynamic>;
    final start = (data['start'] as Timestamp).toDate().toLocal();
    final end = (data['end'] as Timestamp).toDate().toLocal();
    final capacity = (data['capacity'] ?? 1) as int;
    final reserved = (data['reserved'] ?? 0) as int;
    final status = (data['status'] ?? 'open') as String;

    final remaining = capacity - reserved;
    final isFull = remaining <= 0;
    final isAvailable = status == 'open' && remaining > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAvailable
              ? widget.primaryGreen.withOpacity(0.3)
              : Colors.grey.shade300,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isAvailable
              ? () => _confirmReservation(slotDoc, start, end)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? widget.lightGreen.withOpacity(0.3)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.access_time,
                    color: isAvailable ? widget.primaryGreen : Colors.grey,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_timeFmt.format(start)} - ${_timeFmt.format(end)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dateFmt.format(start),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isFull
                                ? 'Complet'
                                : '$remaining place${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''}',
                            style: TextStyle(
                              color: isFull ? Colors.red : Colors.grey.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Badge ou bouton
                if (isFull)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: widget.primaryGreen.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Complet',
                      style: TextStyle(
                        color: widget.primaryGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (isAvailable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: widget.primaryGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Réserver',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Icon(Icons.lock_outline, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReservation(
    QueryDocumentSnapshot slotDoc,
    DateTime start,
    DateTime end,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirmer la réservation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File : ${widget.queueName}'),
            const SizedBox(height: 8),
            Text(
              'Créneau : ${_timeFmt.format(start)} - ${_timeFmt.format(end)}',
            ),
            const SizedBox(height: 8),
            Text('Date : ${_dateFmt.format(start)}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vous recevrez des notifications avec la possibilité d\'annuler',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
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
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Confirmer',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _reserveSlot(slotDoc, start, end);
    }
  }

  Future<void> _reserveSlot(
    QueryDocumentSnapshot slotDoc,
    DateTime start,
    DateTime end,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Connectez-vous pour réserver")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // ignore: unused_local_variable
      final slotData = slotDoc.data() as Map<String, dynamic>;

      final slotRef = _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .collection('queues')
          .doc(widget.queueId)
          .collection('slots')
          .doc(slotDoc.id);

      final reservationsCol = _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .collection('reservations');
      final reservationRef = reservationsCol.doc();

      final now = DateTime.now().toUtc();

      await _fs.runTransaction((tx) async {
        final freshSlot = await tx.get(slotRef);
        if (!freshSlot.exists) throw Exception('Créneau introuvable');

        final freshData = freshSlot.data()!;
        final slotStart = (freshData['start'] as Timestamp).toDate().toUtc();
        final capacity = (freshData['capacity'] ?? 1) as int;
        final reserved = (freshData['reserved'] ?? 0) as int;
        final status = (freshData['status'] ?? 'open') as String;

        if (status != 'open') throw Exception('Ce créneau n\'est plus ouvert');
        if (reserved >= capacity) throw Exception('Ce créneau est complet');

        final minutesUntilStart = slotStart.difference(now).inMinutes;
        if (minutesUntilStart < 10) {
          throw Exception('Délai minimal requis non respecté');
        }

        final reservationPayload = {
          'companyId': widget.entrepriseId,
          'queueId': widget.queueId,
          'queueName': widget.queueName,
          'slotId': slotDoc.id,
          'customerId': user.uid,
          'customerEmail': user.email,
          'slotStart': slotStart,
          'slotEnd': (freshData['end'] as Timestamp).toDate().toUtc(),
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'confirmed',
        };

        tx.set(reservationRef, reservationPayload);
        tx.update(slotRef, {'reserved': FieldValue.increment(1)});
      });

      // ✅ NOUVELLE LOGIQUE - Programmer les notifications avec tous les paramètres requis
      await NotificationService().cancelAll();
      await NotificationService().scheduleReservationNotifications(
        waitMinutes: 180, // 3 heures avant
        slotDurationMinutes: 15,
        // ⭐ NOUVEAUX PARAMÈTRES REQUIS
        reservationId: reservationRef.id,
        companyId: widget.entrepriseId,
        queueId: widget.queueId,
        slotId: slotDoc.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✓ Réservation réussie !'),
            backgroundColor: widget.primaryGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Appeler le callback pour mettre à jour le compteur
        widget.onReservationSuccess();

        // Retour automatique
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: widget.lightGreen.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_busy,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aucun créneau disponible',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vérifiez plus tard ou contactez l\'entreprise',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
