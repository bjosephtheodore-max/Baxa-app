import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

// ============================================================
// TEAM PAGE — Gestion de l'équipe (côté admin uniquement)
// ============================================================
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _companyId;
  String? _companyName;
  bool _isLoading = true;

  // Code d'invitation actif
  String? _activeCode;
  bool _isGeneratingCode = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _companyId = user?.uid;
    _loadData();
  }

  Future<void> _loadData() async {
    if (_companyId == null) return;
    try {
      final doc = await _firestore.collection('companies').doc(_companyId).get();
      if (doc.exists) {
        _companyName =
            (doc.data() as Map<String, dynamic>)['nom'] as String? ?? 'Baxa';
      }
      // Chercher un code d'invitation actif existant
      final inviteSnap = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('invitations')
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (inviteSnap.docs.isNotEmpty) {
        _activeCode =
            (inviteSnap.docs.first.data())['code'] as String?;
      }
    } catch (e) {
      debugPrint('TeamPage load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==============================================================
  // GÉNÉRER UN CODE D'INVITATION
  // ==============================================================
  Future<void> _generateInviteCode() async {
    if (_companyId == null) return;
    setState(() => _isGeneratingCode = true);
    try {
      // Désactiver les anciens codes
      final old = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('invitations')
          .where('active', isEqualTo: true)
          .get();
      final batch = _firestore.batch();
      for (final doc in old.docs) {
        batch.update(doc.reference, {'active': false});
      }
      await batch.commit();

      // Générer un nouveau code à 6 caractères
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rng = Random.secure();
      final code = List.generate(
        6,
        (_) => chars[rng.nextInt(chars.length)],
      ).join();

      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('invitations')
          .add({
            'code': code,
            'companyId': _companyId,
            'companyName': _companyName ?? '',
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) setState(() => _activeCode = code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingCode = false);
    }
  }

  // ==============================================================
  // PARTAGER LE LIEN
  // ==============================================================
  void _shareInvite() {
    if (_activeCode == null) return;
    final message =
        '👋 Rejoignez mon equipe sur Baxa !\n\n'
        '📱 Telechargez l\'app :\n'
        '  Android → https://play.google.com/store/apps/details?id=com.baxa.app\n'
        '  iPhone  → https://apps.apple.com/app/baxa/id000000000\n\n'
        'Puis ouvrez l\'app, choisissez "Rejoindre une equipe" et entrez ce code :\n\n'
        '🔑 *$_activeCode*\n\n'
        '(Ce code est a usage unique, ne le partagez pas.)';
    Share.share(message);
  }

  // ==============================================================
  // RÉVOQUER UN MEMBRE
  // ==============================================================
  Future<void> _revokeMember(String uid, String phone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retirer ce membre ?'),
        content: Text(
          'Le membre ($phone) perdra immédiatement l\'accès à votre espace Baxa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );

    if (confirmed != true || _companyId == null) return;

    try {
      await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('staff')
          .doc(uid)
          .update({'isActive': false});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Membre retiré de l\'équipe.'),
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

  // ==============================================================
  // BUILD
  // ==============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Mon équipe',
          style: TextStyle(
            color: _green,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInviteCard(),
                  const SizedBox(height: 24),
                  _buildMembersList(),
                ],
              ),
            ),
    );
  }

  // ── Carte d'invitation ────────────────────────────────────
  Widget _buildInviteCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _greenLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded, color: _green, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'Inviter un membre',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Générez un code et partagez-le avec votre vigil ou réceptionniste. Maximum 3 membres.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 20),

          // Code actif
          if (_activeCode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _greenLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _activeCode!,
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: _green,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: _green),
                    tooltip: 'Copier',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _activeCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Code copié !'),
                          backgroundColor: _green,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareInvite,
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Partager'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: BorderSide(color: _green.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGeneratingCode ? null : _generateInviteCode,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Nouveau code'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isGeneratingCode ? null : _generateInviteCode,
                icon: _isGeneratingCode
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_link_rounded),
                label: Text(
                  _isGeneratingCode ? 'Génération...' : 'Générer un code',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Liste des membres ──────────────────────────────────────
  Widget _buildMembersList() {
    if (_companyId == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Membres actifs',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('companies')
              .doc(_companyId)
              .collection('staff')
              .where('isActive', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: _green),
                ),
              );
            }

            final members = snapshot.data?.docs ?? [];

            if (members.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.group_outlined,
                      size: 40,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Aucun membre pour l\'instant',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Partagez le code d\'invitation ci-dessus.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: members.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final phone = data['phone'] as String? ?? 'Numéro inconnu';
                final uid = doc.id;
                final joinedAt = data['joinedAt'] as Timestamp?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
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
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _greenLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: _green,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              phone,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                            if (joinedAt != null)
                              Text(
                                'Membre depuis ${_formatDate(joinedAt.toDate())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.person_remove_rounded,
                          color: Colors.red.shade400,
                          size: 22,
                        ),
                        tooltip: 'Retirer de l\'équipe',
                        onPressed: () => _revokeMember(uid, phone),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
