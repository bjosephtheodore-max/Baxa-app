import 'package:flutter/material.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/settings_page.dart';
import 'package:baxa/page%20b-acceuil/company/notifications_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    final companyId = user?.uid ?? 'unknown_company';
    pages = [
      const HousePage(),
      SettingsPage(companyId: companyId),
      const NotificationsPage(),
    ];
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
          NavigationDestination(icon: Icon(Icons.home), label: "Acceuil"),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: "Agenda",
          ),
          NavigationDestination(icon: Icon(Icons.settings), label: "Réglages"),
          NavigationDestination(
            icon: Icon(Icons.notifications),
            label: "Notification",
          ),
        ],
      ),
    );
  }
}
