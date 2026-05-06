import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/company_settings_page.dart';
import 'package:baxa/page%20b-acceuil/company/notifications_page.dart';
import 'package:baxa/page b-acceuil/company/staff_page.dart';
import 'package:baxa/services/notifications/queue_notification_service.dart';

class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key});
  @override
  State<CompanyPage> createState() => CompanyPageState();
}

class CompanyPageState extends State<CompanyPage> {
  int pageIndex = 0;
  bool _roleChecked = false;

  static const List<Widget> _adminPages = [
    HousePage(),
    CompanySettingsPage(),
    NotificationsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkRole();
    _initializeNotificationService();
  }

  Future<void> _checkRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _roleChecked = true);
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data['role'] == 'staff' && data['companyId'] != null) {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => StaffPage(
                  companyId: data['companyId'] as String,
                  companyName: data['companyName'] as String? ?? '',
                ),
              ),
              (route) => false,
            );
          }
          return;
        }
      }

      if (mounted) setState(() => _roleChecked = true);
    } catch (e) {
      if (mounted) setState(() => _roleChecked = true);
    }
  }

  Future<void> _initializeNotificationService() async {
    try {
      await QueueNotificationService().initialize();
      if (mounted) setState(() {});
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
    if (!_roleChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_getTextScaleFactor(context)),
      ),
      child: Scaffold(
        body: IndexedStack(index: pageIndex, children: _adminPages),
        bottomNavigationBar: NavigationBar(
                backgroundColor: Colors.white,
                selectedIndex: pageIndex,
                onDestinationSelected: (int index) {
                  setState(() => pageIndex = index);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home),
                    label: 'Accueil',
                  ),
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
