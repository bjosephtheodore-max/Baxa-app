const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {CloudTasksClient} = require("@google-cloud/tasks");
admin.initializeApp();

const db = admin.firestore();
const tasksClient = new CloudTasksClient();

// Projet/région utilisés pour la file Cloud Tasks des notifications de
// réservation (rappels, validation, créneau passé) — voir FONCTION 7.
const PROJECT_ID =
  admin.app().options.projectId ||
  process.env.GCLOUD_PROJECT ||
  process.env.GCP_PROJECT;
const TASKS_LOCATION = "us-central1";
const TASKS_QUEUE = "reservation-notifications";

// ────────────────────────────────────────────────────────────────────
// Une file est « fermée maintenant » si une fermeture (closureStart /
// closureEnd ; closureEnd absent = fermeture indéterminée) englobe
// l'instant présent. Miroir de isQueueClosedNow() de
// lib/services/booking_constants.dart.
// ────────────────────────────────────────────────────────────────────
function isQueueClosedNow(closureStart, closureEnd, now) {
  if (!closureStart) return false;
  const n = now || new Date();
  const cs = closureStart.toDate ? closureStart.toDate() : closureStart;
  if (n < cs) return false;
  if (closureEnd) {
    const ce = closureEnd.toDate ? closureEnd.toDate() : closureEnd;
    if (n > ce) return false;
  }
  return true;
}

// ────────────────────────────────────────────────────────────────────
// Résumé « recherche » d'une entreprise, écrit sur companies/{id} :
//   queueCount : nombre de files
//   closedNow  : true si TOUTES les files sont fermées maintenant
//   reopenAt   : date de réouverture si toutes datées (absent sinon)
// Permet à la page de recherche client de filtrer / étiqueter sans lire
// la sous-collection `queues` de chaque entreprise.
// ────────────────────────────────────────────────────────────────────
async function writeCompanySearchSummary(companyId, queuesDocs, now) {
  const count = queuesDocs.length;
  let allClosed = count > 0;
  let latestEnd = null;
  let anyIndefinite = false;
  for (const q of queuesDocs) {
    const d = q.data();
    if (!isQueueClosedNow(d.closureStart, d.closureEnd, now)) {
      allClosed = false;
      break;
    }
    if (d.closureEnd) {
      const e = d.closureEnd.toDate();
      if (latestEnd === null || e > latestEnd) latestEnd = e;
    } else {
      anyIndefinite = true;
    }
  }
  const update = {
    queueCount: count,
    closedNow: allClosed,
    reopenAt: (allClosed && !anyIndefinite && latestEnd)
      ? admin.firestore.Timestamp.fromDate(latestEnd)
      : admin.firestore.FieldValue.delete(),
  };
  try {
    await db.collection("companies").doc(companyId).update(update);
  } catch (e) {
    // entreprise supprimée entre-temps, etc. — non bloquant
    console.warn(`writeCompanySearchSummary ${companyId}: ${e.message}`);
  }
}

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

      // ── Récupérer les files ──────────────────────────────────────
      // Toutes les files : les inactives sont ignorées pour la génération
      // (voir ci-dessous), mais une file inactive avec `deleteAfter` doit
      // quand même être traitée pour sa suppression programmée.
      const queuesSnap = await db
        .collection("companies")
        .doc(companyId)
        .collection("queues")
        .get();

      for (const queueDoc of queuesSnap.docs) {
        const queueData = queueDoc.data();
        const queueId = queueDoc.id;

        // Fermeture en cours → on cesse de générer des créneaux pour cette
        // file (inutile de maintenir un horizon que personne ne peut
        // réserver, y compris pour une fermeture datée d'un mois ou d'un an).
        // Exception « préchauffage » : si la réouverture est datée et tombe
        // dans moins de 48h, on régénère déjà pour que les créneaux du jour
        // de réouverture existent. Le nettoyage des vieux créneaux, la
        // promotion des modifs programmées et les suppressions programmées
        // continuent normalement — seule la génération est suspendue.
        const genNow = new Date();
        const closedNow = isQueueClosedNow(
          queueData.closureStart, queueData.closureEnd, genNow,
        );
        let skipGeneration = false;
        if (closedNow) {
          const reopenTs = queueData.closureEnd
            ? queueData.closureEnd.toDate() : null;
          const reopenSoon = reopenTs !== null &&
            (reopenTs.getTime() - genNow.getTime()) < 48 * 60 * 60 * 1000;
          skipGeneration = !reopenSoon;
        }
        if (skipGeneration) {
          console.log(`⏸️ File ${queueId} : fermée, génération suspendue`);
        }

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

        const slotsRef = db
          .collection("companies")
          .doc(companyId)
          .collection("queues")
          .doc(queueId)
          .collection("slots");

        const dailyStatsRef = db
          .collection("companies")
          .doc(companyId)
          .collection("queues")
          .doc(queueId)
          .collection("dailyStats");

        // ── ÉTAPE 1 : Supprimer les vieux créneaux et dailyStats (< J-7) ──
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

          // Supprimer les dailyStats obsolètes (< J-7)
          const oldStatsSnap = await dailyStatsRef
            .where("date", "<", deleteBeforeDate.toISOString().split("T")[0])
            .get();
          if (!oldStatsSnap.empty) {
            let statsBatch = db.batch();
            oldStatsSnap.docs.forEach((d) => statsBatch.delete(d.ref));
            await statsBatch.commit();
          }

          console.log(`🗑️ File ${queueId}: ${deleteCount} vieux créneaux supprimés`);
        }

        // Helper : formater une date en "YYYY-MM-DD"
        const fmtDate = (d) => {
          const y = d.getFullYear();
          const m = String(d.getMonth() + 1).padStart(2, "0");
          const day = String(d.getDate()).padStart(2, "0");
          return `${y}-${m}-${day}`;
        };

        // Helper : écrire/mettre à jour les dailyStats d'un jour en agrégeant les slots existants
        const upsertDailyStats = async (targetDate) => {
          const dayStart = new Date(targetDate);
          dayStart.setHours(0, 0, 0, 0);
          const dayEnd = new Date(dayStart);
          dayEnd.setDate(dayEnd.getDate() + 1);

          const allSlots = await slotsRef
            .where("start", ">=", dayStart)
            .where("start", "<", dayEnd)
            .get();

          // Note : on n'écarte pas le cas "aucun créneau" — une journée vidée
          // (plage supprimée) doit voir son résumé remis à zéro, pas rester
          // figée sur d'anciens chiffres.

          let totalSlots = 0;
          let totalCapacity = 0;
          let reserved = 0;
          let cancelled = 0;

          for (const s of allSlots.docs) {
            const sd = s.data();
            totalSlots++;
            totalCapacity += sd.capacity || 0;
            reserved += sd.reserved || 0;
            cancelled += sd.cancelled || 0;
          }

          await dailyStatsRef.doc(fmtDate(targetDate)).set({
            date: fmtDate(targetDate),
            totalSlots,
            totalCapacity,
            available: totalCapacity - reserved,
            reserved,
            cancelled,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        };

        // ── ÉTAPE 2 : Générer les créneaux manquants selon maxAdvanceDays ──
        for (const timeSlotDoc of timeSlotsSnap.docs) {
          let tsData = timeSlotDoc.data();

          // ── Suppression programmée d'une plage ────────────────────────
          // Marqueur `deleteAfter` posé par l'app : la plage n'accepte plus
          // aucune nouvelle réservation (ses créneaux vides futurs ont déjà
          // été retirés), on ne la régénère donc jamais tant que le marqueur
          // est présent. Une fois la date atteinte ET toutes les réservations
          // en cours passées, on supprime définitivement la plage et ses
          // créneaux restants, puis on recalcule les dailyStats des jours
          // concernés.
          if (tsData.deleteAfter) {
            if (tsData.deleteAfter.toDate() <= today) {
              const nowTs = new Date();
              const remainingSnap = await slotsRef
                .where("timeSlotId", "==", timeSlotDoc.id)
                .get();
              const stillToCome = remainingSnap.docs.filter(
                (d) =>
                  (d.data().reserved || 0) > 0 &&
                  d.data().start.toDate() > nowTs,
              );

              if (stillToCome.length === 0) {
                const affectedDays = new Map();
                let delBatch = db.batch();
                let delCount = 0;
                for (const d of remainingSnap.docs) {
                  const day = d.data().start.toDate();
                  affectedDays.set(fmtDate(day), day);
                  delBatch.delete(d.ref);
                  delCount++;
                  if (delCount >= 450) {
                    await delBatch.commit();
                    delBatch = db.batch();
                    delCount = 0;
                  }
                }
                if (delCount > 0) await delBatch.commit();
                await timeSlotDoc.ref.delete();
                for (const day of affectedDays.values()) {
                  await upsertDailyStats(day);
                }
                totalDeleted += remainingSnap.size;
                console.log(
                  `🗑️ File ${queueId} / plage ${timeSlotDoc.id} : suppression programmée appliquée`,
                );
              }
            }
            // Marqueur présent → ne jamais générer pour cette plage.
            continue;
          }

          // ── Promotion d'une modification programmée arrivée à échéance ──
          // "en attente" → "actuelle" dès que la date d'effet est atteinte.
          // Après promotion, plus aucune branche pending/actuelle à gérer :
          // tsData reflète directement la nouvelle config.
          const pendingEffectiveTs = tsData.pendingEffectiveDate;
          if (pendingEffectiveTs && pendingEffectiveTs.toDate() <= today) {
            const promoted = {
              startTime: tsData.pendingStartTime,
              endTime: tsData.pendingEndTime,
              serviceDurationMinutes: tsData.pendingServiceDurationMinutes,
              capacityPerSlot: tsData.pendingCapacityPerSlot,
              workingDays: tsData.pendingWorkingDays,
              maxAdvanceDays: tsData.pendingMaxAdvanceDays,
              reservationDeadlineMinutes: tsData.pendingReservationDeadlineMinutes,
              pendingStartTime: admin.firestore.FieldValue.delete(),
              pendingEndTime: admin.firestore.FieldValue.delete(),
              pendingServiceDurationMinutes: admin.firestore.FieldValue.delete(),
              pendingCapacityPerSlot: admin.firestore.FieldValue.delete(),
              pendingWorkingDays: admin.firestore.FieldValue.delete(),
              pendingMaxAdvanceDays: admin.firestore.FieldValue.delete(),
              pendingReservationDeadlineMinutes: admin.firestore.FieldValue.delete(),
              pendingEffectiveDate: admin.firestore.FieldValue.delete(),
            };
            await timeSlotDoc.ref.update(promoted);
            tsData = { ...tsData, ...promoted };
            if (tsData.maxAdvanceDays) {
              await queueDoc.ref.update({ maxAdvanceDays: tsData.maxAdvanceDays });
            }
            console.log(`🔄 File ${queueId} / plage ${timeSlotDoc.id} : modification programmée promue`);
          }

          // Fermeture en cours (hors préchauffage 48h) : on ne génère pas.
          if (skipGeneration) continue;

          const currentCfg = {
            startTime: tsData.startTime || "09:00",
            endTime: tsData.endTime || "12:00",
            duration: tsData.serviceDurationMinutes || 15,
            capacity: tsData.capacityPerSlot || 1,
            activeDays: tsData.workingDays || weekdays,
          };

          // Encore en attente (échéance pas encore atteinte) : la période à
          // partir de la date d'effet suit la config en attente, pas
          // l'actuelle — nécessaire pour les jours qui n'ont pas encore été
          // générés à l'avance (au-delà de l'horizon de 7 jours utilisé par
          // la génération immédiate côté app au moment où c'est programmé).
          const stillPendingTs = tsData.pendingEffectiveDate;
          const pendingEffectiveDate = stillPendingTs ? stillPendingTs.toDate() : null;
          const pendingCfg = pendingEffectiveDate
            ? {
                startTime: tsData.pendingStartTime || currentCfg.startTime,
                endTime: tsData.pendingEndTime || currentCfg.endTime,
                duration: tsData.pendingServiceDurationMinutes || currentCfg.duration,
                capacity: tsData.pendingCapacityPerSlot || currentCfg.capacity,
                activeDays: tsData.pendingWorkingDays || currentCfg.activeDays,
              }
            : null;

          const maxAdvanceDays = Math.min(tsData.maxAdvanceDays || 7, 30);

          for (let dayOffset = 0; dayOffset <= 7; dayOffset++) {
            const targetDate = new Date(today);
            targetDate.setDate(targetDate.getDate() + dayOffset);

            const cfg = (pendingCfg && targetDate >= pendingEffectiveDate)
              ? pendingCfg
              : currentCfg;

            // Vérifier si ce jour est ouvré (1=Lundi, 7=Dimanche)
            const jsWeekday = targetDate.getDay();
            const dartWeekday = jsWeekday === 0 ? 7 : jsWeekday;
            if (!cfg.activeDays.includes(dartWeekday)) continue;

            // Parser les heures
            const [startH, startM] = cfg.startTime.split(":").map(Number);
            const [endH, endM] = cfg.endTime.split(":").map(Number);

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

            if (!existingSnap.empty) {
              // Slots déjà générés — créer dailyStats si absent (migration)
              const statsDoc = await dailyStatsRef.doc(fmtDate(targetDate)).get();
              if (!statsDoc.exists) {
                await upsertDailyStats(targetDate);
                console.log(`📊 File ${queueId}: dailyStats créé (migration) pour ${fmtDate(targetDate)}`);
              }
              continue;
            }

            // Générer les créneaux pour ce jour
            let createBatch = db.batch();
            let createCount = 0;
            let cursor = new Date(plageStart);

            while (cursor.getTime() + cfg.duration * 60 * 1000 <= plageEnd.getTime()) {
              const slotEnd = new Date(cursor.getTime() + cfg.duration * 60 * 1000);

              createBatch.set(slotsRef.doc(), {
                "start": cursor,
                "end": slotEnd,
                "capacity": cfg.capacity,
                "reserved": 0,
                "cancelled": 0,
                "status": "open",
                "duration": cfg.duration,
                "isLegacy": false,
                "timeSlotId": timeSlotDoc.id,
              });

              createCount++;
              cursor = new Date(slotEnd);

              if (createCount >= 450) {
                await createBatch.commit();
                createBatch = db.batch();
                createCount = 0;
              }
            }

            if (createCount > 0) {
              await createBatch.commit();
              totalGenerated += createCount;
              // Écrire dailyStats précis en agrégeant les slots de ce jour
              await upsertDailyStats(targetDate);
              console.log(`✅ File ${queueId} / ${fmtDate(targetDate)}: ${createCount} créneaux + dailyStats`);
            }
          }
        }

        // ── Suppression programmée de la file (coquille vide) ─────────
        // L'entreprise a programmé la suppression de toutes les plages ET
        // choisi de supprimer la file elle-même (marqueur `deleteAfter` sur
        // le doc file). Dès qu'il ne reste plus aucune plage et que la date
        // est atteinte, on supprime la file + ses dailyStats.
        if (queueData.deleteAfter && queueData.deleteAfter.toDate() <= today) {
          const remainingTs = await db
            .collection("companies").doc(companyId)
            .collection("queues").doc(queueId)
            .collection("timeSlots").limit(1).get();
          if (remainingTs.empty) {
            const statsSnap = await dailyStatsRef.get();
            let sb = db.batch();
            let sn = 0;
            for (const d of statsSnap.docs) {
              sb.delete(d.ref);
              sn++;
              if (sn >= 450) { await sb.commit(); sb = db.batch(); sn = 0; }
            }
            if (sn > 0) await sb.commit();
            await queueDoc.ref.delete();
            console.log(`🗑️ File ${queueId} : suppression programmée appliquée (plus aucune plage)`);
          }
        }
      }

      // Résumé « recherche » recalculé chaque nuit — rattrape les fermetures
      // datées qui démarrent / se terminent sans écriture de file.
      const freshQueues = await db
        .collection("companies").doc(companyId)
        .collection("queues").get();
      await writeCompanySearchSummary(companyId, freshQueues.docs, new Date());
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

// ====================================================================
// FONCTION 3bis : Résumé « recherche » de l'entreprise, mis à jour dès
// qu'une file est créée, supprimée, fermée ou rouverte. Sert à la page de
// recherche client pour masquer / étiqueter les structures sans mesurer
// leurs files à chaque requête.
// ====================================================================
exports.updateCompanySearchSummary = functions.firestore
  .document("companies/{companyId}/queues/{queueId}")
  .onWrite(async (change, context) => {
    const companyId = context.params.companyId;
    const queuesSnap = await db
      .collection("companies")
      .doc(companyId)
      .collection("queues")
      .get();
    await writeCompanySearchSummary(companyId, queuesSnap.docs, new Date());
    return null;
  });

// ====================================================================
// FONCTION 4 : Push FCM à la création OU mise à jour d'une notification
// in-app client.
//
// onWrite (et non onCreate) car la timeline d'une réservation (rappels →
// validation → créneau passé, voir FONCTION 7) réutilise un seul document
// Firestore mis à jour à chaque étape plutôt que d'en créer un nouveau à
// chaque fois — ça évite d'encombrer l'historique de l'app avec 5 entrées
// par réservation. Chaque mise à jour de ce document doit donc renvoyer
// un nouveau push, pas seulement sa création initiale.
// ====================================================================
exports.sendPushOnNotification = functions.firestore
  .document("customers/{customerId}/notifications/{notificationId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null; // suppression : rien à pousser

    const { customerId } = context.params;
    const data = change.after.data();

    const title = data.title || "Baxa";
    const body = data.body || "";

    // Récupérer le token FCM du client
    const userDoc = await db.collection("users").doc(customerId).get();
    if (!userDoc.exists) return null;

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return null;

    // Les notifications d'une même réservation (rappels, validation,
    // créneau passé) partagent un tag commun pour que chaque nouvelle
    // remplace la précédente dans la barre système au lieu de s'empiler.
    const reservationId = data.payload && data.payload.reservationId;
    const tag = reservationId ? `resa-${reservationId}` : undefined;

    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        android: {
          priority: "high",
          ...(tag ? { notification: { tag } } : {}),
        },
        apns: {
          payload: {
            aps: { sound: "default", ...(tag ? { "thread-id": tag } : {}) },
          },
        },
      });
      console.log(`✅ Push envoyé à ${customerId}: ${title}`);
    } catch (e) {
      console.error(`❌ Erreur push FCM pour ${customerId}:`, e.message);
    }
    return null;
  });

// ====================================================================
// FONCTION 5 : Compteur reservationCount sur les entreprises
// Incrémenté à chaque nouvelle réservation confirmée
// ====================================================================
exports.onReservationCreated = functions.firestore
  .document("companies/{companyId}/reservations/{reservationId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;

    try {
      await db.collection("companies").doc(companyId).update({
        reservationCount: admin.firestore.FieldValue.increment(1),
      });
      console.log(`✅ reservationCount +1 pour ${companyId}`);
    } catch (e) {
      console.error(`❌ Erreur reservationCount pour ${companyId}:`, e.message);
    }
    return null;
  });

// ====================================================================
// FONCTION 6bis : Notification client à l'annulation d'une réservation
// PAR L'ENTREPRISE (réaménagement d'horaires, suppression de plage...).
//
// Le texte de la notification est entièrement généré ici, côté serveur.
// Le client (app entreprise) se contente de marquer la réservation
// "cancelled" + `cancellationSource` — il ne doit JAMAIS écrire lui-même
// dans customers/{id}/notifications (les règles Firestore l'interdisent
// d'ailleurs) : seule une Cloud Function, via l'Admin SDK, peut le faire.
// Ça garantit que le contenu de la notification correspond forcément à
// une action réelle sur une réservation qui appartient bien à CETTE
// entreprise (context.params.companyId), sans jamais faire confiance à
// une donnée fournie par le client.
// ====================================================================
exports.onReservationCancelledByCompany = functions.firestore
  .document("companies/{companyId}/reservations/{reservationId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const { companyId } = context.params;

    // Ne réagir qu'à une transition CONFIRMÉE → ANNULÉE, initiée par
    // l'entreprise (source connue) — jamais aux annulations par le client
    // lui-même, ni aux mises à jour qui ne changent pas le statut.
    const companySources = [
      "company_edit",
      "company_delete_timeslot",
      "company_block_unresolved",
      "company_closure",
    ];
    if (before.status === "cancelled" || after.status !== "cancelled") return null;
    if (!companySources.includes(after.cancellationSource)) return null;

    const customerId = after.customerId;
    if (!customerId || customerId === "manual_booking") return null; // rien à notifier

    const companyDoc = await db.collection("companies").doc(companyId).get();
    const companyName = companyDoc.exists ? (companyDoc.data().nom || "L'entreprise") : "L'entreprise";
    const queueName = after.queueName || "";

    let dateTimeText = "";
    const slotStart = after.slotStart ? after.slotStart.toDate() : null;
    if (slotStart) {
      const dd = String(slotStart.getDate()).padStart(2, "0");
      const mm = String(slotStart.getMonth() + 1).padStart(2, "0");
      const hh = String(slotStart.getHours()).padStart(2, "0");
      const mn = String(slotStart.getMinutes()).padStart(2, "0");
      dateTimeText = ` du ${dd}/${mm}/${slotStart.getFullYear()} à ${hh}h${mn}`;
    }

    let reasonText;
    // Pour une fermeture, la file n'accepte plus de réservations : inutile
    // (et trompeur) d'inviter le client à re-réserver ou de lui afficher le
    // bouton de redirection vers les créneaux.
    let suggestRebook = true;
    if (after.cancellationSource === "company_delete_timeslot") {
      reasonText = "suite à la suppression de cette plage horaire";
    } else if (after.cancellationSource === "company_block_unresolved") {
      reasonText = "car le service n'a pas pu reprendre à temps";
    } else if (after.cancellationSource === "company_closure") {
      reasonText = "suite à une fermeture de l'établissement sur cette période";
      suggestRebook = false;
    } else {
      reasonText = "suite à un réaménagement des horaires de la file";
    }

    const queueId = after.queueId || "";

    try {
      await db.collection("customers").doc(customerId).collection("notifications").add({
        title: "📅 Réservation annulée",
        body:
          `${companyName} a annulé votre réservation${dateTimeText}` +
          `${queueName ? ` chez ${queueName}` : ""} ${reasonText}.` +
          `${suggestRebook ? " Trouvez un nouveau créneau qui vous convient." : ""}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        type: "cancellation_by_company",
        // Permet à l'app d'afficher un bouton qui redirige directement vers
        // les créneaux de cette file (voir notifications_page.dart).
        payload: (queueId && suggestRebook)
          ? { companyId, companyName, queueId, queueName }
          : null,
      });
      console.log(`✅ Notification d'annulation envoyée à ${customerId} (${after.cancellationSource})`);
    } catch (e) {
      console.error(`❌ Erreur notification annulation pour ${customerId}:`, e.message);
    }
    return null;
  });

// ====================================================================
// FONCTION 6ter : Notification client au blocage / déblocage d'un créneau
// PAR L'ENTREPRISE (incident : "Bloquer la plage" sur la page d'accueil).
//
// L'app entreprise pose/retire le flag `suspended` sur la réservation
// (elle ne touche PAS à customers/{id}/notifications, interdit par les
// règles) ; cette fonction envoie le texte, côté serveur.
//   - suspended  false/absent → true  : "service suspendu, on vous reprévient"
//   - suspended  true → false (status confirmed) : "c'est reparti"
// L'annulation "trop tard" est gérée par FONCTION 6bis
// (cancellationSource === 'company_block_unresolved').
// ====================================================================
exports.onReservationBlockChange = functions.firestore
  .document("companies/{companyId}/reservations/{reservationId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const { companyId } = context.params;

    const wasSuspended = before.suspended === true;
    const isSuspended = after.suspended === true;
    if (wasSuspended === isSuspended) return null; // pas une transition

    const customerId = after.customerId;
    if (!customerId || customerId === "manual_booking") return null;

    // Réservation déjà annulée (ex. "trop tard") : c'est FONCTION 6bis qui parle.
    if (after.status !== "confirmed") return null;

    const companyDoc = await db.collection("companies").doc(companyId).get();
    const companyName = companyDoc.exists
      ? (companyDoc.data().nom || "L'entreprise")
      : "L'entreprise";
    const queueName = after.queueName || "";
    const queueId = after.queueId || "";

    let dateTimeText = "";
    const slotStart = after.slotStart ? after.slotStart.toDate() : null;
    if (slotStart) {
      const dd = String(slotStart.getDate()).padStart(2, "0");
      const mm = String(slotStart.getMonth() + 1).padStart(2, "0");
      const hh = String(slotStart.getHours()).padStart(2, "0");
      const mn = String(slotStart.getMinutes()).padStart(2, "0");
      dateTimeText = ` du ${dd}/${mm} à ${hh}h${mn}`;
    }

    let title;
    let body;
    if (isSuspended) {
      const reason = (after.suspendedReason || "").trim();
      title = "⏸️ Réservation suspendue";
      body =
        `${companyName}${queueName ? ` — ${queueName}` : ""} : service ` +
        `momentanément indisponible${reason ? ` (${reason})` : ""}. ` +
        `Votre réservation${dateTimeText} est en attente ; vous serez ` +
        `prévenu(e) dès la reprise.`;
    } else {
      title = "✅ Service de nouveau opérationnel";
      body =
        `${companyName}${queueName ? ` — ${queueName}` : ""} a repris. ` +
        `Votre réservation${dateTimeText} est maintenue.`;
    }

    try {
      await db.collection("customers").doc(customerId).collection("notifications").add({
        title,
        body,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        type: isSuspended ? "reservation_suspended" : "reservation_resumed",
        payload: queueId
          ? { companyId, companyName, queueId, queueName }
          : null,
      });
      console.log(`✅ Notification ${isSuspended ? "suspension" : "reprise"} envoyée à ${customerId}`);
    } catch (e) {
      console.error(`❌ Erreur notification blocage pour ${customerId}:`, e.message);
    }
    return null;
  });

// ====================================================================
// FONCTION 6 : Suppression en cascade d'une entreprise
// Déclenchée quand deletionRequests/{companyId}.status passe à 'approved'
// ====================================================================
exports.onDeleteCompanyApproved = functions.firestore
  .document("deletionRequests/{companyId}")
  .onUpdate(async (change, context) => {
    const after = change.after.data();
    if (after.status !== "approved") return null;

    const companyId = context.params.companyId;
    const companyRef = db.collection("companies").doc(companyId);

    console.log(`🗑️ Démarrage suppression entreprise ${companyId}`);

    try {
      // ── 1. Récupérer les infos de l'entreprise ───────────────────
      const companyDoc = await companyRef.get();
      const companyName = companyDoc.exists ? (companyDoc.data().nom || "") : "";

      // ── 2. Annuler toutes les réservations futures + notifier ─────
      const now = new Date();
      const reservationsSnap = await companyRef
        .collection("reservations")
        .where("status", "==", "confirmed")
        .get();

      const futureReservations = reservationsSnap.docs.filter((doc) => {
        const slotStart = doc.data().slotStart?.toDate();
        return slotStart && slotStart > now;
      });

      let batch = db.batch();
      let count = 0;

      for (const doc of futureReservations) {
        const data = doc.data();
        const customerId = data.customerId;
        const slotStart = data.slotStart?.toDate();

        batch.update(doc.ref, {
          status: "cancelled",
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancellationSource: "company_deleted",
        });
        count++;

        if (customerId && customerId !== "manual_booking" && slotStart) {
          const dd = String(slotStart.getDate()).padStart(2, "0");
          const mm = String(slotStart.getMonth() + 1).padStart(2, "0");
          const hh = String(slotStart.getHours()).padStart(2, "0");
          const mn = String(slotStart.getMinutes()).padStart(2, "0");
          const queueName = data.queueName || companyName;

          const notifRef = db
            .collection("customers")
            .doc(customerId)
            .collection("notifications")
            .doc();
          batch.set(notifRef, {
            title: "📅 Réservation annulée",
            body:
              `Votre réservation du ${dd}/${mm}/${slotStart.getFullYear()} ` +
              `à ${hh}h${mn} chez ${queueName} a été annulée. ` +
              `${companyName} n'est plus disponible sur Baxa.`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            type: "cancellation_by_company",
            payload: null,
          });
          count++;
        }

        if (count >= 400) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
      console.log(`✅ ${futureReservations.length} réservation(s) annulée(s)`);

      // ── 3. Révoquer tous les membres de l'équipe ──────────────────
      const membersSnap = await companyRef.collection("staff").get();
      if (!membersSnap.empty) {
        let memberBatch = db.batch();
        let memberCount = 0;
        for (const doc of membersSnap.docs) {
          memberBatch.update(doc.ref, { isActive: false });
          memberCount++;
          if (memberCount >= 400) {
            await memberBatch.commit();
            memberBatch = db.batch();
            memberCount = 0;
          }
        }
        if (memberCount > 0) await memberBatch.commit();
        console.log(`✅ ${membersSnap.size} membre(s) révoqué(s)`);
      }

      // ── 4. Marquer l'entreprise comme supprimée ───────────────────
      await companyRef.update({
        status: "deleted",
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        isActive: false,
      });

      // ── 5. Supprimer les sous-collections ─────────────────────────
      const deleteSubcollection = async (parentRef, name) => {
        const snap = await parentRef.collection(name).get();
        if (snap.empty) return;
        let b = db.batch();
        let c = 0;
        for (const doc of snap.docs) {
          b.delete(doc.ref);
          c++;
          if (c >= 400) { await b.commit(); b = db.batch(); c = 0; }
        }
        if (c > 0) await b.commit();
      };

      const queuesSnap = await companyRef.collection("queues").get();
      for (const queueDoc of queuesSnap.docs) {
        await deleteSubcollection(queueDoc.ref, "slots");
        await deleteSubcollection(queueDoc.ref, "timeSlots");
        await deleteSubcollection(queueDoc.ref, "dailyStats");
        await queueDoc.ref.delete();
      }
      await deleteSubcollection(companyRef, "notificationsHistory");
      await deleteSubcollection(companyRef, "reservations");
      console.log(`✅ ${queuesSnap.size} file(s) et leurs créneaux supprimés`);

      // ── 6. Marquer la demande comme traitée ───────────────────────
      await change.after.ref.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`🎉 Suppression de l'entreprise ${companyId} terminée`);
      return { success: true };
    } catch (error) {
      console.error(`❌ Erreur suppression ${companyId}:`, error);
      await change.after.ref.update({
        status: "error",
        errorMessage: error.message,
        errorAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw error;
    }
  });

// ====================================================================
// FONCTION 6bis : Alerte admin à la création d'une demande de départ
// Écrit un doc dans `adminAlerts` (collection consultée en console) avec
// le contact et le motif, pour pouvoir joindre l'entreprise pendant le
// délai de grâce.
// ====================================================================
exports.onDeletionRequestCreated = functions.firestore
  .document("deletionRequests/{companyId}")
  .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    await db.collection("adminAlerts").add({
      type: "deletion_request",
      companyId: context.params.companyId,
      companyName: d.companyName || "",
      email: d.email || "",
      phone: d.phone || "",
      reason: d.reason || "",
      requestedAt: d.requestedAt || admin.firestore.FieldValue.serverTimestamp(),
      scheduledDeletionAt: d.executeAfter || null,
      status: "unread",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`🔔 Alerte admin : demande de départ de ${context.params.companyId}`);
    return null;
  });

// ====================================================================
// FONCTION 6ter : L'entreprise annule sa demande de départ (elle supprime
// le doc `deletionRequests/{id}` pendant le délai de grâce). On marque les
// alertes admin correspondantes comme annulées pour ne pas les traiter.
// La réactivation des files se fait côté app (efface `closureStart`).
// ====================================================================
exports.onDeletionRequestCancelled = functions.firestore
  .document("deletionRequests/{companyId}")
  .onDelete(async (snap, context) => {
    const before = snap.data() || {};
    // Ne rien faire si la demande était déjà exécutée / approuvée.
    if (before.status === "approved" || before.status === "completed") return null;

    const alerts = await db
      .collection("adminAlerts")
      .where("companyId", "==", context.params.companyId)
      .where("type", "==", "deletion_request")
      .where("status", "==", "unread")
      .get();
    if (alerts.empty) return null;

    const batch = db.batch();
    alerts.docs.forEach((a) =>
      batch.update(a.ref, {
        status: "cancelled_by_company",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await batch.commit();
    console.log(`↩️ Demande de départ annulée par ${context.params.companyId}`);
    return null;
  });

// ====================================================================
// FONCTION 6quater : Exécution des départs dont le délai de grâce (7 j)
// est écoulé. Passe `status` à "approved", ce qui déclenche la cascade de
// suppression existante (onDeleteCompanyApproved, FONCTION 6).
// ====================================================================
exports.executeScheduledDeletions = functions.pubsub
  .schedule("0 3 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const now = new Date();
    const snap = await db
      .collection("deletionRequests")
      .where("status", "==", "scheduled")
      .get();

    let count = 0;
    for (const doc of snap.docs) {
      const ea = doc.data().executeAfter;
      if (ea && ea.toDate() <= now) {
        await doc.ref.update({
          status: "approved",
          approvedAt: admin.firestore.FieldValue.serverTimestamp(),
          approvedBy: "auto_grace_period",
        });
        count++;
        console.log(`⏱️ Délai de grâce écoulé → suppression approuvée : ${doc.id}`);
      }
    }
    console.log(`🗑️ ${count} départ(s) exécuté(s)`);
    return { processed: count };
  });

// ====================================================================
// FONCTION 7 : Planification serveur des notifications de réservation
// (rappels J-24h/J-1h/J-15min, validation au début du créneau, créneau
// passé à la fin) via Cloud Tasks.
//
// Remplace l'ancien système de notifications locales programmées sur
// l'appareil (AlarmManager côté Android) : celui-ci dépendait de
// permissions fragiles (alarmes exactes, optimisation batterie
// constructeur) et ne laissait aucune trace dans l'historique in-app.
// Ici, chaque étape écrit dans customers/{id}/notifications, ce qui
// déclenche automatiquement le push FCM existant (sendPushOnNotification,
// FONCTION 4) et alimente l'onglet Notifications de l'app — un seul
// mécanisme de livraison pour tous les types de notifications.
// ====================================================================

/** Nom Cloud Tasks déterministe : permet de retrouver/supprimer une tâche
 * sans avoir à la stocker (voir FONCTION 9, annulation). */
function reservationTaskName(reservationId, kind) {
  return (
    `projects/${PROJECT_ID}/locations/${TASKS_LOCATION}` +
    `/queues/${TASKS_QUEUE}/tasks/${reservationId}--${kind}`
  );
}

// Les 3 paliers de rappel sont identifiés par position (reminder_1 = le
// plus en avance, reminder_3 = le plus proche du créneau), pas par leur
// durée réelle — celle-ci est désormais choisie par chaque client (voir
// FONCTION 7), donc ne peut plus servir d'identifiant stable.
const RESERVATION_REMINDER_KINDS = [
  "reminder_1",
  "reminder_2",
  "reminder_3",
  "validation",
  "passed",
];

const DEFAULT_REMINDER_OFFSETS_MINUTES = [1440, 60, 15]; // 24h / 1h / 15min

/** Lit les 3 paliers de rappel choisis par le client (réglages > Rappels de
 * réservation), triés du plus en avance au plus proche du créneau. Retombe
 * sur les valeurs par défaut si rien n'est configuré ou si la valeur
 * enregistrée est invalide (pas 3 entiers positifs distincts). */
async function getReminderOffsets(customerId) {
  try {
    const userDoc = await db.collection("users").doc(customerId).get();
    const raw = userDoc.exists ? userDoc.data().reminderOffsets : null;
    if (
      Array.isArray(raw) &&
      raw.length === 3 &&
      raw.every((n) => Number.isInteger(n) && n > 0) &&
      new Set(raw).size === 3
    ) {
      return [...raw].sort((a, b) => b - a);
    }
  } catch (e) {
    console.error("❌ Erreur lecture reminderOffsets:", e.message);
  }
  return DEFAULT_REMINDER_OFFSETS_MINUTES;
}

exports.scheduleReservationTimeline = functions
  .runWith({ secrets: ["TASK_AUTH_SECRET"] })
  .firestore.document("companies/{companyId}/reservations/{reservationId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const { companyId, reservationId } = context.params;
    const customerId = data.customerId;
    if (!customerId || customerId === "manual_booking") return null;

    const slotStart = data.slotStart ? data.slotStart.toDate() : null;
    const slotEnd = data.slotEnd ? data.slotEnd.toDate() : null;
    if (!slotStart || !slotEnd) return null;

    const companyName = data.companyName || "";
    const queueName = data.queueName || "";

    // Étape "confirmée" : écrite tout de suite (pas besoin de Cloud Tasks,
    // c'est immédiat) — donne une première entrée dans l'historique dès la
    // réservation, plutôt que d'attendre le premier rappel.
    const confirmedContent = reservationStageContent(
      "confirmed",
      companyName,
      queueName,
    );
    await db
      .collection("customers")
      .doc(customerId)
      .collection("notifications")
      .doc(`resa-${reservationId}`)
      .set({
        title: confirmedContent.title,
        body: confirmedContent.body,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        type: "reservation_timeline",
        payload: {
          companyId,
          queueId: data.queueId || "",
          slotId: data.slotId || "",
          reservationId,
          companyName,
          queueName,
        },
      });

    const offsets = await getReminderOffsets(customerId);

    const functionUrl =
      `https://${TASKS_LOCATION}-${PROJECT_ID}.cloudfunctions.net` +
      `/deliverReservationNotification`;
    const secret = process.env.TASK_AUTH_SECRET;
    const now = Date.now();

    const payloadBase = {
      customerId,
      companyId,
      reservationId,
      queueId: data.queueId || "",
      slotId: data.slotId || "",
      companyName,
      queueName,
    };

    const jobs = [
      {
        kind: "reminder_1",
        at: new Date(slotStart.getTime() - offsets[0] * 60000),
        minutes: offsets[0],
      },
      {
        kind: "reminder_2",
        at: new Date(slotStart.getTime() - offsets[1] * 60000),
        minutes: offsets[1],
      },
      {
        kind: "reminder_3",
        at: new Date(slotStart.getTime() - offsets[2] * 60000),
        minutes: offsets[2],
      },
      { kind: "validation", at: slotStart },
      { kind: "passed", at: slotEnd },
    ];

    for (const job of jobs) {
      // On saute les rappels déjà dans le passé (réservation faite tard) ;
      // validation et créneau passé sont, elles, toujours programmées.
      if (job.kind.startsWith("reminder_") && job.at.getTime() <= now + 5000) {
        continue;
      }

      const task = {
        name: reservationTaskName(reservationId, job.kind),
        httpRequest: {
          httpMethod: "POST",
          url: functionUrl,
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${secret}`,
          },
          body: Buffer.from(
            JSON.stringify({
              ...payloadBase,
              kind: job.kind,
              minutes: job.minutes,
            }),
          ).toString("base64"),
        },
        scheduleTime: { seconds: Math.floor(job.at.getTime() / 1000) },
      };

      try {
        await tasksClient.createTask({
          parent: tasksClient.queuePath(PROJECT_ID, TASKS_LOCATION, TASKS_QUEUE),
          task,
        });
      } catch (e) {
        console.error(
          `❌ Erreur création tâche ${job.kind} pour ${reservationId}:`,
          e.message,
        );
      }
    }

    console.log(`✅ Timeline de notifications planifiée pour ${reservationId}`);
    return null;
  });

// ====================================================================
// FONCTION 8 : Endpoint appelé par Cloud Tasks à l'heure programmée pour
// livrer une étape de la timeline (rappel/validation/créneau passé).
//
// Protégé par un secret partagé plutôt qu'une vérification OIDC manuelle
// (appel serveur-à-serveur interne, jamais exposé côté client).
// ====================================================================
// Nom du lieu à afficher dans les rappels : établissement + file si elles
// diffèrent (sinon la file, souvent nommée comme l'établissement, ferait
// doublon), pour lever l'ambiguïté quand le client a plusieurs réservations
// actives dans des établissements différents le même jour.
function reservationVenueLabel(companyName, queueName) {
  if (companyName && queueName && queueName !== companyName) {
    return `${companyName} — ${queueName}`;
  }
  return companyName || queueName || "ton établissement";
}

/** Formate une durée en minutes en texte lisible ("3 heures", "45 minutes")
 * — les options proposées côté client sont toujours des multiples ronds
 * d'heures ou de minutes, donc pas besoin de gérer les cas mixtes. */
function formatMinutesLabel(minutes) {
  if (minutes % 60 === 0) {
    const h = minutes / 60;
    return `${h} heure${h > 1 ? "s" : ""}`;
  }
  return `${minutes} minute${minutes > 1 ? "s" : ""}`;
}

function reservationStageContent(kind, companyName, queueName, reminderMinutes) {
  const place = reservationVenueLabel(companyName, queueName);
  switch (kind) {
    case "confirmed":
      return {
        title: "🎉 Réservation confirmée",
        body: `C'est noté chez ${place} !`,
      };
    case "reminder_1":
    case "reminder_2":
    case "reminder_3":
      return {
        title: "⏰ Rappel",
        body: `Chez ${place}, c'est dans ${formatMinutesLabel(reminderMinutes)}`,
      };
    case "validation":
      return {
        title: "🟢 Validation",
        body: "C'est ton tour, présente-toi maintenant ✅",
      };
    case "passed":
      return { title: "🟠 Créneau passé", body: "Ton créneau est terminé ⌛" };
    default:
      return null;
  }
}

exports.deliverReservationNotification = functions
  .runWith({ secrets: ["TASK_AUTH_SECRET"] })
  .https.onRequest(async (req, res) => {
    if (req.get("Authorization") !== `Bearer ${process.env.TASK_AUTH_SECRET}`) {
      res.status(401).send("Unauthorized");
      return;
    }

    const {
      customerId,
      companyId,
      reservationId,
      queueId,
      slotId,
      companyName,
      queueName,
      kind,
      minutes,
    } = req.body || {};

    const content = reservationStageContent(kind, companyName, queueName, minutes);
    if (!customerId || !companyId || !reservationId || !content) {
      res.status(400).send("Payload invalide");
      return;
    }

    try {
      // La réservation a pu être annulée/remplacée entre la programmation
      // de la tâche et son exécution (course avec FONCTION 9) — dans ce
      // cas normalement déjà supprimée, mais on revérifie par sécurité.
      const resDoc = await db
        .collection("companies")
        .doc(companyId)
        .collection("reservations")
        .doc(reservationId)
        .get();
      if (
        !resDoc.exists ||
        resDoc.data().status !== "confirmed" ||
        resDoc.data().suspended === true
      ) {
        res.status(200).send("Réservation inactive, notification ignorée");
        return;
      }

      // Un seul document par réservation, mis à jour à chaque étape
      // (plutôt qu'un nouveau document à chaque fois) : la précédente
      // notification de la séquence est ainsi automatiquement remplacée
      // dans l'historique de l'app, pas seulement dans la barre système.
      await db
        .collection("customers")
        .doc(customerId)
        .collection("notifications")
        .doc(`resa-${reservationId}`)
        .set({
          title: content.title,
          body: content.body,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          type: "reservation_timeline",
          payload: {
            companyId,
            queueId: queueId || "",
            slotId: slotId || "",
            reservationId,
            companyName: companyName || "",
            queueName: queueName || "",
          },
        });

      console.log(`✅ Étape "${kind}" envoyée pour ${reservationId}`);
      res.status(200).send("OK");
    } catch (e) {
      console.error(
        `❌ Erreur envoi notification ${kind} pour ${reservationId}:`,
        e.message,
      );
      res.status(500).send("Erreur serveur");
    }
  });

// ====================================================================
// FONCTION 9 : Annulation des rappels/validation/créneau-passé restants
// dès qu'une réservation passe à "cancelled" — peu importe la source
// (client depuis "Mes réservations", bouton de notification, entreprise,
// suppression d'entreprise...). Contrairement à l'ancien système local,
// ce nettoyage est garanti au niveau serveur : aucun chemin client ne
// peut oublier de l'appeler.
// ====================================================================
exports.cancelReservationTimeline = functions.firestore
  .document("companies/{companyId}/reservations/{reservationId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const { reservationId } = context.params;

    if (before.status === "cancelled" || after.status !== "cancelled") {
      return null;
    }

    await Promise.all(
      RESERVATION_REMINDER_KINDS.map(async (kind) => {
        try {
          await tasksClient.deleteTask({
            name: reservationTaskName(reservationId, kind),
          });
        } catch (e) {
          if (e.code !== 5) {
            // 5 = NOT_FOUND (déjà exécutée ou jamais programmée) — ignoré.
            console.error(
              `❌ Erreur suppression tâche ${kind} pour ${reservationId}:`,
              e.message,
            );
          }
        }
      }),
    );

    console.log(`✅ Timeline de notifications annulée pour ${reservationId}`);
    return null;
  });

// ====================================================================
// FONCTION 10 : Purge automatique des réservations terminées ou annulées
// depuis plus d'un mois — évite un historique illimité côté client. Le
// masquage individuel (voir app, "Mes réservations") est volontaire et
// immédiat ; cette purge est le filet de sécurité automatique qui
// s'applique à tout le monde, indépendamment du masquage.
// ====================================================================
exports.purgeOldReservations = functions.pubsub
  .schedule("30 2 * * *") // Tous les jours à 2h30 du matin UTC
  .timeZone("Europe/Paris")
  .onRun(async (context) => {
    console.log("🧹 Purge des réservations de plus d'un mois...");

    const oneMonthAgo = new Date();
    oneMonthAgo.setDate(oneMonthAgo.getDate() - 30);

    let totalDeleted = 0;
    const companiesSnap = await db.collection("companies").get();

    for (const companyDoc of companiesSnap.docs) {
      const oldReservations = await companyDoc.ref
        .collection("reservations")
        .where("slotEnd", "<", oneMonthAgo)
        .get();

      if (oldReservations.empty) continue;

      let batch = db.batch();
      let count = 0;

      for (const doc of oldReservations.docs) {
        const data = doc.data();
        batch.delete(doc.ref);
        // Purge aussi la notification "timeline" associée (voir FONCTION 7),
        // sans quoi elle resterait indéfiniment dans l'onglet Notifications
        // du client alors que la réservation qu'elle décrit n'existe plus.
        if (data.customerId) {
          batch.delete(
            db
              .collection("customers")
              .doc(data.customerId)
              .collection("notifications")
              .doc(`resa-${doc.id}`),
          );
        }
        count++;
        totalDeleted++;
        if (count >= 400) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    }

    console.log(`✅ ${totalDeleted} réservation(s) purgée(s)`);
    return null;
  });

// ====================================================================
// FONCTION 12 : Résolution des suspensions expirées
// Filet de sécurité : si l'entreprise a bloqué un créneau (flag
// `suspended` sur la réservation) mais n'a jamais débloqué, et que le
// créneau est maintenant passé → on annule la réservation
// (`company_block_unresolved`) pour que le client soit prévenu qu'il peut
// re-réserver (via FONCTION 6bis) et que la réservation ne reste pas
// "suspendue" indéfiniment.
// ====================================================================
exports.resolveExpiredSuspensions = functions.pubsub
  .schedule("15 2 * * *") // Tous les jours à 2h15 du matin UTC
  .timeZone("Europe/Paris")
  .onRun(async (context) => {
    const now = new Date();
    let total = 0;
    const companiesSnap = await db.collection("companies").get();

    for (const companyDoc of companiesSnap.docs) {
      const snap = await companyDoc.ref
        .collection("reservations")
        .where("status", "==", "confirmed")
        .get();
      if (snap.empty) continue;

      const expired = snap.docs.filter((d) => {
        if (d.data().suspended !== true) return false;
        const se = d.data().slotEnd ? d.data().slotEnd.toDate() : null;
        return se && se < now;
      });
      if (expired.length === 0) continue;

      let batch = db.batch();
      let count = 0;
      for (const doc of expired) {
        batch.update(doc.ref, {
          status: "cancelled",
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancellationSource: "company_block_unresolved",
          suspended: admin.firestore.FieldValue.delete(),
          suspendedReason: admin.firestore.FieldValue.delete(),
          suspendedAt: admin.firestore.FieldValue.delete(),
        });
        count++;
        total++;
        if (count >= 400) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    }

    console.log(`✅ ${total} suspension(s) expirée(s) résolue(s)`);
    return null;
  });