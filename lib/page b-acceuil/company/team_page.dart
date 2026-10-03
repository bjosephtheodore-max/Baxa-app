import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:baxa/services/booking_constants.dart';

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

  // Cache mémoire (durée de l'app) pour éviter un rechargement à vide à
  // chaque ouverture de la page : on affiche tout de suite ce qu'on a déjà
  // vu, pendant qu'un rafraîchissement silencieux tourne en arrière-plan.
  static String? _cachedCompanyId;
  static String? _cachedCompanyName;
  static String? _cachedActiveCode;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _companyId = user?.uid;

    final hasCache = _cachedCompanyId == _companyId && _cachedCompanyId != null;
    if (hasCache) {
      _companyName = _cachedCompanyName;
      _activeCode = _cachedActiveCode;
      _isLoading = false;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    if (_companyId == null) return;
    try {
      // Les deux lectures sont indépendantes : on les lance ensemble au lieu
      // de les enchaîner pour ne pas payer deux allers-retours réseau.
      final docFuture = _firestore.collection('companies').doc(_companyId).get();
      final inviteFuture = _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('invitations')
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      final doc = await docFuture;
      final inviteSnap = await inviteFuture;

      if (doc.exists) {
        _companyName =
            (doc.data() as Map<String, dynamic>)['nom'] as String? ?? 'Baxa';
      }
      _activeCode = inviteSnap.docs.isNotEmpty
          ? (inviteSnap.docs.first.data())['code'] as String?
          : null;

      _cachedCompanyId = _companyId;
      _cachedCompanyName = _companyName;
      _cachedActiveCode = _activeCode;
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

      _cachedActiveCode = code;
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
  // NOMMER / RETIRER UN MEMBRE
  // ==============================================================
  Future<void> _showEditNameDialog({
    required String uid,
    required String phone,
    required String currentName,
  }) async {
    final controller = TextEditingController(text: currentName);
    final newValue = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Text(
                currentName.isEmpty ? 'Ajouter le nom' : 'Modifier le nom',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                // Clavier seulement pour un premier nom : un membre déjà
                // nommé, on rouvre plutôt pour « Retirer de l'équipe ».
                autofocus: currentName.isEmpty,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Nom du membre',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: _green, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Annuler',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text(
                        'Enregistrer',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _revokeMember(uid, phone);
                  },
                  icon: Icon(
                    Icons.person_remove_rounded,
                    color: Colors.red.shade400,
                    size: 18,
                  ),
                  label: Text(
                    'Retirer de l\'équipe',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (newValue != null && newValue.isNotEmpty && newValue != currentName) {
      try {
        await _firestore
            .collection('companies')
            .doc(_companyId)
            .collection('staff')
            .doc(uid)
            .update({'displayName': newValue});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
          );
        }
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
          ? _buildSkeleton()
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

  // ── Skeleton ──────────────────────────────────────────────
  Widget _skBox({double height = 16, double? width, double radius = 8}) =>
      Container(
        height: height,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Carte invitation skeleton
          Container(
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
                    _skBox(height: 42, width: 42, radius: 10),
                    const SizedBox(width: 12),
                    _skBox(height: 18, width: 140),
                  ],
                ),
                const SizedBox(height: 16),
                _skBox(height: 13),
                const SizedBox(height: 6),
                _skBox(height: 13, width: 220),
                const SizedBox(height: 20),
                _skBox(height: 52, radius: 12),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Titre membres skeleton
          _skBox(height: 16, width: 120),
          const SizedBox(height: 12),
          // Lignes membres skeleton
          for (int i = 0; i < 2; i++) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _skBox(height: 42, width: 42, radius: 21),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skBox(height: 15),
                        const SizedBox(height: 6),
                        _skBox(height: 12, width: 140),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
            'Générez un code et partagez-le avec votre vigil ou réceptionniste. '
            'Maximum $kMaxActiveStaff membres.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
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
              return Column(
                children: [
                  for (int i = 0; i < 2; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _skBox(height: 42, width: 42, radius: 21),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _skBox(height: 15),
                                const SizedBox(height: 6),
                                _skBox(height: 12, width: 140),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
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
                final displayName = data['displayName'] as String? ?? '';
                final uid = doc.id;
                final joinedAt = data['joinedAt'] as Timestamp?;
                final lastSeenAt = data['lastSeenAt'] as Timestamp?;

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
                              displayName.isNotEmpty ? displayName : phone,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                            if (displayName.isNotEmpty)
                              Text(
                                phone,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              )
                            else if (joinedAt != null)
                              Text(
                                'Membre depuis ${_formatDate(joinedAt.toDate())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            if (lastSeenAt != null)
                              Text(
                                _lastSeenLabel(lastSeenAt.toDate()),
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
                          Icons.edit_rounded,
                          color: _green,
                          size: 20,
                        ),
                        tooltip: 'Modifier le nom',
                        onPressed: () => _showEditNameDialog(
                          uid: uid,
                          phone: phone,
                          currentName: displayName,
                        ),
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
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'jun',
      'jul',
      'aoû',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // « Actif aujourd'hui », « Vu hier », « Vu il y a 3 jours »…
  String _lastSeenLabel(DateTime date) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (days <= 0) return 'Actif aujourd\'hui';
    if (days == 1) return 'Vu hier';
    if (days < 30) return 'Vu il y a $days jours';
    return 'Vu le ${_formatDate(date)}';
  }
}
