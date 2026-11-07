import 'package:flutter/material.dart';

/// Message en bas de l'écran après l'ajout (ou le retrait) d'une structure
/// des favoris. UN seul style pour toute l'app client (recherche, invite
/// après réservation).
///
/// Remplace le message en cours au lieu d'attendre derrière lui : après une
/// réservation, « Réservation confirmée ! » est encore affiché quand le
/// client ajoute le favori — la confirmation arrivait alors plusieurs
/// secondes plus tard, souvent après le retour à l'écran précédent.
void showFavoriteSnackBar(
  ScaffoldMessengerState messenger, {
  required String nom,
  required bool added,
  Color addedColor = const Color(0xFF4B8B5E),
}) {
  final who = nom.trim().isEmpty ? 'La structure' : nom.trim();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              added ? Icons.star_rounded : Icons.star_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                added
                    ? '$who est maintenant dans vos favoris'
                    : '$who n\'est plus dans vos favoris',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: added ? addedColor : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
}
