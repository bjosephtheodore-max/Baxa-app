import 'package:flutter/material.dart';
import 'package:baxa/page b-acceuil/customer/search_page.dart';
import 'package:baxa/page b-acceuil/customer/house_page.dart';
import 'package:baxa/page%20b-acceuil/customer/notifications_page.dart';
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:baxa/services/notifications/gestionnaire_annulations_page.dart';
import 'dart:io' show Platform;

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});

  @override
  State<CustomerPage> createState() {
    return CustomerPageState();
  }
}

class CustomerPageState extends State<CustomerPage> {
  int pageIndex = 0;
  bool _isInitialized = false;

  // Pages instanciées une seule fois — SearchPage est pushée, pas dans le stack
  static const List<Widget> _pages = [
    HousePage(),
    NotificationsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeCustomerServices();
  }

  /// Initialiser tous les services nécessaires pour la partie customer
  Future<void> _initializeCustomerServices() async {
    if (_isInitialized) return;

    try {
      // 1. Initialiser le service de notifications
      await NotificationService().init();

      // 2. Initialiser le gestionnaire d'annulation
      CancellationHandler().initialize();

      // 3. Demander les permissions iOS si nécessaire
      if (Platform.isIOS) {
        await NotificationService().requestIOSPermissions();
      }

      _isInitialized = true;
      debugPrint('✅ Services customer initialisés avec succès');
    } catch (e) {
      debugPrint('❌ Erreur initialisation services customer: $e');
    }
  }

  /// Calculer le facteur de scaling adaptatif
  double _getTextScaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Design de référence : 390px (iPhone 14 / écrans modernes)
    // Ton écran : 720px physiques / 2.5 density = ~288dp logiques
    // On réduit légèrement pour que tout rentre mieux

    if (width < 340) return 0.80; // Très petits écrans (< 340dp)
    if (width < 380) return 0.88; // Petits/moyens écrans (340-380dp) — TON CAS
    if (width < 420) return 0.95; // Moyens/grands écrans (380-420dp)
    return 1.0; // Grands écrans (> 420dp)
  }

  @override
  Widget build(BuildContext context) {
    // Mapping : pageIndex 0=Accueil, 1=Notifications
    // NavBar :  index   0=Accueil, 1=Recherche (push), 2=Notifications
    final navBarIndex = pageIndex == 1 ? 2 : pageIndex;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_getTextScaleFactor(context)),
      ),
      child: Scaffold(
        body: IndexedStack(index: pageIndex, children: _pages),
        bottomNavigationBar: NavigationBar(
          height: 60,
          backgroundColor: Colors.white,
          selectedIndex: navBarIndex,
          onDestinationSelected: (int index) {
            if (index == 1) {
              // Recherche — plein écran, sans bottom nav
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SearchPage(),
                ),
              );
            } else {
              // 0 → Accueil, 2 → Notifications (pageIndex 1)
              setState(() => pageIndex = index == 2 ? 1 : 0);
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: "Accueil"),
            NavigationDestination(
              icon: Icon(Icons.search),
              label: "Recherche",
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications),
              label: "Notifications",
            ),
          ],
        ),
      ),
    );
  }
}
