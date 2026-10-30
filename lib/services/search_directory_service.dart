import 'package:cloud_firestore/cloud_firestore.dart';

/// Une structure telle que la voit la recherche client : son identifiant et
/// ses champs publics, sous les mêmes noms que dans `companies` (nom, type,
/// typeCategorie, ville, adresse, country, position, queueCount, closedNow,
/// reopenAt) + `popularity` (réservations récentes, recalculée la nuit).
class CompanySearchEntry {
  final String id;
  final Map<String, dynamic> data;

  const CompanySearchEntry(this.id, this.data);
}

/// Annuaire de recherche par pays, tenu à jour par les Cloud Functions
/// (voir functions/search_directory.js).
///
/// Remplace l'écoute de toute la collection `companies` : la page de
/// recherche lit quelques documents d'annuaire (une ligne par structure)
/// au lieu d'un document par structure.
class SearchDirectoryService {
  SearchDirectoryService._();

  static const String _collection = 'searchDirectory';

  /// Annuaire des structures sans pays renseigné : visible partout.
  static const String noCountry = '_none';

  /// Écoute en direct les structures visibles pour [countryCode] (celles du
  /// pays + celles sans pays). Pays inconnu → tous les annuaires, comme
  /// l'ancien filtre qui ne s'appliquait que si le pays était connu.
  static Stream<List<CompanySearchEntry>> watch(String? countryCode) {
    final col = FirebaseFirestore.instance.collection(_collection);
    final code = countryCode?.trim().toUpperCase();
    final Query<Map<String, dynamic>> query =
        (code == null || code.isEmpty || code == 'XX')
        ? col
        : col.where('country', whereIn: [code, noCountry]);

    return query.snapshots().map((snap) {
      final entries = <CompanySearchEntry>[];
      for (final doc in snap.docs) {
        final raw = doc.data()['entries'];
        if (raw is! Map) continue;
        raw.forEach((id, value) {
          if (value is Map) {
            entries.add(
              CompanySearchEntry(id as String, Map<String, dynamic>.from(value)),
            );
          }
        });
      }
      // Ordre stable (les égalités de score gardent toujours le même ordre).
      entries.sort((a, b) => a.id.compareTo(b.id));
      return entries;
    });
  }
}
