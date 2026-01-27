import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/notification_models.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('d MMM yyyy', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  final Color _primaryGreen = const Color.fromARGB(255, 75, 139, 94);
  final Color _lightGreen = const Color.fromARGB(255, 178, 211, 194);

  String? _companyId;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _companyId = user?.uid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _primaryGreen,
        title: const Text(
          'Historique des notifications',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
      ),
      body: _companyId == null
          ? const Center(child: Text('Utilisateur non connecté'))
          : StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('companies')
                  .doc(_companyId)
                  .collection('notificationsHistory')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
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

                final notifications = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final doc = notifications[index];
                    final history = NotificationHistory.fromFirestore(
                      doc.id,
                      doc.data() as Map<String, dynamic>,
                    );

                    return _buildNotificationCard(history);
                  },
                );
              },
            ),
    );
  }

  Widget _buildNotificationCard(NotificationHistory history) {
    final duration = history.slotEnd.difference(history.slotStart);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

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
          onTap: () => _showDetails(history),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête avec nom et date
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _lightGreen.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.check_circle_outline,
                        color: _primaryGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            history.queueName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _dateFmt.format(history.createdAt),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _lightGreen.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${hours}h${minutes}min',
                        style: TextStyle(
                          color: _primaryGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Horaires
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_timeFmt.format(history.slotStart)} - ${_timeFmt.format(history.slotEnd)}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Statistiques en grille
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.people_outline,
                          label: 'Réservations',
                          value: history.totalReservations.toString(),
                          color: Colors.blue,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey.shade300,
                      ),
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.cancel_outlined,
                          label: 'Annulations',
                          value: history.totalCancellations.toString(),
                          color: Colors.orange,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey.shade300,
                      ),
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.check_circle_outline,
                          label: 'Servis',
                          value: history.servedEstimate.toString(),
                          color: _primaryGreen,
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
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showDetails(NotificationHistory history) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(history.queueName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Date', _dateFmt.format(history.createdAt)),
            const SizedBox(height: 8),
            _buildDetailRow(
              'Horaires',
              '${_timeFmt.format(history.slotStart)} - ${_timeFmt.format(history.slotEnd)}',
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Total réservations',
              history.totalReservations.toString(),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              'Annulations',
              history.totalCancellations.toString(),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              'Estimé servis',
              history.servedEstimate.toString(),
              highlight: true,
            ),
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

  Widget _buildDetailRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            fontSize: highlight ? 16 : 14,
            color: highlight ? _primaryGreen : Colors.black87,
          ),
        ),
      ],
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
                Icons.notifications_none,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aucune notification',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'L\'historique de vos files d\'attente apparaîtra ici',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
