import 'package:flutter/material.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/settings_page.dart';
import 'package:baxa/page%20b-acceuil/company/notifications_page.dart';
import 'package:baxa/services/notifications/queue_notification_service.dart';

class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key});

  @override
  State<CompanyPage> createState() {
    return CompanyPageState();
  }
}

class CompanyPageState extends State<CompanyPage> {
  late final List<Widget> pages;
  int pageIndex = 0;
  // ignore: unused_field
  bool _serviceInitialized = false;

  @override
  void initState() {
    super.initState();
    pages = [
      const HousePage(),
      const SettingsPage(),
      const NotificationsPage(),
    ];

    // Initialiser le service de notifications
    _initializeNotificationService();
  }

  Future<void> _initializeNotificationService() async {
    try {
      await QueueNotificationService().initialize();
      if (mounted) {
        setState(() {
          _serviceInitialized = true;
        });
      }
      print('✅ Service de notifications initialisé');
    } catch (e) {
      print('❌ Erreur initialisation notifications: $e');
    }
  }

  @override
  void dispose() {
    // Nettoyer le service quand la page est détruite
    QueueNotificationService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[pageIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        selectedIndex: pageIndex,
        onDestinationSelected: (int index) {
          setState(() {
            pageIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: "Accueil"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Réglages"),
          NavigationDestination(
            icon: Icon(Icons.notifications),
            label: "Notifications",
          ),
        ],
      ),
    );
  }
}
