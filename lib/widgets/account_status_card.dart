import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:baxa/services/booking_constants.dart';

// ════════════════════════════════════════════════════════════════════
// Carte « Statut du compte » — partagée entre la page Paramètres de
// l'entreprise et celle du staff (affichage identique).
//
// Vert « Actif » par défaut ; rouge « Fermé » uniquement quand TOUTE la
// structure est fermée maintenant (toutes les files sous fermeture active).
// Une fermeture seulement programmée (pas encore commencée) ou partielle
// laisse la carte au vert.
// ════════════════════════════════════════════════════════════════════
class AccountStatusCard extends StatelessWidget {
  final String companyId;

  const AccountStatusCard({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('queues')
          .snapshots(),
      builder: (context, snap) {
        final queues = snap.data?.docs ?? [];
        final now = DateTime.now();

        DateTime? closedSince;
        bool allClosed = queues.isNotEmpty;
        for (final q in queues) {
          final d = q.data() as Map<String, dynamic>;
          final cs = (d['closureStart'] as Timestamp?)?.toDate();
          final ce = (d['closureEnd'] as Timestamp?)?.toDate();
          if (!isQueueClosedNow(cs, ce, now: now)) {
            allClosed = false;
            break;
          }
          if (cs != null && (closedSince == null || cs.isAfter(closedSince))) {
            closedSince = cs;
          }
        }

        final closed = allClosed;
        final Color color = closed ? Colors.red : Colors.green;
        final Color bg = closed ? Colors.red.shade50 : Colors.green.shade50;
        final Color border = closed
            ? Colors.red.shade200
            : Colors.green.shade200;
        final IconData icon = closed
            ? Icons.nightlight_round
            : Icons.check_circle;
        final String label = closed ? 'Fermé' : 'Actif';
        final String description = closed
            ? (closedSince != null
                  ? 'Établissement fermé depuis le ${_fmt(closedSince)}.'
                  : 'Établissement fermé.')
            : 'Votre établissement fonctionne normalement.';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 2),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
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
        );
      },
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
