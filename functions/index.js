const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

// ====================================================================
// FONCTION 1 : Avancement automatique des files (toutes les minutes)
// ====================================================================
exports.checkQueuesTimer = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async (context) => {
    const now = new Date();
    const companiesSnap = await db.collection("companies").get();

    for (const companyDoc of companiesSnap.docs) {
      const companyId = companyDoc.id;
      const queuesSnap = await db
        .collection("companies")
        .doc(companyId)
        .collection("queues")
        .get();

      for (const queueDoc of queuesSnap.docs) {
        const queueData = queueDoc.data();
        const avgService = queueData.avgServiceMinutes || 15;
        const margin = queueData.marginMinutes || 2;
        const advanceTime = (avgService + margin) * 60 * 1000;

        const slotsSnap = await db
          .collection("companies")
          .doc(companyId)
          .collection("queues")
          .doc(queueDoc.id)
          .collection("slots")
          .where("status", "==", "active")
          .get();

        for (const slotDoc of slotsSnap.docs) {
          const slotData = slotDoc.data();
          const slotStart = slotData.start.toDate();
          const timeUntilStart = slotStart.getTime() - now.getTime();

          if (timeUntilStart <= advanceTime) {
            await slotDoc.ref.update({ status: "imminent" });
          }
        }
      }
    }
    return null;
  });

// ====================================================================
// FONCTION 2 : Nettoyage automatique des notifications > 7 jours
// ====================================================================
exports.cleanOldNotifications = functions.pubsub
  .schedule("0 2 * * *") // Tous les jours à 2h du matin UTC
  .timeZone("Europe/Paris")
  .onRun(async (context) => {
    console.log("🧹 Nettoyage des notifications anciennes...");

    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    let totalDeleted = 0;
    const companiesSnap = await db.collection("companies").get();

    for (const companyDoc of companiesSnap.docs) {
      const companyId = companyDoc.id;

      const oldNotifs = await db
        .collection("companies")
        .doc(companyId)
        .collection("notificationsHistory")
        .where("createdAt", "<", sevenDaysAgo)
        .get();

      if (oldNotifs.empty) continue;

      let batch = db.batch();
      let count = 0;

      for (const doc of oldNotifs.docs) {
        batch.delete(doc.ref);
        count++;
        if (count >= 500) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();

      totalDeleted += oldNotifs.size;
      console.log(`✅ ${companyId}: ${oldNotifs.size} notification(s) supprimée(s)`);
    }

    console.log(`🎉 Total supprimé : ${totalDeleted} notification(s)`);
    return { success: true, totalDeleted };
  });

// ====================================================================
// FONCTION 3 : Génération automatique des créneaux (tous les jours)
// ====================================================================
exports.generateSlots = functions.pubsub
  .schedule("30 2 * * *") // Tous les jours à 2h30 du matin UTC
  .timeZone("Europe/Paris")
  .onRun(async (context) => {
    console.log("📅 Démarrage génération automatique des créneaux...");

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Date limite passée : J-7 (on supprime ce qui est plus vieux)
    const deleteBeforeDate = new Date(today);
    deleteBeforeDate.setDate(deleteBeforeDate.getDate() - 7);

    // Date limite future : J+14 (on génère jusqu'à là)
    const generateUntilDate = new Date(today);
    generateUntilDate.setDate(generateUntilDate.getDate() + 14);

    let totalGenerated = 0;
    let totalDeleted = 0;

    const companiesSnap = await db.collection("companies").get();
    console.log(`🏢 ${companiesSnap.size} entreprise(s) à traiter`);

    for (const companyDoc of companiesSnap.docs) {
      const companyId = companyDoc.id;

      // ── Récupérer les files actives ──────────────────────────────
      const queuesSnap = await db
        .collection("companies")
        .doc(companyId)
        .collection("queues")
        .where("isActive", "==", true)
        .get();

      for (const queueDoc of queuesSnap.docs) {
        const queueData = queueDoc.data();
        const queueId = queueDoc.id;

        // Jours ouvrés : weekdays ou defaultWorkingDays
        const weekdays = queueData.weekdays
          || queueData.defaultWorkingDays
          || [1, 2, 3, 4, 5];

        // ── Récupérer les plages horaires (timeSlots) ────────────────
        const timeSlotsSnap = await db
          .collection("companies")
          .doc(companyId)
          .collection("queues")
          .doc(queueId)
          .collection("timeSlots")
          .get();

        if (timeSlotsSnap.empty) {
          console.log(`⚠️ File ${queueId} : aucune plage horaire configurée`);
          continue;
        }

        // ── ÉTAPE 1 : Supprimer les vieux créneaux (< J-7) ──────────
        const oldSlotsSnap = await db
          .collection("companies")
          .doc(companyId)
          .collection("queues")
          .doc(queueId)
          .collection("slots")
          .where("start", "<", deleteBeforeDate)
          .get();

        if (!oldSlotsSnap.empty) {
          let deleteBatch = db.batch();
          let deleteCount = 0;

          for (const slotDoc of oldSlotsSnap.docs) {
            // Ne supprimer que si pas de réservation dessus
            const slotData = slotDoc.data();
            if ((slotData.reserved || 0) === 0) {
              deleteBatch.delete(slotDoc.ref);
              deleteCount++;

              if (deleteCount >= 500) {
                await deleteBatch.commit();
                deleteBatch = db.batch();
                deleteCount = 0;
              }
            }
          }
          if (deleteCount > 0) await deleteBatch.commit();
          totalDeleted += deleteCount;
          console.log(`🗑️ File ${queueId}: ${deleteCount} vieux créneaux supprimés`);
        }

        // ── ÉTAPE 2 : Générer les créneaux manquants jusqu'à J+14 ───
        for (const timeSlotDoc of timeSlotsSnap.docs) {
          const tsData = timeSlotDoc.data();

          const startTime = tsData.startTime || "09:00";
          const endTime = tsData.endTime || "12:00";
          const duration = tsData.serviceDurationMinutes || 15;
          const capacity = tsData.capacityPerSlot || 1;

          // Jours actifs pour cette plage (ou hérités de la file)
          const activeDays = tsData.workingDays || weekdays;

          let createBatch = db.batch();
          let createCount = 0;
          const slotsRef = db
            .collection("companies")
            .doc(companyId)
            .collection("queues")
            .doc(queueId)
            .collection("slots");

          // Parcourir chaque jour de aujourd'hui jusqu'à J+14
          for (let dayOffset = 0; dayOffset <= 14; dayOffset++) {
            const targetDate = new Date(today);
            targetDate.setDate(targetDate.getDate() + dayOffset);

            // Vérifier si ce jour est ouvré (1=Lundi, 7=Dimanche)
            const jsWeekday = targetDate.getDay(); // 0=Dim, 1=Lun...
            // Convertir en format Dart (1=Lun, 7=Dim)
            const dartWeekday = jsWeekday === 0 ? 7 : jsWeekday;

            if (!activeDays.includes(dartWeekday)) continue;

            // Parser les heures
            const [startH, startM] = startTime.split(":").map(Number);
            const [endH, endM] = endTime.split(":").map(Number);

            const plageStart = new Date(targetDate);
            plageStart.setHours(startH, startM, 0, 0);

            const plageEnd = new Date(targetDate);
            plageEnd.setHours(endH, endM, 0, 0);

            // Vérifier si des créneaux existent déjà pour cette plage
            const existingSnap = await slotsRef
              .where("start", ">=", plageStart)
              .where("start", "<", plageEnd)
              .limit(1)
              .get();

            if (!existingSnap.empty) continue; // Déjà générés

            // Générer les créneaux minute par minute
            let cursor = new Date(plageStart);

            while (true) {
              const slotEnd = new Date(cursor.getTime() + duration * 60 * 1000);
              if (slotEnd > plageEnd) break;

              createBatch.set(slotsRef.doc(), {
                "start": cursor,
                "end": slotEnd,
                "capacity": capacity,
                "reserved": 0,
                "cancelled": 0,
                "status": "open",
                "duration": duration,
                "isLegacy": false,
              });

              createCount++;
              cursor = new Date(slotEnd);

              // Commit par batch de 450 (marge de sécurité)
              if (createCount >= 450) {
                await createBatch.commit();
                createBatch = db.batch();
                createCount = 0;
              }
            }
          }

          // Commit final
          if (createCount > 0) {
            await createBatch.commit();
            totalGenerated += createCount;
            console.log(`✅ File ${queueId} / plage ${startTime}-${endTime}: ${createCount} créneaux générés`);
          }
        }
      }
    }

    console.log(`🎉 Génération terminée :`);
    console.log(`   → ${totalGenerated} créneaux générés`);
    console.log(`   → ${totalDeleted} vieux créneaux supprimés`);

    return {
      success: true,
      totalGenerated,
      totalDeleted,
      timestamp: new Date().toISOString(),
    };
  });