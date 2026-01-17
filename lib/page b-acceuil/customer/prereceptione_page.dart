import 'package:baxa/page%20b-acceuil/customer/signine_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PrereceptionePage extends StatelessWidget {
  const PrereceptionePage({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final titleSize = (w * 0.07).clamp(18.0, 28.0);
    const bg = Color.fromARGB(255, 190, 248, 197); // bleu ciel identique

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // espace haut pour esthétique
            const SizedBox(height: 28),
            // titre centré, taille responsive
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "Gagnez du temps en rejoignant une file virtuelle",
                textAlign: TextAlign.center,
                style: GoogleFonts.pacifico(
                  fontSize: titleSize,
                  color: Colors.black87,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            // occupe l'espace restant pour pousser le bouton en bas
            const Spacer(),
            // bouton toujours visible à l'intérieur du fond
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SigninePage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Commencer',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
