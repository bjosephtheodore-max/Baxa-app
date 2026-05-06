import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// ============================================================
// STAFF HOME PAGE — Vue simplifiee pour le vigil/receptionniste
// Objectif : ajouter un client en moins de 10 secondes
// ============================================================
class StaffHomePage extends StatefulWidget {
  final String companyId;
  final String companyName;

  const StaffHomePage({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends State<StaffHomePage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _dark = Color(0xFF1A1C2E);

  final _dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ==============================================================
  // AJOUTER UN CLIENT — Bottom sheet rapide
  // ==============================================================
  void _showAddClientSheet(
    BuildContext context,
    String queueId,
    String queueName,
  ) {
    final nameController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Poignee
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              queueName,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ajouter un client a la file',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nom du client (optionnel)',
                hintText: 'Ex : Mamadou Diallo',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Ajouter',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _addWalkInClient(
                    queueId: queueId,
                    queueName: queueName,
                    clientName:
                        nameController.text.trim().isEmpty
                            ? 'Client'
                            : nameController.text.trim(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addWalkInClient({
    required String queueId,
    required String queueName,
    required String clientName,
  }) async {
    final staffUid = FirebaseAuth.instance.currentUser?.uid;
    if (staffUid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(widget.companyId)
          .collection('queues')
          .doc(queueId)
          .collection('walkins')
          .add({
            'nom': clientName,
            'queueName': queueName,
            'companyId': widget.companyId,
            'addedByStaffId': staffUid,
            'status': 'en_attente',
            'date': _dateKey,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$clientName ajouté a la file $queueName'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erreur. Reessayez.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ==============================================================
  // BUILD
  // ==============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.companyName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            Text(
              DateFormat('EEEE d MMM', 'fr_FR').format(DateTime.now()),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade100, height: 1),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('companies')
            .doc(widget.companyId)
            .collection('queues')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          }

          final queues = snapshot.data?.docs ?? [];

          if (queues.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: queues.length,
            itemBuilder: (ctx, i) {
              final data = queues[i].data() as Map<String, dynamic>;
              final queueId = queues[i].id;
              final nom = data['nom'] as String? ?? 'File sans nom';
              return _buildQueueCard(queueId, nom);
            },
          );
        },
      ),
    );
  }

  Widget _buildQueueCard(String queueId, String queueName) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        child: Row(
          children: [
            // Icone file
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _greenLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.people_rounded, color: _green, size: 24),
            ),
            const SizedBox(width: 14),
            // Nom + compteur walk-ins aujourd'hui
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    queueName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _dark,
                    ),
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('companies')
                        .doc(widget.companyId)
                        .collection('queues')
                        .doc(queueId)
                        .collection('walkins')
                        .where('date', isEqualTo: _dateKey)
                        .where('status', isEqualTo: 'en_attente')
                        .snapshots(),
                    builder: (ctx, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return Text(
                        count == 0
                            ? 'Aucun client en attente'
                            : '$count client${count > 1 ? 's' : ''} en attente',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              count == 0
                                  ? Colors.grey.shade400
                                  : _green,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Bouton ajouter
            GestureDetector(
              onTap: () => _showAddClientSheet(context, queueId, queueName),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text(
                      'Ajouter',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.queue_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune file d\'attente',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'L\'administrateur n\'a pas encore cree de file.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
