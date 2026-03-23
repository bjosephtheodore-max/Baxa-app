import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> migrateExistingSlots() async {
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;

  print('🔄 Migration des slots en cours...');

  final companiesSnap = await firestore.collection('companies').get();

  for (final companyDoc in companiesSnap.docs) {
    final companyId = companyDoc.id;

    final queuesSnap = await firestore
        .collection('companies')
        .doc(companyId)
        .collection('queues')
        .get();

    for (final queueDoc in queuesSnap.docs) {
      final queueId = queueDoc.id;

      final slotsSnap = await firestore
          .collection('companies')
          .doc(companyId)
          .collection('queues')
          .doc(queueId)
          .collection('slots')
          .get();

      for (final slotDoc in slotsSnap.docs) {
        final slotData = slotDoc.data();

        final updates = <String, dynamic>{};

        if (!slotData.containsKey('reserved')) {
          updates['reserved'] = 0;
        }
        if (!slotData.containsKey('cancelled')) {
          updates['cancelled'] = 0;
        }
        if (!slotData.containsKey('status')) {
          updates['status'] = 'open';
        }

        if (updates.isNotEmpty) {
          await slotDoc.reference.update(updates);
          print('✅ Slot ${slotDoc.id} migré');
        }
      }
    }
  }

  print('✅ Migration terminée !');
}
