part of 'search_page.dart';

// ── Dialogs & bottom sheets ─────────────────────────────────────────────────
extension _SearchDialogs on _SearchPageState {
  // ── Favoris bottom sheet ──────────────────────────────────────────────────
  Future<void> _showFavoriteSheet(
    DocumentSnapshot doc,
    String nom,
    String? type,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final companyId = doc.id;
    final isFav = _favoriteIds.contains(companyId);
    final data = doc.data() as Map<String, dynamic>;
    final ville = data['ville'] as String?;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          32 + MediaQuery.of(ctx).padding.bottom,
        ),
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Bloquer la restauration du focus sur le TextField
                  // pour éviter que le clavier remonte lors de la fermeture du sheet
                  _searchFocusNode.canRequestFocus = false;
                  Navigator.pop(ctx);
                  if (!isFav) {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null && user.isAnonymous) {
                      _pendingFavoriteId = companyId;
                      _pendingFavoriteName = nom;
                      _pendingFavoriteType = type;
                      _showRegistrationNeededSheet();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _searchFocusNode.canRequestFocus = true;
                      });
                      return;
                    }
                  }
                  _searchFocusNode.canRequestFocus = true;
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _navigateToCompany(companyId, nom);
                  if (mounted) {
                    _recordVisit(
                      companyId: companyId,
                      nom: nom,
                      type: type,
                      ville: ville,
                    );
                  }
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
                  style: TextStyle(
                    color: _dark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widget C (search_page) : inscription requise — dialog centré ────────
  void _showRegistrationNeededSheet() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: _greenLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: _green,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Terminez votre inscription',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _dark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Pour ajouter des favoris et réserver depuis votre page d\'accueil, créez votre compte gratuit en deux clics.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SigninePage(),
                      ),
                    );
                    if (!mounted) return;
                    _searchFocusNode.canRequestFocus = true;
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null &&
                        !user.isAnonymous &&
                        _pendingFavoriteId != null) {
                      final id = _pendingFavoriteId!;
                      final name = _pendingFavoriteName ?? '';
                      final type = _pendingFavoriteType;
                      _pendingFavoriteId = null;
                      _pendingFavoriteName = null;
                      _pendingFavoriteType = null;
                      await _toggleFavorite(
                        companyId: id,
                        nom: name,
                        type: type,
                        isFav: false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Terminer l\'inscription',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  _pendingFavoriteId = null;
                  _pendingFavoriteName = null;
                  _pendingFavoriteType = null;
                  Navigator.pop(ctx);
                },
                child: Text(
                  'Plus tard',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget E : proposition d'activer la localisation ─────────────────────
  // Déclenché à la première recherche effectuée sans position connue.
  // Affiché au maximum 2 fois à vie (par compte, ou par appareil pour un
  // client anonyme) pour ne jamais devenir intrusif.
  Future<void> _maybeShowLocationPrompt() async {
    final permission = await _locationService.checkPermission();
    // Déjà accordée, refusée définitivement, ou statut indéterminable :
    // dans tous ces cas il n'y a rien à proposer ici.
    if (permission != LocationPermission.denied) return;

    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final key = '$_locationPromptCountKeyPrefix$uid';
    final shownCount = prefs.getInt(key) ?? 0;
    if (shownCount >= 2) return;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          32 + MediaQuery.of(ctx).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: _greenLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.my_location_rounded,
                color: _green,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Trouvez les structures près de vous',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Activez votre position pour faciliter vos recherches : '
              'Baxa vous montrera en priorité les structures les plus proches de vous.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final granted = await _locationService.requestPermission();
                  if ((granted == LocationPermission.always ||
                          granted == LocationPermission.whileInUse)) {
                    final pos = await _locationService.getCurrentPosition();
                    if (pos != null) _setUserPosition(pos);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Activer ma position',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Plus tard',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );

    await prefs.setInt(key, shownCount + 1);
  }
}
