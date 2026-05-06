import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:baxa/page b-acceuil/company/settings_page.dart';

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
  bool _notificationsEnabled = true;
  bool _isGeneratingPoster = false;
  final GlobalKey _posterKey = GlobalKey();

  // ── KeepAlive : empêche Flutter de détruire la page ──────────────────────
  @override
  bool get wantKeepAlive => true;

  static const Color _green = Color.fromARGB(255, 75, 139, 94);

  static const List<String> _structureTypes = [
    'Banque',
    'Restaurant',
    'Commerce',
    'Administration',
    'Hôpital',
    'Clinique',
    'Cabinet médical',
    'Laboratoire',
    'Pharmacie',
    'Centre de santé',
    'Autre',
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

        // ✅ AUTO-CRÉATION du champ companyStatus s'il n'existe pas
        if (!data.containsKey('companyStatus')) {
          await _firestore.collection('companies').doc(_companyId).update({
            'companyStatus': 'active',
            'statusUpdatedAt': FieldValue.serverTimestamp(),
          });
          data['companyStatus'] = 'active';
        }

        setState(() {
          _companyData = data;
          _notificationsEnabled = data['notificationsEnabled'] ?? true;
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
        toolbarHeight: 48,
        title: Text(
          'Paramètres',
          style: TextStyle(
            color: _green,
            fontWeight: FontWeight.w700,
            fontSize: 23,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildQueuesSection(),
                  const SizedBox(height: 24),
                  _buildQrCodeSection(),
                  const SizedBox(height: 24),
                  _buildAccountInfoSection(),
                  const SizedBox(height: 24),
                  _buildAccountStatusSection(),
                  const SizedBox(height: 24),
                  _buildNotificationsSection(),
                  const SizedBox(height: 24),
                  _buildSecuritySection(),
                  const SizedBox(height: 24),
                  _buildSupportSection(),
                ],
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
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withOpacity(0.3), width: 1.5),
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
      ],
    );
  }

  // ==================== QR CODE ====================
  Widget _buildQrCodeSection() {
    final companyName = _companyData?['nom'] ?? 'Mon Entreprise';
    final qrUrl = 'https://baxa.app/company/$_companyId';

    return _buildSection(
      title: 'Mon QR Code',
      icon: Icons.qr_code_2_rounded,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _green.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Info text
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: _green,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Affichez ce QR code dans votre établissement pour que vos clients réservent instantanément.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Aperçu de l'affiche
              RepaintBoundary(
                key: _posterKey,
                child: _buildPoster(companyName: companyName, qrUrl: qrUrl),
              ),

              const SizedBox(height: 20),

              // Lien direct
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, color: _green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        qrUrl,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Bouton partager l'affiche
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isGeneratingPoster ? null : _sharePoster,
                  icon: _isGeneratingPoster
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share_rounded, color: Colors.white),
                  label: Text(
                    _isGeneratingPoster
                        ? 'Préparation...'
                        : 'Partager l\'affiche',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Affiche prête à imprimer ──────────────────────────────────────────────
  Widget _buildPoster({required String companyName, required String qrUrl}) {
    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4B8B5E), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bande verte décorative en haut
          Container(
            width: 60,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF4B8B5E),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          const SizedBox(height: 20),

          // Nom de l'entreprise
          Text(
            companyName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E2D23),
              height: 1.2,
            ),
          ),

          const SizedBox(height: 18),

          // Phrase choc AVANT le QR — capte l'attention
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Ne perdez plus votre temps dans la file.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4B8B5E),
                height: 1.3,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // QR Code — grand et central
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFB2D3C2), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4B8B5E).withOpacity(0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: qrUrl,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF1E2D23),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF1E2D23),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Instruction en 3 étapes
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepBadge(number: '1', label: 'Scannez'),
              _StepArrow(),
              _StepBadge(number: '2', label: 'Réservez'),
              _StepArrow(),
              _StepBadge(number: '3', label: 'Revenez'),
            ],
          ),

          const SizedBox(height: 20),

          // Séparateur
          Divider(color: Colors.grey.shade200),

          const SizedBox(height: 10),

          // Baxa en bas — discret
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4B8B5E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Baxa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Réservez votre place en 30 secondes',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Partager l'affiche ────────────────────────────────────────────────────
  Future<void> _sharePoster() async {
    setState(() => _isGeneratingPoster = true);
    try {
      // Capture via RepaintBoundary — natif Flutter, aucun package externe
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Widget non trouvé');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Conversion échouée');

      final imageBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final companyName = (_companyData?['nom'] ?? 'entreprise')
          .replaceAll(' ', '_')
          .toLowerCase();
      final file = File('${tempDir.path}/affiche_$companyName.png');
      await file.writeAsBytes(imageBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '📍 Réservez votre place chez ${_companyData?['nom'] ?? 'notre établissement'} sans attendre ! Scannez le QR code.',
        subject: 'Affiche QR Code - ${_companyData?['nom'] ?? ''}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du partage: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPoster = false);
    }
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
      ],
    );
  }

  Widget _buildEditableField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onEdit,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _green, size: 24),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: onEdit,
            color: _green,
          ),
        ],
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
    final status = _companyData?['companyStatus'] as String? ?? 'active';
    final statusConfig = _getStatusConfig(status);

    return _buildSection(
      title: 'Statut du compte',
      icon: Icons.shield,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusConfig.bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusConfig.borderColor, width: 2),
          ),
          child: Row(
            children: [
              Icon(statusConfig.icon, color: statusConfig.color, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          statusConfig.label,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: statusConfig.color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: statusConfig.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusConfig.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status) {
      case 'active':
        return _StatusConfig(
          label: 'Actif',
          description:
              'Votre compte fonctionne normalement. Tous les services sont accessibles.',
          icon: Icons.check_circle,
          color: Colors.green,
          bgColor: Colors.green.shade50,
          borderColor: Colors.green.shade200,
        );
      case 'pending':
        return _StatusConfig(
          label: 'En attente',
          description:
              'Votre compte est en cours de validation. Accès limité temporairement.',
          icon: Icons.schedule,
          color: Colors.orange,
          bgColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade200,
        );
      case 'suspended':
        return _StatusConfig(
          label: 'Suspendu',
          description:
              'Votre compte a été suspendu. Contactez le support pour plus d\'informations.',
          icon: Icons.block,
          color: Colors.red,
          bgColor: Colors.red.shade50,
          borderColor: Colors.red.shade200,
        );
      default:
        return _getStatusConfig('active');
    }
  }

  // ==================== NOTIFICATIONS ====================
  Widget _buildNotificationsSection() {
    return _buildSection(
      title: 'Préférences',
      icon: Icons.notifications,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_active, color: _green, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications importantes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Recommandé pour une optimisation optimale',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _notificationsEnabled,
                onChanged: (value) {
                  if (!value) {
                    _showNotificationDisableDialog();
                  } else {
                    _updateNotificationPreference(true);
                  }
                },
                activeColor: _green,
              ),
            ],
          ),
        ),
      ],
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

  // ==================== SUPPORT ====================
  Widget _buildSupportSection() {
    return _buildSection(
      title: 'Aide',
      icon: Icons.help,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _contactSupport,
            icon: Icon(Icons.mail, color: _green),
            label: Text(
              'Contacter le support',
              style: TextStyle(color: _green, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: _green, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
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

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Modifier le nom'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nom de l\'entreprise',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            child: const Text(
              'Enregistrer',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
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

    final newVille = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Modifier la ville'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Ville',
            prefixIcon: Icon(Icons.place_outlined),
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            child: const Text(
              'Enregistrer',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (newVille != null && newVille.isNotEmpty) {
      await _updateField('ville', newVille);
    }
  }

  Future<void> _showEditStructureDialog() async {
    final currentType =
        (_companyData?['type'] as String?) ?? _structureTypes.first;

    final newType = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Type de structure'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _structureTypes.map((type) {
            return RadioListTile<String>(
              title: Text(type),
              value: type,
              groupValue: currentType,
              activeColor: _green,
              onChanged: (value) => Navigator.pop(ctx, value),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );

    if (newType != null) {
      await _updateField('type', newType);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Changer le mot de passe'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Ancien mot de passe',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Les mots de passe ne correspondent pas'),
                  ),
                );
                return;
              }

              await _changePassword(
                oldPasswordController.text,
                newPasswordController.text,
              );
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            child: const Text('Changer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showNotificationDisableDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_off_rounded,
                  color: Colors.orange.shade600,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Desactiver les notifications ?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Les notifications vous permettent de suivre vos reservations en temps reel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Desactiver'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      _updateNotificationPreference(false);
    }
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

  Future<void> _updateNotificationPreference(bool enabled) async {
    if (_companyId == null) return;

    try {
      await _firestore.collection('companies').doc(_companyId).update({
        'notificationsEnabled': enabled,
      });

      setState(() => _notificationsEnabled = enabled);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled ? 'Notifications activées' : 'Notifications désactivées',
            ),
          ),
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

  Future<void> _contactSupport() async {
    final email = Uri.encodeComponent('support@baxa.app');
    final subject = Uri.encodeComponent(
      'Support Baxa - ${_companyData?['nom'] ?? 'Entreprise'}',
    );
    final body = Uri.encodeComponent(
      'Bonjour,\n\n'
      'J\'ai besoin d\'aide concernant mon compte entreprise.\n\n'
      'Informations du compte :\n'
      '- Nom : ${_companyData?['nom'] ?? 'Non défini'}\n'
      '- Email : ${_companyData?['email'] ?? 'Non défini'}\n'
      '- ID : $_companyId\n\n'
      'Ma demande :\n\n',
    );

    final url = Uri.parse('mailto:$email?subject=$subject&body=$body');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible d\'ouvrir l\'application mail'),
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
}

// ==================== HELPER CLASS ====================
class _StatusConfig {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color borderColor;

  _StatusConfig({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.borderColor,
  });
}

// ── Step badge pour l'affiche ─────────────────────────────────────────────
class _StepBadge extends StatelessWidget {
  final String number;
  final String label;
  const _StepBadge({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF4B8B5E),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E2D23),
          ),
        ),
      ],
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14, left: 6, right: 6),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 14,
        color: Color(0xFFB2D3C2),
      ),
    );
  }
}
