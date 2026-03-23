import 'package:flutter/material.dart';
import 'package:baxa/page%20b-acceuil/customer/search_page.dart';
import 'package:baxa/page%20b-acceuil/customer/persona_page.dart';
import 'package:baxa/page%20b-acceuil/customer/my_reservations_page.dart';
import 'package:baxa/page%20b-acceuil/customer/companyqueue_page.dart';
import 'package:baxa/page b-acceuil/customer/annulation_confirmation_page.dart';
import 'package:baxa/services/notifications/gestionnaire_annulations_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class HousePage extends StatefulWidget {
  const HousePage({super.key});
  @override
  State<HousePage> createState() => _HousePageState();
}

class _HousePageState extends State<HousePage>
    with AutomaticKeepAliveClientMixin {
  // ── KeepAlive ─────────────────────────────────────────────
  @override
  bool get wantKeepAlive => true;

  // ── Palette chaleureuse (vert vivant, fond légèrement teinté, pas de noir froid)
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _greenMid = Color(0xFFB2D3C2);
  static const Color _bg = Color(0xFFF7F9F7);
  static const Color _dark = Color(0xFF1E2D23); // vert très foncé, chaleureux

  final DateFormat _dateFmt = DateFormat('EEE d MMM', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _checkPendingCancellation();
  }

  Future<void> _checkPendingCancellation() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final reservation = await CancellationHandler().findActiveReservation(
        user.uid,
      );
      if (reservation != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CancellationConfirmationPage(reservation: reservation),
          ),
        );
      }
    }
  }

  // ── Bottom sheet annulation ──────────────────────────────────────────────
  Future<void> _showCancelSheet(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final queueName = data['queueName'] ?? 'cette réservation';
    final slotStart = (data['slotStart'] as Timestamp).toDate();

    final confirmed = await showModalBottomSheet<bool>(
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
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_busy_rounded,
                color: Colors.red.shade400,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Annuler ce rendez-vous ?',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$queueName · ${_timeFmt.format(slotStart)} le ${_dateFmt.format(slotStart)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Text(
              'Êtes-vous sûr de vraiment vouloir annuler ce rendez-vous ?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Non',
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
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Oui',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) await _cancelReservation(doc);
  }

  Future<void> _cancelReservation(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(doc.reference, {'status': 'cancelled'});

      final companyId = data['companyId'] as String?;
      final queueId = data['queueId'] as String?;
      final slotId = data['slotId'] as String?;

      if (companyId != null && queueId != null && slotId != null) {
        final slotRef = FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .collection('queues')
            .doc(queueId)
            .collection('slots')
            .doc(slotId);
        batch.update(slotRef, {'reserved': FieldValue.increment(-1)});
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Réservation annulée'),
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

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context); // requis par AutomaticKeepAliveClientMixin
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Prochains rendez-vous'),
                    const SizedBox(height: 12),
                    _buildUpcomingAppointments(),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Mes favoris'),
                    const SizedBox(height: 12),
                    _buildFavorites(),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Accès rapide'),
                    const SizedBox(height: 12),
                    _buildQuickActions(),
                    const SizedBox(height: 28),
                    _buildInfoCard(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFEDF3EF), width: 1.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo pill vert vivant
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      'Baxa',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  // Avatar vert clair avec bordure, pas intimidant
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PersonaPage()),
                    ),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _greenLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: _greenMid, width: 2),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: _green,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Headline avec emoji pour chaleur
              Text(
                'Votre place,',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                  height: 1.15,
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'sans attendre ',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _green,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Barre recherche fond vert très clair
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _greenLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _greenMid, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: _green,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Rechercher une entreprise...',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF8AAD97),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section title ─────────────────────────────────────────────────────────
  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: _green,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _dark,
          ),
        ),
      ],
    );
  }

  // ── Prochains rendez-vous ─────────────────────────────────────────────────
  Widget _buildUpcomingAppointments() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _buildEmptyAppointments();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('reservations')
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'confirmed')
          .orderBy('slotStart')
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 120,
            child: Center(
              child: CircularProgressIndicator(color: _green, strokeWidth: 2),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyAppointments();
        }
        final now = DateTime.now();
        final futureDocs = snapshot.data!.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return (d['slotStart'] as Timestamp).toDate().isAfter(now);
        }).toList();

        if (futureDocs.isEmpty) return _buildEmptyAppointments();

        return SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: futureDocs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _buildAppointmentCard(futureDocs[i]),
          ),
        );
      },
    );
  }

  Widget _buildAppointmentCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final queueName = data['queueName'] ?? 'Réservation';
    final companyName = data['companyName'] ?? queueName;
    final slotStart = (data['slotStart'] as Timestamp).toDate();
    final slotEnd = (data['slotEnd'] as Timestamp).toDate();

    return Container(
      width: 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _greenMid.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _green.withOpacity(0.07),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _greenLight,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: _green,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  companyName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _dark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            queueName,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 13, color: _green),
              const SizedBox(width: 4),
              Text(
                '${_timeFmt.format(slotStart)} – ${_timeFmt.format(slotEnd)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _dateFmt.format(slotStart),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _showCancelSheet(doc),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200, width: 1),
              ),
              child: Text(
                'Je ne viens plus',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAppointments() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _greenMid.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _greenLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              color: _green,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aucun rendez-vous',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Vos prochaines réservations apparaîtront ici',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Favoris ──────────────────────────────────────────────────────────────
  Widget _buildFavorites() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _buildEmptyFavorites();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 110,
            child: Center(
              child: CircularProgressIndicator(color: _green, strokeWidth: 2),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyFavorites();
        }

        final docs = snapshot.data!.docs;
        return SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final fav = docs[i].data() as Map<String, dynamic>;
              final nom = fav['nom'] ?? '?';
              final type = fav['type'] ?? '';
              final companyId = docs[i].id;
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompanyQueuePage(
                      entrepriseId: companyId,
                      entrepriseNom: nom,
                    ),
                  ),
                ),
                child: Container(
                  width: 110,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _greenMid.withOpacity(0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _green.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_green, Color(0xFF2D5A3D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        nom,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _dark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      if (type.isNotEmpty)
                        Text(
                          type,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyFavorites() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _greenMid.withOpacity(0.4), width: 1.5),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline_rounded, color: _greenMid, size: 26),
            const SizedBox(height: 6),
            Text(
              'Appui long sur une entreprise\npour l\'ajouter aux favoris',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Accès rapide ──────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildQuickCard(
            icon: Icons.search_rounded,
            title: 'Rechercher',
            color: _green,
            bg: _greenLight,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickCard(
            icon: Icons.event_note_rounded,
            title: 'Mes réservations',
            color: const Color(0xFFE07B39),
            bg: const Color(0xFFFFF3EC),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyReservationsPage()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickCard({
    required IconData icon,
    required String title,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: _dark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Info card ─────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _greenLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _greenMid.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: _green,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comment ça marche ?',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Recherchez, réservez et recevez des alertes. Annulez en un tap si vous ne pouvez plus venir.',
                  style: TextStyle(
                    color: Color(0xFF4A7A5A),
                    fontSize: 12,
                    height: 1.4,
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
