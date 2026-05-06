import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:baxa/page%20b-acceuil/customer/companyqueue_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SearchPage extends StatefulWidget {
  final bool openScanner;
  const SearchPage({super.key, this.openScanner = false});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // ── Palette (identique à house_page)
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _greenMid = Color(0xFFB2D3C2);
  static const Color _dark = Color(0xFF1E2D23);

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  String searchText = '';
  String? typeSelectionne;

  // Favoris
  Set<String> _favoriteIds = {};

  // Historique des recherches
  static const String _historyKey = 'search_history';
  List<String> _history = [];

  final List<String> typesEntreprises = [
    'Tous',
    'Banque',
    'Restaurant',
    'Commerce',
    'Administration',
    'Médical',
    'Autre',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadFavoriteIds();
    _loadHistory();
    if (widget.openScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openQrScanner());
    }
  }

  Future<void> _loadFavoriteIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .get();
    if (mounted) {
      setState(() {
        _favoriteIds = snap.docs.map((d) => d.id).toSet();
      });
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => searchText = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Normalisation (accents + minuscules) ──────────────────────────────────
  static String _normalize(String s) {
    const src = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
    const dst = 'aaaaaaceeeeiiiinoooooouuuuyyoeae';
    var r = s.toLowerCase();
    for (var i = 0; i < src.length; i++) {
      r = r.replaceAll(src[i], dst[i]);
    }
    return r;
  }

  // ── Distance de Levenshtein ────────────────────────────────────────────────
  static int _levenshtein(String a, String b) {
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

  // ── Score de pertinence (plus grand = meilleur) ────────────────────────────
  // Cherche dans : nom, ville, type
  double _scoreMatch(Map<String, dynamic> data, String query) {
    if (query.isEmpty) return 1.0; // tout passe
    final q = _normalize(query.trim());
    if (q.isEmpty) return 1.0;

    final nom = _normalize(data['nom'] as String? ?? '');
    final ville = _normalize(data['ville'] as String? ?? '');
    final type = _normalize(data['type'] as String? ?? '');

    double best = 0;
    for (final field in [nom, ville, type]) {
      if (field.isEmpty) continue;
      double score = 0;
      if (field == q)
        score = 5.0; // exact
      else if (field.startsWith(q))
        score = 4.0; // préfixe exact
      else if (field.split(' ').any((w) => w.startsWith(q)))
        score = 3.0; // mot commence par
      else if (field.contains(q))
        score = 2.0; // contient
      else {
        // Tolérance aux fautes — Levenshtein sur chaque mot
        for (final word in field.split(' ')) {
          if (word.length < 3) continue;
          final dist = _levenshtein(q, word);
          if (dist == 1)
            score = score < 1.5 ? 1.5 : score;
          else if (dist == 2)
            score = score < 0.8 ? 0.8 : score;
        }
        // Multi-mot : chaque mot de la query doit matcher quelque chose
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
    return best;
  }

  // ── Historique des recherches ──────────────────────────────────────────────
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _history = prefs.getStringList(_historyKey) ?? []);
    }
  }

  Future<void> _saveToHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final h = List<String>.from(_history)
      ..remove(q) // évite les doublons
      ..insert(0, q); // plus récent en premier
    if (h.length > 6) h.removeLast();
    await prefs.setStringList(_historyKey, h);
    if (mounted) setState(() => _history = h);
  }

  Future<void> _removeFromHistory(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final h = List<String>.from(_history)..remove(query);
    await prefs.setStringList(_historyKey, h);
    if (mounted) setState(() => _history = h);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) setState(() => _history = []);
  }

  void _applyHistoryQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(offset: query.length);
    setState(() => searchText = query);
  }

  Stream<QuerySnapshot> _getEntreprisesStream() {
    Query q = FirebaseFirestore.instance.collection("companies");
    if (typeSelectionne != null && typeSelectionne != 'Tous') {
      q = q.where("type", isEqualTo: typeSelectionne);
    }
    return q.snapshots();
  }

  // ── Scanner QR code ──────────────────────────────────────────────────────
  Future<void> _openQrScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _QrScannerPage(
          onScanned: (companyId, companyNom) {
            // Ferme le scanner et navigue vers la file de l'entreprise
            Navigator.pop(context); // ferme scanner
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CompanyQueuePage(
                  entrepriseId: companyId,
                  entrepriseNom: companyNom,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Appui long → bottom sheet favoris ────────────────────────────────────
  Future<void> _showFavoriteSheet(
    DocumentSnapshot doc,
    String nom,
    String? type,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final companyId = doc.id;
    final isFav = _favoriteIds.contains(companyId);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // Avatar entreprise
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_green, Color(0xFF2D5A3D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              nom,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            if (type != null)
              Text(
                type,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            const SizedBox(height: 24),

            // Bouton ajouter / retirer favori
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _toggleFavorite(
                    companyId: companyId,
                    nom: nom,
                    type: type,
                    isFav: isFav,
                  );
                },
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFav ? Colors.red.shade400 : _green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Bouton voir
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompanyQueuePage(
                        entrepriseId: companyId,
                        entrepriseNom: nom,
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: _greenMid, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Voir les files',
                  style: TextStyle(color: _dark, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFavorite({
    required String companyId,
    required String nom,
    required String? type,
    required bool isFav,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(companyId);

    try {
      if (isFav) {
        await ref.delete();
        setState(() => _favoriteIds.remove(companyId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$nom retiré des favoris'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.grey.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        await ref.set({
          'nom': nom,
          'type': type ?? '',
          'companyId': companyId,
          'addedAt': FieldValue.serverTimestamp(),
        });
        setState(() => _favoriteIds.add(companyId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$nom ajouté aux favoris ⭐'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: _green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1C2E)),
          onPressed: () => Navigator.pop(context),
        ),
        // TextField directement dans l'AppBar
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: !widget.openScanner,
          decoration: InputDecoration(
            hintText: typeSelectionne != null && typeSelectionne != 'Tous'
                ? 'Dans $typeSelectionne...'
                : 'Nom ou ville d\'une structure',
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF1A1C2E),
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          // Bouton effacer — visible si du texte est saisi
          if (searchText.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: Colors.grey.shade500,
                size: 22,
              ),
              onPressed: () {
                _searchController.clear();
                if (mounted) setState(() => searchText = '');
              },
            ),
          // Scanner QR — toujours visible à droite
          IconButton(
            onPressed: _openQrScanner,
            icon: const Icon(
              Icons.qr_code_scanner_rounded,
              color: _green,
              size: 24,
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade100, height: 1),
        ),
      ),
      body: Column(
        children: [
          // ── Indice appui long ──────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Text(
                  'Appui long sur une entreprise pour l\'ajouter aux favoris',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),

          // ── Filtres ────────────────────────────────────────────────────
          Container(
            height: 54,
            color: Colors.white,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              physics: const BouncingScrollPhysics(),
              itemCount: typesEntreprises.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final type = typesEntreprises[i];
                final isSelected =
                    typeSelectionne == type ||
                    (typeSelectionne == null && type == 'Tous');
                return FilterChip(
                  selected: isSelected,
                  label: Text(type),
                  onSelected: (_) {
                    if (mounted) {
                      setState(
                        () => typeSelectionne = type == 'Tous' ? null : type,
                      );
                    }
                  },
                  backgroundColor: Colors.white,
                  selectedColor: _greenLight,
                  labelStyle: TextStyle(
                    color: isSelected ? _green : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isSelected ? _green : Colors.grey.shade300,
                    width: isSelected ? 1.5 : 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // ── Résultats + Historique ─────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getEntreprisesStream(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _green),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.business_outlined,
                    title: 'Aucune structure',
                    subtitle: 'Aucune structure inscrite pour le moment',
                  );
                }

                // Scoring et tri par pertinence
                final docs = snapshot.data!.docs;
                final scored =
                    docs
                        .map(
                          (d) => (
                            doc: d,
                            score: _scoreMatch(
                              d.data() as Map<String, dynamic>,
                              searchText,
                            ),
                          ),
                        )
                        .where((item) => item.score > 0)
                        .toList()
                      ..sort((a, b) => b.score.compareTo(a.score));

                if (scored.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.search_off,
                    title: 'Aucun résultat',
                    subtitle:
                        'Aucune structure trouvée pour "$searchText".\n'
                        'Vérifiez l\'orthographe ou essayez un autre mot.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount:
                      scored.length +
                      (searchText.isEmpty && _history.isNotEmpty ? 1 : 0),
                  itemBuilder: (_, i) {
                    // Section historique en tête de liste (recherche vide)
                    if (searchText.isEmpty && _history.isNotEmpty && i == 0) {
                      return _buildHistorySection();
                    }
                    final offset = searchText.isEmpty && _history.isNotEmpty
                        ? 1
                        : 0;
                    final item = scored[i - offset];
                    final data = item.doc.data() as Map<String, dynamic>;
                    return Column(
                      children: [
                        _buildCompanyCard(
                          doc: item.doc,
                          nom: data['nom'] ?? 'Sans nom',
                          type: data['type'] as String?,
                          ville: data['ville'] as String?,
                        ),
                        Divider(
                          height: 1,
                          indent: 72,
                          color: Colors.grey.shade100,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Section historique des recherches ─────────────────────────────────────
  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'Recherches récentes',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1C2E),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearHistory,
                child: Text(
                  'Tout effacer',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._history.map(
          (q) => ListTile(
            dense: true,
            leading: Icon(
              Icons.history_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
            title: Text(
              q,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1A1C2E)),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: Colors.grey.shade400,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _removeFromHistory(q),
            ),
            onTap: () => _applyHistoryQuery(q),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'Toutes les structures',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C2E),
            ),
          ),
        ),
      ],
    );
  }

  // ── Carte entreprise avec appui long ─────────────────────────────────────
  Widget _buildCompanyCard({
    required DocumentSnapshot doc,
    required String nom,
    String? type,
    String? ville,
  }) {
    final isFav = _favoriteIds.contains(doc.id);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          final q = _searchController.text.trim();
          if (q.isNotEmpty) _saveToHistory(q);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CompanyQueuePage(entrepriseId: doc.id, entrepriseNom: nom),
            ),
          );
        },
        onLongPress: () => _showFavoriteSheet(doc, nom, type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar avec initiale
              Stack(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_green, Color(0xFF2D5A3D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child: Text(
                        nom.isNotEmpty ? nom[0].toUpperCase() : "?",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  // Badge favori ⭐
                  if (isFav)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: Colors.white,
                          size: 11,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 14),

              // Infos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHighlightedText(nom),
                    const SizedBox(height: 4),
                    if (type != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _greenLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          type,
                          style: const TextStyle(
                            color: _green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (ville != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 11,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              ville,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Flèche
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _greenLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  size: 13,
                  color: _green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String nom) {
    if (searchText.isEmpty ||
        !nom.toLowerCase().contains(searchText.toLowerCase())) {
      return Text(
        nom,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: _dark,
        ),
      );
    }
    final start = nom.toLowerCase().indexOf(searchText.toLowerCase());
    final end = start + searchText.length;
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: _dark,
        ),
        children: [
          TextSpan(text: nom.substring(0, start)),
          TextSpan(
            text: nom.substring(start, end),
            style: const TextStyle(
              backgroundColor: Color(0xFFFFF176),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: nom.substring(end)),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _greenLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: _greenMid),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page scanner QR ───────────────────────────────────────────────────────
class _QrScannerPage extends StatefulWidget {
  final void Function(String companyId, String companyNom) onScanned;
  const _QrScannerPage({required this.onScanned});

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  static const Color _green = Color(0xFF4B8B5E);
  // ignore: unused_field
  static const Color _dark = Color(0xFF1E2D23);

  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Extrait le companyId depuis l'URL baxa.app/company/{id}
  String? _extractCompanyId(String rawValue) {
    try {
      final uri = Uri.parse(rawValue);
      // Supporte : https://baxa.app/company/abc123
      //        ou : baxa.app/company/abc123
      final segments = uri.pathSegments;
      final idx = segments.indexOf('company');
      if (idx != -1 && idx + 1 < segments.length) {
        return segments[idx + 1];
      }
    } catch (_) {}
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    final companyId = _extractCompanyId(raw);

    if (companyId == null) {
      // QR non reconnu — affiche un message discret
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('QR code non reconnu par Baxa'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    await _controller.stop();

    try {
      // Récupère le nom de l'entreprise depuis Firestore
      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Entreprise introuvable'),
              backgroundColor: Colors.red.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          setState(() => _isProcessing = false);
          await _controller.start();
        }
        return;
      }

      final nom = (doc.data()?['nom'] as String?) ?? 'Entreprise';
      widget.onScanned(companyId, nom);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isProcessing = false);
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Caméra ────────────────────────────────────────────────────
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // ── Overlay sombre avec fenêtre de scan ───────────────────────
          _buildScanOverlay(),

          // ── Header ────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      // Bouton retour
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha:0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),

                      const Spacer(),

                      Text(
                        'Scanner un QR code',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),

                      const Spacer(),

                      // Bouton torche
                      GestureDetector(
                        onTap: () async {
                          await _controller.toggleTorch();
                          setState(() => _torchOn = !_torchOn);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _torchOn
                                ? _green.withValues(alpha:0.8)
                                : Colors.black.withValues(alpha:0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _torchOn
                                ? Icons.flashlight_on_rounded
                                : Icons.flashlight_off_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Instructions en bas ────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha:0.85), Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  if (_isProcessing)
                    Column(
                      children: [
                        const CircularProgressIndicator(color: _green),
                        const SizedBox(height: 12),
                        Text(
                          'Chargement de l\'entreprise...',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _green.withValues(alpha:0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.qr_code_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Pointez vers le QR code Baxa',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Le scan est automatique',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha:0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Overlay avec fenêtre de scan transparente ─────────────────────────────
  Widget _buildScanOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth * 0.65;
        final top = (constraints.maxHeight - size) / 2 - 40;
        final left = (constraints.maxWidth - size) / 2;

        return Stack(
          children: [
            // Fond sombre
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha:0.55),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: left,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Coins verts du cadre de scan
            Positioned(
              top: top - 2,
              left: left - 2,
              child: _buildCorners(size + 4),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCorners(double size) {
    const double cornerLen = 24;
    const double cornerWidth = 3.5;
    const color = _green;
    const radius = Radius.circular(4);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Top-left
          Positioned(
            top: 0,
            left: 0,
            child: _corner(
              cornerLen,
              cornerWidth,
              color,
              radius,
              topLeft: true,
            ),
          ),
          // Top-right
          Positioned(
            top: 0,
            right: 0,
            child: _corner(
              cornerLen,
              cornerWidth,
              color,
              radius,
              topRight: true,
            ),
          ),
          // Bottom-left
          Positioned(
            bottom: 0,
            left: 0,
            child: _corner(
              cornerLen,
              cornerWidth,
              color,
              radius,
              bottomLeft: true,
            ),
          ),
          // Bottom-right
          Positioned(
            bottom: 0,
            right: 0,
            child: _corner(
              cornerLen,
              cornerWidth,
              color,
              radius,
              bottomRight: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner(
    double len,
    double w,
    Color color,
    Radius r, {
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return CustomPaint(
      size: Size(len, len),
      painter: _CornerPainter(
        color: color,
        strokeWidth: w,
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
      ),
    );
  }
}

// ── Peintre des coins du cadre ────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool topLeft, topRight, bottomLeft, bottomRight;

  _CornerPainter({
    required this.color,
    required this.strokeWidth,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    if (topLeft) {
      canvas.drawLine(Offset(0, h), Offset(0, 0), paint);
      canvas.drawLine(Offset(0, 0), Offset(w, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(0, 0), Offset(w, 0), paint);
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(Offset(0, 0), Offset(0, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    }
    if (bottomRight) {
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
