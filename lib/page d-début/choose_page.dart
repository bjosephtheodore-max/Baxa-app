import 'package:baxa/page%20b-acceuil/company/prereception_page.dart';
import 'package:baxa/page%20b-acceuil/customer/prereceptione_page.dart';
import 'package:baxa/page b-acceuil/company/staff_auth_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

class ChoosePage extends StatefulWidget {
  const ChoosePage({super.key});

  @override
  State<ChoosePage> createState() => _ChoosePageState();
}

class _ChoosePageState extends State<ChoosePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _card1Fade;
  late final Animation<Offset> _card1Slide;
  late final Animation<double> _card2Fade;
  late final Animation<Offset> _card2Slide;
  late final Animation<double> _staffFade;

  int? _pressedIndex;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _titleFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _titleSlide = Tween(begin: const Offset(0, -0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _card1Fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.3, 0.65, curve: Curves.easeOut),
    );
    _card1Slide = Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.3, 0.65, curve: Curves.easeOut),
      ),
    );

    _card2Fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.45, 0.80, curve: Curves.easeOut),
    );
    _card2Slide = Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.45, 0.80, curve: Curves.easeOut),
      ),
    );

    _staffFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.72, 1.0, curve: Curves.easeOut),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFEAF3ED),
              Color(0xFFD6EBDe),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.10,
                child: Lottie.asset(
                  'assets/animations/City Skyline Building.json',
                  fit: BoxFit.cover,
                  repeat: true,
                ),
              ),
            ),
            SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Titre animé
                FadeTransition(
                  opacity: _titleFade,
                  child: SlideTransition(
                    position: _titleSlide,
                    child: Column(
                      children: [
                        Text(
                          'Bienvenue sur Baxa',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.pacifico(
                            fontSize: (width * 0.08).clamp(24.0, 36.0),
                            color: Colors.black87,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Qui êtes-vous ?',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Cartes animées
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: _card1Fade,
                        child: SlideTransition(
                          position: _card1Slide,
                          child: _buildChoiceCard(
                            index: 0,
                            context: context,
                            emoji: '🏢',
                            title: 'Je suis une Structure',
                            subtitle: 'Gérer mes files d\'attente',
                            color: const Color(0xFF4B8B5E),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrereceptionPage(),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      FadeTransition(
                        opacity: _card2Fade,
                        child: SlideTransition(
                          position: _card2Slide,
                          child: _buildChoiceCard(
                            index: 1,
                            context: context,
                            emoji: '👤',
                            title: 'Je suis un Client',
                            subtitle: 'Réserver ma place sans attendre',
                            color: const Color(0xFF34A853),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrereceptionePage(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Lien staff animé
                FadeTransition(
                  opacity: _staffFade,
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StaffAuthPage(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          const Text(
                            'Vous avez un code d\'invitation ?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black45,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Rejoindre une équipe →',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF4B8B5E),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
            ),  // SafeArea
          ],  // Stack children
        ),  // Stack
      ),
    );
  }

  Widget _buildChoiceCard({
    required int index,
    required BuildContext context,
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final pressed = _pressedIndex == index;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressedIndex = index),
      onTapUp: (_) {
        setState(() => _pressedIndex = null);
        onTap();
      },
      onTapCancel: () => setState(() => _pressedIndex = null),
      child: AnimatedScale(
        scale: pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: pressed ? 0.04 : 0.08),
                blurRadius: pressed ? 6 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 40)),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
