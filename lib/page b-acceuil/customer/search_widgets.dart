part of 'search_page.dart';

String _formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

// ── Widgets présentationnels ─────────────────────────────────────────────────
extension _SearchWidgets on _SearchPageState {
  Widget _buildQrInvitationCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openQrScanner,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_green, Color(0xFF2D5A3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan rapide',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Scannez le QR code de votre structure\npour réserver en 2 clics',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Carte suggestion de ville ─────────────────────────────────────────────
  Widget _buildCitySuggestionCard(String city) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _setSearchText(city),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _greenLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.place_rounded, color: _green, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Voir les structures à $city',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _dark,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Animation staggered ───────────────────────────────────────────────────
  Widget _buildAnimatedCard(Widget child, int index, {String? uniqueKey}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(uniqueKey ?? index),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: (160 + index * 22).clamp(0, 420)),
      curve: Curves.easeOut,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  // ── Skeleton loading ──────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (_, i) => _buildSkeletonItem(),
    );
  }

  Widget _buildSkeletonItem() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _shimmerBox(54, 54, radius: 13),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBox(14, double.infinity),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _shimmerBox(20, 64, radius: 8),
                    const SizedBox(width: 8),
                    _shimmerBox(10, 90, radius: 4),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _shimmerBox(28, 28, radius: 14),
        ],
      ),
    );
  }

  Widget _shimmerBox(double height, double? width, {double radius = 8}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ── Carte entreprise ──────────────────────────────────────────────────────
  Widget _buildCompanyCard({
    required DocumentSnapshot doc,
    required String nom,
    String? type,
    String? ville,
    bool isHistory = false,
  }) {
    final isFav = _favoriteIds.contains(doc.id);
    final data = doc.data() as Map<String, dynamic>;
    final distKm = _distanceKmFor(data);
    final adresse = data['adresse'] as String?;
    // La distance s'affiche à côté du type (jamais avec la ville, pour ne
    // pas surcharger une seule ligne). L'adresse, quand l'entreprise l'a
    // renseignée, prend la place de la ville en dessous — plus utile pour
    // se repérer, en particulier si plusieurs structures portent le même nom.
    final showAdresseLine = adresse != null && adresse.isNotEmpty;
    final showDistanceOnTypeLine = distKm != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            HapticFeedback.lightImpact();
            await _navigateToCompany(doc.id, nom);
            if (mounted) {
              _recordVisit(
                companyId: doc.id,
                nom: nom,
                type: type,
                ville: ville,
              );
            }
          },
          onLongPress: () => _showFavoriteSheet(doc, nom, type),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nom,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: _dark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (type != null || showDistanceOnTypeLine)
                        Row(
                          children: [
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
                            if (showDistanceOnTypeLine) ...[
                              if (type != null) const SizedBox(width: 6),
                              const Icon(
                                Icons.near_me_rounded,
                                size: 11,
                                color: _green,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'à ${_formatDistance(distKm)}',
                                style: const TextStyle(
                                  color: _green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      if (showAdresseLine) ...[
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
                                adresse,
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
                      ] else if (ville != null) ...[
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
                      _buildCompanyStatusPill(data),
                    ],
                  ),
                ),

                // Trailing : horloge pour historique, flèche pour les autres
                if (isHistory)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.history_rounded,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
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
      ),
    );
  }

  // Mention d'état sous le nom : « Rouvre le … » / « Fermé pour l'instant » /
  // « Pas encore de file ». Rien si la structure est ouverte et a des files.
  Widget _buildCompanyStatusPill(Map<String, dynamic> data) {
    String label;
    Color fg;
    Color bg;

    if (_companyClosedNow(data)) {
      final reopen = _companyReopenAt(data);
      if (reopen != null) {
        label =
            'Rouvre le ${reopen.day.toString().padLeft(2, '0')}/${reopen.month.toString().padLeft(2, '0')}';
        fg = Colors.red.shade600;
        bg = Colors.red.shade50;
      } else {
        label = 'Fermé pour l\'instant';
        fg = Colors.grey.shade600;
        bg = Colors.grey.shade100;
      }
    } else if (_companyHasNoQueue(data)) {
      label = 'Pas encore de file';
      fg = Colors.grey.shade600;
      bg = Colors.grey.shade100;
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
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
              child: Icon(icon, size: 56, color: _green),
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
