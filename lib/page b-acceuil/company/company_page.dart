import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:baxa/page b-acceuil/company/house_page.dart';
import 'package:baxa/page b-acceuil/company/company_settings_page.dart';
import 'package:baxa/page%20b-acceuil/company/company_notifications_page.dart';
import 'package:baxa/page b-acceuil/company/staff_page.dart';
import 'package:baxa/page b-acceuil/company/company_deletion_gate_page.dart';
import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';
import 'package:baxa/services/company_account_service.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:baxa/services/notifications/company_messaging_service.dart';
import 'package:baxa/services/onboarding_service.dart';
import 'package:baxa/services/time_zone_service.dart';
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
  bool _roleCheckFailed = false;
  // Compte valide mais sans espace structure (client…) : écran de sortie.
  bool _notACompany = false;

  late final String _companyId = FirebaseAuth.instance.currentUser?.uid ?? '_';

  // Flux stable des notifications récentes adressées à l'admin — alimente
  // la pastille de non-lus (barre de nav + icône de l'app). L'admin a
  // uid == companyId.
  late final Query<Map<String, dynamic>> _recentNotifs =
      CompanyNotificationsPage.queryFor(
        companyId: _companyId,
        audience: 'admin',
      ).limit(50);

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

      // Pas membre d'équipe : le compte doit être une STRUCTURE (étiquette
      // posée par le serveur à l'inscription). Un compte client — ou un
      // ancien compte Google à qui l'on a donné un mot de passe — n'entre
      // jamais dans l'espace structure.
      final role = await CompanyAccountService.resolveRole();
      if (role.role != CompanyRole.company) {
        if (mounted) setState(() => _notACompany = true);
        return;
      }

      // Admin : fuseau de la structure (une seule fois, s'il manque).
      unawaited(TimeZoneService.ensureCompanyTimeZone(user.uid));

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
      // Rôle illisible (réseau…) : ne surtout pas afficher l'espace admin
      // par défaut — un membre du staff s'y retrouverait. On propose de
      // réessayer.
      if (mounted) setState(() => _roleCheckFailed = true);
    }
  }

  void _retryRoleCheck() {
    setState(() => _roleCheckFailed = false);
    _checkRole();
  }

  // Ferme la session et revient au choix « client / structure / équipe ».
  Future<void> _leaveNotACompany() async {
    await Auth().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ChoosePage()),
      (route) => false,
    );
  }

  Widget _buildNotACompany() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEEF5F0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    size: 32,
                    color: Color(0xFF3F7A51),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Aucun espace structure pour ce compte',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2E1F),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ce compte n\'a pas de structure inscrite sur Baxa. Pour '
                  'inscrire la vôtre, utilisez « S\'inscrire » avec une autre '
                  'adresse e-mail.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF4A564E),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _leaveNotACompany,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F7A51),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Retour à l\'accueil',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    if (_notACompany) return _buildNotACompany();

    if (_roleCheckFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Impossible de charger votre compte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Vérifiez votre connexion internet puis réessayez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _retryRoleCheck,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B8B5E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                        unreadWhere: (d) =>
                            (d['audience'] ?? 'admin') == 'admin',
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
