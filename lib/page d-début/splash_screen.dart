import 'dart:async';

import 'package:flutter/material.dart';
import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Écran de chargement Flutter affiché dès la 1ère frame (le splash natif se
/// retire à ce moment-là, voir main). Logo animé + "Chargement..." tant que
/// l'init strictement nécessaire (formats de date, fuseau horaire) n'est pas
/// terminée, puis bascule immédiate vers ChoosePage.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _logoSlide;

  Timer? _dotsTimer;
  int _dotsCount = 0;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoOpacity = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut));
    _logoCtrl.forward();

    // ── Points qui s'enchaînent : "Chargement" → "." → ".." → "..." ────────
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() => _dotsCount = (_dotsCount + 1) % 4);
    });

    _loadApp();
  }

  Future<void> _loadApp() async {
    // ── Init strictement nécessaire au premier écran : formats de date FR et
    //    fuseau horaire. Les notifications sont initialisées après la 1ère
    //    frame (voir main._initDeferredServices). Chaque tâche est isolée :
    //    un échec ne bloque jamais le démarrage. ─────────────────────────────
    await Future.wait([
      _safe(() => initializeDateFormatting('fr_FR', null)),
      _safe(_initTimezone),
    ]);

    if (!mounted) return;
    _navigateToApp();
  }

  Future<void> _safe(Future<void> Function() task) async {
    try {
      await task();
    } catch (e, st) {
      debugPrint('Erreur init splash: $e\n$st');
    }
  }

  Future<void> _initTimezone() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.local);
  }

  void _navigateToApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ChoosePage(),
        transitionDuration: Duration.zero, // bascule sèche, ChoosePage s'anime
        barrierColor: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _dotsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Taille du texte adaptée à la largeur de l'écran
    final fontSize = (size.width * 0.22).clamp(60.0, 110.0);
    final dots = '.' * _dotsCount;

    return Scaffold(
      body: Container(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
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
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 130,
                    child: Text(
                      'Chargement$dots',
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
