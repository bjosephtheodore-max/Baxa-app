import 'package:flutter/material.dart';
import 'package:baxa/page%20b-acceuil/company/prereception_page.dart';
import 'package:baxa/page%20b-acceuil/customer/prereceptione_page.dart';
import 'package:google_fonts/google_fonts.dart';

class ChoosePage extends StatelessWidget {
  const ChoosePage({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color.fromARGB(
      255,
      190,
      248,
      197,
    ); // même couleur que prereception_page
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // court texte explicatif
              Text(
                'Structure = gérer les files\nPersonne = rejoindre une file',
                textAlign: TextAlign.center,
                style: GoogleFonts.pacifico(
                  fontSize: (width * 0.07).clamp(20.0, 30.0),
                  color: Colors.black87,
                  fontWeight: FontWeight.w400,
                ),
              ),

              // espace pour pousser les boutons vers le bas (esthétique similaire)
              const Spacer(),

              // boutons bas, style inspiré de prereception_page
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Flexible(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrereceptionPage(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 18,
                          ),
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                        child: const Text('Structure'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrereceptionePage(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 18,
                          ),
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                        child: const Text('Personne'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
