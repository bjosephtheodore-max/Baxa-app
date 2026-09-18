import 'package:cloud_firestore/cloud_firestore.dart';

// ════════════════════════════════════════════════════════════════════
// Annulation en masse de réservations côté entreprise (fermeture,
// départ de Baxa…).
// ════════════════════════════════════════════════════════════════════

/// Annule un lot de réservations et **répare les compteurs** — comme le
/// fait toute annulation individuelle de l'app :
///  • la réservation passe à `status: cancelled` (+ `cancelledAt`,
///    `cancellationSource`) ;
///  • le créneau : `reserved -1`, `cancelled +1` ;
///  • les `dailyStats` du jour : `reserved -1`, `available +1`,
///    `cancelled +1`.
///
/// Le client est prévenu côté serveur par la Cloud Function
/// `onReservationCancelledByCompany`, grâce au `cancellationSource`.
///
/// [reservationDocs] : documents `companies/{id}/reservations` déjà filtrés
/// par l'appelant (statut, période…). Renvoie le nombre de réservations
/// annulées.
Future<int> cancelReservationsBatch({
  required FirebaseFirestore firestore,
  required String companyId,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> reservationDocs,
  required String cancellationSource,
}) async {
  if (reservationDocs.isEmpty) return 0;

  final companyRef = firestore.collection('companies').doc(companyId);

  WriteBatch batch = firestore.batch();
  int ops = 0;
  int cancelled = 0;

  Future<void> flush() async {
    if (ops == 0) return;
    await batch.commit();
    batch = firestore.batch();
    ops = 0;
  }

  for (final doc in reservationDocs) {
    final data = doc.data();
    final queueId = data['queueId'] as String?;
    final slotId = data['slotId'] as String?;
    final slotStart = (data['slotStart'] as Timestamp?)?.toDate();

    batch.update(doc.reference, {
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancellationSource': cancellationSource,
    });
    ops++;

    if (queueId != null && slotId != null) {
      final queueRef = companyRef.collection('queues').doc(queueId);

      batch.update(queueRef.collection('slots').doc(slotId), {
        'reserved': FieldValue.increment(-1),
        'cancelled': FieldValue.increment(1),
      });
      ops++;

      if (slotStart != null) {
        final dateStr =
            '${slotStart.year}-'
            '${slotStart.month.toString().padLeft(2, '0')}-'
            '${slotStart.day.toString().padLeft(2, '0')}';
        batch.set(queueRef.collection('dailyStats').doc(dateStr), {
          'reserved': FieldValue.increment(-1),
          'available': FieldValue.increment(1),
          'cancelled': FieldValue.increment(1),
        }, SetOptions(merge: true));
        ops++;
      }
    }

    cancelled++;
    if (ops >= 450) await flush();
  }
  await flush();
  return cancelled;
}
