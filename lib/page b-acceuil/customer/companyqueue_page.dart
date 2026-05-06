import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:baxa/page%20b-acceuil/customer/my_reservations_page.dart';
import 'package:baxa/page%20b-acceuil/customer/slots_page.dart';
// ============================================================================
// PAGE PRINCIPALE : Liste des files d'attente
// ============================================================================

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

  final Color _primaryGreen = const Color.fromARGB(255, 75, 139, 94);
  final Color _lightGreen = const Color.fromARGB(255, 178, 211, 194);

  // ignore: unused_field
  bool _loading = false;
  String? _selectedQueueId;
  int _activeReservationsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadActiveReservationsCount();
  }

  Future<void> _loadActiveReservationsCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _fs
          .collectionGroup('reservations')
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'confirmed')
          .get();

      final now = DateTime.now();
      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final slotStart = (data['slotStart'] as Timestamp).toDate();
        if (slotStart.isAfter(now)) count++;
      }

      setState(() => _activeReservationsCount = count);
    } catch (e) {
      debugPrint('Erreur chargement réservations: $e');
    }
  }

  void _shareCompany() {
    final nom = widget.entrepriseNom;
    final id = widget.entrepriseId;
    final link = 'https://baxa.app/company/$id';

    Share.share(
      '📍 $nom\n'
      'Réserve ta place sans attendre !\n'
      '👉 $link',
      subject: 'Réserve chez $nom sur Baxa',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _buildAppBar(),
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroHeader(),
                const SizedBox(height: 28),
                _buildSectionTitle('Files d\'attente', queues.length),
                const SizedBox(height: 12),
                ...queues.map((queueDoc) {
                  final queueData = queueDoc.data() as Map<String, dynamic>;
                  return _buildQueueCard(
                    queueId: queueDoc.id,
                    queueName: queueData['name'] ?? 'File',
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Color(0xFF1A1C2E)),
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reserver',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            widget.entrepriseNom,
            style: const TextStyle(
              color: Color(0xFF1A1C2E),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: Colors.grey.shade100, height: 1),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.share_rounded, color: Colors.grey.shade600),
          tooltip: 'Partager',
          onPressed: _shareCompany,
        ),
        Stack(
          children: [
            IconButton(
              icon: Icon(
                Icons.event_note_rounded,
                color: Colors.grey.shade600,
              ),
              tooltip: 'Mes reservations',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyReservationsPage(),
                  ),
                );
                if (result == true || result == null) {
                  _loadActiveReservationsCount();
                }
              },
            ),
            if (_activeReservationsCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade500,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
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
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryGreen.withOpacity(0.12),
            _lightGreen.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryGreen.withOpacity(0.15), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _primaryGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.event_available_rounded,
              color: _primaryGreen,
              size: 30,
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
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _primaryGreen,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sélectionnez une file d\'attente ci-dessous',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _primaryGreen.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: _primaryGreen,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueCard({
    required String queueId,
    required String queueName,
    required Map<String, dynamic> queueData,
  }) {
    final isSelected = _selectedQueueId == queueId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? _primaryGreen.withOpacity(0.5)
              : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() => _selectedQueueId = queueId);
            _showSlotsPage(queueId, queueName);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _lightGreen.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: _primaryGreen,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        queueName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Voir les créneaux disponibles',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _primaryGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _primaryGreen,
                    size: 20,
                  ),
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
        builder: (context) => SlotsPage(
          entrepriseId: widget.entrepriseId,
          queueId: queueId,
          queueName: queueName,
          primaryGreen: _primaryGreen,
          lightGreen: _lightGreen,
          onReservationSuccess: _loadActiveReservationsCount,
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
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_rounded,
                size: 56,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aucune file disponible',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cette entreprise n\'a pas encore créé de files d\'attente',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
