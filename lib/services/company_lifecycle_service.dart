import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:baxa/services/slot_generation_service.dart';

// ════════════════════════════════════════════════════════════════════
// Cycle de vie du compte entreprise — départ / retour de Baxa.
// ════════════════════════════════════════════════════════════════════

/// Annule un départ programmé (« Revenir sur Baxa ») : supprime la demande
/// `deletionRequests/{companyId}`, rouvre toutes les files (efface la
/// fermeture posée au moment du départ) et régénère leurs créneaux.
///
/// Les réservations déjà annulées ne sont PAS rétablies.
Future<void> cancelCompanyDeletion({
  required FirebaseFirestore firestore,
  required String companyId,
}) async {
  final queuesSnap = await firestore
      .collection('companies')
      .doc(companyId)
      .collection('queues')
      .get();

  // Effacer les fermetures AVANT de supprimer la demande : la CF
  // onCompanyStateChange voit alors encore `deletionRequests` au moment
  // du basculement et saute la notif « rouvert » (le staff est déjà
  // déconnecté à ce stade).
  if (queuesSnap.docs.isNotEmpty) {
    final batch = firestore.batch();
    for (final q in queuesSnap.docs) {
      batch.update(q.reference, {
        'closureStart': FieldValue.delete(),
        'closureEnd': FieldValue.delete(),
      });
    }
    await batch.commit();
  }

  await firestore.collection('deletionRequests').doc(companyId).delete();

  for (final q in queuesSnap.docs) {
    try {
      await regenerateSlotsForQueue(
        firestore: firestore,
        companyId: companyId,
        queueId: q.id,
      );
    } catch (_) {
      // La Cloud Function de nuit rattrapera.
    }
  }
}
