import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:baxa/page%20b-acceuil/company/settings_page.dart'
    show QueueTimeSlotsPage;
import 'package:baxa/page%20b-acceuil/company/team_page.dart';

/// Page « Notifications » partagée par l'espace admin et l'espace staff.
///
/// Source unique : `companies/{companyId}/companyNotifications`, écrite
/// uniquement côté serveur (Cloud Functions). Le filtrage par destinataire se
/// fait EN MÉMOIRE sur un flux plafonné — aucun index Firestore composite.
///
/// Deux tailles de carte (récap riche / alerte compacte), regroupement par
/// période, et un code couleur à trois familles : vert (demande / positif),
/// ambre (à surveiller), gris (information / bilan).
class CompanyNotificationsPage extends StatefulWidget {
  const CompanyNotificationsPage({
    super.key,
    required this.companyId,
    required this.audience,
    this.staffId,
  });

  final String companyId;

  /// `'admin'` ou `'staff'`.
  final String audience;

  /// Requis quand [audience] vaut `'staff'` : ne garder que ses notifs.
  final String? staffId;

  @override
  State<CompanyNotificationsPage> createState() =>
      _CompanyNotificationsPageState();
}

class _CompanyNotificationsPageState extends State<CompanyNotificationsPage> {
  static const _green = Color(0xFF4B8B5E);
  static const _dark = Color(0xFF1A1C2E);
  static const _ground = Color(0xFFF7F8F6);

  late final Query<Map<String, dynamic>> _stream = FirebaseFirestore.instance
      .collection('companies')
      .doc(widget.companyId)
      .collection('companyNotifications')
      .orderBy('createdAt', descending: true)
      .limit(50);

  bool _isForMe(Map<String, dynamic> d) {
    final aud = (d['audience'] as String?) ?? 'admin';
    if (widget.audience == 'staff') {
      return aud == 'staff' && d['staffId'] == widget.staffId;
    }
    return aud == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            color: _dark,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Tout supprimer',
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: Colors.grey.shade500,
            ),
            onPressed: _confirmClearAll,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade100, height: 1),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _green, strokeWidth: 2),
            );
          }
          final docs = (snap.data?.docs ?? [])
              .where((d) => _isForMe(d.data()))
              .toList();
          if (docs.isEmpty) return const _EmptyState();

          final groups = _groupByPeriod(docs);
          return ListView(
            // Marge basse élargie : la barre de navigation flotte au-dessus
            // du contenu (extendBody), la dernière carte doit rester lisible.
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 104),
            children: [
              for (final g in groups) ...[
                _SectionHeader(g.label),
                for (final doc in g.docs)
                  _NotifCard(
                    key: ValueKey(doc.id),
                    id: doc.id,
                    data: doc.data(),
                    companyId: widget.companyId,
                    onDelete: () => _delete(doc.id),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Regroupement Aujourd'hui / Cette semaine / Plus tôt ────────────────
  List<_Group> _groupByPeriod(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(const Duration(days: 7));

    final today = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final week = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final older = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in docs) {
      final ts = d.data()['createdAt'];
      final date = ts is Timestamp ? ts.toDate() : now;
      if (!date.isBefore(startOfToday)) {
        today.add(d);
      } else if (!date.isBefore(startOfWeek)) {
        week.add(d);
      } else {
        older.add(d);
      }
    }

    return [
      if (today.isNotEmpty) _Group("Aujourd'hui", today),
      if (week.isNotEmpty) _Group('Cette semaine', week),
      if (older.isNotEmpty) _Group('Plus tôt', older),
    ];
  }

  Future<void> _delete(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(widget.companyId)
          .collection('companyNotifications')
          .doc(id)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Tout supprimer ?'),
        content: const Text(
          'Toutes les notifications de cette liste seront supprimées.',
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
            child: const Text('Tout supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final coll = FirebaseFirestore.instance
        .collection('companies')
        .doc(widget.companyId)
        .collection('companyNotifications');
    try {
      final snap = await coll.orderBy('createdAt', descending: true).get();
      final batch = FirebaseFirestore.instance.batch();
      var n = 0;
      for (final d in snap.docs) {
        if (!_isForMe(d.data())) continue;
        batch.delete(d.reference);
        if (++n >= 400) break;
      }
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// Style par type de notification
// ════════════════════════════════════════════════════════════════════
enum _Family { green, amber, grey }

class _Style {
  final IconData icon;
  final _Family family;
  final String label;
  final bool rich; // carte haute (récap)
  // Emoji affiché en grand à la place de la pastille+icône (évite le doublon
  // avec l'emoji déjà présent dans le titre).
  final String? bigEmoji;
  const _Style(
    this.icon,
    this.family,
    this.label, {
    this.rich = false,
    this.bigEmoji,
  });
}

const Map<String, _Style> _styles = {
  'day_digest': _Style(Icons.wb_sunny_rounded, _Family.grey, 'Résumé'),
  'plage_full': _Style(Icons.trending_up_rounded, _Family.green, 'Demande'),
  'plage_near_full': _Style(
    Icons.trending_up_rounded,
    _Family.amber,
    'À surveiller',
  ),
  'plage_underused': _Style(Icons.trending_down_rounded, _Family.grey, 'Bilan'),
  'staff_joined': _Style(
    Icons.person_add_alt_1_rounded,
    _Family.green,
    'Équipe',
  ),
  'plage_recap': _Style(
    Icons.bar_chart_rounded,
    _Family.grey,
    'Bilan du jour',
    rich: true,
    bigEmoji: '📊',
  ),
  'queue_checkin': _Style(Icons.visibility_rounded, _Family.grey, "Coup d'œil"),
};

const _Style _fallbackStyle = _Style(
  Icons.notifications_rounded,
  _Family.grey,
  'Info',
);

class _Palette {
  final Color accent, iconBg, iconColor, badgeBg, border;
  const _Palette(
    this.accent,
    this.iconBg,
    this.iconColor,
    this.badgeBg,
    this.border,
  );
}

_Palette _paletteFor(_Family f) {
  switch (f) {
    case _Family.green:
      return const _Palette(
        Color(0xFF4B8B5E),
        Color(0xFFE8F5ED),
        Color(0xFF3B7A4E),
        Color(0xFFE8F5ED),
        Color(0x334B8B5E),
      );
    case _Family.amber:
      return const _Palette(
        Color(0xFFB9770E),
        Color(0xFFFBF0DE),
        Color(0xFF97620B),
        Color(0xFFFBF0DE),
        Color(0x33B9770E),
      );
    case _Family.grey:
      return const _Palette(
        Color(0xFF6B7A70),
        Color(0xFFEEF3EE),
        Color(0xFF56635B),
        Color(0xFFEEF3EE),
        Color(0xFFE1E8E1),
      );
  }
}

// ════════════════════════════════════════════════════════════════════
class _NotifCard extends StatelessWidget {
  const _NotifCard({
    super.key,
    required this.id,
    required this.data,
    required this.companyId,
    required this.onDelete,
  });

  final String id;
  final Map<String, dynamic> data;
  final String companyId;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? '';
    final style = _styles[type] ?? _fallbackStyle;
    final pal = _paletteFor(style.family);

    final rawTitle = data['title'] as String? ?? 'Notification';
    final body = data['body'] as String? ?? '';
    final createdAt = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    final payload = (data['payload'] as Map?)?.cast<String, dynamic>();

    // Le titre porte déjà un emoji (côté CF) ; quand on l'affiche en grand à
    // gauche (bigEmoji), on évite de le répéter dans le texte.
    final title = style.bigEmoji != null
        ? rawTitle.replaceFirst('${style.bigEmoji} ', '')
        : rawTitle;

    // Bilan du jour : la barre d'accent suit la performance réelle plutôt
    // qu'une couleur de famille fixe — verte si bonne/record.
    final recapVerdict = type == 'plage_recap'
        ? (payload?['verdict'] as String?)
        : null;
    final cardAccent = (recapVerdict == 'record' || recapVerdict == 'bonne')
        ? const Color(0xFF4B8B5E)
        : pal.accent;

    return Dismissible(
      key: ValueKey('dismiss-$id'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 24),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.border),
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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: cardAccent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (style.bigEmoji != null)
                          SizedBox(
                            width: 34,
                            child: Center(
                              child: Text(
                                style.bigEmoji!,
                                style: const TextStyle(fontSize: 27),
                              ),
                            ),
                          )
                        else
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: pal.iconBg,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            style.icon,
                            color: pal.iconColor,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: const Color(0xFF1A1C2E),
                                      ),
                                    ),
                                  ),
                                  if (createdAt != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      _relativeTime(createdAt),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (body.isNotEmpty && type != 'plage_recap') ...[
                                const SizedBox(height: 4),
                                Text(
                                  body,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                              if (type == 'plage_recap') ...[
                                const SizedBox(height: 6),
                                _RecapCard(payload ?? const {}),
                              ] else ...[
                                const SizedBox(height: 8),
                                _Pill(style.label, pal),
                              ],
                              ..._buildAction(context, type, payload, pal),
                            ],
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
      ),
    );
  }

  List<Widget> _buildAction(
    BuildContext context,
    String type,
    Map<String, dynamic>? payload,
    _Palette pal,
  ) {
    String? label;
    VoidCallback? onTap;

    if ((type == 'plage_full' ||
            type == 'plage_near_full' ||
            type == 'plage_underused') &&
        payload?['queueId'] is String) {
      label = 'Ajuster cette plage';
      onTap = () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QueueTimeSlotsPage(
            companyId: companyId,
            queueId: payload!['queueId'] as String,
            queueName: payload['queueName'] as String? ?? 'File',
          ),
        ),
      );
    } else if (type == 'staff_joined') {
      label = "Voir l'équipe";
      onTap = () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TeamPage()),
      );
    }

    if (label == null) return const [];
    return [
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: pal.accent,
            side: BorderSide(color: pal.accent),
            padding: const EdgeInsets.symmetric(vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(label),
        ),
      ),
    ];
  }
}

// ════════════════════════════════════════════════════════════════════
// Carte « Bilan du jour » — compacte, colorée, verdict en bas.
// ════════════════════════════════════════════════════════════════════
class _RecapCard extends StatelessWidget {
  const _RecapCard(this.p);
  final Map<String, dynamic> p;

  static const _dark = Color(0xFF1A1C2E);

  // Deux teintes seulement : un remplissage faible n'est pas une erreur (une
  // "journée calme" arrive), le rouge d'alerte n'a donc pas sa place ici —
  // le chip verdict en bas qualifie déjà la journée en mots.
  Color _fillColor(int pct) =>
      pct >= 70 ? const Color(0xFF3B7A4E) : const Color(0xFFB9770E);

  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final res = _int(p['reservations']);

    // Journée à zéro : on ne montre pas un tableau de zéros, juste un
    // encouragement.
    if (res == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          'Aucune réservation aujourd\'hui. Partagez votre QR code pour '
          'attirer vos premiers clients 📣',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: Colors.grey.shade700,
          ),
        ),
      );
    }

    final cancel = _int(p['cancellations']);
    final fill = _int(p['fillPct']);
    final empty = _int(p['emptySlots']);
    final silent = _int(p['silentPlages']);
    final verdict = p['verdict'] as String? ?? 'calme';
    final plages = ((p['plages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    const verdictLabels = {
      'record': 'Journée record',
      'bonne': 'Bonne journée',
      'calme': 'Journée calme',
    };
    final verdictGreen = verdict == 'record' || verdict == 'bonne';
    final verdictColor = verdictGreen
        ? const Color(0xFF3B7A4E)
        : const Color(0xFF6B7A70);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        // ── Ligne primaire : réservations (+ annulations) ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$res',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _dark,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              res > 1 ? 'réservations' : 'réservation',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            if (cancel > 0) ...[
              Text('  ·  ', style: TextStyle(color: Colors.grey.shade400)),
              Text(
                '$cancel ${cancel > 1 ? "annulations" : "annulation"}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        // ── Ligne secondaire : remplissage · créneaux vides · ⓘ ──
        Row(
          children: [
            Text(
              '$fill % rempli',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _fillColor(fill),
              ),
            ),
            Text(
              '  ·  $empty ${empty > 1 ? "créneaux vides" : "créneau vide"}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _showLegend(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
        // ── Détail par plage active ──
        if (plages.isNotEmpty || silent > 0) ...[
          const SizedBox(height: 9),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 8),
          for (final pl in plages) _plageLine(pl),
          if (silent > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '+ $silent ${silent > 1 ? "plages" : "plage"} sans réservation',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
        // ── Verdict ──
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: verdictColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            verdictLabels[verdict] ?? 'Journée calme',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: verdictColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _plageLine(Map<String, dynamic> pl) {
    final range = pl['range']?.toString() ?? '';
    final r = _int(pl['reservations']);
    final f = _int(pl['fillPct']);
    final e = _int(pl['emptySlots']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _fillColor(f),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            range,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$r rés. · $f % · $e vides',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegend(BuildContext context) {
    Widget row(String term, String desc) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            term,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            desc,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
        ],
      ),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Comment lire ce bilan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
              'réservations',
              'Places réservées par vos clients aujourd\'hui.',
            ),
            row(
              '% rempli',
              'Part des places proposées qui ont été réservées '
                  '(places réservées ÷ places proposées sur la journée).',
            ),
            row('vides', 'Créneaux du jour où personne n\'a réservé.'),
            row(
              'annulations',
              'Réservations que des clients ont annulées dans la journée.',
            ),
            row(
              'La pastille',
              '🟢 plage bien remplie · 🟠 encore de la place.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.pal);
  final String label;
  final _Palette pal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pal.badgeBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: pal.accent,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8, top: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: Color(0xFFEEF3EE),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 46,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Aucune notification',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1C2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Les bilans de vos files et les alertes\napparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group {
  final String label;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  _Group(this.label, this.docs);
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return "À l'instant";
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
  if (diff.inDays == 1) return 'Hier';
  if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
  return DateFormat('d MMM', 'fr_FR').format(dt);
}
