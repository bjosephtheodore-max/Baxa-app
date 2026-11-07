import 'package:baxa/services/password_rules.dart';
import 'package:flutter/material.dart';

/// Les critères du mot de passe, cochés en vert au fil de la frappe, sous le
/// champ. On voit où l'on en est : pas de refus surprise au moment de
/// valider. À utiliser quand un mot de passe est CHOISI (inscription,
/// changement), jamais à la connexion.
class PasswordChecklist extends StatelessWidget {
  final TextEditingController controller;

  /// Couleur des critères remplis (vert de l'écran qui l'affiche).
  final Color okColor;

  const PasswordChecklist({
    super.key,
    required this.controller,
    this.okColor = const Color(0xFF2F5E3D),
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, _) {
        final criteria = passwordCriteria(value.text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in criteria)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      c.ok
                          ? Icons.check_circle_outline_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: c.ok ? okColor : const Color(0xFF5F6B63),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: c.ok ? okColor : const Color(0xFF5F6B63),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
