import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/company_settings_page.dart';
import 'package:baxa/page%20b-acceuil/company/company_notifications_page.dart';
import 'package:baxa/page b-acceuil/company/staff_page.dart';
import 'package:baxa/page b-acceuil/company/company_deletion_gate_page.dart';
import 'package:baxa/services/notifications/company_messaging_service.dart';
import 'package:baxa/services/onboarding_service.dart';
import 'package:baxa/widgets/notifications_nav_icon.dart';
import 'package:baxa/widgets/onboarding_widgets.dart';

class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key});
  @override
  State<CompanyPage> createState() => CompanyPageState();
}

class CompanyPageState extends State<CompanyPage> {
  int pageIndex = 0;
  bool _roleChecked = false;

  late final String _companyId =
      FirebaseAuth.instance.currentUser?.uid ?? '_';

  // Flux stable des notifications récentes de l'entreprise — alimente la
  // pastille de non-lus (barre de nav + icône de l'app). L'admin a
  // uid == companyId.
  late final Query<Map<String, dynamic>> _recentNotifs = FirebaseFirestore
      .instance
      .collection('companies')
      .doc(_companyId)
      .collection('companyNotifications')
      .orderBy('createdAt', descending: true)
      .limit(50);

  // null = normal · 'scheduled' = départ en cours (délai de grâce) ·
  // 'gone' = compte déjà supprimé.
  String? _deletionStatus;
  Map<String, dynamic>? _deletionData;

  late final List<Widget> _adminPages = [
    const HousePage(),
    const CompanySettingsPage(),
    CompanyNotificationsPage(companyId: _companyId, audience: 'admin'),
  ];

  @override
  void initState() {
    super.initState();
    _checkRole();
    CompanyMessagingService.instance.start(
      onOpenNotifications: () {
        if (!mounted) return;
        setState(() => pageIndex = 2);
        NotificationsNavIcon.markSeen();
      },
    );
    OnboardingService().checkAndInit();
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
          await FirebaseAnalytics.instance.setUserProperty(
            name: 'role',
            value: 'staff',
          );
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

      // Admin : départ de Baxa en cours ?
      try {
        final dr = await FirebaseFirestore.instance
            .collection('deletionRequests')
            .doc(user.uid)
            .get();
        if (dr.exists) {
          final s = dr.data()?['status'];
          if (s == 'scheduled' || s == 'pending') {
            _deletionStatus = 'scheduled';
            _deletionData = dr.data();
          } else if (s == 'approved' || s == 'completed') {
            _deletionStatus = 'gone';
          }
        }
      } catch (_) {}

      await FirebaseAnalytics.instance.setUserProperty(
        name: 'role',
        value: 'company',
      );
      if (mounted) setState(() => _roleChecked = true);
    } catch (e) {
      if (mounted) setState(() => _roleChecked = true);
    }
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_deletionStatus != null) {
      return CompanyDeletionGatePage(
        companyId: FirebaseAuth.instance.currentUser?.uid ?? '',
        status: _deletionStatus!,
        data: _deletionData,
        onRevived: () => setState(() {
          _deletionStatus = null;
          _deletionData = null;
        }),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_getTextScaleFactor(context))),
      child: Stack(
        children: [
          Scaffold(
            body: IndexedStack(index: pageIndex, children: _adminPages),
            // Fin trait au-dessus de la barre (façon WhatsApp) plutôt qu'une
            // ombre. Posé DEVANT la barre via un Column : mis en fond
            // (DecoratedBox), le blanc opaque de la barre le recouvrait.
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
                NavigationBar(
                  selectedIndex: pageIndex,
              onDestinationSelected: (int index) {
                if (index == 1) OnboardingService().advance(1);
                // "Lu" à l'entrée comme à la sortie de l'onglet Notifications
                // (couvre une notif arrivée pendant la consultation).
                final leavingNotifs = pageIndex == 2 && index != 2;
                final enteringNotifs = index == 2;
                if (leavingNotifs || enteringNotifs) {
                  NotificationsNavIcon.markSeen();
                }
                setState(() => pageIndex = index);
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Accueil',
                ),
                NavigationDestination(
                  icon: ListenableBuilder(
                    listenable: OnboardingService(),
                    builder: (_, __) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.settings_outlined),
                        if (OnboardingService().step == 1)
                          const Positioned(
                            top: -4,
                            right: -4,
                            child: PulsingDot(),
                          ),
                      ],
                    ),
                  ),
                  selectedIcon: ListenableBuilder(
                    listenable: OnboardingService(),
                    builder: (_, __) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.settings_rounded),
                        if (OnboardingService().step == 1)
                          const Positioned(
                            top: -4,
                            right: -4,
                            child: PulsingDot(),
                          ),
                      ],
                    ),
                  ),
                  label: 'Réglages',
                ),
                NavigationDestination(
                  icon: NotificationsNavIcon(
                    recentNotifications: _recentNotifs,
                    unreadWhere: (d) => (d['audience'] ?? 'admin') == 'admin',
                    selected: pageIndex == 2,
                  ),
                  label: 'Notifications',
                ),
              ],
              ),
            ],
          ),
          ),
          Positioned(
            bottom: 80 + MediaQuery.of(context).padding.bottom,
            left: 0,
            right: 0,
            child: ListenableBuilder(
              listenable: OnboardingService(),
              builder: (_, __) {
                if (OnboardingService().step != 1) {
                  return const SizedBox.shrink();
                }
                return const Center(
                  child: PulsingHint(
                    text: 'Appuyez sur Réglages',
                    icon: Icons.settings,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
