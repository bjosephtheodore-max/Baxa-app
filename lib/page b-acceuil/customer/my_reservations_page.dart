import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MyReservationsPage extends StatefulWidget {
  const MyReservationsPage({super.key});

  @override
  State<MyReservationsPage> createState() => _MyReservationsPageState();
}

class _MyReservationsPageState extends State<MyReservationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('d MMM yyyy', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  final Color _primaryGreen = const Color.fromARGB(255, 75, 139, 94);
  final Color _lightGreen = const Color.fromARGB(255, 178, 211, 194);

  String? _userId;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userId = user?.uid;
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes réservations')),
        body: const Center(child: Text('Veuillez vous connecter')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _primaryGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Mes réservations',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getReservationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _primaryGreen),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final reservations = snapshot.data!.docs;

          // Séparer les réservations actives et passées
          final now = DateTime.now();
          final activeReservations = <QueryDocumentSnapshot>[];
          final pastReservations = <QueryDocumentSnapshot>[];

          for (final doc in reservations) {
            final data = doc.data() as Map<String, dynamic>;
            final slotStart = (data['slotStart'] as Timestamp).toDate();
            final status = data['status'] ?? 'confirmed';

            if (status == 'cancelled') {
              pastReservations.add(doc);
            } else if (slotStart.isAfter(now)) {
              activeReservations.add(doc);
            } else {
              pastReservations.add(doc);
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Bannière d'information en haut
              if (activeReservations.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _lightGreen.withOpacity(0.3),
                        _lightGreen.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: _primaryGreen),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Vous avez ${activeReservations.length} réservation${activeReservations.length > 1 ? 's' : ''} active${activeReservations.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            color: _primaryGreen,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (activeReservations.isNotEmpty) ...[
                _buildSectionTitle('Réservations actives'),
                const SizedBox(height: 12),
                ...activeReservations.map(
                  (doc) => _buildReservationCard(doc, isActive: true),
                ),
                const SizedBox(height: 24),
              ],

              if (pastReservations.isNotEmpty) ...[
                _buildSectionTitle('Historique'),
                const SizedBox(height: 12),
                ...pastReservations.map(
                  (doc) => _buildReservationCard(doc, isActive: false),
                ),
              ],
            ],
          );
        },
      ),
      // FloatingActionButton pour créer une nouvelle réservation
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Retourner à la page précédente ou naviguer vers la liste des entreprises
          Navigator.pop(
            context,
            true,
          ); // Le 'true' indique qu'il faut recharger
        },
        backgroundColor: _primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nouvelle réservation',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getReservationsStream() {
    // Chercher dans toutes les companies où customerId = userId
    // Note: Cette approche nécessite une structure de données adaptée
    // Alternative: Créer une collection customers/{userId}/reservations

    // Pour ce MVP, on utilise une requête collection group
    return _firestore
        .collectionGroup('reservations')
        .where('customerId', isEqualTo: _userId)
        .orderBy('slotStart', descending: false)
        .snapshots();
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildReservationCard(
    QueryDocumentSnapshot doc, {
    required bool isActive,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    final companyId = data['companyId'] ?? '';
    final queueId = data['queueId'] ?? '';
    final slotId = data['slotId'] ?? '';
    final queueName = data['queueName'] ?? 'File';
    final slotStart = (data['slotStart'] as Timestamp).toDate();
    final slotEnd = (data['slotEnd'] as Timestamp).toDate();
    final status = data['status'] ?? 'confirmed';

    final isCancelled = status == 'cancelled';
    final isPast = slotStart.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCancelled
              ? Colors.red.shade200
              : isActive
              ? _primaryGreen.withOpacity(0.3)
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête avec statut
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isCancelled
                        ? Colors.red.shade50
                        : isActive
                        ? _lightGreen.withOpacity(0.3)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCancelled
                        ? Icons.cancel_outlined
                        : isActive
                        ? Icons.event_available
                        : Icons.event_busy,
                    color: isCancelled
                        ? Colors.red
                        : isActive
                        ? _primaryGreen
                        : Colors.grey.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
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
                        _dateFmt.format(slotStart),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCancelled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Annulée',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (isPast)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Passée',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Horaires
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 20,
                    color: Colors.grey.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_timeFmt.format(slotStart)} - ${_timeFmt.format(slotEnd)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),

            // Bouton d'annulation (seulement si actif et pas encore annulé)
            if (isActive && !isCancelled) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmCancellation(
                    doc.reference,
                    companyId,
                    queueId,
                    slotId,
                    queueName,
                    slotStart,
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Annuler cette réservation'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancellation(
    DocumentReference reservationRef,
    String companyId,
    String queueId,
    String slotId,
    String queueName,
    DateTime slotStart,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Annuler la réservation ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File : $queueName'),
            const SizedBox(height: 8),
            Text('Date : ${_dateFmt.format(slotStart)}'),
            const SizedBox(height: 8),
            Text('Heure : ${_timeFmt.format(slotStart)}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cette action est irréversible',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
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
            child: const Text('Non, garder'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Oui, annuler',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _cancelReservation(reservationRef, companyId, queueId, slotId);
    }
  }

  Future<void> _cancelReservation(
    DocumentReference reservationRef,
    String companyId,
    String queueId,
    String slotId,
  ) async {
    try {
      await _firestore.runTransaction((transaction) async {
        // 1. Récupérer la référence du slot
        final slotRef = _firestore
            .collection('companies')
            .doc(companyId)
            .collection('queues')
            .doc(queueId)
            .collection('slots')
            .doc(slotId);

        // 2. Décrémenter reserved ET incrémenter cancelled
        transaction.update(slotRef, {
          'reserved': FieldValue.increment(-1), // ← DÉCRÉMENTER
          'cancelled': FieldValue.increment(1), // ← INCRÉMENTER
        });

        // 3. Marquer la réservation comme annulée
        transaction.update(reservationRef, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✓ Réservation annulée'),
          backgroundColor: _primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
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
              'Aucune réservation',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos réservations apparaîtront ici',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Bouton pour commencer à réserver
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Faire une réservation',
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
