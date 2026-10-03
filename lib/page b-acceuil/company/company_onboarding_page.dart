import 'dart:async';

import 'package:baxa/page%20b-acceuil/company/prereception_page.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// ONBOARDING STRUCTURE — présentation avant l'inscription
// ============================================================
// Parcours après « Je suis une Structure » (choose_page) :
//   1. La promesse            ┐ cette page (2 écrans, PageView)
//   2. Comment ça marche      ┘
//   3. Votre structure        → PrereceptionPage (formulaire)
//   4. Une journée chez [Nom] → CompanyDayPreviewPage (animation)
//   5. Inscription            → SigninPage
//
// Les écrans 1-2 ne s'affichent qu'une fois par appareil : au retour, on
// va directement au formulaire. Les employés (code d'invitation) passent
// par StaffAuthPage et ne voient jamais ce parcours.

const Color _greenDark = Color(0xFF3F7A51);
const Color _greenSoft = Color(0xFFEEF5F0);
const Color _dark = Color(0xFF1A2E1F);
const Color _muted = Color(0xFF4A564E);

/// Point d'entrée depuis choose_page : présentation au premier passage,
/// formulaire directement ensuite.
class CompanyOnboarding {
  static const String _seenKey = 'company_onboarding_seen';

  static Future<void> open(BuildContext context) async {
    var seen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(_seenKey) ?? false;
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            seen ? const PrereceptionPage() : const CompanyOnboardingPage(),
      ),
    );
  }

  static Future<void> _markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  /// Un événement par écran vu : mesure où les structures décrochent.
  static void logStep(String step) {
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'company_onboarding_step',
        parameters: {'step': step},
      ),
    );
  }
}

class CompanyOnboardingPage extends StatefulWidget {
  const CompanyOnboardingPage({super.key});

  @override
  State<CompanyOnboardingPage> createState() => _CompanyOnboardingPageState();
}

class _CompanyOnboardingPageState extends State<CompanyOnboardingPage> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _steps = ['promesse', 'fonctionnement'];

  @override
  void initState() {
    super.initState();
    CompanyOnboarding.logStep(_steps[0]);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_page > 0) {
      _goTo(_page - 1);
    } else {
      Navigator.pop(context);
    }
  }

  // Vers le formulaire : la présentation est considérée comme vue, qu'on
  // l'ait parcourue ou passée. On empile (push) pour que le retour depuis
  // le formulaire ramène ici, comme dans la maquette.
  void _goToForm({required bool skipped}) {
    unawaited(CompanyOnboarding._markSeen());
    if (skipped) {
      unawaited(
        FirebaseAnalytics.instance.logEvent(
          name: 'company_onboarding_skip',
          parameters: {'from': _steps[_page]},
        ),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrereceptionPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _steps.length - 1;
    return PopScope(
      // Retour système sur le 2e écran : revenir au 1er, pas quitter.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_page - 1);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _back,
                      tooltip: 'Retour',
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: _greenDark,
                        size: 30,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _goToForm(skipped: true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                      ),
                      child: const Text(
                        'Passer',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    CompanyOnboarding.logStep(_steps[i]);
                  },
                  children: const [_PromisePage(), _HowItWorksPage()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  children: [
                    _Dots(count: _steps.length, index: _page),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isLast
                            ? () => _goToForm(skipped: false)
                            : () => _goTo(_page + 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _greenDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          isLast ? 'Configurer ma structure' : 'Découvrir comment',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mise en page commune : défile si l'écran est trop petit ──────────────────
class _ScrollableFill extends StatelessWidget {
  final Widget child;
  const _ScrollableFill({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}

// ============================================================
// 1 · LA PROMESSE
// ============================================================
class _PromisePage extends StatelessWidget {
  const _PromisePage();

  @override
  Widget build(BuildContext context) {
    return _ScrollableFill(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const _Tag(
            label: 'Avant',
            detail: 'une file qui s\'allonge',
            icon: Icons.close_rounded,
            color: Color(0xFF5E5E58),
          ),
          const SizedBox(height: 8),
          const _QueueIllustration(),
          const SizedBox(height: 28),
          const _Tag(
            label: 'Avec Baxa',
            detail: 'chacun à son heure',
            icon: Icons.check_rounded,
            color: _greenDark,
          ),
          const SizedBox(height: 8),
          const _AgendaIllustration(),
          const Spacer(),
          const SizedBox(height: 24),
          const Text(
            'Transformez votre file d\'attente en agenda.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: _dark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ils n\'attendent plus. Ils arrivent.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final String detail;
  final IconData icon;
  final Color color;

  const _Tag({
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· $detail',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Guichet + file de personnes qui s'estompe vers la droite.
class _QueueIllustration extends StatelessWidget {
  const _QueueIllustration();

  static const _shades = [
    Color(0xFFA3A39D),
    Color(0xFFA3A39D),
    Color(0xFFA3A39D),
    Color(0xFFA3A39D),
    Color(0xFFA3A39D),
    Color(0xFFBDBDB7),
    Color(0xFFCFCFCA),
    Color(0xFFDEDED9),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F2),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 48,
            padding: const EdgeInsets.only(top: 6),
            alignment: Alignment.topCenter,
            decoration: const BoxDecoration(
              color: Color(0xFF8A8A84),
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Container(
              width: 16,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // La file s'adapte à la largeur : jamais de débordement.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final c in _shades)
                    Icon(Icons.person_rounded, size: 34, color: c),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6, left: 2),
                    child: Text(
                      '…',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA3A39D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaIllustration extends StatelessWidget {
  const _AgendaIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        children: [
          _AgendaRow(time: '08:00 – 08:15', label: 'Awa D.', booked: true),
          SizedBox(height: 8),
          _AgendaRow(time: '08:15 – 08:30', label: 'M. Sarr', booked: true),
          SizedBox(height: 8),
          _AgendaRow(time: '08:30 – 08:45', label: 'Disponible', booked: false),
        ],
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  final String time;
  final String label;
  final bool booked;

  const _AgendaRow({
    required this.time,
    required this.label,
    required this.booked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _dark,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: booked ? Colors.blue.shade700 : const Color(0xFF2F5E3D),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 2 · COMMENT ÇA MARCHE
// ============================================================
class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    return _ScrollableFill(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Simple pour vous, simple pour eux.',
            style: TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: _dark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
          const _Step(
            number: 1,
            title: 'Vous fixez vos horaires',
            body:
                'Une seule fois : vos plages horaires, la durée d\'un passage, '
                'le nombre de guichets.',
          ),
          const _Step(
            number: 2,
            title: 'Vos clients réservent',
            body:
                'Depuis votre QR code, dans l\'app Baxa, ou c\'est vous qui les '
                'inscrivez au guichet, depuis votre agenda Baxa.',
          ),
          const _Step(
            number: 3,
            title: 'Ils arrivent au bon moment',
            body:
                'Une notification les prévient avant leur passage. Vous les '
                'recevez au fil de la journée.',
            isLast: true,
          ),
          const SizedBox(height: 22),
          const Text(
            'CE QUE VOUS Y GAGNEZ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _greenDark,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _GainTile(
                  icon: Icons.visibility_outlined,
                  label: 'Votre journée d\'un coup d\'œil',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _GainTile(
                  icon: Icons.favorite_border_rounded,
                  label: 'Des clients qui restent',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _GainTile(
                  icon: Icons.schedule_rounded,
                  label: 'Zéro attente, zéro doute',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _GainTile(
                  icon: Icons.trending_up_rounded,
                  label: 'Un flux client optimisé',
                ),
              ),
            ],
          ),
          const Spacer(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final bool isLast;

  const _Step({
    required this.number,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _greenDark,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFFD8EADD),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GainTile extends StatelessWidget {
  final IconData icon;
  final String label;

  const _GainTile({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: _greenDark),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? _greenDark : const Color(0xFFC9D6CD),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
