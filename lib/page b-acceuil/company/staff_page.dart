import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/staff_settings_page.dart';
import 'package:baxa/widgets/notifications_nav_icon.dart';

// ============================================================
// STAFF PAGE — Wrapper avec bottom nav pour le staff
// Accueil | Notifications | Paramètres
// ============================================================
class StaffPage extends StatefulWidget {
  final String companyId;
  final String companyName;

  const StaffPage({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  int _pageIndex = 0;

  // Flux stable des notifications récentes destinées à ce membre du staff —
  // alimente la pastille de non-lus (barre de nav + icône de l'app).
  late final Query<Map<String, dynamic>> _recentNotifs = FirebaseFirestore
      .instance
      .collection('companies')
      .doc(widget.companyId)
      .collection('notificationsAdmin')
      .where('staffId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '_')
      .orderBy('createdAt', descending: true)
      .limit(50);

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HousePage(),
      _StaffNotificationsPage(companyId: widget.companyId),
      StaffSettingsPage(
        companyId: widget.companyId,
        companyName: widget.companyName,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _pageIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        height: 60,
        backgroundColor: Colors.white,
        selectedIndex: _pageIndex,
        onDestinationSelected: (i) {
          // "Lu" à l'entrée comme à la sortie de l'onglet Notifications.
          final leavingNotifs = _pageIndex == 1 && i != 1;
          final enteringNotifs = i == 1;
          if (leavingNotifs || enteringNotifs) {
            NotificationsNavIcon.markSeen();
          }
          setState(() => _pageIndex = i);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: NotificationsNavIcon(recentNotifications: _recentNotifs),
            label: 'Notifications',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}

// ── Notifications staff ──────────────────────────────────────
class _StaffNotificationsPage extends StatelessWidget {
  final String companyId;
  const _StaffNotificationsPage({required this.companyId});

  static const Color _green = Color(0xFF4B8B5E);
  static const Color _dark = Color(0xFF1A1C2E);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _dark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade100, height: 1),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .collection('notificationsAdmin')
            .where('staffId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
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
                      Icons.notifications_none_rounded,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aucune notification',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5ED),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.notifications_rounded,
                        color: _green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: _dark,
                            ),
                          ),
                          if ((data['body'] as String? ?? '').isNotEmpty)
                            Text(
                              data['body'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
