import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/staff_settings_page.dart';
import 'package:baxa/page%20b-acceuil/company/company_notifications_page.dart';
import 'package:baxa/services/notifications/company_messaging_service.dart';
import 'package:baxa/widgets/notifications_nav_icon.dart';

// ============================================================
// STAFF PAGE — Wrapper avec bottom nav pour le staff
// Accueil | Paramètres | Notifications (même ordre que company_page.dart)
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

class _StaffPageState extends State<StaffPage> with WidgetsBindingObserver {
  int _pageIndex = 0;

  // Dernière activité affichée à l'admin dans « Mon équipe » : écrite à
  // l'ouverture et au retour au premier plan, au plus une fois / 15 min.
  static const _lastSeenThrottle = Duration(minutes: 15);
  DateTime? _lastSeenWrittenAt;

  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '_';

  // Flux stable des notifications récentes de l'entreprise — le filtrage
  // « adressées à ce membre » se fait en mémoire (unreadWhere / _isForMe).
  late final Query<Map<String, dynamic>> _recentNotifs = FirebaseFirestore
      .instance
      .collection('companies')
      .doc(widget.companyId)
      .collection('companyNotifications')
      .orderBy('createdAt', descending: true)
      .limit(50);

  bool _staffNotif(Map<String, dynamic> d) =>
      d['audience'] == 'staff' && d['staffId'] == _uid;

  Future<void> _touchLastSeen() async {
    final now = DateTime.now();
    final last = _lastSeenWrittenAt;
    if (last != null && now.difference(last) < _lastSeenThrottle) return;
    _lastSeenWrittenAt = now;
    try {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(widget.companyId)
          .collection('staff')
          .doc(_uid)
          .update({'lastSeenAt': FieldValue.serverTimestamp()});
    } catch (_) {
      // Purement informatif : un échec (hors ligne, membre retiré) est muet.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _touchLastSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _touchLastSeen();
    CompanyMessagingService.instance.start(
      onOpenNotifications: () {
        if (!mounted) return;
        setState(() => _pageIndex = 2);
        NotificationsNavIcon.markSeen();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HousePage(staffCompanyId: widget.companyId),
      StaffSettingsPage(
        companyId: widget.companyId,
        companyName: widget.companyName,
      ),
      CompanyNotificationsPage(
        companyId: widget.companyId,
        audience: 'staff',
        staffId: _uid,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _pageIndex, children: pages),
      // Fin trait au-dessus de la barre (façon WhatsApp) plutôt qu'une
      // ombre. Posé DEVANT la barre via un Column : en fond, le blanc
      // opaque de la barre le recouvrait.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.06),
          ),
          NavigationBar(
            selectedIndex: _pageIndex,
        onDestinationSelected: (i) {
          // "Lu" à l'entrée comme à la sortie de l'onglet Notifications.
          final leavingNotifs = _pageIndex == 2 && i != 2;
          final enteringNotifs = i == 2;
          if (leavingNotifs || enteringNotifs) {
            NotificationsNavIcon.markSeen();
          }
          setState(() => _pageIndex = i);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Paramètres',
          ),
          NavigationDestination(
            icon: NotificationsNavIcon(
              recentNotifications: _recentNotifs,
              unreadWhere: _staffNotif,
              selected: _pageIndex == 2,
            ),
            label: 'Notifications',
          ),
        ],
        ),
      ],
      ),
    );
  }
}
