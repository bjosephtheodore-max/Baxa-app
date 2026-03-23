import 'package:flutter/material.dart';
import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';

/// Splash screen Flutter — net, animé, transition fade vers ChoosePage
/// Remplace le splash Android natif qui pixellise
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // Animation logo : fade in + légère montée
  late Animation<double> _logoOpacity;
  late Animation<Offset> _logoSlide;

  // Animation de sortie : fade out vers ChoosePage
  late Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // ── Logo entre en scène (0% → 45% de la durée) ──────────────────────
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
          ),
        );

    // ── Fade out de tout le splash (75% → 100%) ──────────────────────────
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.75, 1.0, curve: Curves.easeIn),
      ),
    );

    // Lancer l'animation puis naviguer
    _ctrl.forward().then((_) => _navigateToApp());
  }

  void _navigateToApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ChoosePage(),
        transitionDuration: Duration.zero, // fade déjà fait par le splash
        barrierColor: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Taille du texte adaptée à la largeur de l'écran
    final fontSize = (size.width * 0.22).clamp(60.0, 110.0);

    return Scaffold(
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return FadeTransition(
            opacity: _exitOpacity,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              // ── Fond blanc avec dégradé doux ───────────────────────────
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFFFFF), // blanc pur
                    Color(0xFFF2FAF5), // blanc légèrement teinté vert
                    Color(0xFFE6F4EC), // vert très très doux
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: Center(
                child: FadeTransition(
                  opacity: _logoOpacity,
                  child: SlideTransition(
                    position: _logoSlide,
                    child: ShaderMask(
                      // ── Dégradé vert sur le texte Baxa ─────────────────
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF00C853), // vert vif
                          Color(0xFF00BFA5), // vert-turquoise
                          Color(0xFF1DE9B6), // vert clair lumineux
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ).createShader(bounds),
                      blendMode: BlendMode.srcIn,
                      child: Text(
                        'Baxa',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                          height: 1.0,
                          // Couleur ignorée — ShaderMask applique le dégradé
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
