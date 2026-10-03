import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:baxa/services/profession_constants.dart';

const Color _green = Color(0xFF4B8B5E);

/// Bottom sheet de sélection de profession — liste fermée à un seul tap,
/// "Autre" inclus comme valeur fixe (jamais de champ texte derrière).
/// Retourne la catégorie choisie, ou `null` si l'utilisateur a passé/fermé
/// la sheet sans choisir.
Future<String?> showProfessionPickerSheet(
  BuildContext context, {
  String? current,
  bool showSkip = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ProfessionPickerSheet(current: current, showSkip: showSkip),
  );
}

class _ProfessionPickerSheet extends StatelessWidget {
  final String? current;
  final bool showSkip;

  const _ProfessionPickerSheet({this.current, required this.showSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Quelle est votre profession ?',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ça nous aide à mieux adapter Baxa à votre métier.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kProfessionCategories.map((category) {
                final selected = category == current;
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(context, category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? _green : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? _green : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (showSkip) ...[
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Passer',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
