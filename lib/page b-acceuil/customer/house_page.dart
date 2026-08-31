import 'package:flutter/material.dart';
import 'package:baxa/page%20b-acceuil/customer/search_page.dart';
import 'package:baxa/page%20b-acceuil/customer/persona_page.dart';
import 'package:baxa/page%20b-acceuil/customer/my_reservations_page.dart';
import 'package:baxa/page%20b-acceuil/customer/companyqueue_page.dart';
import 'package:baxa/page%20b-acceuil/customer/slots_page.dart';
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
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // ── KeepAlive ─────────────────────────────────────────────
  @override
  bool get wantKeepAlive => true;

  // ── Palette épurée — vert uniquement pour la marque et les actions
  static const Color _green = Color(0xFF4B8B5E); // vert marque
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _dark = Color(0xFF1A1C2E); // quasi-noir neutre
  final DateFormat _dateFmt = DateFormat('EEE d MMM', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  String? _prenom;
  bool _isScrolled = false;
  // Empêche un double/triple tap sur une carte de déclencher plusieurs
  // navigations en parallèle (chacune finirait par empiler sa propre page
  // de créneaux une fois sa requête résolue) — un seul tap "gagne" à la fois.
  bool _isOpeningCompany = false;
  late final ScrollController _scrollController;
  Stream<QuerySnapshot>? _appointmentsStream;
  Stream<QuerySnapshot>? _favoritesStream;

  late final AnimationController _headerAnimCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _headerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    // Le fade se termine à 65% de la durée — apparition rapide
    _headerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerAnimCtrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );
    // Le slide continue sur toute la durée avec une décélération plus physique
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, -0.07), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _headerAnimCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 0;
      if (scrolled != _isScrolled) setState(() => _isScrolled = scrolled);
    });
    _headerAnimCtrl.forward();
    _checkPendingCancellation();
    _loadPrenom();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _appointmentsStream = FirebaseFirestore.instance
          .collectionGroup('reservations')
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'confirmed')
          .snapshots();
      _favoritesStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .limit(10)
          .snapshots();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _headerAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrenom() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() => _prenom = doc.data()?['prenom'] as String?);
      }
    } catch (_) {}
  }

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bon matin';
    if (h < 18) return 'Bonjour';
    return 'Bonsoir';
  }

  IconData _getGreetingIcon() {
    final h = DateTime.now().hour;
    if (h < 12) return Icons.wb_sunny_outlined;
    if (h < 18) return Icons.light_mode_rounded;
    return Icons.nights_stay_outlined;
  }

  String _getRelativeTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Demain';
    if (diff <= 7) return 'Dans $diff jours';
    return _dateFmt.format(date);
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

  // ── Navigation favoris (skip si 1 seule file) ───────────────────────────
  Future<void> _navigateToFavorite(String companyId, String nom) async {
    if (_isOpeningCompany) return;
    _isOpeningCompany = true;

    // LOG TEMPORAIRE DE DIAGNOSTIC — à retirer une fois la cause trouvée.
    final tapAt = DateTime.now();
    debugPrint('🔎[NAV-FAV] tap "$nom" ($companyId) @ $tapAt');

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Délai volontaire : le StreamBuilder de "Mes favoris" retrie la liste
        // dès que ce champ change, ce qui faisait visiblement bouger les
        // cartes au moment même du tap, juste avant la navigation. En
        // retardant l'écriture au-delà de la durée de la transition de page,
        // le réarrangement se produit une fois la liste hors champ.
        Future.delayed(const Duration(milliseconds: 500), () {
          FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('favorites')
              .doc(companyId)
              .update({'lastAccessedAt': FieldValue.serverTimestamp()})
              .ignore();
        });
      }

      if (!mounted) return;

      final queuesSnap = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('queues')
          .orderBy('createdAt')
          .get();

      debugPrint(
        '🔎[NAV-FAV] queuesSnap "$nom" reçu après '
        '${DateTime.now().difference(tapAt).inMilliseconds}ms '
        '(fromCache=${queuesSnap.metadata.isFromCache})',
      );

      if (!mounted) return;

      if (queuesSnap.docs.length == 1) {
        final queueDoc = queuesSnap.docs.first;
        final queueData = queueDoc.data();
        debugPrint(
          '🔎[NAV-FAV] push SlotsPage "$nom" @ '
          '+${DateTime.now().difference(tapAt).inMilliseconds}ms',
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SlotsPage(
              entrepriseId: companyId,
              entrepriseNom: nom,
              queueId: queueDoc.id,
              queueName: queueData['name'] as String? ?? 'File',
              primaryGreen: _green,
              lightGreen: _greenLight,
              onReservationSuccess: () {},
            ),
          ),
        );
      } else {
        debugPrint(
          '🔎[NAV-FAV] push CompanyQueuePage "$nom" @ '
          '+${DateTime.now().difference(tapAt).inMilliseconds}ms',
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CompanyQueuePage(
              entrepriseId: companyId,
              entrepriseNom: nom,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint(
        '🔎[NAV-FAV] erreur "$nom" @ '
        '+${DateTime.now().difference(tapAt).inMilliseconds}ms: $e',
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CompanyQueuePage(
              entrepriseId: companyId,
              entrepriseNom: nom,
            ),
          ),
        );
      }
    } finally {
      _isOpeningCompany = false;
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
    final companyId = data['companyId'] as String?;
    final queueId = data['queueId'] as String?;
    final slotId = data['slotId'] as String?;
    final slotStartTs = data['slotStart'] as Timestamp?;

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.update(doc.reference, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        if (companyId != null && queueId != null && slotId != null) {
          final slotRef = FirebaseFirestore.instance
              .collection('companies')
              .doc(companyId)
              .collection('queues')
              .doc(queueId)
              .collection('slots')
              .doc(slotId);
          tx.update(slotRef, {
            'reserved': FieldValue.increment(-1),
            'cancelled': FieldValue.increment(1),
          });

          if (slotStartTs != null) {
            final slotStart = slotStartTs.toDate().toLocal();
            final dateStr =
                '${slotStart.year}-'
                '${slotStart.month.toString().padLeft(2, '0')}-'
                '${slotStart.day.toString().padLeft(2, '0')}';
            final dailyStatsRef = FirebaseFirestore.instance
                .collection('companies')
                .doc(companyId)
                .collection('queues')
                .doc(queueId)
                .collection('dailyStats')
                .doc(dateStr);
            tx.set(dailyStatsRef, {
              'reserved': FieldValue.increment(-1),
              'available': FieldValue.increment(1),
              'cancelled': FieldValue.increment(1),
            }, SetOptions(merge: true));
          }
        }
      });

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
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                boxShadow: _isScrolled
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : [],
              ),
              child: FadeTransition(
                opacity: _headerFade,
                child: SlideTransition(
                  position: _headerSlide,
                  child: _buildHeader(),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
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
        color: Color(0xFF1B3A2A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo pill — blanc sur fond sombre
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      'Baxa',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF1B3A2A),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // Avatar
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PersonaPage()),
                      );
                      if (mounted) _loadPrenom();
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: _prenom != null
                          ? Center(
                              child: Text(
                                _prenom![0].toUpperCase(),
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.person_rounded,
                              color: Colors.white.withValues(alpha: 0.7),
                              size: 22,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Icon(
                    _getGreetingIcon(),
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_getGreeting()}, ${_prenom ?? ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Barre de recherche — blanche, ressort fort sur fond sombre
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SearchPage()),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 22,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                color: Colors.grey.shade400,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Rechercher...',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey.shade400,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 30,
                      color: Colors.grey.shade200,
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchPage(openScanner: true),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: _green,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
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
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _dark,
        letterSpacing: -0.2,
      ),
    );
  }

  // ── Prochains rendez-vous ─────────────────────────────────────────────────
  Widget _buildUpcomingAppointments() {
    if (_appointmentsStream == null) return _buildEmptyAppointments();

    return StreamBuilder<QuerySnapshot>(
      stream: _appointmentsStream,
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
        final futureDocs =
            snapshot.data!.docs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              // Actif jusqu'à la FIN du créneau (pas son début) : un
              // rendez-vous en cours doit rester visible sur l'accueil,
              // pas disparaître dès qu'il démarre.
              return (d['slotEnd'] as Timestamp).toDate().isAfter(now);
            }).toList()..sort((a, b) {
              final aTs =
                  (a.data() as Map<String, dynamic>)['slotStart'] as Timestamp;
              final bTs =
                  (b.data() as Map<String, dynamic>)['slotStart'] as Timestamp;
              return aTs.compareTo(bTs);
            });
        final displayDocs = futureDocs.take(5).toList();

        if (displayDocs.isEmpty) return _buildEmptyAppointments();

        // Hauteur dictée par le contenu réel (IntrinsicHeight) plutôt qu'une
        // valeur fixe devinée à l'avance — un rendu de police légèrement
        // plus haut sur certains appareils (observé sur un Xiaomi Android 16)
        // ne peut plus faire déborder la carte de quelques pixels.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < displayDocs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  _buildAppointmentCard(displayDocs[i]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppointmentCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final storedName = (data['companyName'] as String?)?.isNotEmpty == true
        ? data['companyName'] as String
        : (data['queueName'] as String?)?.isNotEmpty == true
            ? data['queueName'] as String
            : null;
    final companyId = data['companyId'] as String?;

    if (storedName != null) {
      return _buildAppointmentCardContent(doc, data, storedName);
    }

    if (companyId == null) {
      return _buildAppointmentCardContent(doc, data, 'Réservation');
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get(),
      builder: (context, snap) {
        String name = 'Réservation';
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>?;
          name = (d?['nom'] as String?) ?? 'Réservation';
        }
        return _buildAppointmentCardContent(doc, data, name);
      },
    );
  }

  Widget _buildAppointmentCardContent(
    DocumentSnapshot doc,
    Map<String, dynamic> data,
    String companyName,
  ) {
    final slotStart = (data['slotStart'] as Timestamp).toDate();
    final slotEnd = (data['slotEnd'] as Timestamp).toDate();
    final queueName = data['queueName'] as String? ?? '';

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: _green),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _greenLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.event_available_rounded,
                            color: _green,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            companyName,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: _dark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _greenLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _green.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 9,
                                color: _green,
                              ),
                              const SizedBox(width: 3),
                              const Text(
                                'Confirmé',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: _green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (queueName.isNotEmpty &&
                        queueName != companyName) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 34),
                        child: Text(
                          queueName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _getRelativeTime(slotStart),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _dark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 12,
                          color: _green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_timeFmt.format(slotStart)} – ${_timeFmt.format(slotEnd)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _CancelButton(onTap: () => _showCancelSheet(doc)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAppointments() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                  'Pas encore de rendez-vous',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Trouvez une structure près de vous',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B3A2A),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      'Réserver maintenant →',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
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
    if (_favoritesStream == null) return _buildEmptyFavorites();

    return StreamBuilder<QuerySnapshot>(
      stream: _favoritesStream,
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

        final docs = [...snapshot.data!.docs]..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs =
                (aData['lastAccessedAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                (aData['addedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            final bTs =
                (bData['lastAccessedAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                (bData['addedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            return bTs.compareTo(aTs);
          });
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
                onTap: () => _navigateToFavorite(companyId, nom),
                child: Stack(
                  children: [
                    Container(
                      width: 110,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Colors.grey.shade100, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
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
                                colors: [
                                  Color(0xFF4B8B5E),
                                  Color(0xFF1B3A2A),
                                ],
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
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        Icons.star_rounded,
                        color: Color(0xFFE8A020),
                        size: 14,
                      ),
                    ),
                  ],
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
        border: Border.all(color: Colors.grey.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 38),
            const SizedBox(height: 6),
            Text(
              'Appui long sur une structure\npour l\'ajouter aux favoris',
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
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
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
        color: const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE4A0), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD166).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: Color(0xFFD4870A),
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

class _CancelButton extends StatefulWidget {
  const _CancelButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.88),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.88, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 78,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
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
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.red.shade400,
            ),
          ),
        ),
      ),
    );
  }
}
