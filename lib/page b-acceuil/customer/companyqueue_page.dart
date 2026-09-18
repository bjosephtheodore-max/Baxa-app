import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:baxa/page%20b-acceuil/customer/my_reservations_page.dart';
import 'package:baxa/page%20b-acceuil/customer/slots_page.dart';
import 'package:baxa/services/booking_constants.dart';

// ============================================================================
// PAGE PRINCIPALE : Liste des files d'attente
// ============================================================================

class CompanyQueuePage extends StatefulWidget {
  final String entrepriseId;
  final String entrepriseNom;

  const CompanyQueuePage({
    super.key,
    required this.entrepriseId,
    required this.entrepriseNom,
  });

  @override
  State<CompanyQueuePage> createState() => _CompanyQueuePageState();
}

class _CompanyQueuePageState extends State<CompanyQueuePage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static const Color _primaryGreen = Color(0xFF4B8B5E);
  static const Color _lightGreen = Color(0xFFB2D3C2);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _darkGreen = Color(0xFF2D5A3D);
  static const Color _dark = Color(0xFF1E2D23);

  String? _selectedQueueId;
  int _activeReservationsCount = 0;
  Map<String, dynamic>? _companyData;

  late final Stream<QuerySnapshot> _queuesStream;

  @override
  void initState() {
    super.initState();
    // Créé une seule fois : ne dépend que de widget.entrepriseId (fixe),
    // pour éviter que StreamBuilder ne se réabonne à chaque setState.
    _queuesStream = _fs
        .collection('companies')
        .doc(widget.entrepriseId)
        .collection('queues')
        .orderBy('createdAt')
        .snapshots();
    _loadActiveReservationsCount();
    _loadCompanyData();
  }

  Future<void> _loadCompanyData() async {
    try {
      final doc = await _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .get();
      if (doc.exists && mounted) {
        setState(() => _companyData = doc.data());
      }
    } catch (_) {}
  }

  Future<void> _loadActiveReservationsCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _fs
          .collectionGroup('reservations')
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'confirmed')
          .get();

      final now = DateTime.now();
      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final slotStart = (data['slotStart'] as Timestamp).toDate();
        if (slotStart.isAfter(now)) count++;
      }

      setState(() => _activeReservationsCount = count);
    } catch (e) {
      debugPrint('Erreur chargement réservations: $e');
    }
  }

  void _shareCompany() {
    final nom = widget.entrepriseNom;
    final id = widget.entrepriseId;
    final link = 'https://baxa.app/company/$id';

    Share.share(
      '📍 $nom\n'
      'Réserve ta place sans attendre !\n'
      '👉 $link',
      subject: 'Réserve chez $nom sur Baxa',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_companyData?['status'] == 'deleted') {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F8FA),
        appBar: _buildAppBar(),
        body: _buildUnavailableState(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _buildAppBar(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _queuesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _primaryGreen),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final queues = snapshot.data!.docs;

          // Fermeture au niveau structure = TOUTES les files fermées (ou
          // toutes planifiées pour fermeture). Les fermetures partielles
          // s'affichent file par file dans les cartes.
          final now = DateTime.now();
          int closedNow = 0;
          int closedOrPlanned = 0;
          DateTime? earliestStart;
          DateTime? latestEnd; // null si au moins une fermeture indéterminée
          bool anyIndeterminate = false;
          for (final q in queues) {
            final d = q.data() as Map<String, dynamic>;
            final cs = (d['closureStart'] as Timestamp?)?.toDate();
            final ce = (d['closureEnd'] as Timestamp?)?.toDate();
            if (cs == null) continue;
            if (isQueueClosedNow(cs, ce, now: now)) {
              closedNow++;
              closedOrPlanned++;
            } else if (now.isBefore(cs)) {
              closedOrPlanned++;
            } else {
              continue; // fermeture passée
            }
            if (earliestStart == null || cs.isBefore(earliestStart)) {
              earliestStart = cs;
            }
            if (ce == null) {
              anyIndeterminate = true;
            } else if (latestEnd == null || ce.isAfter(latestEnd)) {
              latestEnd = ce;
            }
          }
          final total = queues.length;
          final isCompanyClosed = total > 0 && closedNow == total;
          final isUpcomingClosure =
              total > 0 && closedOrPlanned == total && !isCompanyClosed;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroHeader(),
                if (isCompanyClosed || isUpcomingClosure) ...[
                  const SizedBox(height: 16),
                  _buildClosureBanner(
                    earliestStart,
                    anyIndeterminate ? null : latestEnd,
                    isActive: isCompanyClosed,
                  ),
                ],
                const SizedBox(height: 28),
                _buildSectionTitle('Files d\'attente', queues.length),
                const SizedBox(height: 12),
                ...queues.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final queueDoc = entry.value;
                  final queueData = queueDoc.data() as Map<String, dynamic>;
                  return _buildAnimatedCard(
                    _buildQueueCard(
                      index: idx,
                      queueId: queueDoc.id,
                      queueName: queueData['name'] ?? 'File',
                      queueData: queueData,
                      isCompanyClosed: isCompanyClosed,
                    ),
                    idx,
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Color(0xFF1A1C2E)),
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reserver',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            widget.entrepriseNom,
            style: GoogleFonts.poppins(
              color: _dark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: Colors.grey.shade100, height: 1),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.share_rounded, color: Colors.grey.shade600),
          tooltip: 'Partager',
          onPressed: _shareCompany,
        ),
        // Le badge est posé DANS l'icône (pas autour du bouton) : le
        // IconButton reste un bouton Material tout simple, avec la même
        // zone de toucher et le même effet d'appui que celui de partage —
        // l'ancien `Stack` qui enveloppait le bouton lui-même perturbait
        // son toucher sur certains appareils.
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.event_note_rounded, color: Colors.grey.shade600),
              if (_activeReservationsCount > 0)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade500,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _activeReservationsCount > 9
                          ? '9+'
                          : '$_activeReservationsCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          tooltip: 'Mes reservations',
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MyReservationsPage(),
              ),
            );
            if (result == true || result == null) {
              _loadActiveReservationsCount();
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHeroHeader() {
    final initial = widget.entrepriseNom.isNotEmpty
        ? widget.entrepriseNom[0].toUpperCase()
        : '?';
    final adresse = (_companyData?['adresse'] as String?)?.isNotEmpty == true
        ? _companyData!['adresse'] as String
        : _companyData?['ville'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryGreen, _darkGreen],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primaryGreen.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choisissez votre service',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sélectionnez une file d\'attente ci-dessous',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (adresse != null && adresse.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          adresse,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _dark,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _greenLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: _primaryGreen,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedCard(Widget child, int index) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(index),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: (160 + index * 40).clamp(0, 420)),
      curve: Curves.easeOut,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  Widget _buildQueueCard({
    required int index,
    required String queueId,
    required String queueName,
    required Map<String, dynamic> queueData,
    bool isCompanyClosed = false,
  }) {
    final closureStart = (queueData['closureStart'] as Timestamp?)?.toDate();
    final closureEnd = (queueData['closureEnd'] as Timestamp?)?.toDate();
    final isQueueClosed = isQueueClosedNow(closureStart, closureEnd);
    final cutoffTs = queueData['reservationCutoffDate'] as Timestamp?;
    final cutoffDate = cutoffTs?.toDate().toLocal();
    final hasCutoff = cutoffDate != null;
    final isUnavailable = isQueueClosed || isCompanyClosed;
    final isSelected = _selectedQueueId == queueId && !isUnavailable;

    String subtitle;
    Color subtitleColor;
    IconData subtitleIcon;
    if (isCompanyClosed || isQueueClosed) {
      // closureEnd est stocké à la veille de la réouverture (23:59:59).
      final reopen = closureEnd?.add(const Duration(seconds: 1));
      subtitle = (reopen != null && reopen.isAfter(DateTime.now()))
          ? 'Réouvre le ${reopen.day.toString().padLeft(2, '0')}/${reopen.month.toString().padLeft(2, '0')}'
          : 'Réservations fermées';
      subtitleColor = Colors.orange.shade400;
      subtitleIcon = Icons.nightlight_round_outlined;
    } else if (hasCutoff) {
      final dd = cutoffDate.day.toString().padLeft(2, '0');
      final mm = cutoffDate.month.toString().padLeft(2, '0');
      subtitle = 'Ouvert jusqu\'au $dd/$mm/${cutoffDate.year}';
      subtitleColor = Colors.orange.shade500;
      subtitleIcon = Icons.event_outlined;
    } else {
      subtitle = 'Voir les créneaux disponibles';
      subtitleColor = Colors.grey.shade500;
      subtitleIcon = Icons.calendar_month_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnavailable ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? _primaryGreen.withValues(alpha: 0.5)
              : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isUnavailable
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedQueueId = queueId);
                  _showSlotsPage(queueId, queueData);
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar avec gradient + numéro badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: isUnavailable
                            ? null
                            : const LinearGradient(
                                colors: [_primaryGreen, _darkGreen],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        color: isUnavailable ? Colors.grey.shade200 : null,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isUnavailable
                            ? Icons.pause_circle_outline_rounded
                            : Icons.groups_rounded,
                        color: isUnavailable
                            ? Colors.grey.shade400
                            : Colors.white,
                        size: 26,
                      ),
                    ),
                    if (!isUnavailable)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _primaryGreen.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: _primaryGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        queueName,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isUnavailable ? Colors.grey.shade500 : _dark,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(subtitleIcon, size: 13, color: subtitleColor),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              subtitle,
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isUnavailable)
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: _greenLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios,
                      size: 13,
                      color: _primaryGreen,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClosureBanner(
    DateTime? closureStart,
    DateTime? closureEnd, {
    required bool isActive,
  }) {
    if (closureStart == null) return const SizedBox.shrink();

    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    // closureEnd est stocké à la veille de la réouverture (23:59:59).
    final reopen = closureEnd?.add(const Duration(seconds: 1));

    final bg = isActive ? Colors.red.shade50 : const Color(0xFFFFF8EC);
    final border = isActive ? Colors.red.shade200 : const Color(0xFFDEC98A);
    final icon = isActive ? Icons.block_rounded : Icons.schedule_rounded;
    final iconColor = isActive ? Colors.red.shade600 : const Color(0xFFAA7C2A);
    final textColor = isActive ? Colors.red.shade800 : const Color(0xFF7A5618);
    final String label;
    if (isActive) {
      label = reopen != null
          ? 'Structure fermée — réouverture le ${fmt(reopen)}'
          : 'Structure fermée jusqu\'à nouvel ordre';
    } else {
      label = reopen != null
          ? 'Fermeture du ${fmt(closureStart)}, réouverture le ${fmt(reopen)}'
          : 'Fermeture prévue à partir du ${fmt(closureStart)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSlotsPage(String queueId, Map<String, dynamic> queueData) {
    SlotsPage.prefetch(widget.entrepriseId, queueId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SlotsPage.fromQueueData(
          companyId: widget.entrepriseId,
          queueId: queueId,
          queueData: queueData,
          entrepriseNom: widget.entrepriseNom,
          primaryGreen: _primaryGreen,
          lightGreen: _lightGreen,
          onReservationSuccess: _loadActiveReservationsCount,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                color: _greenLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inbox_rounded,
                size: 56,
                color: _primaryGreen,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucune file disponible',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cette entreprise n\'a pas encore créé de files d\'attente',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailableState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.storefront_outlined,
                size: 56,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Entreprise indisponible',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cette entreprise n\'est plus disponible sur Baxa',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
