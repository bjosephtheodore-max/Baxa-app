import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:baxa/page%20b-acceuil/customer/slots_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);
  // Même teinte que celle utilisée par les autres pages qui ouvrent
  // SlotsPage (companyqueue_page.dart, search_page.dart) — _greenLight
  // ci-dessus est trop pâle, elle sert uniquement aux badges de cette page.
  static const Color _slotsPageLightGreen = Color(0xFFB2D3C2);
  static const Color _dark = Color(0xFF1A1C2E);

  final NotificationService _notifSvc = NotificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('EEE d MMM', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _notifSvc.init();
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier · ${_timeFmt.format(dt)}';
    return '${_dateFmt.format(dt)} · ${_timeFmt.format(dt)}';
  }

  _NotifType _parseType(String title) {
    final t = title.toLowerCase();
    if (t.contains('validation') || t.contains('🟢') || t.contains('tour')) {
      return _NotifType.validation;
    }
    if (t.contains('passé') || t.contains('terminé') || t.contains('🟠')) {
      return _NotifType.passed;
    }
    if (t.contains('annul')) return _NotifType.cancelled;
    if (t.contains('confirmée') || t.contains('🎉')) {
      return _NotifType.confirmed;
    }
    return _NotifType.reminder;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            color: _dark,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Tout supprimer',
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: Colors.grey.shade500,
            ),
            onPressed: _showDeleteAllConfirmation,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade100, height: 1),
        ),
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          final userId = authSnapshot.data?.uid;
          if (userId == null) {
            return const Center(
              child: CircularProgressIndicator(color: _green, strokeWidth: 2),
            );
          }
          return StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('customers')
                .doc(userId)
                .collection('notifications')
                .orderBy('createdAt', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: _green,
                    strokeWidth: 2,
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState();
              }
              final docs = snapshot.data!.docs;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final doc = docs[i];
                  return _buildNotifCard(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNotifCard(String id, Map<String, dynamic> data) {
    final title = data['title'] as String? ?? 'Notification';
    final body = data['body'] as String? ?? '';
    final createdAt = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    final cfg = _configFor(_parseType(title));

    // Bouton "Trouver un créneau" : uniquement pour une annulation par
    // l'entreprise, et seulement si la Cloud Function a bien fourni de quoi
    // rediriger (payload absent = notification plus ancienne, sans ce champ).
    final payload = data['payload'] as Map<String, dynamic>?;
    final canFindNewSlot =
        data['type'] == 'cancellation_by_company' &&
        payload != null &&
        (payload['queueId'] as String?)?.isNotEmpty == true &&
        (payload['companyId'] as String?)?.isNotEmpty == true;

    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 26),
            SizedBox(height: 4),
            Text(
              'Supprimer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => _deleteNotification(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cfg.borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: cfg.accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cfg.iconBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(cfg.icon, color: cfg.iconColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: _dark,
                                      ),
                                    ),
                                  ),
                                  if (createdAt != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      _relativeTime(createdAt),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  body,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: cfg.badgeBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  cfg.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: cfg.accent,
                                  ),
                                ),
                              ),
                              if (canFindNewSlot) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _goToSlots(payload),
                                    icon: const Icon(
                                      Icons.search_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Trouver un créneau'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _green,
                                      side: const BorderSide(color: _green),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goToSlots(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final companyId = payload['companyId'] as String? ?? '';
    final queueId = payload['queueId'] as String? ?? '';
    if (companyId.isEmpty || queueId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlotsPage(
          entrepriseId: companyId,
          entrepriseNom: payload['companyName'] as String? ?? '',
          queueId: queueId,
          queueName: payload['queueName'] as String? ?? 'File',
          primaryGreen: _green,
          lightGreen: _slotsPageLightGreen,
          onReservationSuccess: () {},
        ),
      ),
    );
  }

  _NotifCfg _configFor(_NotifType type) {
    switch (type) {
      case _NotifType.validation:
        return _NotifCfg(
          icon: Icons.check_circle_rounded,
          iconColor: _green,
          iconBg: _greenLight,
          accent: _green,
          borderColor: _green.withValues(alpha: 0.2),
          badgeBg: _greenLight,
          label: 'C\'est ton tour',
        );
      case _NotifType.passed:
        return _NotifCfg(
          icon: Icons.timelapse_rounded,
          iconColor: Colors.orange.shade600,
          iconBg: Colors.orange.shade50,
          accent: Colors.orange.shade500,
          borderColor: Colors.orange.shade100,
          badgeBg: Colors.orange.shade50,
          label: 'Créneau passé',
        );
      case _NotifType.cancelled:
        return _NotifCfg(
          icon: Icons.event_busy_rounded,
          iconColor: Colors.red.shade400,
          iconBg: Colors.red.shade50,
          accent: Colors.red.shade400,
          borderColor: Colors.red.shade100,
          badgeBg: Colors.red.shade50,
          label: 'Annulation',
        );
      case _NotifType.reminder:
        return _NotifCfg(
          icon: Icons.access_alarm_rounded,
          iconColor: Colors.blue.shade500,
          iconBg: Colors.blue.shade50,
          accent: Colors.blue.shade400,
          borderColor: Colors.blue.shade100,
          badgeBg: Colors.blue.shade50,
          label: 'Rappel',
        );
      case _NotifType.confirmed:
        return _NotifCfg(
          icon: Icons.celebration_rounded,
          iconColor: _green,
          iconBg: _greenLight,
          accent: _green,
          borderColor: _green.withValues(alpha: 0.2),
          badgeBg: _greenLight,
          label: 'Confirmée',
        );
    }
  }

  Future<void> _deleteNotification(String id) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      await _firestore
          .collection('customers')
          .doc(userId)
          .collection('notifications')
          .doc(id)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteAllConfirmation() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          32 + MediaQuery.of(ctx).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_forever_rounded,
                color: Colors.red.shade400,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tout supprimer ?',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toutes vos notifications seront supprimées définitivement.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Annuler',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Supprimer tout',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) await _deleteAllNotifications();
  }

  Future<void> _deleteAllNotifications() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      await _notifSvc.cancelAll();
      final snap = await _firestore
          .collection('customers')
          .doc(userId)
          .collection('notifications')
          .get();
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${snap.docs.length} notification${snap.docs.length > 1 ? 's' : ''} supprimée${snap.docs.length > 1 ? 's' : ''}',
            ),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
              decoration: const BoxDecoration(
                color: _greenLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 48,
                color: _green.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucune notification',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos rappels et alertes de réservation apparaîtront ici',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _NotifType { reminder, validation, passed, cancelled, confirmed }

class _NotifCfg {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color accent;
  final Color borderColor;
  final Color badgeBg;
  final String label;

  const _NotifCfg({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.accent,
    required this.borderColor,
    required this.badgeBg,
    required this.label,
  });
}
