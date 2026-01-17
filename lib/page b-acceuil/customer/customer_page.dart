import 'package:flutter/material.dart';
import 'package:baxa/page b-acceuil/customer/search_page.dart';
import 'package:baxa/page b-acceuil/customer/house_page.dart';
import 'package:baxa/page%20b-acceuil/customer/notifications_page.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});

  @override
  State<CustomerPage> createState() {
    return CustomerPageState();
  }
}

class CustomerPageState extends State<CustomerPage> {
  final pages = [HousePage(), SearchPage(), NotificationsPage()];

  int pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[pageIndex],
      bottomNavigationBar: NavigationBar(
        height: 60,
        backgroundColor: Colors.white,
        selectedIndex: pageIndex,
        onDestinationSelected: (int index) {
          setState(() {
            pageIndex = index;
          });
        },

        destinations: [
          NavigationDestination(icon: Icon(Icons.home), label: "Acceuil"),
          NavigationDestination(icon: Icon(Icons.search), label: "Recherche"),
          NavigationDestination(
            icon: Icon(Icons.notifications),
            label: "Notifications",
          ),
        ],
      ),
    );
  }
}
