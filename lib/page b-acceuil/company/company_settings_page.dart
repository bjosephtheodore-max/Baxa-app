import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:baxa/page b-acceuil/company/settings_page.dart';
import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/slot_generation_service.dart';
import 'package:baxa/services/reservation_admin_service.dart';
import 'package:baxa/widgets/account_status_card.dart';
import 'package:baxa/widgets/qr_code_section.dart';
import 'package:baxa/services/location_service.dart';
import 'package:baxa/services/onboarding_service.dart';
import 'package:baxa/widgets/onboarding_widgets.dart';
import 'package:baxa/widgets/baxa_date_picker_theme.dart';
import 'package:baxa/services/geo_address_service.dart';

class CompanySettingsPage extends StatefulWidget {
  const CompanySettingsPage({super.key});

  @override
  State<CompanySettingsPage> createState() => _CompanySettingsPageState();
}

class _CompanySettingsPageState extends State<CompanySettingsPage>
    with AutomaticKeepAliveClientMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _companyId;
  Map<String, dynamic>? _companyData;
  bool _isLoading = true;

  // Rappel « ajoutez votre position » : masquable, mais seulement pour la
  // session — il revient tant que la position n'est pas renseignée.
  bool _positionNudgeDismissed = false;

  // La structure n'a pas encore de point GPS → invisible dans la recherche
  // par proximité, et son pays peut être faux (hérité de la locale).
  bool get _positionMissing => _companyData?['position'] is! GeoPoint;

  // ── KeepAlive : empêche Flutter de détruire la page ──────────────────────
  @override
  bool get wantKeepAlive => true;

  static const Color _green = Color.fromARGB(255, 75, 139, 94);

  static const List<Map<String, dynamic>> _structureTypes = [
    {'label': 'Banque', 'icon': Icons.account_balance_rounded},
    {'label': 'Restaurant', 'icon': Icons.restaurant_rounded},
    {'label': 'Commerce', 'icon': Icons.storefront_rounded},
    {'label': 'Administration', 'icon': Icons.business_center_rounded},
    {'label': 'Hôpital', 'icon': Icons.local_hospital_rounded},
    {'label': 'Autre', 'icon': Icons.category_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _companyId = _auth.currentUser?.uid;
    _loadCompanyData();
  }

  Future<void> _loadCompanyData() async {
    if (_companyId == null) return;

    try {
      final doc = await _firestore
          .collection('companies')
          .doc(_companyId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        setState(() {
          _companyData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement données : $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    super.build(context); // requis par AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(
          'Paramètres',
          style: GoogleFonts.poppins(
            color: const Color(0xFF1A1C2E),
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade100, height: 1),
        ),
      ),
      body: ListenableBuilder(
        listenable: OnboardingService(),
        builder: (context, child) {
          if (_isLoading || OnboardingService().step != 2) return child!;
          return Stack(
            children: [
              child!,
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(color: Colors.black.withValues(alpha: 0.58)),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: _buildQueuesSection(),
              ),
            ],
          );
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                // Marge basse élargie : la barre de navigation flotte au-dessus
                // du contenu (extendBody).
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rappel « ajoutez votre position » — masqué pendant
                    // tout le parcours guidé de premier lancement, pour ne
                    // pas parasiter la création de la 1ʳᵉ file. Réactif :
                    // réapparaît dès que l'onboarding se termine.
                    ListenableBuilder(
                      listenable: OnboardingService(),
                      builder: (context, _) {
                        final show =
                            _positionMissing &&
                            !_positionNudgeDismissed &&
                            !OnboardingService().isActive;
                        if (!show) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildPositionNudge(),
                        );
                      },
                    ),
                    _buildQueuesSection(),
                    const SizedBox(height: 24),
                    _buildQrCodeSection(),
                    const SizedBox(height: 24),
                    _buildAccountInfoSection(),
                    const SizedBox(height: 24),
                    _buildAccountStatusSection(),
                    const SizedBox(height: 24),
                    _buildClosureSection(),
                    const SizedBox(height: 24),
                    _buildSecuritySection(),
                    const SizedBox(height: 28),
                    _buildBottomActions(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  // ==================== GESTION DES FILES ====================
  Widget _buildQueuesSection() {
    return _buildSection(
      title: 'Files d\'attente',
      icon: Icons.queue,
      children: [
        ListenableBuilder(
          listenable: OnboardingService(),
          builder: (context, child) {
            final active = OnboardingService().step == 2;
            return active
                ? PulsingGlow(
                    borderRadius: BorderRadius.circular(12),
                    child: child!,
                  )
                : child!;
          },
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                OnboardingService().advance(2);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _green.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.people_outline,
                        color: _green,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gérer les files d\'attente',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Créer, modifier et configurer vos files',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: _green,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== QR CODE ====================
  Widget _buildQrCodeSection() {
    if (_companyId == null) return const SizedBox.shrink();
    return _buildSection(
      title: 'Mon QR Code',
      icon: Icons.qr_code_2_rounded,
      children: [
        QrCodeSection(
          companyId: _companyId!,
          companyName: _companyData?['nom'] as String? ?? 'Mon Entreprise',
        ),
      ],
    );
  }

  // ==================== INFORMATIONS DU COMPTE ====================
  Widget _buildAccountInfoSection() {
    return _buildSection(
      title: 'Informations du compte',
      icon: Icons.account_circle,
      children: [
        _buildEditableField(
          label: 'Nom de l\'entreprise',
          value: _companyData?['nom'] ?? 'Non défini',
          icon: Icons.business,
          onEdit: () => _showEditNameDialog(),
        ),
        const SizedBox(height: 12),
        _buildReadOnlyField(
          label: 'Email',
          value:
              _companyData?['email'] ??
              _auth.currentUser?.email ??
              'Non défini',
          icon: Icons.email,
          hint: 'L\'email ne peut pas être modifié',
        ),
        const SizedBox(height: 12),
        _buildEditableField(
          label: 'Type de structure',
          value: _companyData?['type'] ?? 'Non défini',
          icon: Icons.location_city,
          onEdit: () => _showEditStructureDialog(),
        ),
        const SizedBox(height: 12),
        _buildEditableField(
          label: 'Ville',
          value: _companyData?['ville'] ?? 'Non défini',
          icon: Icons.place_outlined,
          onEdit: () => _showEditVilleDialog(),
        ),
        const SizedBox(height: 12),
        _buildEditableField(
          label: 'Position',
          value: (_companyData?['adresse'] as String?)?.isNotEmpty == true
              ? _companyData!['adresse'] as String
              : 'Non définie',
          icon: Icons.my_location_rounded,
          onEdit: () => _showEditPositionDialog(),
          alert: _positionMissing && !OnboardingService().isActive,
          alertText: _positionMissing && !OnboardingService().isActive
              ? 'À compléter depuis votre établissement — sans elle, vos '
                    'clients ne vous trouvent pas dans la recherche par '
                    'proximité.'
              : null,
        ),
      ],
    );
  }

  // Bandeau de rappel affiché tant que la position GPS n'est pas
  // renseignée (masquable pour la session).
  Widget _buildPositionNudge() {
    const amber = Color(0xFFB26B00);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0C67A), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.location_off_rounded, color: amber, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Terminez votre configuration',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ajoutez la position de votre établissement, sur place. '
                  'Sans elle, vos clients ne vous trouvent pas dans la '
                  'recherche par proximité et ne voient pas la distance '
                  'jusqu\'à chez vous.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: _showEditPositionDialog,
                    icon: const Icon(Icons.my_location_rounded, size: 16),
                    label: const Text('Ajouter ma position'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: amber,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.grey.shade500,
            ),
            onPressed: () => setState(() => _positionNudgeDismissed = true),
            tooltip: 'Masquer',
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onEdit,
    bool alert = false,
    String? alertText,
  }) {
    const amber = Color(0xFFB26B00);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: alert ? const Color(0xFFFFF8EC) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: alert
                  ? Border.all(color: const Color(0xFFF0C67A), width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: alert ? amber : _green, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: alert ? amber : null,
                        ),
                      ),
                      if (alert && alertText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          alertText,
                          style: const TextStyle(
                            fontSize: 11,
                            color: amber,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  alert ? Icons.error_outline_rounded : Icons.edit,
                  size: 20,
                  color: alert ? amber : _green,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    String? hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STATUT DU COMPTE ====================
  Widget _buildAccountStatusSection() {
    if (_companyId == null) return const SizedBox.shrink();
    return _buildSection(
      title: 'Statut du compte',
      icon: Icons.shield,
      children: [AccountStatusCard(companyId: _companyId!)],
    );
  }

  // ==================== SÉCURITÉ ====================
  Widget _buildSecuritySection() {
    return _buildSection(
      title: 'Sécurité',
      icon: Icons.lock,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _showChangePasswordDialog,
            icon: const Icon(Icons.vpn_key, color: Colors.white),
            label: const Text(
              'Changer le mot de passe',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== BAS DE PAGE : SESSION + DÉPART ====================
  // « Se déconnecter » en bouton contour neutre ; juste en dessous, un lien
  // gris minuscule « Quitter Baxa → » qui mène — après ré-authentification —
  // au parcours de départ. Le contraste bouton / lien texte suffit à noyer
  // la suppression. Une fois un départ programmé, l'admin ne revient jamais
  // ici : il est arrêté au gate dès la connexion (CompanyDeletionGatePage).
  Widget _buildBottomActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Se déconnecter'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey.shade800,
            side: BorderSide(color: Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _reauthThenShowLeaveSheet,
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade500,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Quitter Baxa →', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  // Ré-authentification par mot de passe avant d'ouvrir le parcours de
  // suppression. L'email est déjà connu — on ne redemande que le mot de passe.
  Future<void> _reauthThenShowLeaveSheet() async {
    final email = _auth.currentUser?.email;
    if (email == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ReauthPasswordDialog(email: email),
    );
    if (ok == true && mounted) {
      await _showLeaveSheet();
    }
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Se déconnecter'),
        content: const Text(
          'Vous vous déconnectez, mais votre établissement reste actif et '
          'visible sur Baxa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ChoosePage()),
      (route) => false,
    );
  }

  // ==================== QUITTER BAXA ====================

  static const int _graceDays = 7;

  Future<void> _showLeaveSheet() async {
    final companyName = _companyData?['nom'] as String? ?? 'votre structure';

    // Le contenu est un StatefulWidget dédié : il possède et libère lui-même
    // son TextEditingController dans dispose(), ce qui évite le crash
    // « _dependents.isEmpty is not true » qd on libère le contrôleur pendant
    // que la feuille se referme encore.
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _LeaveBaxaSheet(companyName: companyName, graceDays: _graceDays),
    );

    if (reason != null && mounted) {
      await _submitLeaveRequest(reason);
    }
  }

  Future<void> _submitLeaveRequest(String reason) async {
    final companyId = _companyId;
    if (companyId == null) return;
    try {
      final now = DateTime.now();
      final executeAfter = now.add(const Duration(days: _graceDays));

      final data = <String, dynamic>{
        'companyId': companyId,
        'companyName': _companyData?['nom'] ?? '',
        'email': _auth.currentUser?.email ?? _companyData?['email'] ?? '',
        'phone': _companyData?['telephone'] ?? _companyData?['phone'] ?? '',
        'reason': reason,
        'requestedAt': FieldValue.serverTimestamp(),
        'requestedBy': _auth.currentUser?.uid ?? '',
        'status': 'scheduled',
        'executeAfter': Timestamp.fromDate(executeAfter),
      };
      await _firestore.collection('deletionRequests').doc(companyId).set(data);

      // Fermeture indéterminée immédiate de toutes les files + annulation
      // des réservations à venir (le client est prévenu par la Cloud
      // Function, source `company_closure`).
      final queuesSnap = await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('queues')
          .get();

      if (queuesSnap.docs.isNotEmpty) {
        final closeBatch = _firestore.batch();
        for (final q in queuesSnap.docs) {
          closeBatch.update(q.reference, {
            'closureStart': Timestamp.fromDate(now),
            'closureEnd': FieldValue.delete(),
          });
        }
        await closeBatch.commit();
      }

      final resSnap = await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('reservations')
          .where('status', isEqualTo: 'confirmed')
          .get();
      final toCancel = resSnap.docs.where((d) {
        final ss = (d.data()['slotStart'] as Timestamp?)?.toDate();
        return ss != null && ss.isAfter(now);
      }).toList();
      await cancelReservationsBatch(
        firestore: _firestore,
        companyId: companyId,
        reservationDocs: toCancel,
        cancellationSource: 'company_closure',
      );

      // L'établissement part : l'accès du staff s'arrête tout de suite (le
      // listener de révocation les déconnecte). En cas de retour dans les
      // 7 jours, l'admin ré-invite ses membres avec de nouveaux codes.
      final staffSnap = await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('staff')
          .where('isActive', isEqualTo: true)
          .get();
      if (staffSnap.docs.isNotEmpty) {
        final staffBatch = _firestore.batch();
        for (final s in staffSnap.docs) {
          staffBatch.update(s.reference, {'isActive': false});
        }
        await staffBatch.commit();
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Départ enregistré'),
          content: Text(
            'Votre établissement est fermé et sera définitivement supprimé le '
            '${_formatDate(executeAfter)}.\n\n'
            'Vous pouvez encore revenir : reconnectez-vous avant cette date.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Compris'),
            ),
          ],
        ),
      );

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ChoosePage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ==================== FERMETURE TEMPORAIRE ====================

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _buildClosureSection() {
    if (_companyId == null) return const SizedBox.shrink();
    return _buildSection(
      title: 'Fermetures',
      icon: Icons.nightlight_round_outlined,
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('companies')
              .doc(_companyId)
              .collection('queues')
              .snapshots(),
          builder: (context, snap) {
            final queues = snap.data?.docs ?? [];
            final now = DateTime.now();

            // Regrouper les fermetures actives / à venir par (début, fin).
            final groups = <String, _ClosureGroup>{};
            for (final q in queues) {
              final d = q.data() as Map<String, dynamic>;
              final cs = (d['closureStart'] as Timestamp?)?.toDate();
              if (cs == null) continue;
              final ce = (d['closureEnd'] as Timestamp?)?.toDate();
              if (ce != null && ce.isBefore(now)) continue; // fermeture passée
              final key =
                  '${cs.millisecondsSinceEpoch}_${ce?.millisecondsSinceEpoch ?? 0}';
              final g = groups.putIfAbsent(
                key,
                () => _ClosureGroup(start: cs, end: ce),
              );
              g.queueIds.add(q.id);
              g.queueNames.add(d['name'] as String? ?? 'File');
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groups.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                          color: _green,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Aucune fermeture en cours',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...groups.values.map(
                    (g) => _buildClosureCard(g, queues.length, now),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: queues.isEmpty
                        ? null
                        : () => _openPlanClosureSheet(queues),
                    icon: const Icon(
                      Icons.event_busy_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    label: const Text(
                      'Planifier une fermeture',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade500,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildClosureCard(_ClosureGroup g, int totalQueues, DateTime now) {
    final active = isQueueClosedNow(g.start, g.end, now: now);
    final allFiles = g.queueIds.length == totalQueues;
    final scopeLabel = allFiles
        ? 'Toute la structure'
        : g.queueNames.length == 1
        ? g.queueNames.first
        : '${g.queueNames.length} files';
    final String dateLabel;
    if (g.end != null) {
      // g.end est stocké à la veille de la réouverture (23:59:59).
      final reopen = g.end!.add(const Duration(seconds: 1));
      dateLabel = active
          ? 'Réouverture le ${_formatDate(reopen)}'
          : 'Du ${_formatDate(g.start)}, réouverture le ${_formatDate(reopen)}';
    } else {
      dateLabel = active
          ? 'Fermé jusqu\'à nouvel ordre'
          : 'À partir du ${_formatDate(g.start)}, sans fin';
    }
    final c = active ? Colors.red : Colors.indigo;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scopeLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.shade700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dateLabel,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  _reopenClosure(g.queueIds.toList(), wasActive: active),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                active
                    ? 'Rouvrir immédiatement'
                    : 'Annuler la fermeture prévue',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reopenClosure(
    List<String> queueIds, {
    required bool wasActive,
  }) async {
    if (_companyId == null) return;

    // Confirmation systématique — ces boutons peuvent être touchés par
    // inadvertance.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          wasActive
              ? 'Rouvrir immédiatement ?'
              : 'Annuler la fermeture prévue ?',
        ),
        content: Text(
          wasActive
              ? 'Les réservations rouvrent tout de suite et les créneaux sont '
                    'régénérés. Toute date de réouverture prévue est annulée.'
              : 'La fermeture programmée est annulée. Les réservations restent '
                    'ouvertes normalement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
            ),
            child: Text(wasActive ? 'Rouvrir' : 'Annuler la fermeture'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final batch = _firestore.batch();
      for (final id in queueIds) {
        batch.update(
          _firestore
              .collection('companies')
              .doc(_companyId)
              .collection('queues')
              .doc(id),
          {
            'closureStart': FieldValue.delete(),
            'closureEnd': FieldValue.delete(),
          },
        );
      }
      await batch.commit();

      // Régénération immédiate des créneaux — seulement si la fermeture
      // était active (sinon la génération n'avait jamais été suspendue).
      if (wasActive) {
        for (final id in queueIds) {
          try {
            await regenerateSlotsForQueue(
              firestore: _firestore,
              companyId: _companyId!,
              queueId: id,
            );
          } catch (_) {
            // La CF de nuit rattrapera si la régénération immédiate échoue.
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasActive ? 'Réservations rouvertes.' : 'Fermeture annulée.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _openPlanClosureSheet(List<QueryDocumentSnapshot> queues) async {
    if (_companyId == null) return;
    final result = await showModalBottomSheet<_ClosurePlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanClosureSheet(
        companyId: _companyId!,
        queues: [
          for (final q in queues)
            (
              id: q.id,
              name:
                  (q.data() as Map<String, dynamic>)['name'] as String? ??
                  'File',
            ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await _applyClosure(result);
  }

  Future<void> _applyClosure(_ClosurePlan p) async {
    if (_companyId == null) return;
    try {
      // 1. Poser la fermeture sur les files ciblées.
      final batch = _firestore.batch();
      for (final id in p.queueIds) {
        batch.update(
          _firestore
              .collection('companies')
              .doc(_companyId)
              .collection('queues')
              .doc(id),
          {
            'closureStart': Timestamp.fromDate(p.start),
            'closureEnd': p.end != null
                ? Timestamp.fromDate(p.end!)
                : FieldValue.delete(),
          },
        );
      }
      await batch.commit();

      // 2. Annuler les réservations attrapées, si l'entreprise l'a choisi.
      // La notification part côté serveur (Cloud Function
      // onReservationCancelledByCompany, source `company_closure`).
      int cancelled = 0;
      if (p.cancelCaught) {
        final snap = await _firestore
            .collection('companies')
            .doc(_companyId)
            .collection('reservations')
            .where('status', isEqualTo: 'confirmed')
            .get();
        final caught = snap.docs.where((doc) {
          final data = doc.data();
          if (!p.queueIds.contains(data['queueId'])) return false;
          final ss = (data['slotStart'] as Timestamp?)?.toDate();
          if (ss == null || ss.isBefore(p.start)) return false;
          if (p.end != null && ss.isAfter(p.end!)) return false;
          return true;
        }).toList();

        cancelled = await cancelReservationsBatch(
          firestore: _firestore,
          companyId: _companyId!,
          reservationDocs: caught,
          cancellationSource: 'company_closure',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancelled > 0
                ? 'Fermeture enregistrée. $cancelled réservation${cancelled > 1 ? 's' : ''} annulée${cancelled > 1 ? 's' : ''} et notifiée${cancelled > 1 ? 's' : ''}.'
                : 'Fermeture enregistrée — aucun client impacté.',
          ),
          backgroundColor: Colors.indigo.shade600,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ==================== HELPER WIDGET ====================
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5ED),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: _green),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }

  // ==================== DIALOGS ====================

  Future<void> _showEditNameDialog() async {
    final controller = TextEditingController(text: _companyData?['nom'] ?? '');
    String? errorText;

    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.business_rounded,
                        color: _green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Modifier le nom',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1C2E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  onChanged: (_) {
                    if (errorText != null) setSheet(() => errorText = null);
                  },
                  decoration: InputDecoration(
                    hintText: 'Nom de l\'entreprise',
                    errorText: errorText,
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(
                      Icons.business_outlined,
                      color: _green,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: _green, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isEmpty) {
                        setSheet(() => errorText = 'Veuillez entrer un nom');
                        return;
                      }
                      Navigator.pop(ctx, value);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Enregistrer',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _updateField('nom', newName);
    }
  }

  Future<void> _showEditVilleDialog() async {
    final controller = TextEditingController(
      text: _companyData?['ville'] ?? '',
    );
    String? errorText;

    final newVille = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.place_rounded,
                        color: _green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Modifier la ville',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1C2E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  onChanged: (_) {
                    if (errorText != null) setSheet(() => errorText = null);
                  },
                  decoration: InputDecoration(
                    hintText: 'Ville',
                    errorText: errorText,
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.place_outlined, color: _green),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: _green, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isEmpty) {
                        setSheet(() => errorText = 'Veuillez entrer une ville');
                        return;
                      }
                      Navigator.pop(ctx, value);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Enregistrer',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (newVille != null && newVille.isNotEmpty) {
      final fields = <String, dynamic>{'ville': newVille};

      // Si le pays est encore inconnu, on tente de le déduire de
      // l'adresse + la ville saisies (utile au filtre pays de la
      // recherche). La `position` ne se définit QUE via le dialogue
      // « Position », sur place — jamais par géocodage de ville ici.
      final hasPosition = _companyData?['position'] is GeoPoint;
      final country = (_companyData?['country'] as String?)?.trim() ?? '';
      final hasCountry = country.isNotEmpty && country.toUpperCase() != 'XX';
      if (!hasCountry) {
        final adresse = (_companyData?['adresse'] as String?)?.trim() ?? '';
        final query = adresse.isNotEmpty ? '$adresse, $newVille' : newVille;
        final geoFields = await _deriveGeoFields(
          query,
          knownPosition: hasPosition
              ? _companyData!['position'] as GeoPoint
              : null,
        );
        geoFields.remove('position');
        fields.addAll(geoFields);
      }
      await _updateFields(fields);
    }
  }

  Future<void> _showEditPositionDialog() async {
    final controller = TextEditingController(
      text: _companyData?['adresse'] as String? ?? '',
    );
    // Position déjà enregistrée : on la conserve tant que le gérant ne
    // recapte pas sa position sur place. Le géocodage du texte ne servira
    // que si aucune position n'existe encore (ni ici, ni en base).
    final storedPosition = _companyData?['position'] is GeoPoint
        ? _companyData!['position'] as GeoPoint
        : null;
    GeoPoint? capturedPosition = storedPosition;
    // true seulement si le gérant a appuyé sur « Utiliser ma position »
    // pendant cette session → le GPS prime alors sur tout le reste.
    bool freshGpsCaptured = false;
    bool isLocating = false;
    bool isSaving = false;
    String? errorText;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.my_location_rounded,
                        color: _green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Position de la structure',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1C2E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Placez-vous physiquement dans votre établissement avant '
                  'd\'appuyer : c\'est ce point qui permet à vos clients de '
                  'vous trouver et d\'être classés selon leur distance.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: isLocating
                        ? null
                        : () async {
                            setSheet(() => isLocating = true);
                            final locationService = LocationService();
                            final pos = await locationService
                                .getCurrentPosition();
                            if (pos == null) {
                              final serviceOn = await locationService
                                  .isServiceEnabled();
                              setSheet(() {
                                isLocating = false;
                                errorText = serviceOn
                                    ? 'Autorisez Baxa à utiliser votre localisation pour remplir '
                                          'automatiquement l\'adresse de votre structure — ça se '
                                          'passe dans les réglages du téléphone.'
                                    : 'Activez la localisation de votre téléphone pour remplir '
                                          'automatiquement l\'adresse de votre structure.';
                              });
                              return;
                            }
                            final geo = await GeoAddressService()
                                .fromCoordinates(pos.latitude, pos.longitude);
                            setSheet(() {
                              isLocating = false;
                              errorText = null;
                              capturedPosition = GeoPoint(
                                pos.latitude,
                                pos.longitude,
                              );
                              freshGpsCaptured = true;
                              final adresse = geo?.formatted ?? '';
                              if (adresse.isNotEmpty) {
                                controller.text = adresse;
                              }
                            });
                          },
                    icon: isLocating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _green,
                            ),
                          )
                        : const Icon(
                            Icons.gps_fixed_rounded,
                            color: _green,
                            size: 18,
                          ),
                    label: Text(
                      isLocating
                          ? 'Localisation en cours...'
                          : 'Utiliser ma position actuelle',
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _green),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  onChanged: (_) {
                    if (errorText != null) setSheet(() => errorText = null);
                  },
                  decoration: InputDecoration(
                    hintText: 'Ex : Almadies, en face de la pharmacie...',
                    errorText: errorText,
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(
                      Icons.edit_location_alt_outlined,
                      color: _green,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: _green, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Si l\'adresse trouvée automatiquement n\'est pas assez '
                  'précise, corrigez-la avec un repère facile à identifier '
                  '(ex : "Almadies, en face de la pharmacie X") pour que vos '
                  'clients retrouvent facilement votre établissement.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final value = controller.text.trim();
                            if (value.isEmpty) {
                              setSheet(
                                () => errorText = 'Veuillez entrer une adresse',
                              );
                              return;
                            }

                            // Priorité : GPS recapté sur place > position
                            // déjà enregistrée > géocodage du texte (dernier
                            // recours, uniquement si aucune position connue).
                            var position = capturedPosition;
                            String source;
                            if (freshGpsCaptured) {
                              source = 'gps';
                            } else if (position != null) {
                              source = 'kept';
                            } else {
                              setSheet(() {
                                isSaving = true;
                                errorText = null;
                              });
                              final geo = await GeoAddressService().fromAddress(
                                value,
                              );
                              position = geo?.position;
                              source = 'geocoded';
                              if (ctx.mounted) {
                                setSheet(() => isSaving = false);
                              }
                            }

                            if (ctx.mounted) {
                              Navigator.pop(ctx, {
                                'adresse': value,
                                'position': position,
                                'source': source,
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Enregistrer',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null) {
      final adresse = result['adresse'] as String;
      final position = result['position'] as GeoPoint?;
      final source = result['source'] as String? ?? 'kept';
      final fields = <String, dynamic>{'adresse': adresse};
      if (position != null) fields['position'] = position;

      // `gps` / `geocoded` : la position vient d'être (re)définie → on
      // fait confiance au géocodage pour rafraîchir pays / région.
      // `kept` : simple correction de texte, position inchangée → on ne
      // comble que les infos manquantes, sans rien écraser.
      fields.addAll(
        await _deriveGeoFields(
          adresse,
          knownPosition: position,
          overwrite: source != 'kept',
        ),
      );
      await _updateFields(fields);
    }
  }

  /// Déduit `country` (code ISO), `countryName` et `region` à partir d'un
  /// texte d'adresse et/ou d'une position. La `ville` n'est jamais touchée :
  /// c'est une saisie humaine (dropdown à l'inscription), plus fiable que
  /// le `locality` du géocodeur, souvent un quartier.
  ///
  /// Best effort et silencieux : renvoie une map vide si le géocodage
  /// échoue. Avec [knownPosition] on fait un géocodage inverse (la
  /// position n'est jamais modifiée) ; sans, un géocodage direct qui peut
  /// aussi fournir une `position`. [overwrite] autorise l'écrasement de
  /// valeurs déjà présentes (sinon on ne comble que ce qui manque).
  Future<Map<String, dynamic>> _deriveGeoFields(
    String addressText, {
    GeoPoint? knownPosition,
    bool overwrite = false,
  }) async {
    final fields = <String, dynamic>{};
    final text = addressText.trim();
    if (text.isEmpty && knownPosition == null) return fields;

    final currentCountry = (_companyData?['country'] as String?)?.trim() ?? '';
    final countryKnown =
        currentCountry.isNotEmpty && currentCountry.toUpperCase() != 'XX';
    final currentName = (_companyData?['countryName'] as String?)?.trim() ?? '';
    final currentRegion = (_companyData?['region'] as String?)?.trim() ?? '';

    // Mode « comblement » et rien à combler → on évite un appel réseau.
    if (!overwrite &&
        countryKnown &&
        currentName.isNotEmpty &&
        currentRegion.isNotEmpty) {
      return fields;
    }

    final service = GeoAddressService();
    GeoAddress? geo;
    if (knownPosition != null) {
      geo = await service.fromCoordinates(
        knownPosition.latitude,
        knownPosition.longitude,
      );
    } else {
      geo = await service.fromAddress(text);
      final pos = geo?.position;
      if (pos != null) fields['position'] = pos;
    }
    if (geo == null) return fields;

    if (geo.countryCode != null && (overwrite || !countryKnown)) {
      fields['country'] = geo.countryCode;
    }
    if (geo.country != null && (overwrite || currentName.isEmpty)) {
      fields['countryName'] = geo.country;
    }
    if (geo.region != null && (overwrite || currentRegion.isEmpty)) {
      fields['region'] = geo.region;
    }
    return fields;
  }

  Future<void> _showEditStructureDialog() async {
    final currentType = _companyData?['type'] as String? ?? '';

    final newType = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final bottomPad = 24.0 + MediaQuery.of(sheetCtx).padding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.category_rounded,
                            color: _green,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Type de structure',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1C2E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _structureTypes.map((option) {
                      final label = option['label'] as String;
                      final icon = option['icon'] as IconData;
                      final isSelected =
                          label == currentType ||
                          (label == 'Autre' &&
                              currentType.isNotEmpty &&
                              !_structureTypes.any(
                                (t) => t['label'] == currentType,
                              ));
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () async {
                            if (label == 'Autre') {
                              final custom = await _showCustomStructureInput(
                                sheetCtx,
                              );
                              if (!sheetCtx.mounted) return;
                              if (custom != null && custom.isNotEmpty) {
                                Navigator.pop(sheetCtx, custom);
                              }
                            } else {
                              Navigator.pop(sheetCtx, label);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _green.withValues(alpha: 0.06)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? _green.withValues(alpha: 0.4)
                                    : Colors.grey.shade200,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  icon,
                                  color: isSelected
                                      ? _green
                                      : Colors.grey.shade500,
                                  size: 20,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? const Color(0xFF1A1C2E)
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: _green,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (newType != null) {
      await _updateField('type', newType);
    }
  }

  Future<String?> _showCustomStructureInput(BuildContext sheetCtx) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: sheetCtx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.category_rounded,
                color: _green,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Type de structure',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Ex: Pharmacie, École, Hôtel…',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _green, width: 1.5),
            ),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Annuler',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isLoading = false;
    String? confirmError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
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
                const SizedBox(height: 24),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: _green,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Changer le mot de passe',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1C2E),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Sécurisez votre compte',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Ancien mot de passe
                _buildPasswordField(
                  controller: oldCtrl,
                  hint: 'Mot de passe actuel',
                  obscure: obscureOld,
                  autofocus: true,
                  onToggle: () => setSheet(() => obscureOld = !obscureOld),
                ),
                const SizedBox(height: 14),

                // Nouveau mot de passe
                _buildPasswordField(
                  controller: newCtrl,
                  hint: 'Nouveau mot de passe',
                  obscure: obscureNew,
                  onToggle: () => setSheet(() => obscureNew = !obscureNew),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Au moins 6 caractères recommandés',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 14),

                // Confirmer
                _buildPasswordField(
                  controller: confirmCtrl,
                  hint: 'Confirmer le nouveau mot de passe',
                  obscure: obscureConfirm,
                  onToggle: () =>
                      setSheet(() => obscureConfirm = !obscureConfirm),
                  errorText: confirmError,
                  onChanged: (_) {
                    if (confirmError != null) {
                      setSheet(() => confirmError = null);
                    }
                  },
                ),
                const SizedBox(height: 24),

                // Bouton
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            if (newCtrl.text != confirmCtrl.text) {
                              setSheet(
                                () => confirmError =
                                    'Les mots de passe ne correspondent pas',
                              );
                              return;
                            }
                            setSheet(() => isLoading = true);
                            await _changePassword(oldCtrl.text, newCtrl.text);
                            if (sheetCtx.mounted) {
                              Navigator.pop(sheetCtx);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      disabledBackgroundColor: _green.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Mettre à jour',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? errorText,
    ValueChanged<String>? onChanged,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: _green,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey.shade400,
            size: 20,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: _green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }

  // ==================== ACTIONS ====================

  Future<void> _updateField(String field, dynamic value) async {
    if (_companyId == null) return;

    try {
      await _firestore.collection('companies').doc(_companyId).update({
        field: value,
      });

      setState(() {
        _companyData?[field] = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informations mises à jour')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  // Variante de `_updateField` pour écrire plusieurs champs en une seule
  // fois (ex. position + adresse, mis à jour ensemble).
  Future<void> _updateFields(Map<String, dynamic> fields) async {
    if (_companyId == null) return;

    try {
      await _firestore.collection('companies').doc(_companyId).update(fields);

      setState(() {
        fields.forEach((key, value) => _companyData?[key] = value);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informations mises à jour')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  Future<void> _changePassword(String oldPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Ré-authentification
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: oldPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mot de passe modifié avec succès')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Erreur lors du changement de mot de passe';

      if (e.code == 'wrong-password') {
        message = 'Ancien mot de passe incorrect';
      } else if (e.code == 'weak-password') {
        message = 'Le nouveau mot de passe est trop faible';
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

// ============================================================
// FERMETURE — modèles + feuille de planification
// ============================================================

class _ClosureGroup {
  final DateTime start;
  final DateTime? end;
  final Set<String> queueIds = {};
  final List<String> queueNames = [];
  _ClosureGroup({required this.start, this.end});
}

class _ClosurePlan {
  final List<String> queueIds;
  final DateTime start;
  final DateTime? end;
  final bool cancelCaught;
  _ClosurePlan({
    required this.queueIds,
    required this.start,
    this.end,
    required this.cancelCaught,
  });
}

class _PlanClosureSheet extends StatefulWidget {
  final String companyId;
  final List<({String id, String name})> queues;
  const _PlanClosureSheet({required this.companyId, required this.queues});

  @override
  State<_PlanClosureSheet> createState() => _PlanClosureSheetState();
}

class _PlanClosureSheetState extends State<_PlanClosureSheet> {
  static const _indigo = Color(0xFF5C6BC0);

  bool _scopeAll = true;
  final Set<String> _selected = {};
  DateTime? _start;
  bool _endKnown = false;
  DateTime? _end; // jour de réouverture choisi par l'entreprise
  bool _earlierAllowed = false;

  bool _loading = true;
  List<QueryDocumentSnapshot> _reservations = [];

  @override
  void initState() {
    super.initState();
    if (widget.queues.length == 1) _selected.add(widget.queues.first.id);
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final snap = await FirebaseFirestore.instance
          .collection('companies')
          .doc(widget.companyId)
          .collection('reservations')
          .where('status', isEqualTo: 'confirmed')
          .get();
      _reservations = snap.docs.where((d) {
        final se = (d.data()['slotEnd'] as Timestamp?)?.toDate();
        return se != null && se.isAfter(now);
      }).toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _start = _minStart;
    });
  }

  List<String> get _scopeIds =>
      _scopeAll ? widget.queues.map((q) => q.id).toList() : _selected.toList();

  DateTime get _tomorrow {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 1);
  }

  // Première date sans impact : lendemain de la dernière réservation de la
  // portée (ou demain si aucune).
  DateTime get _minStart {
    DateTime? furthest;
    for (final r in _reservations) {
      final data = r.data() as Map<String, dynamic>;
      if (!_scopeIds.contains(data['queueId'])) continue;
      final ss = (data['slotStart'] as Timestamp?)?.toDate();
      if (ss != null && (furthest == null || ss.isAfter(furthest))) {
        furthest = ss;
      }
    }
    if (furthest == null) return _tomorrow;
    return DateTime(furthest.year, furthest.month, furthest.day + 1);
  }

  // `_end` = jour de réouverture choisi par l'entreprise. La file est donc
  // fermée jusqu'à la veille à 23:59:59.
  DateTime? get _resolvedEnd => _endKnown && _end != null
      ? DateTime(
          _end!.year,
          _end!.month,
          _end!.day,
        ).subtract(const Duration(seconds: 1))
      : null;

  int get _caughtCount {
    final s = _start;
    if (s == null) return 0;
    final endLimit = _resolvedEnd;
    return _reservations.where((r) {
      final data = r.data() as Map<String, dynamic>;
      if (!_scopeIds.contains(data['queueId'])) return false;
      final ss = (data['slotStart'] as Timestamp?)?.toDate();
      if (ss == null || ss.isBefore(s)) return false;
      if (endLimit != null && ss.isAfter(endLimit)) return false;
      return true;
    }).length;
  }

  bool get _valid =>
      _scopeIds.isNotEmpty && _start != null && (!_endKnown || _end != null);

  void _submit(bool cancelCaught) {
    Navigator.pop(
      context,
      _ClosurePlan(
        queueIds: _scopeIds,
        start: _start!,
        end: _resolvedEnd,
        cancelCaught: cancelCaught,
      ),
    );
  }

  Future<void> _pickStart() async {
    final first = _earlierAllowed ? _tomorrow : _minStart;
    final init = (_start != null && !_start!.isBefore(first)) ? _start! : first;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: DateTime(DateTime.now().year + 2),
      helpText: 'Premier jour de fermeture',
      builder: (context, child) =>
          Theme(data: baxaDatePickerTheme(context, _indigo), child: child!),
    );
    if (picked != null && mounted) {
      setState(() {
        _start = picked;
        if (_end != null && !_end!.isAfter(picked)) _end = null;
      });
    }
  }

  Future<void> _pickEnd() async {
    final s = _start ?? _minStart;
    final first = s.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: (_end != null && !_end!.isBefore(first)) ? _end! : first,
      firstDate: first,
      lastDate: DateTime(s.year + 2),
      helpText: 'Jour de réouverture',
      builder: (context, child) =>
          Theme(data: baxaDatePickerTheme(context, _indigo), child: child!),
    );
    if (picked != null && mounted) setState(() => _end = picked);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final multi = widget.queues.length > 1;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 +
            MediaQuery.of(context).padding.bottom +
            MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Planifier une fermeture',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1C2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Bloque les nouvelles réservations. Réversible à tout moment.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (multi) ...[
                _label('1. Quelles files ?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('Toute la structure', _scopeAll, () {
                      setState(() {
                        _scopeAll = true;
                        _start = _minStart;
                      });
                    }),
                    _chip('Certaines files', !_scopeAll, () {
                      setState(() => _scopeAll = false);
                    }),
                  ],
                ),
                if (!_scopeAll) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Choisissez la ou les files concernées',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final q in widget.queues)
                        _chip(q.name, _selected.contains(q.id), () {
                          setState(() {
                            if (_selected.contains(q.id)) {
                              _selected.remove(q.id);
                            } else {
                              _selected.add(q.id);
                            }
                            _start = _minStart;
                          });
                        }),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
              ],
              _label('${multi ? '2' : '1'}. À partir de quand ?'),
              OutlinedButton.icon(
                onPressed: _pickStart,
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(_start != null ? _fmt(_start!) : 'Choisir'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _indigo,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    _caughtCount == 0
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    size: 15,
                    color: _caughtCount == 0
                        ? Colors.green.shade600
                        : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _caughtCount == 0
                          ? 'Aucune réservation dans la période'
                          : '$_caughtCount réservation${_caughtCount > 1 ? 's' : ''} dans la période',
                      style: TextStyle(
                        fontSize: 12,
                        color: _caughtCount == 0
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              if (!_earlierAllowed && _minStart.isAfter(_tomorrow)) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _earlierAllowed = true),
                  icon: const Icon(Icons.event_busy_rounded, size: 16),
                  label: const Text('Besoin de fermer avant ?'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _label('${multi ? '3' : '2'}. Jusqu\'à quand ?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    'Date de réouverture',
                    _endKnown,
                    () => setState(() => _endKnown = true),
                  ),
                  _chip('Indéterminée', !_endKnown, () {
                    setState(() {
                      _endKnown = false;
                      _end = null;
                    });
                  }),
                ],
              ),
              if (_endKnown) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickEnd,
                  icon: const Icon(Icons.event_available_rounded, size: 16),
                  label: Text(
                    _end != null
                        ? 'Réouverture le ${_fmt(_end!)}'
                        : 'Choisir une date',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _indigo,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              if (_caughtCount == 0)
                _bigButton(
                  'Planifier la fermeture',
                  _indigo,
                  _valid ? () => _submit(false) : null,
                )
              else ...[
                Text(
                  '$_caughtCount réservation${_caughtCount > 1 ? 's' : ''} '
                  'tombe${_caughtCount > 1 ? 'nt' : ''} dans la période.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _bigButton(
                  'Fermer — annuler ces réservations',
                  Colors.red.shade600,
                  _valid ? () => _submit(true) : null,
                ),
                const SizedBox(height: 8),
                _bigButton(
                  'Rester ouvert pour ces clients',
                  Colors.orange.shade700,
                  _valid ? () => _submit(false) : null,
                ),
                const SizedBox(height: 8),
                Text(
                  '« Annuler » : vous ne serez pas là, ces clients sont prévenus. '
                  '« Rester ouvert » : vous honorez ces créneaux, seules les '
                  'nouvelles réservations sont bloquées.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade800,
      ),
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _indigo : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _indigo : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : Colors.grey.shade800,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigButton(String label, Color color, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: Colors.grey.shade300,
          padding: const EdgeInsets.symmetric(vertical: 13),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Ré-authentification par mot de passe — StatefulWidget dédié pour que le
// TextEditingController vive et meure avec le widget (évite le crash
// « _dependents.isEmpty is not true »).
// ============================================================
class _ReauthPasswordDialog extends StatefulWidget {
  final String email;
  const _ReauthPasswordDialog({required this.email});

  @override
  State<_ReauthPasswordDialog> createState() => _ReauthPasswordDialogState();
}

class _ReauthPasswordDialogState extends State<_ReauthPasswordDialog> {
  static const Color _green = Color.fromARGB(255, 75, 139, 94);

  final _pwdCtrl = TextEditingController();
  String? _errorText;
  bool _checking = false;
  bool _obscure = true;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_pwdCtrl.text.isEmpty) {
      setState(() => _errorText = 'Entrez votre mot de passe');
      return;
    }
    setState(() {
      _checking = true;
      _errorText = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      final cred = EmailAuthProvider.credential(
        email: widget.email,
        password: _pwdCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _errorText =
            (e.code == 'wrong-password' || e.code == 'invalid-credential')
            ? 'Mot de passe incorrect'
            : 'Vérification impossible';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: _green,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirmez votre mot de passe',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1C2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pour continuer, saisissez le mot de passe de\n${widget.email}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pwdCtrl,
              obscureText: _obscure,
              autofocus: true,
              onSubmitted: (_) => _confirm(),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              decoration: InputDecoration(
                hintText: 'Mot de passe',
                errorText: _errorText,
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _green, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.red.shade300),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.red.shade400,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _checking
                        ? null
                        : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: Colors.grey.shade300),
                      foregroundColor: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _checking ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Confirmer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Feuille « Quitter Baxa » — StatefulWidget dédié (même raison : le
// TextEditingController du champ « raison » vit et meurt avec le widget).
// Renvoie via Navigator.pop la raison saisie (String, possiblement vide)
// si l'entreprise confirme ; null si elle revient en arrière.
// ============================================================
class _LeaveBaxaSheet extends StatefulWidget {
  final String companyName;
  final int graceDays;

  const _LeaveBaxaSheet({required this.companyName, required this.graceDays});

  @override
  State<_LeaveBaxaSheet> createState() => _LeaveBaxaSheetState();
}

class _LeaveBaxaSheetState extends State<_LeaveBaxaSheet> {
  static const Color _green = Color.fromARGB(255, 75, 139, 94);

  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Widget _timelineRow({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.exit_to_app_rounded,
                      color: Colors.red.shade600,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quitter Baxa',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _timelineRow(
                icon: Icons.nightlight_round,
                title: 'Dès maintenant',
                text:
                    '${widget.companyName} est fermé aux nouvelles réservations. '
                    'Les réservations en cours sont annulées et les clients prévenus.',
              ),
              const SizedBox(height: 12),
              _timelineRow(
                icon: Icons.timer_outlined,
                title: 'Pendant ${widget.graceDays} jours',
                text:
                    'Reconnectez-vous et annulez la suppression pour tout '
                    'réactiver.',
              ),
              const SizedBox(height: 12),
              _timelineRow(
                icon: Icons.delete_forever_rounded,
                title: 'Après ${widget.graceDays} jours',
                text:
                    'Le compte, les files et toutes les données sont '
                    'définitivement supprimés. L\'équipe est déconnectée.',
              ),
              const SizedBox(height: 20),
              Text(
                'Pourquoi partez-vous ? (facultatif)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                maxLength: 300,
                decoration: InputDecoration(
                  hintText: 'Votre retour nous aide à améliorer Baxa.',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _green),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade300),
                        foregroundColor: Colors.grey.shade800,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Retour'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, _reasonCtrl.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Quitter Baxa'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
