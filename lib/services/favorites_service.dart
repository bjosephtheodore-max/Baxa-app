import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ════════════════════════════════════════════════════════════════════
// Écriture partagée du favori — utilisée à la fois par le geste d'appui
// long (search_page) et par la proposition après 3 réservations
// (slots_page), pour que les deux ne puissent plus diverger comme avant
// (l'un avait le repli « inscription requise », l'autre avalait les
// erreurs en silence).
// ════════════════════════════════════════════════════════════════════
class FavoritesService {
  /// Ajoute [companyId] aux favoris de l'utilisateur connecté.
  /// Lève une exception si l'utilisateur n'est pas connecté ou si
  /// l'écriture échoue — à l'appelant de l'attraper et d'informer l'user.
  static Future<void> addFavorite({
    required String companyId,
    required String nom,
    String? type,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(companyId)
        .set({
          'nom': nom,
          'type': type ?? '',
          'companyId': companyId,
          'addedAt': FieldValue.serverTimestamp(),
        });
  }
}
