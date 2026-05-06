import 'package:baxa/page%20b-acceuil/company/prereception_page.dart';
import 'package:baxa/page%20b-acceuil/customer/prereceptione_page.dart';
import 'package:baxa/page b-acceuil/company/staff_auth_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChoosePage extends StatelessWidget {
  const ChoosePage({super.key});

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
              Color(0xFFFFFFFF), // blanc pur en haut
              Color(0xFFEAF3ED), // vert très doux au milieu
              Color(0xFFD6EBDe), // vert légèrement plus présent en bas
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Titre principal
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

                const SizedBox(height: 40),

                // Cartes de choix
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildChoiceCard(
                        context: context,
                        icon: Icons.business,
                        emoji: '🏢',
                        title: 'Je suis une Structure',
                        subtitle: 'Gérer mes files d\'attente',
                        color: const Color.fromARGB(255, 75, 139, 94),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrereceptionPage(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      _buildChoiceCard(
                        context: context,
                        icon: Icons.person,
                        emoji: '👤',
                        title: 'Je suis un Client',
                        subtitle: 'Réserver ma place sans attendre',
                        color: const Color.fromARGB(255, 52, 168, 83),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrereceptionePage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Lien staff discret en bas
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StaffAuthPage(),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                        ),
                        children: [
                          const TextSpan(text: 'Vous avez un code d\'invitation ? '),
                          TextSpan(
                            text: 'Rejoindre une equipe',
                            style: TextStyle(
                              color: Color(0xFF4B8B5E),
                              fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }

  Widget _buildChoiceCard({
    required BuildContext context,
    required IconData icon,
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icône/Emoji à gauche
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 40)),
            ),

            const SizedBox(width: 20),

            // Texte
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

            // Flèche à droite
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
