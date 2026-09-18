import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:baxa/page b-acceuil/customer/search_page.dart';
import 'package:baxa/page b-acceuil/customer/house_page.dart';
import 'package:baxa/page%20b-acceuil/customer/notifications_page.dart';
import 'package:baxa/page%20b-acceuil/customer/reservation_ticket_page.dart';
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:baxa/services/notifications/gestionnaire_annulations_page.dart';
import 'package:baxa/widgets/notifications_nav_icon.dart';
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

  StreamSubscription<RemoteMessage>? _fcmTapSub;

  // Flux stable des notifications récentes du client — alimente la pastille
  // de non-lus (barre de nav + icône de l'app), voir NotificationsNavIcon.
  late final Query<Map<String, dynamic>> _recentNotifs = FirebaseFirestore
      .instance
      .collection('customers')
      .doc(FirebaseAuth.instance.currentUser?.uid ?? '_')
      .collection('notifications')
      .orderBy('createdAt', descending: true)
      .limit(50);

  // Pages instanciées une seule fois — SearchPage est pushée, pas dans le stack
  static const List<Widget> _pages = [
    HousePage(),
    NotificationsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeCustomerServices();
    _setupNotificationTapHandling();
  }

  @override
  void dispose() {
    _fcmTapSub?.cancel();
    super.dispose();
  }

  /// Initialiser tous les services nécessaires pour la partie customer
  Future<void> _initializeCustomerServices() async {
    if (_isInitialized) return;

    try {
      // 1. Initialiser le service de notifications
      await NotificationService().init();

      // 1bis. Purger d'éventuels rappels programmés localement par une
      // version antérieure de l'app (avant migration vers les
      // notifications planifiées côté serveur) — évite les doublons.
      await NotificationService().cancelAll();

      // 2. Initialiser le gestionnaire d'annulation
      CancellationHandler().initialize();

      // 3. Demander les permissions iOS si nécessaire
      if (Platform.isIOS) {
        await NotificationService().requestIOSPermissions();
      }

      // 4. Permission notifications (Android 13+ / iOS) + token FCM à jour.
      // Fait ici (à chaque ouverture de l'app), pas seulement à la
      // connexion : couvre aussi les sessions déjà connectées avant ce
      // correctif, sans obliger à se déconnecter/reconnecter.
      try {
        await FirebaseMessaging.instance.requestPermission();
        final user = FirebaseAuth.instance.currentUser;
        final token = await FirebaseMessaging.instance.getToken();
        if (user != null && token != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'fcmToken': token}, SetOptions(merge: true));
        }
      } catch (_) {}

      _isInitialized = true;
      debugPrint('✅ Services customer initialisés avec succès');
    } catch (e) {
      debugPrint('❌ Erreur initialisation services customer: $e');
    }
  }

  // ── Badge de notifications non lues ─────────────────────────────────────
  //
  // "Non lu" = créé après la dernière visite de l'onglet Notifications
  // (users/{uid}.notificationsLastSeenAt), pas un suivi par notification —
  // même logique que la plupart des apps grand public. Toute la mécanique
  // (écoute, comptage, pastille de l'icône de l'app) vit désormais dans
  // NotificationsNavIcon, partagé avec les espaces company et staff.

  void _setupNotificationTapHandling() {
    // App en arrière-plan, tap sur la notif → premier plan directement sur
    // l'onglet Notifications (+ ticket vivant par-dessus si c'est "c'est
    // ton tour", voir _handleNotificationTap).
    _fcmTapSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (!mounted) return;
      NotificationsNavIcon.markSeen();
      _handleNotificationTap(message);
    });

    // App totalement fermée, ouverte via le tap sur la notif.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null && mounted) {
        NotificationsNavIcon.markSeen();
        _handleNotificationTap(message);
      }
    });
  }

  // Atterrit toujours sur l'onglet Notifications ; en plus, pour l'étape
  // "c'est ton tour" uniquement (voir sendPushOnNotification côté serveur,
  // seule celle-ci fournit ce `data`), ouvre directement le ticket vivant
  // par-dessus — un tap sur les autres notifs (confirmée, rappel, créneau
  // passé, annulation...) n'a rien de plus à faire que d'ouvrir la liste.
  void _handleNotificationTap(RemoteMessage message) {
    setState(() => pageIndex = 1);

    final data = message.data;
    if (data['deepLink'] != 'ticket') return;
    final slotStart = DateTime.tryParse(data['slotStart'] ?? '');
    final slotEnd = DateTime.tryParse(data['slotEnd'] ?? '');
    if (slotStart == null || slotEnd == null) return;

    // Le premier frame doit avoir posé l'onglet Notifications (et, à froid,
    // le Navigator lui-même) avant qu'on puisse empiler le ticket dessus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReservationTicketPage(
            companyName: data['companyName'] ?? '',
            queueName: data['queueName'] ?? '',
            slotStart: slotStart,
            slotEnd: slotEnd,
          ),
        ),
      );
    });
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
              selectedIndex: navBarIndex,
          onDestinationSelected: (int index) {
            // "Lu" dès qu'on entre sur l'onglet Notifications, et aussi
            // quand on le quitte (couvre le cas où une notif arrive
            // pendant qu'on est déjà en train de regarder l'écran).
            final leavingNotifications = pageIndex == 1 && index != 2;
            final enteringNotifications = index == 2;
            if (leavingNotifications || enteringNotifications) {
              NotificationsNavIcon.markSeen();
            }

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
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: "Accueil",
            ),
            const NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search_rounded),
              label: "Recherche",
            ),
            NavigationDestination(
              icon: NotificationsNavIcon(
                recentNotifications: _recentNotifs,
                selected: navBarIndex == 2,
              ),
              label: "Notifications",
            ),
          ],
          ),
        ],
        ),
      ),
    );
  }
}
