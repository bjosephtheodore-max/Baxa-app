part of 'search_page.dart';

// ── Logique de recherche : normalisation, score, proximité ────────────────
extension _SearchScoring on _SearchPageState {
  String _normalize(String s) {
    const src = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
    const dst = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    var r = s.toLowerCase();
    for (var i = 0; i < src.length; i++) {
      r = r.replaceAll(src[i], dst[i]);
    }
    return r;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final curr = [i + 1, ...List<int>.filled(b.length, 0)];
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        curr[j + 1] = [
          prev[j + 1] + 1,
          curr[j] + 1,
          prev[j] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      prev.setAll(0, curr);
    }
    return prev[b.length];
  }

  // Distance en km entre le client et une entreprise, si les deux positions
  // sont connues — null sinon (permet un affichage/scoring gracieux quand
  // la géolocalisation n'est pas disponible côté client ou entreprise).
  double? _distanceKmFor(Map<String, dynamic> data) {
    final userPos = _userPosition;
    if (userPos == null) return null;
    final pos = data['position'];
    if (pos is! GeoPoint) return null;
    return LocationService.distanceKm(
      userPos.latitude,
      userPos.longitude,
      pos.latitude,
      pos.longitude,
    );
  }

  // Petit bonus de score qui favorise les résultats proches sans jamais
  // masquer un résultat pertinent plus loin (juste un coup de pouce au tri).
  double _distanceBonusFor(Map<String, dynamic> data) {
    final km = _distanceKmFor(data);
    if (km == null) return 0;
    return (1.0 / (1.0 + km / 5)).clamp(0.0, 1.0) * 0.6;
  }

  // Score textuel enrichi par la popularité et la proximité
  double _scoreMatch(Map<String, dynamic> data, String query) {
    final reservationCount = (data['reservationCount'] as num?)?.toInt() ?? 0;
    final popularityBonus = math.log(reservationCount + 1) * 0.2;
    final distanceBonus = _distanceBonusFor(data);

    if (query.isEmpty) return 1.0 + popularityBonus + distanceBonus;
    final q = _normalize(query.trim());
    if (q.isEmpty) return 1.0 + popularityBonus + distanceBonus;

    final nom = _normalize(data['nom'] as String? ?? '');
    final ville = _normalize(data['ville'] as String? ?? '');
    final type = _normalize(data['type'] as String? ?? '');

    double best = 0;
    for (final field in [nom, ville, type]) {
      if (field.isEmpty) continue;
      double score = 0;
      if (field == q) {
        score = 5.0;
      } else if (field.startsWith(q)) {
        score = 4.0;
      } else if (field.split(' ').any((w) => w.startsWith(q))) {
        score = 3.0;
      } else if (field.contains(q)) {
        score = 2.0;
      } else {
        for (final word in field.split(' ')) {
          if (word.length < 3) continue;
          final dist = _levenshtein(q, word);
          if (dist == 1) {
            score = score < 1.5 ? 1.5 : score;
          } else if (dist == 2) {
            score = score < 0.8 ? 0.8 : score;
          }
        }
        final qWords = q.split(' ').where((w) => w.length >= 2).toList();
        if (qWords.length > 1) {
          final allMatch = qWords.every(
            (qw) =>
                field.contains(qw) ||
                field.split(' ').any((fw) => _levenshtein(qw, fw) <= 1),
          );
          if (allMatch) score = score < 2.5 ? 2.5 : score;
        }
      }
      if (score > best) best = score;
    }
    return best > 0 ? best + popularityBonus + distanceBonus : 0;
  }

  // Détecte si la saisie correspond à une ville connue (mot unique, ≥4 chars)
  String? _detectCity(List<DocumentSnapshot> docs, String query) {
    final q = query.trim();
    if (q.length < 4 || q.contains(' ')) return null;
    final qNorm = _normalize(q);
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ville = data['ville'] as String? ?? '';
      if (ville.isEmpty) continue;
      final villeNorm = _normalize(ville);
      if (villeNorm == qNorm || villeNorm.startsWith(qNorm)) return ville;
    }
    return null;
  }

  // ── État « recherche » d'une structure (champs dénormalisés maintenus
  //    par les Cloud Functions). Champ absent = ancienne structure → on la
  //    considère comme normale (rétro-compatibilité).
  bool _companyHasNoQueue(Map<String, dynamic> data) => data['queueCount'] == 0;

  bool _companyClosedNow(Map<String, dynamic> data) =>
      data['closedNow'] == true;

  DateTime? _companyReopenAt(Map<String, dynamic> data) =>
      (data['reopenAt'] as Timestamp?)?.toDate();

  // Pénalité de tri appliquée aux résultats de recherche : les structures
  // ouvertes avec au moins une file remontent, les fermées / sans file
  // sont doucement rétrogradées (sans jamais masquer une correspondance
  // exacte de nom).
  double _searchStatePenalty(Map<String, dynamic> data) {
    if (_companyHasNoQueue(data)) return 1.0;
    if (_companyClosedNow(data)) return 0.5;
    return 0;
  }

  // Popularité + diversification par type — les entreprises dont la
  // position est connue et proche du client passent en premier.
  // Exclut les structures sans file et les structures fermées : elles ne
  // doivent pas encombrer les recommandations (mais restent trouvables
  // par une recherche explicite).
  List<DocumentSnapshot> _getDiversePopular(
    List<DocumentSnapshot> allDocs,
    Set<String> excludeIds,
    int count,
  ) {
    if (count <= 0) return [];
    final candidates = allDocs.where((d) {
      if (excludeIds.contains(d.id)) return false;
      final data = d.data() as Map<String, dynamic>;
      if (_companyHasNoQueue(data)) return false;
      if (_companyClosedNow(data)) return false;
      return true;
    }).toList();

    candidates.sort((a, b) {
      final da = a.data() as Map<String, dynamic>;
      final db = b.data() as Map<String, dynamic>;

      final distA = _distanceKmFor(da);
      final distB = _distanceKmFor(db);
      if (distA != null && distB != null) return distA.compareTo(distB);
      if (distA != null) return -1;
      if (distB != null) return 1;

      final ra = (da['reservationCount'] as num?)?.toInt() ?? 0;
      final rb = (db['reservationCount'] as num?)?.toInt() ?? 0;
      return rb.compareTo(ra);
    });

    if (candidates.length <= count) return candidates;

    // Grouper par type (ordre = tri ci-dessus conservé dans chaque groupe)
    final Map<String, List<DocumentSnapshot>> byType = {};
    for (final doc in candidates) {
      final type =
          (doc.data() as Map<String, dynamic>)['type'] as String? ?? 'Autre';
      byType.putIfAbsent(type, () => []).add(doc);
    }

    // Round-robin : 1 par type à tour de rôle
    final result = <DocumentSnapshot>[];
    while (result.length < count) {
      bool anyLeft = false;
      for (final list in byType.values) {
        if (result.length >= count) break;
        if (list.isNotEmpty) {
          result.add(list.removeAt(0));
          anyLeft = true;
        }
      }
      if (!anyLeft) break;
    }
    return result;
  }

  Stream<QuerySnapshot> _getEntreprisesStream() {
    Query q = FirebaseFirestore.instance.collection("companies");
    if (typeSelectionne != null && typeSelectionne != 'Tous') {
      if (typeSelectionne == 'Autre') {
        q = q.where("typeCategorie", isEqualTo: 'Autre');
      } else {
        q = q.where("type", isEqualTo: typeSelectionne);
      }
    }
    return q.snapshots();
  }
}
