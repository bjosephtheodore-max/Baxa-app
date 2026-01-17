import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/notification_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final NotificationService _notifSvc = NotificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _df = DateFormat('dd/MM/yyyy HH:mm');
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _notifSvc.init();
    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }

    try {
      final snap = await _firestore
          .collection('customers')
          .doc(user.uid)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      _items = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'title': data['title'] ?? 'Notification',
          'body': data['body'] ?? '',
          'createdAt': data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : null,
          'payload': data['payload'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Load notifications failed: $e');
      _items = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteNotification(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _firestore
        .collection('customers')
        .doc(user.uid)
        .collection('notifications')
        .doc(id)
        .delete();
    await _loadNotifications();
  }

  Future<void> _clearLocalScheduledForAll() async {
    await _notifSvc.cancelAll();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Toutes les notifications locales programmées ont été annulées.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 75, 139, 94),
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Annuler toutes les notifications locales',
            icon: const Icon(Icons.notifications_off),
            onPressed: _clearLocalScheduledForAll,
          ),
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Aucune notification pour l’instant.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = _items[i];
                final createdAt = it['createdAt'] as DateTime?;
                return ListTile(
                  leading: const Icon(Icons.notifications),
                  title: Text(it['title'] ?? ''),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((it['body'] ?? '').isNotEmpty) Text(it['body']),
                      if (createdAt != null)
                        Text(
                          _df.format(createdAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteNotification(it['id'] as String),
                  ),
                );
              },
            ),
    );
  }
}
