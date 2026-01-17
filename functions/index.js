const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

// Exécute toutes les minutes (ajuste en prod)
exports.checkQueuesTimer = functions.pubsub.schedule('every 1 minutes').onRun(async (context) => {
  const now = admin.firestore.Timestamp.now();
  const empresas = await db.collection('Entreprises').listDocuments();
  for (const docRef of empresas) {
    try {
      const queuesSnap = await docRef.collection('queues').get();
      for (const qDoc of queuesSnap.docs) {
        const q = qDoc.data();
        const last = q.currentClientEnteredAt;
        if (!last) continue;
        const avgMin = q.avgServiceMinutes || 10;
        const margin = q.marginMinutes || 0;
        const deadline = last.toDate().getTime() + (avgMin + margin) * 60 * 1000;
        if (Date.now() > deadline) {
          await qDoc.ref.update({
            positionIndex: admin.firestore.FieldValue.increment(1),
            lastAutoAdvancedAt: now,
          });
          // TODO: envoyer notification au client suivant si besoin
        }
      }
    } catch (e) {
      console.error('Error scanning queues for', docRef.id, e);
    }
  }
  return null;
});