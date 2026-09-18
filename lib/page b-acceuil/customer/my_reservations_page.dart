import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:baxa/page%20b-acceuil/customer/search_page.dart';

class MyReservationsPage extends StatefulWidget {
  const MyReservationsPage({super.key});

  @override
  State<MyReservationsPage> createState() => _MyReservationsPageState();
}

class _MyReservationsPageState extends State<MyReservationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('EEE d MMM', 'fr_FR');
  final DateFormat _dateFmtLong = DateFormat('EEEE d MMMM', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _dark = Color(0xFF1A1C2E);
  static const Color _headerGreen = Color(0xFF1B3A2A);

  String? _userId;
  final Map<String, String> _companyNameCache = {};
  final Set<String> _fetchingIds = {};

  bool _isLoading = true;
  String? _error;
  List<QueryDocumentSnapshot> _reservations = [];
  Set<String> _hiddenIds = {};

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    if (_userId != null) _loadData();
  }

  // Chargement ponctuel (plutôt qu'une écoute .snapshots() permanente) :
  // cette page n'a pas besoin de mise à jour seconde par seconde, et ça
  // évite de facturer une lecture Firestore à chaque changement pendant
  // que l'écran reste ouvert. Le geste "tirer pour rafraîchir" couvre le
  // besoin de mise à jour manuelle.
  Future<void> _loadData() async {
    if (_userId == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _firestore
            .collectionGroup('reservations')
            .where('customerId', isEqualTo: _userId)
            .where('status', isEqualTo: 'confirmed')
            .get(),
        _firestore.collection('users').doc(_userId).get(),
      ]);
      final reservationsSnap = results[0] as QuerySnapshot;
      final userDoc = results[1] as DocumentSnapshot;
      final hidden =
          (userDoc.data() as Map<String, dynamic>?)?['hiddenReservations']
              as List?;

      if (!mounted) return;
      setState(() {
        _reservations = reservationsSnap.docs;
        _hiddenIds = hidden?.map((e) => e.toString()).toSet() ?? {};
        _isLoading = false;
      });
      _prefetchCompanyNames(_reservations);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  // Masquage côté client (pas de suppression réelle) : le document de
  // réservation est partagé avec l'entreprise, qui en garde légitimement
  // besoin pour ses propres statistiques — seule la vue du client change.
  Future<void> _hideReservation(String docId) async {
    if (_userId == null) return;
    final previous = Set<String>.of(_hiddenIds);
    setState(() => _hiddenIds = {..._hiddenIds, docId});
    try {
      await _firestore.collection('users').doc(_userId).set({
        'hiddenReservations': FieldValue.arrayUnion([docId]),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      setState(() => _hiddenIds = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _prefetchCompanyNames(List<QueryDocumentSnapshot> docs) {
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final stored = data['companyName'] as String?;
      if (stored != null && stored.isNotEmpty) continue;

      final companyId = data['companyId'] as String? ?? '';
      if (companyId.isEmpty) continue;
      if (_companyNameCache.containsKey(companyId)) continue;
      if (_fetchingIds.contains(companyId)) continue;

      _fetchingIds.add(companyId);
      _firestore
          .collection('companies')
          .doc(companyId)
          .get()
          .then((snap) {
            final name = (snap.data()?['nom'] as String?) ?? '';
            if (!mounted) return;
            setState(() {
              _companyNameCache[companyId] = name.isNotEmpty
                  ? name
                  : (data['queueName'] as String? ?? '');
            });
          })
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes réservations')),
        body: const Center(child: Text('Veuillez vous connecter')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _headerGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Mes réservations',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _green,
        onRefresh: _loadData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 400,
            child: Center(
              child: CircularProgressIndicator(color: _green, strokeWidth: 2),
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 400,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erreur : $_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final visible =
        _reservations.where((d) => !_hiddenIds.contains(d.id)).toList()
          ..sort((a, b) {
            final aTs =
                (a.data() as Map<String, dynamic>)['slotStart'] as Timestamp;
            final bTs =
                (b.data() as Map<String, dynamic>)['slotStart'] as Timestamp;
            return aTs.compareTo(bTs);
          });

    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: 400, child: _buildEmptyState())],
      );
    }

    final now = DateTime.now();
    final activeReservations = <QueryDocumentSnapshot>[];
    final pastReservations = <QueryDocumentSnapshot>[];

    for (final doc in visible) {
      final data = doc.data() as Map<String, dynamic>;
      final slotEnd = (data['slotEnd'] as Timestamp).toDate();
      final status = data['status'] ?? 'confirmed';

      // Actif jusqu'à la FIN du créneau (pas son début) : un rendez-vous en
      // cours doit rester visible en "À venir", pas basculer en Historique
      // dès qu'il démarre.
      if (status == 'cancelled') {
        pastReservations.add(doc);
      } else if (slotEnd.isAfter(now)) {
        activeReservations.add(doc);
      } else {
        pastReservations.add(doc);
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        if (activeReservations.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _greenLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _green.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: _green,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${activeReservations.length} réservation${activeReservations.length > 1 ? 's' : ''} à venir',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: _green,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (activeReservations.isNotEmpty) ...[
          _buildSectionTitle('À venir'),
          const SizedBox(height: 12),
          ...activeReservations.map(
            (doc) => _buildReservationCard(doc, isActive: true),
          ),
          const SizedBox(height: 28),
        ],

        if (pastReservations.isNotEmpty) ...[
          _buildSectionTitle('Historique'),
          const SizedBox(height: 12),
          ...pastReservations.map(
            (doc) => Dismissible(
              key: Key('hide-${doc.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Masquer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              onDismissed: (_) => _hideReservation(doc.id),
              child: _buildReservationCard(doc, isActive: false),
            ),
          ),
        ],
      ],
    );
  }

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

  // ── Carte réservation ──────────────────────────────────────────────────────
  Widget _buildReservationCard(
    QueryDocumentSnapshot doc, {
    required bool isActive,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    final companyId = data['companyId'] as String? ?? '';

    final name = (data['companyName'] as String?)?.isNotEmpty == true
        ? data['companyName'] as String
        : _companyNameCache[companyId]?.isNotEmpty == true
        ? _companyNameCache[companyId]!
        : (data['queueName'] as String?)?.isNotEmpty == true
        ? data['queueName'] as String
        : 'Réservation';

    return _buildCardContent(doc, data, name, isActive: isActive);
  }

  Widget _buildCardContent(
    QueryDocumentSnapshot doc,
    Map<String, dynamic> data,
    String companyName, {
    required bool isActive,
  }) {
    final companyId = data['companyId'] as String? ?? '';
    final queueId = data['queueId'] as String? ?? '';
    final slotId = data['slotId'] as String? ?? '';
    final queueName = data['queueName'] as String? ?? '';
    final slotStart = (data['slotStart'] as Timestamp).toDate();
    final slotEnd = (data['slotEnd'] as Timestamp).toDate();
    final status = data['status'] as String? ?? 'confirmed';

    final isCancelled = status == 'cancelled';
    final isPast = slotEnd.isBefore(DateTime.now());
    final isSuspended = data['suspended'] == true && !isCancelled;
    final suspendedReason = data['suspendedReason'] as String?;

    Color borderColor;
    Color iconBg;
    Color iconColor;
    IconData iconData;

    if (isCancelled) {
      borderColor = Colors.red.shade100;
      iconBg = Colors.red.shade50;
      iconColor = Colors.red.shade300;
      iconData = Icons.event_busy_rounded;
    } else if (isSuspended) {
      borderColor = Colors.orange.shade200;
      iconBg = Colors.orange.shade50;
      iconColor = Colors.orange.shade400;
      iconData = Icons.pause_circle_outline_rounded;
    } else if (isActive) {
      borderColor = _green.withValues(alpha: 0.2);
      iconBg = _greenLight;
      iconColor = _green;
      iconData = Icons.event_available_rounded;
    } else {
      borderColor = Colors.grey.shade200;
      iconBg = Colors.grey.shade100;
      iconColor = Colors.grey.shade500;
      iconData = Icons.event_note_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        // IntrinsicHeight : calcule d'abord la hauteur naturelle du contenu
        // (variable selon le bouton "Annuler" et la 2e ligne de texte)
        // avant que CrossAxisAlignment.stretch n'étire la bande colorée —
        // sans ça, le Row hérite d'une hauteur infinie dans le ListView.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                color: isActive && !isCancelled ? _green : borderColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(iconData, color: iconColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  companyName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _dark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (queueName.isNotEmpty &&
                                    queueName != companyName) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    queueName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  _dateFmt.format(slotStart),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(
                            isCancelled,
                            isPast,
                            isActive,
                            isSuspended,
                          ),
                        ],
                      ),
                      if (isSuspended) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.shade100),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  (suspendedReason != null &&
                                          suspendedReason.isNotEmpty)
                                      ? 'Service suspendu : $suspendedReason. Vous serez prévenu(e) à la reprise.'
                                      : 'Service momentanément suspendu. Vous serez prévenu(e) à la reprise.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: isActive && !isCancelled
                              ? _greenLight
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: isActive && !isCancelled
                                  ? _green
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_timeFmt.format(slotStart)} – ${_timeFmt.format(slotEnd)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isActive && !isCancelled
                                    ? _green
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isActive && !isCancelled) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _confirmCancellation(
                            doc.reference,
                            companyId,
                            queueId,
                            slotId,
                            companyName,
                            slotStart,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.red.shade200,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'Annuler cette réservation',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildStatusBadge(
    bool isCancelled,
    bool isPast,
    bool isActive, [
    bool isSuspended = false,
  ]) {
    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.shade100, width: 1),
        ),
        child: Text(
          'Annulée',
          style: TextStyle(
            color: Colors.red.shade400,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (isSuspended) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade200, width: 1),
        ),
        child: Text(
          'Suspendue',
          style: TextStyle(
            color: Colors.orange.shade700,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (isPast) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Passée',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _greenLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _green.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 9, color: _green),
          const SizedBox(width: 3),
          const Text(
            'Confirmée',
            style: TextStyle(
              color: _green,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheet annulation ────────────────────────────────────────────────
  Future<void> _confirmCancellation(
    DocumentReference reservationRef,
    String companyId,
    String queueId,
    String slotId,
    String companyName,
    DateTime slotStart,
  ) async {
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
            const SizedBox(height: 8),
            Text(
              companyName,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _green,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_dateFmtLong.format(slotStart)[0].toUpperCase()}${_dateFmtLong.format(slotStart).substring(1)} · ${_timeFmt.format(slotStart)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Text(
              'Cette action est irréversible.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
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
                      'Garder',
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
                      'Annuler',
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

    if (confirmed == true && mounted) {
      await _cancelReservation(
        reservationRef,
        companyId,
        queueId,
        slotId,
        slotStart,
      );
    }
  }

  Future<void> _cancelReservation(
    DocumentReference reservationRef,
    String companyId,
    String queueId,
    String slotId,
    DateTime slotStart,
  ) async {
    final dateStr =
        '${slotStart.year}-'
        '${slotStart.month.toString().padLeft(2, '0')}-'
        '${slotStart.day.toString().padLeft(2, '0')}';

    final dailyStatsRef = _firestore
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .doc(queueId)
        .collection('dailyStats')
        .doc(dateStr);

    try {
      await _firestore.runTransaction((transaction) async {
        final slotRef = _firestore
            .collection('companies')
            .doc(companyId)
            .collection('queues')
            .doc(queueId)
            .collection('slots')
            .doc(slotId);

        transaction.update(slotRef, {
          'reserved': FieldValue.increment(-1),
          'cancelled': FieldValue.increment(1),
        });
        transaction.update(reservationRef, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
        transaction.set(dailyStatsRef, {
          'reserved': FieldValue.increment(-1),
          'available': FieldValue.increment(1),
          'cancelled': FieldValue.increment(1),
        }, SetOptions(merge: true));
      });

      if (!mounted) return;
      // Retrait immédiat de la liste — la page ne se recharge (un seul .get)
      // qu'à la réouverture ou au tirer-pour-rafraîchir.
      setState(() {
        _reservations = _reservations
            .where((d) => d.reference.path != reservationRef.path)
            .toList();
      });
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: _greenLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_today_outlined,
                size: 48,
                color: _green.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucune réservation',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos réservations apparaîtront ici',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SearchPage()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _headerGreen,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  'Faire une réservation →',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
