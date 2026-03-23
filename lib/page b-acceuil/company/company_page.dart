import 'package:flutter/material.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/company_settings_page.dart';
import 'package:baxa/page%20b-acceuil/company/notifications_page.dart';
import 'package:baxa/services/notifications/queue_notification_service.dart';

class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key});
  @override
  State<CompanyPage> createState() => CompanyPageState();
}

class CompanyPageState extends State<CompanyPage> {
  int pageIndex = 0;
  // ignore: unused_field
  bool _serviceInitialized = false;

  // Pages instanciées une seule fois — jamais recréées
  static const List<Widget> _pages = [
    HousePage(),
    CompanySettingsPage(),
    NotificationsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeNotificationService();
  }

  Future<void> _initializeNotificationService() async {
    try {
      await QueueNotificationService().initialize();
      if (mounted) setState(() => _serviceInitialized = true);
    } catch (e) {
      debugPrint('❌ Erreur initialisation notifications: $e');
    }
  }

  @override
  void dispose() {
    QueueNotificationService().dispose();
    super.dispose();
  }

  double _getTextScaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 340) return 0.80;
    if (width < 380) return 0.88;
    if (width < 420) return 0.95;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaleFactor: _getTextScaleFactor(context)),
      child: Scaffold(
        // ── IndexedStack garde toutes les pages montées en mémoire ──────
        // Résultat : navigation instantanée, zéro rechargement Firestore
        body: IndexedStack(index: pageIndex, children: _pages),
        bottomNavigationBar: NavigationBar(
          backgroundColor: Colors.white,
          selectedIndex: pageIndex,
          onDestinationSelected: (int index) {
            setState(() => pageIndex = index);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Réglages',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications),
              label: 'Notifications',
            ),
          ],
        ),
      ),
    );
  }
}
