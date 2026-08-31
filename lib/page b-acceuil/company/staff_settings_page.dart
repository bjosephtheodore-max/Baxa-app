import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baxa/widgets/qr_code_section.dart';
import 'package:baxa/widgets/account_status_card.dart';

// ============================================================
// STAFF SETTINGS PAGE — version allégée de company_settings_page pour
// les membres de l'équipe. Mêmes blocs visuels, mais :
//  • « Mon QR Code » et « Informations du compte » hérités de la
//    structure, non modifiables (l'e-mail n'est pas affiché) ;
//  • « Statut du compte » identique (carte partagée) ;
//  • une déconnexion propre au membre (ne touche pas l'admin).
// ============================================================
class StaffSettingsPage extends StatefulWidget {
  final String companyId;
  final String companyName;

  const StaffSettingsPage({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<StaffSettingsPage> createState() => _StaffSettingsPageState();
}

class _StaffSettingsPageState extends State<StaffSettingsPage> {
  static const Color _green = Color.fromARGB(255, 75, 139, 94);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _companyData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .get();
      if (mounted) {
        setState(() {
          _companyData = doc.data();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _companyData?['nom'] as String? ?? widget.companyName;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(
                    title: 'Mon QR Code',
                    icon: Icons.qr_code_2_rounded,
                    children: [
                      QrCodeSection(
                        companyId: widget.companyId,
                        companyName: name,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _section(
                    title: 'Informations du compte',
                    icon: Icons.account_circle,
                    children: [
                      _readOnly(
                        label: 'Rôle',
                        value: 'Membre de l\'équipe',
                        icon: Icons.badge_outlined,
                      ),
                      const SizedBox(height: 12),
                      _readOnly(
                        label: 'Nom de l\'entreprise',
                        value: name,
                        icon: Icons.business,
                      ),
                      const SizedBox(height: 12),
                      _readOnly(
                        label: 'Type de structure',
                        value: _companyData?['type'] as String? ?? 'Non défini',
                        icon: Icons.location_city,
                      ),
                      const SizedBox(height: 12),
                      _readOnly(
                        label: 'Ville',
                        value:
                            _companyData?['ville'] as String? ?? 'Non défini',
                        icon: Icons.place_outlined,
                      ),
                      const SizedBox(height: 12),
                      _readOnly(
                        label: 'Position',
                        value:
                            (_companyData?['adresse'] as String?)?.isNotEmpty ==
                                true
                            ? _companyData!['adresse'] as String
                            : 'Non définie',
                        icon: Icons.my_location_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _section(
                    title: 'Statut du compte',
                    icon: Icons.shield,
                    children: [AccountStatusCard(companyId: widget.companyId)],
                  ),
                  const SizedBox(height: 24),
                  _section(
                    title: 'Session',
                    icon: Icons.logout_rounded,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Future<void> _confirmLogout() async {
    final name = _companyData?['nom'] as String? ?? widget.companyName;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Se déconnecter'),
        content: Text(
          'Vous vous déconnectez de $name. Vous pourrez vous reconnecter '
          'avec un nouveau code fourni par le gérant.',
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
  }

  // ── Blocs visuels (miroir de company_settings_page) ──────────────
  Widget _section({
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

  Widget _readOnly({
    required String label,
    required String value,
    required IconData icon,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
