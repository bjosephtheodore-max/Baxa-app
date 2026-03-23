import 'package:baxa/services/firebase/auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class PersonaPage extends StatefulWidget {
  const PersonaPage({super.key});

  @override
  State<PersonaPage> createState() => _PersonaPageState();
}

class _PersonaPageState extends State<PersonaPage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _bgColor = Color(0xFFF6F8FA);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _uid;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser?.uid;
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (_uid == null) return;
    // ── Si déjà chargé, affichage instantané — pas de requête Firestore
    if (_userData != null) return;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userData = doc.data();
          _notificationsEnabled = _userData?['notificationsEnabled'] ?? true;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Erreur chargement profil: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateField(String field, dynamic value) async {
    if (_uid == null) return;
    try {
      await _firestore.collection('users').doc(_uid).update({field: value});
      setState(() => _userData?[field] = value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Mis à jour avec succès'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateNotification(bool enabled) async {
    if (_uid == null) return;
    try {
      await _firestore.collection('users').doc(_uid).update({
        'notificationsEnabled': enabled,
      });
      setState(() => _notificationsEnabled = enabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled ? 'Notifications activées' : 'Notifications désactivées',
            ),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erreur notifications: $e');
    }
  }

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Se déconnecter'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Déconnexion',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      try {
        await Auth().logout();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur déconnexion: $e')));
        }
      }
    }
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  Future<void> _showEditDialog({
    required String title,
    required String field,
    required String currentValue,
    bool optional = false,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Enregistrer',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (newValue != null && (optional || newValue.isNotEmpty)) {
      await _updateField(field, newValue);
    }
  }

  Future<void> _showNotificationDisableDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
            SizedBox(width: 10),
            Text('Désactiver ?'),
          ],
        ),
        content: const Text(
          'Vous ne recevrez plus d\'alertes sur vos réservations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Désactiver',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) await _updateNotification(false);
  }

  // ── Liens externes ───────────────────────────────────────────────────────

  Future<void> _openAvis() async {
    // TODO: remplacer par votre email de feedback
    const email = 'feedback@baxa.app';
    final url = Uri.parse(
      'mailto:$email?subject=${Uri.encodeComponent('Avis sur Baxa')}&body=${Uri.encodeComponent('Bonjour,\n\nVoici mon avis sur l\'application Baxa :\n\n')}',
    );
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
  }

  Future<void> _openWhatsApp() async {
    // TODO: remplacer par votre numéro WhatsApp (format international sans +)
    const numero = '000000000000';
    final url = Uri.parse('https://wa.me/$numero');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp')),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Mon profil',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Avatar card ────────────────────────────────────────
                  _buildAvatarCard(),

                  const SizedBox(height: 24),

                  // ── Infos personnelles ─────────────────────────────────
                  _buildSection(
                    title: 'Informations personnelles',
                    icon: Icons.person_outline_rounded,
                    children: [
                      _buildEditableRow(
                        label: 'Nom',
                        value: _userData?['nom'] ?? '—',
                        onEdit: () => _showEditDialog(
                          title: 'Modifier le nom',
                          field: 'nom',
                          currentValue: _userData?['nom'] ?? '',
                        ),
                      ),
                      _buildDivider(),
                      _buildEditableRow(
                        label: 'Prénom',
                        value: _userData?['prenom'] ?? '—',
                        onEdit: () => _showEditDialog(
                          title: 'Modifier le prénom',
                          field: 'prenom',
                          currentValue: _userData?['prenom'] ?? '',
                        ),
                      ),
                      _buildDivider(),
                      _buildEditableRow(
                        label: 'Profession',
                        value:
                            (_userData?['profession'] as String?)?.isNotEmpty ==
                                true
                            ? _userData!['profession']
                            : 'Non renseigné',
                        onEdit: () => _showEditDialog(
                          title: 'Modifier la profession',
                          field: 'profession',
                          currentValue: _userData?['profession'] ?? '',
                          optional: true,
                        ),
                      ),
                      _buildDivider(),
                      _buildReadOnlyRow(
                        label: 'Email',
                        value: _auth.currentUser?.email ?? '—',
                        hint: 'Non modifiable',
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Préférences ────────────────────────────────────────
                  _buildSection(
                    title: 'Préférences',
                    icon: Icons.tune_rounded,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: _green,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Notifications',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Alertes réservations et annulations',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _notificationsEnabled,
                              activeColor: _green,
                              onChanged: (value) {
                                if (!value) {
                                  _showNotificationDisableDialog();
                                } else {
                                  _updateNotification(true);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Support ────────────────────────────────────────────
                  _buildSection(
                    title: 'Support',
                    icon: Icons.support_agent_rounded,
                    children: [
                      _buildTappableRow(
                        icon: Icons.star_outline_rounded,
                        iconColor: Colors.amber,
                        label: 'Laisser un avis',
                        subtitle: 'Partagez votre expérience avec nous',
                        onTap: _openAvis,
                      ),
                      _buildDivider(),
                      _buildTappableRow(
                        icon: Icons.chat_bubble_outline_rounded,
                        iconColor: const Color(0xFF25D366),
                        label: 'Aide & Support',
                        subtitle: 'Contactez-nous sur WhatsApp',
                        onTap: _openWhatsApp,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // ── Déconnexion ────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _confirmAndLogout,
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      label: const Text(
                        'Se déconnecter',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Widgets helpers ──────────────────────────────────────────────────────

  Widget _buildAvatarCard() {
    final nom = (_userData?['nom'] as String?) ?? '';
    final prenom = (_userData?['prenom'] as String?) ?? '';
    final profession = (_userData?['profession'] as String?) ?? '';
    final initiales =
        '${prenom.isNotEmpty ? prenom[0] : ''}${nom.isNotEmpty ? nom[0] : ''}'
            .toUpperCase();
    final email = _auth.currentUser?.email ?? '';
    final fullName = '$prenom $nom'.trim();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar avec initiales
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4B8B5E), Color(0xFF1A2E20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _green.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initiales.isNotEmpty ? initiales : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
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
                  fullName.isNotEmpty ? fullName : 'Utilisateur',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                if (profession.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      profession,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _green,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 7),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildEditableRow({
    required String label,
    required String value,
    required VoidCallback onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_rounded, size: 15, color: _green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyRow({
    required String label,
    required String value,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: Colors.grey.shade300,
          ),
        ],
      ),
    );
  }

  Widget _buildTappableRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.grey.shade100,
    );
  }
}
