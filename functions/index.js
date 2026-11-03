const {
  onDocumentCreated, onDocumentUpdated, onDocumentWritten, onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onRequest, onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");
const {CloudTasksClient} = require("@google-cloud/tasks");
const wake = require("./wake");
const searchDir = require("./search_directory");
const zone = require("./zone");
const suspension = require("./suspension");
admin.initializeApp();

// Plafond d'instances par fonction (2e génération). Par défaut chacune peut
// monter à 100 instances, ce qui épuise le quota de processeur de la région
// de Johannesburg dès le déploiement — et laisserait une boucle accidentelle
// faire grimper la facture. Au-delà du plafond, les événements Firestore
// attendent et sont relivrés : rien n'est perdu. À relever (avec une
// demande de quota) quand le trafic le justifiera.
setGlobalOptions({ maxInstances: 20 });

const db = admin.firestore();
const tasksClient = new CloudTasksClient();

// Régions des fonctions 2e génération.
// - DB_REGION : à côté de la base Firestore (Johannesburg) — pour tout ce
//   qui lit / écrit beaucoup. Les déclencheurs Firestore 2e génération
//   doivent de toute façon être dans la région de la base.
// - SCHEDULER_REGION : Cloud Scheduler et Cloud Tasks n'existent pas à
//   Johannesburg ; les tâches planifiées sont donc lancées depuis l'Europe.
const DB_REGION = "africa-south1";
const SCHEDULER_REGION = "europe-west1";

// Adaptateurs 2e génération : le corps des fonctions garde sa signature
// historique — (snap | change, context) pour les déclencheurs Firestore,
// (data, context) pour les fonctions appelables — et seule l'enveloppe
// change. Tous tournent à côté de la base (DB_REGION).
function triggerOpts(docOrOpts) {
  const o = typeof docOrOpts === "string" ? { document: docOrOpts } : docOrOpts;
  return { region: DB_REGION, ...o };
}
const asV1 = (handler) => (event) =>
  handler(event.data, { params: event.params });
const v2Created = (d, handler) => onDocumentCreated(triggerOpts(d), asV1(handler));
const v2Updated = (d, handler) => onDocumentUpdated(triggerOpts(d), asV1(handler));
const v2Written = (d, handler) => onDocumentWritten(triggerOpts(d), asV1(handler));
const v2Deleted = (d, handler) => onDocumentDeleted(triggerOpts(d), asV1(handler));
const v2Callable = (handler) => onCall(
  { region: DB_REGION },
  (request) => handler(request.data, { auth: request.auth }),
);

// Projet/région utilisés pour la file Cloud Tasks des notifications de
// réservation (rappels, validation, créneau passé) — voir FONCTION 7.
const PROJECT_ID =
  admin.app().options.projectId ||
  process.env.GCLOUD_PROJECT ||
  process.env.GCP_PROJECT;
const TASKS_LOCATION = "us-central1";
const TASKS_QUEUE = "reservation-notifications";

// Nombre maximum de réservations qu'un client peut créer par jour.
// MIROIR de kMaxDailyReservations (lib/services/booking_constants.dart) —
// si la limite change là-bas, la changer ici aussi.
const MAX_DAILY_RESERVATIONS = 5;

// Nombre maximum de membres actifs dans une équipe.
// MIROIR de kMaxActiveStaff (lib/services/booking_constants.dart).
const MAX_ACTIVE_STAFF = 5;

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

/** Fuseau horaire d'une structure (`timeZone` de sa fiche), ou celui par
 * défaut si absent / invalide. Voir zone.js. */
async function companyTimeZone(companyId) {
  const snap = await db.collection("companies").doc(companyId).get();
  return zone.tzOf(snap.exists ? snap.get("timeZone") : null);
}

// ────────────────────────────────────────────────────────────────────
// Résumé « recherche » d'une entreprise, écrit sur companies/{id} :
//   queueCount        : nombre de files
//   closedNow         : true si TOUTES les files sont fermées maintenant
//   reopenAt          : date de réouverture si toutes datées (absent sinon)
//   closurePlannedFor : plus proche fermeture posée mais PAS encore active
//                       (absent si aucune / si déjà fermé)
// Permet à la page de recherche client de filtrer / étiqueter, et à la CF
// onCompanyStateChange de prévenir le staff, sans lire la sous-collection
// `queues` de chaque entreprise.
// ────────────────────────────────────────────────────────────────────
async function writeCompanySearchSummary(companyId, queuesDocs, now) {
  const n = now || new Date();
  const count = queuesDocs.length;
  let allClosed = count > 0;
  let latestEnd = null;
  let anyIndefinite = false;
  let earliestPlanned = null;

  for (const q of queuesDocs) {
    const d = q.data();
    const closed = isQueueClosedNow(d.closureStart, d.closureEnd, n);
    if (!closed) allClosed = false;

    if (closed) {
      if (d.closureEnd) {
        const e = d.closureEnd.toDate();
        if (latestEnd === null || e > latestEnd) latestEnd = e;
      } else {
        anyIndefinite = true;
      }
    } else if (d.closureStart) {
      const cs = d.closureStart.toDate();
      if (cs > n && (earliestPlanned === null || cs < earliestPlanned)) {
        earliestPlanned = cs;
      }
    }
  }

  const update = {
    queueCount: count,
    closedNow: allClosed,
    reopenAt: (allClosed && !anyIndefinite && latestEnd)
      ? admin.firestore.Timestamp.fromDate(latestEnd)
      : admin.firestore.FieldValue.delete(),
    closurePlannedFor: (!allClosed && earliestPlanned)
      ? admin.firestore.Timestamp.fromDate(earliestPlanned)
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
// FONCTION 2 : Nettoyage automatique du journal de notifications entreprise
//
// Durée de vie PAR TYPE (le journal doit rester lisible — surtout des
// récaps, jamais un magma) :
//   récap de plage ............ 30 jours
//   bilan hebdo (sous-utilisée)  7 jours
//   plage complète / bientôt / membre / ajouts équipe . 2 jours
//   résumé du matin / coup de coude ............. 24 h
// Purge aussi l'ancienne collection `notificationsHistory` (transition).
// ====================================================================
const COMPANY_NOTIF_TTL_HOURS = {
  plage_recap: 30 * 24,
  plage_underused: 7 * 24,
  plage_full: 2 * 24,
  plage_near_full: 2 * 24,
  staff_joined: 2 * 24,
  staff_left: 2 * 24,
  team_adds: 2 * 24,
  day_digest: 24,
  queue_checkin: 24,
};
const COMPANY_NOTIF_DEFAULT_TTL_HOURS = 7 * 24;

/** Purge le journal de notifications d'UNE structure (durée de vie par
 * type). Lancée chaque nuit par la maintenance de nuit. */
async function cleanCompanyNotifications(companyId) {
  const companyRef = db.collection("companies").doc(companyId);
  const now = Date.now();
  // Rien de plus jeune que 24h ne peut être expiré — pré-filtre grossier.
  const coarseCutoff = new Date(now - 24 * 3600 * 1000);
  const sevenDaysAgo = new Date(now - 7 * 24 * 3600 * 1000);
  let totalDeleted = 0;

  // ── Journal unifié : purge par type ──
  const journalSnap = await companyRef
    .collection("companyNotifications")
    .where("createdAt", "<", coarseCutoff)
    .get();

  let batch = db.batch();
  let count = 0;
  for (const doc of journalSnap.docs) {
    const d = doc.data();
    const created = d.createdAt ? d.createdAt.toDate().getTime() : 0;
    const ttlH = COMPANY_NOTIF_TTL_HOURS[d.type] ||
      COMPANY_NOTIF_DEFAULT_TTL_HOURS;
    if (created && now - created > ttlH * 3600 * 1000) {
      batch.delete(doc.ref);
      totalDeleted++;
      if (++count >= 400) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }
  }
  if (count > 0) await batch.commit();

  // ── Ancienne collection (transition) : > 7 jours ──
  const oldNotifs = await companyRef
    .collection("notificationsHistory")
    .where("createdAt", "<", sevenDaysAgo)
    .get();
  if (!oldNotifs.empty) {
    let b2 = db.batch();
    oldNotifs.docs.forEach((doc) => b2.delete(doc.ref));
    await b2.commit();
    totalDeleted += oldNotifs.size;
  }
  return totalDeleted;
}

// ====================================================================
// FONCTION 3 : Génération automatique des créneaux d'UNE structure
// (lancée chaque nuit par la maintenance de nuit, voir companyJob).
// ====================================================================
async function generateSlotsForCompany(companyId) {
  // Tous les jours et toutes les heures (« 9h » d'une plage, minuit…) sont
  // ceux du fuseau de la structure (voir zone.js).
  const tz = await companyTimeZone(companyId);
  const todayStr = zone.ymdIn(new Date(), tz);
  const today = zone.dayBounds(todayStr, tz).start; // minuit local

  // Date limite passée : J-7 (on supprime ce qui est plus vieux)
  const deleteBeforeStr = zone.addDays(todayStr, -7);
  const deleteBeforeDate = zone.dayBounds(deleteBeforeStr, tz).start;

  let totalGenerated = 0;
  let totalDeleted = 0;

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
        .where("date", "<", deleteBeforeStr)
        .get();
      if (!oldStatsSnap.empty) {
        let statsBatch = db.batch();
        oldStatsSnap.docs.forEach((d) => statsBatch.delete(d.ref));
        await statsBatch.commit();
      }

      console.log(`🗑️ File ${queueId}: ${deleteCount} vieux créneaux supprimés`);
    }

    // Helper : écrire/mettre à jour les dailyStats d'un jour local
    // (« AAAA-MM-JJ ») en agrégeant les slots existants
    const upsertDailyStats = async (dayStr) => {
      const { start: dayStart, end: dayEnd } = zone.dayBounds(dayStr, tz);

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

      await dailyStatsRef.doc(dayStr).set({
        date: dayStr,
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
            const affectedDays = new Set();
            let delBatch = db.batch();
            let delCount = 0;
            for (const d of remainingSnap.docs) {
              affectedDays.add(zone.ymdIn(d.data().start.toDate(), tz));
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
            for (const dayStr of affectedDays) {
              await upsertDailyStats(dayStr);
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
        // `maxAdvanceDays` est désormais un réglage de la FILE (doc file),
        // plus de la plage : rien à resynchroniser ici.
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

      // Horizon de génération fixe (8 jours). Ce que le client VOIT est
      // borné séparément par `maxAdvanceDays` du doc file (filtre d'affichage).
      for (let dayOffset = 0; dayOffset <= 7; dayOffset++) {
        const dayStr = zone.addDays(todayStr, dayOffset);
        const dayStart = zone.dayBounds(dayStr, tz).start;

        const cfg = (pendingCfg && dayStart >= pendingEffectiveDate)
          ? pendingCfg
          : currentCfg;

        // Vérifier si ce jour est ouvré (1=Lundi, 7=Dimanche)
        if (!cfg.activeDays.includes(zone.weekdayOf(dayStr))) continue;

        // Heures murales de la plage, dans le fuseau de la structure
        // (« 24:00 » = minuit du lendemain).
        const plageStart = zone.zonedTime(dayStr, cfg.startTime, tz);
        const plageEnd = zone.zonedTime(dayStr, cfg.endTime, tz);

        // Vérifier si des créneaux existent déjà pour cette plage
        const existingSnap = await slotsRef
          .where("start", ">=", plageStart)
          .where("start", "<", plageEnd)
          .limit(1)
          .get();

        if (!existingSnap.empty) {
          // Slots déjà générés — créer dailyStats si absent (migration)
          const statsDoc = await dailyStatsRef.doc(dayStr).get();
          if (!statsDoc.exists) {
            await upsertDailyStats(dayStr);
            console.log(`📊 File ${queueId}: dailyStats créé (migration) pour ${dayStr}`);
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
          await upsertDailyStats(dayStr);
          console.log(`✅ File ${queueId} / ${dayStr}: ${createCount} créneaux + dailyStats`);
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

  return { generated: totalGenerated, deleted: totalDeleted };
}

// ====================================================================
// FONCTION 3bis : Résumé « recherche » de l'entreprise, mis à jour dès
// qu'une file est créée, supprimée, fermée ou rouverte. Sert à la page de
// recherche client pour masquer / étiqueter les structures sans mesurer
// leurs files à chaque requête.
// ====================================================================
exports.updateCompanySearchSummary = v2Written("companies/{companyId}/queues/{queueId}", async (change, context) => {
    const companyId = context.params.companyId;
    const queuesSnap = await db
      .collection("companies")
      .doc(companyId)
      .collection("queues")
      .get();
    await writeCompanySearchSummary(companyId, queuesSnap.docs, new Date());

    // Même déclencheur (pas d'appel de fonction en plus) : une file créée,
    // supprimée, fermée ou rouverte change les horaires du jour → les
    // réveils des notifs (bilan, coup d'œil, ajouts équipe) sont replanifiés.
    if (queueScheduleChanged(change)) {
      try {
        await requestCompanyReplan(companyId);
      } catch (e) {
        console.error(`❌ requestCompanyReplan ${companyId}:`, e.message);
      }
    }
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
exports.sendPushOnNotification = v2Written("customers/{customerId}/notifications/{notificationId}", async (change, context) => {
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

    // Deep-link vers le ticket vivant : uniquement pour l'étape "c'est ton
    // tour" (voir la discussion produit — un créneau confirmé/passé n'a
    // rien à prouver, pas besoin d'y emmener directement). Les valeurs
    // FCM `data` doivent être des chaînes, d'où les vérifications ici.
    const p = data.payload || {};
    const dataPayload =
      data.kind === "validation" && p.slotStart && p.slotEnd
        ? {
            deepLink: "ticket",
            companyName: p.companyName || "",
            queueName: p.queueName || "",
            slotStart: p.slotStart,
            slotEnd: p.slotEnd,
          }
        : undefined;

    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        ...(dataPayload ? { data: dataPayload } : {}),
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
// FONCTION 5 : Alerte remplissage à chaque nouvelle réservation
//
// L'ancien compteur `reservationCount` (incrémenté ici sur la fiche
// entreprise) n'est plus écrit : la popularité est recalculée chaque nuit
// dans l'annuaire de recherche (voir rebuildSearchDirectory). Écrire la
// fiche à chaque réservation la renvoyait à tous les clients qui
// écoutaient la recherche.
// ====================================================================
exports.onReservationCreated = v2Created("companies/{companyId}/reservations/{reservationId}", async (snap, context) => {
    const { companyId } = context.params;

    // Alerte remplissage de la plage concernée (plage_full / plage_near_full).
    try {
      await checkPlageFillAfterReservation(companyId, snap.data());
    } catch (e) {
      console.error(`❌ checkPlageFill ${companyId}:`, e.message);
    }
    return null;
  });

// ====================================================================
// FONCTION 5bis : Rappel « plus qu'une réservation aujourd'hui »
//
// Remplace l'ancien bottom sheet local de l'app. Quand le quota
// journalier d'un client tombe à 1 réservation restante (donc juste
// après sa MAX_DAILY_RESERVATIONS - 1 -ème réservation du jour), on lui
// écrit une notification. Le push part ensuite tout seul (FONCTION 4).
//
// - Une seule fois par jour : marqueur `dailyQuotaWarnSentOn` sur le
//   profil, comparé à `lastBookingDate` (date calculée côté app, heure
//   locale de l'appareil) pour éviter les décalages autour de minuit.
// - Ignoré pour les inscriptions faites par le staff (`manual_booking`)
//   et pour les remplacements de créneau (`replacedReservationId`), qui
//   ne consomment pas le quota.
// ====================================================================
exports.notifyDailyQuotaWarning = v2Created("companies/{companyId}/reservations/{reservationId}", async (snap) => {
    const data = snap.data();
    const customerId = data.customerId;

    if (!customerId || customerId === "manual_booking") return null;
    if (data.replacedReservationId) return null;

    const userRef = db.collection("users").doc(customerId);

    try {
      await db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) return;
        const u = userSnap.data();

        const dailyCount = u.dailyBookingCount || 0;
        const bookingDate = u.lastBookingDate || "";

        // On ne prévient qu'à l'instant précis où il ne reste qu'UNE
        // réservation pour la journée.
        if (dailyCount !== MAX_DAILY_RESERVATIONS - 1) return;

        // Déjà prévenu pour cette même journée.
        if (!bookingDate || u.dailyQuotaWarnSentOn === bookingDate) return;

        const used = MAX_DAILY_RESERVATIONS - 1;
        const notifRef = db
          .collection("customers")
          .doc(customerId)
          .collection("notifications")
          .doc(`daily-quota-${bookingDate}`);

        tx.set(notifRef, {
          title: "⏳ Plus qu'une réservation aujourd'hui",
          body:
            `Tu as utilisé ${used} de tes ${MAX_DAILY_RESERVATIONS} ` +
            "réservations du jour, il t'en reste 1. Ton quota se recharge " +
            "demain 🔄 — et tu peux toujours t'inscrire directement sur place.",
          type: "daily_quota_warning",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        tx.set(
          userRef,
          { dailyQuotaWarnSentOn: bookingDate },
          { merge: true },
        );
      });
    } catch (e) {
      console.error(`❌ notifyDailyQuotaWarning ${customerId}:`, e.message);
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
exports.onReservationCancelledByCompany = v2Updated("companies/{companyId}/reservations/{reservationId}", async (change, context) => {
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

    // Date et heure dans le fuseau de la structure (voir zone.js).
    const tz = zone.tzOf(companyDoc.exists ? companyDoc.get("timeZone") : null);
    let dateTimeText = "";
    const slotStart = after.slotStart ? after.slotStart.toDate() : null;
    if (slotStart) {
      dateTimeText =
        ` du ${zone.fmtDdMmYyyy(slotStart, tz)} à ${zone.fmtHHhMM(slotStart, tz)}`;
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
exports.onReservationBlockChange = v2Updated("companies/{companyId}/reservations/{reservationId}", async (change, context) => {
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

    // Date et heure dans le fuseau de la structure (voir zone.js).
    const tz = zone.tzOf(companyDoc.exists ? companyDoc.get("timeZone") : null);
    let dateTimeText = "";
    const slotStart = after.slotStart ? after.slotStart.toDate() : null;
    if (slotStart) {
      dateTimeText =
        ` du ${zone.fmtDdMm(slotStart, tz)} à ${zone.fmtHHhMM(slotStart, tz)}`;
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
exports.onDeleteCompanyApproved = v2Updated("deletionRequests/{companyId}", async (change, context) => {
    const after = change.after.data();
    if (after.status !== "approved") return null;

    const companyId = context.params.companyId;
    const companyRef = db.collection("companies").doc(companyId);

    console.log(`🗑️ Démarrage suppression entreprise ${companyId}`);

    try {
      // ── 1. Récupérer les infos de l'entreprise ───────────────────
      const companyDoc = await companyRef.get();
      const companyName = companyDoc.exists ? (companyDoc.data().nom || "") : "";
      // Dates des notifications dans le fuseau de la structure (zone.js).
      const tz = zone.tzOf(companyDoc.exists ? companyDoc.get("timeZone") : null);

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
          const queueName = data.queueName || companyName;

          const notifRef = db
            .collection("customers")
            .doc(customerId)
            .collection("notifications")
            .doc();
          batch.set(notifRef, {
            title: "📅 Réservation annulée",
            body:
              `Votre réservation du ${zone.fmtDdMmYyyy(slotStart, tz)} ` +
              `à ${zone.fmtHHhMM(slotStart, tz)} chez ${queueName} a été annulée. ` +
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
          // Le motif n'écrase pas celui d'un membre déjà parti ou retiré.
          memberBatch.update(
            doc.ref,
            doc.get("isActive") === true
              ? { isActive: false, revokedReason: "company_leaving" }
              : { isActive: false },
          );
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
exports.onDeletionRequestCreated = v2Created("deletionRequests/{companyId}", async (snap, context) => {
    const companyId = context.params.companyId;
    const d = snap.data() || {};
    await db.collection("adminAlerts").add({
      type: "deletion_request",
      companyId,
      companyName: d.companyName || "",
      email: d.email || "",
      phone: d.phone || "",
      reason: d.reason || "",
      requestedAt: d.requestedAt || admin.firestore.FieldValue.serverTimestamp(),
      scheduledDeletionAt: d.executeAfter || null,
      status: "unread",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`🔔 Alerte admin : demande de départ de ${companyId}`);

    // Prévenir chaque membre d'équipe que l'établissement quitte Baxa, PUIS
    // couper son accès — dans cet ordre, ici, pour qu'aucun membre ne soit
    // désactivé avant d'avoir été prévenu. Le motif posé sur la fiche staff
    // permet à l'app d'expliquer la déconnexion.
    const name = d.companyName || "L'établissement";
    const members = await notifyAllActiveStaff(companyId, {
      type: "structure_leaving",
      title: `👋 ${name} quitte Baxa`,
      body:
        "Votre accès à l'espace équipe prend fin. Si l'établissement revient, " +
        "votre responsable vous enverra un nouveau code d'invitation.",
    });
    if (members.length > 0) {
      const batch = db.batch();
      for (const m of members) {
        batch.update(m.ref, {
          isActive: false,
          revokedReason: "company_leaving",
        });
      }
      await batch.commit();
    }
    return null;
  });

// ====================================================================
// FONCTION 6ter : L'entreprise annule sa demande de départ (elle supprime
// le doc `deletionRequests/{id}` pendant le délai de grâce). On marque les
// alertes admin correspondantes comme annulées pour ne pas les traiter.
// La réactivation des files se fait côté app (efface `closureStart`).
// ====================================================================
exports.onDeletionRequestCancelled = v2Deleted("deletionRequests/{companyId}", async (snap, context) => {
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
exports.executeScheduledDeletions = onSchedule(
  { schedule: "0 3 * * *", timeZone: "UTC", region: SCHEDULER_REGION },
  async () => {
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

exports.scheduleReservationTimeline = v2Created({
  document: "companies/{companyId}/reservations/{reservationId}",
  secrets: ["TASK_AUTH_SECRET"],
}, async (snap, context) => {
    const data = snap.data();
    const { companyId, reservationId } = context.params;
    const customerId = data.customerId;
    if (!customerId || customerId === "manual_booking") return null;

    const slotStart = data.slotStart ? data.slotStart.toDate() : null;
    const slotEnd = data.slotEnd ? data.slotEnd.toDate() : null;
    if (!slotStart || !slotEnd) return null;

    const companyName = data.companyName || "";
    const queueName = data.queueName || "";
    // Heures des rappels affichées dans le fuseau de la structure.
    const timeZone = await companyTimeZone(companyId);

    // Étape "confirmée" : écrite tout de suite (pas besoin de Cloud Tasks,
    // c'est immédiat) — donne une première entrée dans l'historique dès la
    // réservation, plutôt que d'attendre le premier rappel.
    const confirmedContent = reservationStageContent(
      "confirmed",
      companyName,
      queueName,
      undefined,
      slotStart,
      slotEnd,
      timeZone,
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
        kind: "confirmed",
        payload: {
          companyId,
          queueId: data.queueId || "",
          slotId: data.slotId || "",
          reservationId,
          companyName,
          queueName,
          slotStart: slotStart.toISOString(),
          slotEnd: slotEnd.toISOString(),
        },
      });

    const offsets = await getReminderOffsets(customerId);

    const functionUrl =
      `https://${DB_REGION}-${PROJECT_ID}.cloudfunctions.net` +
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
      slotStart: slotStart.toISOString(),
      slotEnd: slotEnd.toISOString(),
      timeZone,
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

/** "28/02" — volontairement sans année : le titre de la notif doit rester
 * court (voir reservationStageContent), l'année n'aide en rien à repérer une
 * capture d'écran réutilisée d'un jour à l'autre. */
function formatDayMonth(date, tz) {
  return zone.fmtDdMm(date, tz);
}

/** "12h30 - 12h40" (heure locale de la structure) */
function formatHourRange(start, end, tz) {
  return `${zone.fmtHHhMM(start, tz)} - ${zone.fmtHHhMM(end, tz)}`;
}

function reservationStageContent(
  kind,
  companyName,
  queueName,
  reminderMinutes,
  slotStart,
  slotEnd,
  tz,
) {
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
      // Établissement + file + date directement dans le titre (rendu en gras
      // nativement par l'OS) : vérifiable par le personnel en un coup d'œil,
      // sans ouvrir la notif. La date pousse un éventuel réutilisateur d'une
      // capture d'écran à devoir la refaire chaque jour plutôt qu'une seule
      // fois — voir la discussion sur la fraude aux notifications.
      return {
        title: `🟢 ${place} · ${formatDayMonth(slotStart, tz)}`,
        body:
          `C'est ton tour (${formatHourRange(slotStart, slotEnd, tz)}), ` +
          "présente-toi maintenant ✅",
      };
    case "passed":
      return {
        title: `🟠 ${place} · ${formatDayMonth(slotStart, tz)}`,
        body: `Ton créneau (${formatHourRange(slotStart, slotEnd, tz)}) est terminé ⌛`,
      };
    default:
      return null;
  }
}

exports.deliverReservationNotification = onRequest(
  { region: DB_REGION, secrets: ["TASK_AUTH_SECRET"] },
  async (req, res) => {
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
      slotStart: slotStartIso,
      slotEnd: slotEndIso,
      timeZone,
    } = req.body || {};

    const slotStart = slotStartIso ? new Date(slotStartIso) : null;
    const slotEnd = slotEndIso ? new Date(slotEndIso) : null;

    const content = reservationStageContent(
      kind,
      companyName,
      queueName,
      minutes,
      slotStart,
      slotEnd,
      zone.tzOf(timeZone),
    );
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

      // Fin du créneau alors que la plage est toujours bloquée : le client
      // ne peut plus être servi → on annule sa réservation maintenant (même
      // effet qu'un « Débloquer » de l'entreprise), au lieu d'attendre le
      // filet de sécurité de nuit. FONCTION 6bis envoie la notification.
      // Transaction : si l'entreprise débloque au même instant, un seul des
      // deux agit (le second voit la réservation déjà résolue).
      if (suspension.shouldResolveAtSlotEnd(kind, resDoc.data())) {
        const resolved = await db.runTransaction(async (tx) => {
          const fresh = await tx.get(resDoc.ref);
          if (!suspension.isStillSuspended(fresh.data())) return false;
          tx.update(
            resDoc.ref,
            suspension.unresolvedSuspensionUpdate(
              admin.firestore.FieldValue,
            ),
          );
          return true;
        });
        console.log(
          resolved ?
            `⏹️ Suspension non résolue → réservation ${reservationId} annulée` :
            `Réservation ${reservationId} déjà résolue`,
        );
        res.status(200).send(resolved ? "Suspension résolue" : "Déjà résolue");
        return;
      }

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
          kind,
          payload: {
            companyId,
            queueId: queueId || "",
            slotId: slotId || "",
            reservationId,
            companyName: companyName || "",
            queueName: queueName || "",
            slotStart: slotStartIso || "",
            slotEnd: slotEndIso || "",
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
exports.cancelReservationTimeline = v2Updated("companies/{companyId}/reservations/{reservationId}", async (change, context) => {
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
async function purgeCompanyReservations(companyId) {
  const oneMonthAgo = new Date();
  oneMonthAgo.setDate(oneMonthAgo.getDate() - 30);

  const oldReservations = await db
    .collection("companies").doc(companyId)
    .collection("reservations")
    .where("slotEnd", "<", oneMonthAgo)
    .get();
  if (oldReservations.empty) return 0;

  let totalDeleted = 0;
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
  return totalDeleted;
}

// ====================================================================
// FONCTION 12 : Résolution des suspensions expirées
// Filet de sécurité : si l'entreprise a bloqué un créneau (flag
// `suspended` sur la réservation) mais n'a jamais débloqué, et que le
// créneau est maintenant passé → on annule la réservation
// (`company_block_unresolved`) pour que le client soit prévenu qu'il peut
// re-réserver (via FONCTION 6bis) et que la réservation ne reste pas
// "suspendue" indéfiniment.
// ====================================================================
async function resolveCompanySuspensions(companyId) {
  const now = new Date();
  // Seules les réservations suspendues sont lues (avant : toutes les
  // réservations confirmées de la structure, puis filtre en mémoire).
  const snap = await db
    .collection("companies").doc(companyId)
    .collection("reservations")
    .where("status", "==", "confirmed")
    .where("suspended", "==", true)
    .get();
  if (snap.empty) return 0;

  const expired = snap.docs.filter((d) => {
    const se = d.data().slotEnd ? d.data().slotEnd.toDate() : null;
    return se && se < now;
  });
  if (expired.length === 0) return 0;

  let total = 0;
  let batch = db.batch();
  let count = 0;
  for (const doc of expired) {
    batch.update(
      doc.ref,
      suspension.unresolvedSuspensionUpdate(admin.firestore.FieldValue),
    );
    count++;
    total++;
    if (count >= 400) {
      await batch.commit();
      batch = db.batch();
      count = 0;
    }
  }
  if (count > 0) await batch.commit();
  return total;
}

// ════════════════════════════════════════════════════════════════════
// NOTIFICATIONS ENTREPRISE
//
// Journal unifié : companies/{companyId}/companyNotifications, écrit
// UNIQUEMENT ici (Admin SDK). L'app le lit (onglet Notifications admin +
// staff, pastille de non-lus). Le push est livré par sendCompanyPush.
// ════════════════════════════════════════════════════════════════════

// Jours et heures des notifications : toujours ceux du fuseau de la
// structure (zone.js — todayBounds, ymdIn, fmtClock, fmtDateFr…).
const NEAR_FULL_PCT = 85;
const UNDERUSED_PCT = 10;

/** "08:00" → "8h" · "08:30" → "8h30" · "24:00" → "minuit". */
function fmtHm(hm) {
  if (!hm) return "";
  if (hm === "24:00") return "minuit";
  const [h, m] = String(hm).split(":").map((x) => parseInt(x, 10));
  if (Number.isNaN(h)) return "";
  return m ? `${h}h${String(m).padStart(2, "0")}` : `${h}h`;
}

/** Libellé "8h–12h" à partir d'un doc timeSlot. */
function rangeLabel(tsData) {
  const a = fmtHm(tsData && tsData.startTime);
  const b = fmtHm(tsData && tsData.endTime);
  return a && b ? `${a}–${b}` : "";
}


function fillPct(reservations, capacity) {
  if (!capacity) return 0;
  return Math.round((reservations / capacity) * 100);
}

/** Écrit une entrée dans le journal. Le push suit via sendCompanyPush.
 * `opts.docId` (facultatif) : identifiant fixe — si l'entrée existe déjà
 * (tâche de nuit relancée après une erreur), rien n'est réécrit, donc pas
 * de doublon ni de second push. */
async function writeCompanyNotification(companyId, opts) {
  const doc = {
    type: opts.type,
    title: opts.title,
    body: opts.body || "",
    audience: opts.audience || "admin",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (opts.staffId) doc.staffId = opts.staffId;
  if (opts.payload) doc.payload = opts.payload;
  const col = db
    .collection("companies")
    .doc(companyId)
    .collection("companyNotifications");
  if (!opts.docId) {
    await col.add(doc);
    return;
  }
  try {
    await col.doc(opts.docId).create(doc);
  } catch (e) {
    if (e.code !== 6) throw e; // 6 = ALREADY_EXISTS : déjà écrite
  }
}


/** Écrit la même notification pour chaque membre d'équipe ACTIF
 * (audience "staff", une entrée par staffId → un push par personne).
 * Retourne les documents staff prévenus. */
async function notifyAllActiveStaff(companyId, opts) {
  const staffSnap = await db
    .collection("companies")
    .doc(companyId)
    .collection("staff")
    .where("isActive", "==", true)
    .get();
  await Promise.all(
    staffSnap.docs.map((s) =>
      writeCompanyNotification(companyId, {
        ...opts,
        audience: "staff",
        staffId: s.id,
        docId: opts.docId ? `${opts.docId}-${s.id}` : undefined,
      }),
    ),
  );
  return staffSnap.docs;
}

/** Notification opérationnelle : l'entrée admin, puis une copie pour chaque
 * membre actif. `staffBody` remplace le corps côté staff quand celui de
 * l'admin parle de réglages que le staff ne peut pas faire. */
async function notifyAdminAndStaff(companyId, opts, staffBody) {
  await writeCompanyNotification(companyId, { ...opts, audience: "admin" });
  await notifyAllActiveStaff(companyId, {
    ...opts,
    body: staffBody !== undefined ? staffBody : opts.body,
  });
}

/** Agrège les créneaux d'une file sur [from, to[, groupés par plage
 * (timeSlotId). Retourne une Map timeSlotId → {reservations, capacity,
 * emptySlots, cancellations, remaining, firstStart, lastEnd}. Si `now` est
 * fourni, `remaining` = réservations des créneaux non encore terminés. */
async function aggregateSlotsByPlage(companyId, queueId, from, to, now) {
  const snap = await db
    .collection("companies")
    .doc(companyId)
    .collection("queues")
    .doc(queueId)
    .collection("slots")
    .where("start", ">=", from)
    .where("start", "<", to)
    .get();

  const byPlage = new Map();
  for (const s of snap.docs) {
    const d = s.data();
    if (!d.start || !d.end) continue;
    const key = d.timeSlotId || "_";
    let g = byPlage.get(key);
    if (!g) {
      g = {
        reservations: 0, capacity: 0, emptySlots: 0, cancellations: 0,
        remaining: 0, firstStart: null, lastEnd: null,
      };
      byPlage.set(key, g);
    }
    const reserved = d.reserved || 0;
    g.reservations += reserved;
    g.capacity += d.capacity || 0;
    g.cancellations += d.cancelled || 0;
    if (reserved === 0) g.emptySlots += 1;
    const st = d.start.toDate();
    const en = d.end.toDate();
    if (!g.firstStart || st < g.firstStart) g.firstStart = st;
    if (!g.lastEnd || en > g.lastEnd) g.lastEnd = en;
    if (now && en > now) g.remaining += reserved;
  }
  return byPlage;
}

// ── Livraison push ──────────────────────────────────────────────────
exports.sendCompanyPush = v2Created("companies/{companyId}/companyNotifications/{notifId}", async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();

    // audience "staff" → le membre concerné · sinon l'admin (uid == companyId)
    const recipientUid =
      data.audience === "staff" ? data.staffId : companyId;
    if (!recipientUid) return null;

    const userDoc = await db.collection("users").doc(recipientUid).get();
    const token = userDoc.exists ? userDoc.data().fcmToken : null;
    if (!token) return null;

    try {
      await admin.messaging().send({
        token,
        notification: {
          title: data.title || "Baxa",
          body: data.body || "",
        },
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
      });
      console.log(`✅ Push entreprise → ${companyId} (${data.type})`);
    } catch (e) {
      console.error(`❌ sendCompanyPush ${companyId}:`, e.message);
    }
    return null;
  });

// ── Fermeture / réouverture / fermeture programmée → staff ──────────
// Se branche sur le résumé companies/{id} maintenu par
// writeCompanySearchSummary. Dédup naturel : une fermeture multi-files
// réécrit companies/{id} N fois, mais seule la 1ʳᵉ fait basculer le champ.
exports.onCompanyStateChange = v2Updated("companies/{companyId}", async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const wasClosed = before.closedNow === true;
    const isClosed = after.closedNow === true;
    const plannedBefore = before.closurePlannedFor
      ? before.closurePlannedFor.toDate().getTime() : null;
    const plannedAfter = after.closurePlannedFor
      ? after.closurePlannedFor.toDate().getTime() : null;

    if (wasClosed === isClosed && plannedBefore === plannedAfter) return null;

    // Pendant un départ de Baxa : la messagerie staff est gérée par
    // onDeletionRequestCreated (« quitte Baxa ») et la ré-invitation au
    // retour — on saute les notifs génériques fermé/rouvert/prévue.
    const dr = await db.collection("deletionRequests").doc(companyId).get();
    if (dr.exists && dr.data().status !== "completed") return null;

    const name = after.nom || "Votre établissement";
    const tz = zone.tzOf(after.timeZone); // dates dans le fuseau de la structure

    if (!wasClosed && isClosed) {
      const reopen = after.reopenAt ? after.reopenAt.toDate() : null;
      await notifyAllActiveStaff(companyId, {
        type: "structure_closed",
        title: "🔒 Réservations fermées",
        body: reopen
          ? `${name} ne prend plus de nouvelles réservations jusqu'au ` +
            `${zone.fmtDateFr(reopen, tz)}. Les clients déjà réservés restent à ` +
            `honorer — ils sont dans votre agenda.`
          : `${name} ne prend plus de nouvelles réservations. Les clients ` +
            `déjà réservés restent à honorer — ils sont dans votre agenda.`,
      });
      return null;
    }

    if (wasClosed && !isClosed) {
      await notifyAllActiveStaff(companyId, {
        type: "structure_reopened",
        title: "✅ Réservations rouvertes",
        body: `${name} accepte de nouveau les réservations. Tout est reparti.`,
      });
      return null;
    }

    if (plannedAfter !== null && plannedAfter !== plannedBefore) {
      const start = after.closurePlannedFor.toDate();
      await notifyAllActiveStaff(companyId, {
        type: "structure_closure_planned",
        title: "📅 Fermeture prévue",
        body:
          `${name} sera fermé aux réservations à partir du ` +
          `${zone.fmtDateFr(start, tz)}. Les clients déjà réservés pour cette période ` +
          `restent à honorer.`,
      });
      return null;
    }

    return null;
  });

// ── Nouveau membre d'équipe → admin ─────────────────────────────────
exports.onStaffJoined = v2Created("companies/{companyId}/staff/{staffUid}", async (snap, context) => {
    const { companyId, staffUid } = context.params;
    const d = snap.data() || {};
    if (d.isActive === false) return null;

    const name =
      d.displayName || d.email || d.phone || "Un nouveau membre";
    await writeCompanyNotification(companyId, {
      type: "staff_joined",
      title: "👋 Nouveau membre dans l'équipe",
      body: `${name} a rejoint votre équipe via le code d'invitation.`,
      audience: "admin",
      payload: { staffUid, staffName: name },
    });
    return null;
  });

// ── Équipe : rejoindre / quitter (fonctions appelables) ─────────────
// Toute l'adhésion à une équipe passe par le serveur : les règles
// Firestore interdisent au client de créer son document staff. C'est ce
// qui garantit qu'on ne devient membre QU'AVEC un code valide, que la
// limite MAX_ACTIVE_STAFF est tenue, et qu'un ancien membre (parti ou
// retiré) peut être réactivé avec un nouveau code.

function normalizeInviteCode(raw) {
  return String(raw || "").trim().toUpperCase();
}

/** Invitation active portant ce code, `{used: true}` si le code existe
 *  mais a déjà servi, ou null s'il n'existe pas. */
async function findInvite(code) {
  const snap = await db
    .collectionGroup("invitations")
    .where("code", "==", code)
    .get();
  if (snap.empty) return null;
  const active = snap.docs.find((d) => d.get("active") === true);
  return active ? {doc: active} : {used: true};
}

function inviteCompanyId(inviteDoc) {
  return inviteDoc.get("companyId") || inviteDoc.ref.parent.parent.id;
}

async function requireActiveInvite(rawCode) {
  const code = normalizeInviteCode(rawCode);
  if (!code) {
    throw new HttpsError("invalid-argument", "Code manquant.");
  }
  const found = await findInvite(code);
  if (!found) throw new HttpsError("not-found", "Code invalide.");
  if (found.used) {
    throw new HttpsError("failed-precondition", "Code déjà utilisé.");
  }
  return found.doc;
}

// Vérification du code AVANT connexion (1re étape de l'écran staff) :
// renvoie seulement le nom de l'entreprise. Les invitations ne sont plus
// lisibles publiquement, cette fonction les remplace.
exports.checkInviteCode = v2Callable(async (data) => {
  const invite = await requireActiveInvite(data && data.code);
  const companyId = inviteCompanyId(invite);
  const activeSnap = await db
    .collection("companies").doc(companyId)
    .collection("staff")
    .where("isActive", "==", true)
    .get();
  if (activeSnap.size >= MAX_ACTIVE_STAFF) {
    throw new HttpsError("resource-exhausted", "Équipe complète.");
  }
  return {companyName: invite.get("companyName") || ""};
});

// Adhésion avec un code : nouveau membre OU ancien membre réactivé.
exports.joinTeamWithCode = v2Callable(async (data, context) => {
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  const uid = context.auth.uid;
  const token = context.auth.token || {};
  const invite = await requireActiveInvite(data && data.code);
  const companyId = inviteCompanyId(invite);
  const companyName = invite.get("companyName") || "";

  if (uid === companyId) {
    throw new HttpsError(
      "failed-precondition", "Ce compte est celui de l'entreprise.",
    );
  }

  const staffCol = db.collection("companies").doc(companyId)
    .collection("staff");
  const staffRef = staffCol.doc(uid);
  const userRef = db.collection("users").doc(uid);
  const ownCompanyRef = db.collection("companies").doc(uid);

  const result = await db.runTransaction(async (tx) => {
    // Toutes les lectures d'abord (contrainte des transactions).
    const [inv, staffDoc, userDoc, ownCompany, activeSnap] =
      await Promise.all([
        tx.get(invite.ref),
        tx.get(staffRef),
        tx.get(userRef),
        tx.get(ownCompanyRef),
        tx.get(staffCol.where("isActive", "==", true)),
      ]);

    if (ownCompany.exists) {
      throw new HttpsError(
        "failed-precondition", "Ce compte est déjà un compte entreprise.",
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const userData = {role: "staff", companyId, companyName, updatedAt: now};

    if (staffDoc.exists && staffDoc.get("isActive") === true) {
      // Déjà membre actif : simple reconnexion, le code reste disponible.
      tx.set(userRef, userData, {merge: true});
      return {status: "already"};
    }

    if (!inv.exists || inv.get("active") !== true) {
      throw new HttpsError("failed-precondition", "Code déjà utilisé.");
    }
    if (activeSnap.size >= MAX_ACTIVE_STAFF) {
      throw new HttpsError("resource-exhausted", "Équipe complète.");
    }

    // Membre d'une AUTRE équipe : on le détache de l'ancienne (un compte
    // staff = une seule équipe).
    const prev = userDoc.exists ? userDoc.data() : {};
    let prevStaffRef = null;
    if (prev.role === "staff" && prev.companyId &&
        prev.companyId !== companyId) {
      prevStaffRef = db
        .collection("companies").doc(prev.companyId)
        .collection("staff").doc(uid);
      const prevStaff = await tx.get(prevStaffRef);
      if (!prevStaff.exists || prevStaff.get("isActive") !== true) {
        prevStaffRef = null;
      }
    }

    const phone = token.phone_number || "";
    const email = token.email || "";

    if (prevStaffRef) {
      tx.update(prevStaffRef, {
        isActive: false, leftAt: now, revokedReason: "left",
      });
    }

    if (staffDoc.exists) {
      // Retour d'un ancien membre : on garde son nom (posé par l'admin)
      // et sa date d'arrivée d'origine.
      const update = {
        isActive: true,
        rejoinedAt: now,
        lastSeenAt: now,
        leftAt: admin.firestore.FieldValue.delete(),
        revokedReason: admin.firestore.FieldValue.delete(),
      };
      if (phone) update.phone = phone;
      if (email) update.email = email;
      tx.update(staffRef, update);
    } else {
      tx.set(staffRef, {
        uid,
        phone,
        email,
        displayName: token.name || "",
        companyId,
        role: "staff",
        isActive: true,
        joinedAt: now,
        lastSeenAt: now,
      });
    }

    tx.update(invite.ref, {active: false, usedBy: uid, usedAt: now});
    tx.set(userRef, userData, {merge: true});

    return {
      status: staffDoc.exists ? "rejoined" : "joined",
      name: (staffDoc.exists && staffDoc.get("displayName")) ||
        token.name || email || phone || "Un membre",
    };
  });

  // Un nouveau document déclenche onStaffJoined ; une réactivation non,
  // d'où la notification envoyée ici.
  if (result.status === "rejoined") {
    // Il repart d'une liste vide : ses anciennes notifs (dont un éventuel
    // « X quitte Baxa ») ne doivent pas réapparaître.
    const old = await db
      .collection("companies").doc(companyId)
      .collection("companyNotifications")
      .where("staffId", "==", uid)
      .get();
    if (!old.empty) {
      const batch = db.batch();
      old.docs.slice(0, 400).forEach((n) => batch.delete(n.ref));
      await batch.commit();
    }


    await writeCompanyNotification(companyId, {
      type: "staff_joined",
      title: "👋 Retour dans l'équipe",
      body: `${result.name} a rejoint à nouveau votre équipe.`,
      audience: "admin",
      payload: {staffUid: uid, staffName: result.name},
    });
  }

  return {companyId, companyName};
});

// Départ volontaire (« Quitter l'équipe »). La simple déconnexion, elle,
// ne touche à rien : le membre reste dans l'équipe.
exports.leaveTeam = v2Callable(async (data, context) => {
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();
  const companyId = userDoc.exists ? userDoc.get("companyId") : null;
  if (!userDoc.exists || userDoc.get("role") !== "staff" || !companyId) {
    return {ok: true};
  }

  const staffRef = db
    .collection("companies").doc(companyId)
    .collection("staff").doc(uid);
  const staffDoc = await staffRef.get();
  const wasActive = staffDoc.exists && staffDoc.get("isActive") === true;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const del = admin.firestore.FieldValue.delete();

  const batch = db.batch();
  if (wasActive) {
    batch.update(staffRef, {isActive: false, leftAt: now, revokedReason: "left"});
  }
  batch.update(userRef, {
    role: del,
    companyId: del,
    companyName: del,
    updatedAt: now,
  });
  await batch.commit();

  if (wasActive) {
    const d = staffDoc.data() || {};
    const name = d.displayName || d.email || d.phone || "Un membre";
    await writeCompanyNotification(companyId, {
      type: "staff_left",
      title: "Départ de l'équipe",
      body: `${name} a quitté votre équipe.`,
      audience: "admin",
      payload: {staffUid: uid, staffName: name},
    });
  }
  return {ok: true};
});

// ── Réservations client (réserver / remplacer / annuler) ────────────
// Fonction 2e génération en africa-south1 : voir booking.js.
exports.booking = require("./booking").booking;

// ── Plage complète / bientôt complète (déclenché à chaque réservation) ─
async function checkPlageFillAfterReservation(companyId, resa) {
  const slotId = resa && resa.slotId;
  const queueId = resa && resa.queueId;
  if (!slotId || !queueId) return;

  const queueRef = db
    .collection("companies").doc(companyId)
    .collection("queues").doc(queueId);

  const slotDoc = await queueRef.collection("slots").doc(slotId).get();
  if (!slotDoc.exists) return;
  const slot = slotDoc.data();
  const timeSlotId = slot.timeSlotId;
  if (!timeSlotId || !slot.start) return;

  const now = new Date();
  // « Aujourd'hui » chez la structure.
  const tz = await companyTimeZone(companyId);
  const { start, end } = zone.todayBounds(now, tz);
  const slotStart = slot.start.toDate();
  if (slotStart < start || slotStart >= end) return; // pas aujourd'hui

  const byPlage = await aggregateSlotsByPlage(companyId, queueId, start, end);
  const g = byPlage.get(timeSlotId);
  if (!g || !g.capacity) return;
  const pct = fillPct(g.reservations, g.capacity);
  if (pct < NEAR_FULL_PCT) return;

  const tsRef = queueRef.collection("timeSlots").doc(timeSlotId);
  const tsDoc = await tsRef.get();
  const tsData = tsDoc.exists ? tsDoc.data() : {};
  const today = zone.ymdIn(now, tz);
  const label = rangeLabel(tsData) ||
    `${zone.fmtClock(g.firstStart, tz)}–${zone.fmtClock(g.lastEnd, tz)}` ||
    "cette plage";

  const queueDoc = await queueRef.get();
  const queueName =
    (queueDoc.exists && queueDoc.data().name) || "votre file";

  if (pct >= 100) {
    if (tsData.fullNotifiedOn === today) return;
    await notifyAdminAndStaff(
      companyId,
      {
        type: "plage_full",
        title: `📈 ${queueName} · plage ${label} complète`,
        body:
          "Toutes les places d'aujourd'hui sont réservées. Allongez la " +
          "plage ou augmentez la capacité d'accueil pour recevoir plus de " +
          "clients, dans les limites de votre capacité de gestion.",
        payload: { queueId, queueName, timeSlotId, range: label },
      },
      "Toutes les places d'aujourd'hui sont réservées sur cette plage.",
    );
    await tsRef.set(
      { fullNotifiedOn: today, nearFullNotifiedOn: today },
      { merge: true },
    );
    return;
  }

  // 85 % ≤ pct < 100 %
  if (tsData.nearFullNotifiedOn === today || tsData.fullNotifiedOn === today) {
    return;
  }
  const free = g.capacity - g.reservations;
  const freeLabel = `Il reste ${free} place${free > 1 ? "s" : ""} aujourd'hui`;
  await notifyAdminAndStaff(
    companyId,
    {
      type: "plage_near_full",
      title: `📈 ${queueName} · plage ${label} bientôt complète`,
      body:
        `${freeLabel}. Pensez à allonger la plage ou augmenter la ` +
        "capacité d'accueil, dans les limites de votre capacité de gestion.",
      payload: { queueId, queueName, timeSlotId, range: label },
    },
    `${freeLabel} sur cette plage.`,
  );
  await tsRef.set({ nearFullNotifiedOn: today }, { merge: true });
}

// ════════════════════════════════════════════════════════════════════
// RÉVEILS : Bilan du jour, coup d'œil, ajouts de l'équipe
//
// Voir functions/wake.js pour le principe. En bref, chaque structure a un
// document `companyWake/{companyId}` :
//   events              : échéances datées [{kind, queueId?, day, at, …}]
//   wakeAt              : Timestamp de la plus proche (null si aucune)
//   plannedDay          : jour (AAAA-MM-JJ) de la dernière planification
//   plannedAt           : instant de cette planification
//   replanRequestedAt   : posé par les déclencheurs (plage / fermeture
//                         modifiée) → replanifier au prochain passage
//   sent                : registre anti-doublon {"recap:<file>": jour, …}
//
// - Le chef horloge (clockDispatch) planifie la journée de chaque
//   structure à 0h DANS SON FUSEAU (tâche `planDay`).
// - Le même chef, toutes les 15 min, ne traite que les structures dont
//   `wakeAt` est passé (une seule requête, ~1 lecture si rien à faire).
// - Filet : `wakeAt` ne dépasse jamais 0h30 locale du lendemain
//   (capAtLocalRollover) — une planification manquée est rattrapée.
// - Jours et heures sont ceux du fuseau de la structure (zone.js). Le jour
//   d'une échéance (et non l'heure du passage) fixe les bornes lues : un
//   récap de minuit porte bien sur la veille.
// ════════════════════════════════════════════════════════════════════

function wakeRef(companyId) {
  return db.collection("companyWake").doc(companyId);
}

function tsOrNull(msValue) {
  return msValue == null
    ? null
    : admin.firestore.Timestamp.fromMillis(msValue);
}

/** Réveil au plus tard 30 min après le minuit local suivant : même sans
 * échéance, chaque structure se replanifie chaque jour (processCompanyWake
 * voit alors `plannedDay` ≠ aujourd'hui), quel que soit son fuseau. */
function capAtLocalRollover(wakeMs, today, tz) {
  const rollover = zone.dayBounds(zone.addDays(today, 1), tz).start.getTime() +
    30 * 60 * 1000;
  return wakeMs == null ? rollover : Math.min(wakeMs, rollover);
}

/**
 * Calcule les échéances du jour `day` pour toutes les files ouvertes de la
 * structure (lecture des créneaux de ce jour, une fois par file).
 */
async function computeDayEvents(companyId, day, now, sent, tz) {
  const { start, end } = zone.dayBounds(day, tz);
  const queuesSnap = await db
    .collection("companies").doc(companyId)
    .collection("queues").get();

  const queueEvents = [];
  for (const queueDoc of queuesSnap.docs) {
    const qd = queueDoc.data();
    if (isQueueClosedNow(qd.closureStart, qd.closureEnd, now)) continue;
    const plages = await aggregateSlotsByPlage(
      companyId, queueDoc.id, start, end,
    );
    queueEvents.push(...wake.planQueueEvents({
      queueId: queueDoc.id, day, plages, now, sent,
    }));
  }
  const team = wake.planTeamEvent({ day, queueEvents, sent });
  return team ? [...queueEvents, team] : queueEvents;
}

/** (Re)planifie le jour en cours d'une structure et écrit son réveil. */
async function planCompanyWake(companyId, now) {
  const ref = wakeRef(companyId);
  const snap = await ref.get();
  const prev = snap.exists ? snap.data() : {};
  const tz = await companyTimeZone(companyId);
  const today = zone.ymdIn(now, tz);
  const sent = wake.pruneSent(prev.sent, zone.addDays(today, -2));
  const fresh = await computeDayEvents(companyId, today, now, sent, tz);
  const events = wake.mergeDayEvents(prev.events, today, fresh);
  await ref.set({
    events,
    wakeAt: tsOrNull(capAtLocalRollover(wake.nextWakeAt(events), today, tz)),
    plannedDay: today,
    plannedAt: admin.firestore.Timestamp.fromDate(now),
    sent,
  }, { merge: true });
}

/** Demande une replanification (plage ou fermeture modifiée) : le
 * prochain passage, au plus tôt dans 2 min, relira les créneaux du jour. */
async function requestCompanyReplan(companyId) {
  const at = Date.now() + wake.REPLAN_DEBOUNCE_MS;
  const ref = wakeRef(companyId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const cur = snap.exists && snap.get("wakeAt")
      ? snap.get("wakeAt").toMillis()
      : null;
    tx.set(ref, {
      replanRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      wakeAt: tsOrNull(cur == null ? at : Math.min(cur, at)),
    }, { merge: true });
  });
}

// Champs écrits sur les plages par les notifs serveur (pas des horaires).
const TIMESLOT_NOTIF_MARKERS = [
  "fullNotifiedOn", "nearFullNotifiedOn", "underusedNotifiedAt",
];
// Champs d'une file qui changent ses horaires du jour : création /
// suppression, fermeture posée, levée ou « Rouvrir immédiatement ».
const QUEUE_SCHEDULE_FIELDS = ["closureStart", "closureEnd", "isActive"];

/** Vrai si le doc est créé / supprimé, ou si un champ autre que
 * `ignored` a changé. */
function scheduleFieldsChanged(change, ignored) {
  if (!change.before.exists || !change.after.exists) return true;
  const a = { ...change.before.data() };
  const b = { ...change.after.data() };
  for (const k of ignored) {
    delete a[k];
    delete b[k];
  }
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) {
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) return true;
  }
  return false;
}

/** Vrai si la file est créée / supprimée ou si sa fermeture change. */
function queueScheduleChanged(change) {
  if (!change.before.exists || !change.after.exists) return true;
  const a = change.before.data();
  const b = change.after.data();
  return QUEUE_SCHEDULE_FIELDS.some(
    (k) => JSON.stringify(a[k]) !== JSON.stringify(b[k]),
  );
}

// ── Contenu des notifications ───────────────────────────────────────

/** Corps et payload du « 📊 Bilan du jour » (logique inchangée). */
async function buildRecapNotification(queueRef, plages, queueName, word, tz) {
  const tsSnap = await queueRef.collection("timeSlots").get();
  const tsMap = new Map(tsSnap.docs.map((t) => [t.id, t.data()]));
  const entries = [...plages.entries()].sort(
    (a, b) =>
      (a[1].firstStart ? a[1].firstStart.getTime() : 0) -
      (b[1].firstStart ? b[1].firstStart.getTime() : 0),
  );
  // Seules les plages qui ont eu ≥ 1 réservation sont détaillées ;
  // les autres sont résumées en « + N plages sans réservation ».
  const activePlages = [];
  let silentPlages = 0;
  let totalRes = 0;
  let totalCap = 0;
  let totalCancel = 0;
  let totalEmpty = 0;
  for (const [tsId, g] of entries) {
    const label = rangeLabel(tsMap.get(tsId)) ||
      `${zone.fmtClock(g.firstStart, tz)}–${zone.fmtClock(g.lastEnd, tz)}`;
    totalRes += g.reservations;
    totalCap += g.capacity;
    totalCancel += g.cancellations;
    totalEmpty += g.emptySlots;
    if (g.reservations > 0) {
      activePlages.push({
        range: label,
        reservations: g.reservations,
        fillPct: fillPct(g.reservations, g.capacity),
        emptySlots: g.emptySlots,
      });
    } else {
      silentPlages += 1;
    }
  }

  // Taux de remplissage de la file = places réservées / places proposées
  // sur toute la journée (pondéré par la capacité, pas la moyenne des %
  // de plages : une petite plage vide ne doit pas écraser le chiffre).
  const queueFill = fillPct(totalRes, totalCap);
  const verdict = queueFill >= 90
    ? "record"
    : queueFill >= 60 ? "bonne" : "calme";

  let body;
  if (totalRes === 0) {
    body =
      `Aucune réservation ${word}. Partagez votre QR code pour ` +
      "attirer vos premiers clients 📣";
  } else {
    const parts = [`${totalRes} réservation${totalRes > 1 ? "s" : ""}`];
    if (totalCancel > 0) {
      parts.push(`${totalCancel} annulation${totalCancel > 1 ? "s" : ""}`);
    }
    parts.push(`${queueFill} % rempli`);
    body = parts.join(" · ");
  }

  return {
    title: `📊 Bilan du jour · ${queueName}`,
    body,
    payload: {
      reservations: totalRes,
      cancellations: totalCancel,
      fillPct: queueFill,
      emptySlots: totalEmpty,
      verdict,
      plages: activePlages,
      silentPlages,
    },
  };
}

// ── Traitement d'une échéance ───────────────────────────────────────
// Chaque handler renvoie {sent: bool} si l'échéance est consommée, ou
// {retryAt: ms} pour la repousser (ex. plage allongée entre-temps).

async function handleRecapEvent(companyId, ev, now, today, tz) {
  const queueRef = db
    .collection("companies").doc(companyId)
    .collection("queues").doc(ev.queueId);
  const queueDoc = await queueRef.get();
  if (!queueDoc.exists) return { sent: false };
  const qd = queueDoc.data();
  if (isQueueClosedNow(qd.closureStart, qd.closureEnd, now)) {
    return { sent: false };
  }

  const { start, end } = zone.dayBounds(ev.day, tz);
  const plages = await aggregateSlotsByPlage(
    companyId, ev.queueId, start, end, now,
  );
  if (plages.size === 0) return { sent: false };

  // Filet de sécurité : un créneau finit encore plus tard (plage allongée
  // dans la journée) → on attend sa fin au lieu d'envoyer trop tôt.
  let dayLast = 0;
  for (const g of plages.values()) {
    if (g.lastEnd && g.lastEnd.getTime() > dayLast) dayLast = g.lastEnd.getTime();
  }
  if (dayLast > now.getTime()) return { retryAt: dayLast };

  const queueName = qd.name || "votre file";
  const recap = await buildRecapNotification(
    queueRef, plages, queueName, wake.dayWord(ev.day, today), tz,
  );
  await writeCompanyNotification(companyId, {
    type: "plage_recap",
    title: recap.title,
    body: recap.body,
    audience: "admin",
    payload: {
      queueId: ev.queueId, queueName, day: ev.day, ...recap.payload,
    },
  });
  return { sent: true, recapEnd: dayLast };
}

async function handleCheckinEvent(companyId, ev, now, tz) {
  // Hors de la plage, ou trop tard après son milieu : périmé.
  if (now.getTime() > ev.until) return { sent: false };
  if (now.getTime() - ev.at > wake.CHECKIN_MAX_DELAY_MS) return { sent: false };

  const companyRef = db.collection("companies").doc(companyId);
  const queueRef = companyRef.collection("queues").doc(ev.queueId);
  const queueDoc = await queueRef.get();
  if (!queueDoc.exists) return { sent: false };
  const qd = queueDoc.data();
  if (isQueueClosedNow(qd.closureStart, qd.closureEnd, now)) {
    return { sent: false };
  }

  const { start, end } = zone.dayBounds(ev.day, tz);
  const plages = await aggregateSlotsByPlage(
    companyId, ev.queueId, start, end, now,
  );
  let remainingTotal = 0;
  for (const g of plages.values()) remainingTotal += g.remaining;
  if (remainingTotal < 3) return { sent: false };

  // Aucune autre notif admin envoyée depuis le début de cette plage ? (les
  // copies staff partent avec leur entrée admin : pas besoin de les compter)
  const since = await companyRef
    .collection("companyNotifications")
    .where("audience", "==", "admin")
    .where("createdAt", ">=", admin.firestore.Timestamp.fromMillis(ev.from))
    .limit(1)
    .get();
  if (!since.empty) return { sent: false };

  const queueName = qd.name || "votre file";
  const per = remainingTotal > 1
    ? "personnes encore à servir"
    : "personne encore à servir";
  await notifyAdminAndStaff(companyId, {
    type: "queue_checkin",
    title: `👀 Un coup d'œil sur ${queueName} ?`,
    body: `Votre file tourne — ${remainingTotal} ${per} aujourd'hui.`,
    payload: { queueId: ev.queueId, queueName, toServe: remainingTotal },
  });
  return { sent: true };
}

async function handleTeamEvent(companyId, ev, today, tz) {
  // Inscriptions manuelles du staff faites ce jour-là (date de l'ajout),
  // encore actives — mêmes critères que wake.isStaffManualAdd. Requête de
  // comptage : 1 lecture quel que soit le nombre d'ajouts (index composite
  // source + createdByRole + status + createdAt, firestore.indexes.json).
  const { start, end } = zone.dayBounds(ev.day, tz);
  const agg = await db
    .collection("companies").doc(companyId)
    .collection("reservations")
    .where("source", "==", "company_manual")
    .where("createdByRole", "==", "staff")
    .where("status", "==", "confirmed")
    .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(start))
    .where("createdAt", "<", admin.firestore.Timestamp.fromDate(end))
    .count()
    .get();
  const count = agg.data().count;
  if (count === 0) return { sent: false };

  await writeCompanyNotification(companyId, {
    type: "team_adds",
    title: "👥 Ajouts de votre équipe",
    body: wake.teamAddsBody(count, wake.dayWord(ev.day, today)),
    audience: "admin",
    payload: { day: ev.day, count },
  });
  return { sent: true };
}

/** Traite les échéances arrivées à terme d'une structure. */
async function processCompanyWake(companyId, now) {
  const ref = wakeRef(companyId);
  const tz = await companyTimeZone(companyId);
  const today = zone.ymdIn(now, tz); // jour local de la structure
  let data = (await ref.get()).data() || {};

  // Replanification demandée (ou planification de nuit manquée). Une
  // demande toute fraîche attend son délai : l'app est peut-être encore en
  // train de régénérer les créneaux du jour.
  const requested = data.replanRequestedAt && data.replanRequestedAt.toMillis();
  const planned = data.plannedAt && data.plannedAt.toMillis();
  const replanReady = !!requested && (!planned || requested > planned) &&
    now.getTime() >= requested + wake.REPLAN_DEBOUNCE_MS;
  if (data.plannedDay !== today || replanReady) {
    await planCompanyWake(companyId, now);
    data = (await ref.get()).data() || {};
  }

  const sent = { ...(data.sent || {}) };
  const { due, later } = wake.splitDue(data.events, now);
  const keep = [...later];

  for (const ev of due) {
    const kind = ev.kind;
    if (wake.alreadySent(sent, kind, ev.queueId, ev.day)) continue;
    try {
      let res;
      if (kind === "recap") {
        res = await handleRecapEvent(companyId, ev, now, today, tz);
      } else if (kind === "checkin") {
        res = await handleCheckinEvent(companyId, ev, now, tz);
      } else if (kind === "team") {
        // La dernière file a été allongée : le récap équipe suit.
        const pendingRecap = keep
          .filter((e) => e.kind === "recap" && e.day === ev.day)
          .reduce((mx, e) => Math.max(mx, e.at), 0);
        res = pendingRecap > ev.at
          ? { retryAt: pendingRecap }
          : await handleTeamEvent(companyId, ev, today, tz);
      } else {
        continue;
      }

      if (res.retryAt) {
        keep.push({ ...ev, at: res.retryAt });
        if (kind === "recap") {
          // Le récap équipe du même jour ne doit pas partir avant.
          for (const e of keep) {
            if (e.kind === "team" && e.day === ev.day && e.at < res.retryAt) {
              e.at = res.retryAt;
            }
          }
        }
        continue;
      }
      if (res.sent) sent[wake.sentKey(kind, ev.queueId)] = ev.day;
      if (res.sent && kind === "checkin") {
        // Un seul coup d'œil par file et par jour.
        for (let i = keep.length - 1; i >= 0; i--) {
          const e = keep[i];
          if (e.kind === "checkin" && e.queueId === ev.queueId && e.day === ev.day) {
            keep.splice(i, 1);
          }
        }
      }
    } catch (e) {
      // Échéance en erreur : on la garde pour le prochain passage plutôt
      // que de perdre la notif.
      console.error(`❌ Réveil ${kind} ${companyId}/${ev.queueId || "-"}:`, e.message);
      keep.push(ev);
    }
  }

  keep.sort((a, b) => a.at - b.at);
  // Écriture finale en transaction : si un déclencheur a demandé une
  // replanification pendant le traitement, on garde un réveil immédiat.
  await db.runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    const req = cur.get("replanRequestedAt");
    const plannedNow = cur.get("plannedAt");
    let wakeMs = capAtLocalRollover(wake.nextWakeAt(keep), today, tz);
    if (req && (!plannedNow || req.toMillis() > plannedNow.toMillis())) {
      const soon = Math.max(
        req.toMillis() + wake.REPLAN_DEBOUNCE_MS, now.getTime(),
      );
      wakeMs = wakeMs == null ? soon : Math.min(wakeMs, soon);
    }
    tx.set(ref, { events: keep, wakeAt: tsOrNull(wakeMs), sent }, { merge: true });
  });
}

// ════════════════════════════════════════════════════════════════════
// TÂCHES PLANIFIÉES : UN CHEF, UN OUVRIER PAR STRUCTURE
//
// Avant, chaque tâche planifiée passait sur toutes les structures l'une
// après l'autre dans une seule exécution (limite de temps → structures
// de fin de liste jamais traitées quand il y en a beaucoup).
//
// Maintenant, un « chef horloge » (clockDispatch, toutes les 15 min, en
// Europe : Cloud Scheduler et Cloud Tasks n'existent pas à Johannesburg)
// dépose une tâche par structure dans la file Cloud Tasks `company-jobs`,
// à l'heure LOCALE de chaque structure (0h, 2h, 7h, lundi 6h). Chaque tâche appelle
// l'ouvrier `companyJob` (Johannesburg, à côté de la base), qui traite
// UNE structure avec son propre chrono. Une tâche en erreur est
// réessayée (3 tentatives) : tout ce que fait l'ouvrier peut être rejoué
// sans doublon (vérifications existantes + notifications à identifiant
// fixe, voir writeCompanyNotification).
// ════════════════════════════════════════════════════════════════════
const COMPANY_JOBS_QUEUE = "company-jobs";
const COMPANY_JOB_URL =
  `https://${DB_REGION}-${PROJECT_ID}.cloudfunctions.net/companyJob`;

/** Travail fait par l'ouvrier, par type de tâche. */
const COMPANY_JOBS = {
  // Maintenance de nuit (ex-tâches de 2h00 à 2h30, dans le même ordre) :
  // suspensions expirées → journal de notifs → vieilles réservations →
  // créneaux. Une étape en erreur n'empêche pas les suivantes ; la tâche
  // est ensuite réessayée en entier.
  nightly: async (companyId) => {
    const steps = [
      ["suspensions", resolveCompanySuspensions],
      ["notifications", cleanCompanyNotifications],
      ["réservations", purgeCompanyReservations],
      ["créneaux", generateSlotsForCompany],
    ];
    const failed = [];
    for (const [label, step] of steps) {
      try {
        await step(companyId);
      } catch (e) {
        console.error(`❌ Nuit ${companyId} / ${label}:`, e.message);
        failed.push(label);
      }
    }
    if (failed.length) throw new Error(`étapes en erreur : ${failed.join(", ")}`);
  },
  dayDigest: (companyId) => dayDigestForCompany(companyId),
  weeklyReview: (companyId) => weeklyReviewForCompany(companyId),
  planDay: (companyId) => planCompanyWake(companyId, new Date()),
  wake: (companyId) => processCompanyWake(companyId, new Date()),
};

// File créée au premier passage si elle n'existe pas encore (une fois par
// instance) : rien à configurer à la main dans la console.
let companyJobsQueueReady = null;
function ensureCompanyJobsQueue() {
  if (!companyJobsQueueReady) {
    const name = tasksClient.queuePath(
      PROJECT_ID, SCHEDULER_REGION, COMPANY_JOBS_QUEUE,
    );
    companyJobsQueueReady = tasksClient.getQueue({ name })
      .catch(async (e) => {
        if (e.code !== 5) throw e; // 5 = NOT_FOUND
        try {
          await tasksClient.createQueue({
            parent: tasksClient.locationPath(PROJECT_ID, SCHEDULER_REGION),
            queue: {
              name,
              // Pas plus de 20 structures traitées en même temps : la base
              // n'est pas inondée au moment des passages.
              rateLimits: { maxConcurrentDispatches: 20, maxDispatchesPerSecond: 20 },
              retryConfig: { maxAttempts: 3, minBackoff: { seconds: 60 } },
            },
          });
          console.log(`🆕 File Cloud Tasks ${COMPANY_JOBS_QUEUE} créée`);
        } catch (err) {
          if (err.code !== 6) throw err; // 6 = ALREADY_EXISTS
        }
      })
      .catch((e) => {
        companyJobsQueueReady = null;
        throw e;
      });
  }
  return companyJobsQueueReady;
}

/** Nom de tâche : préfixe haché (Cloud Tasks déconseille les noms
 * séquentiels) + type + passage + structure. Un même nom ne peut être créé
 * qu'une fois : un chef relancé ne double pas le travail. */
function companyJobTaskName(job, runKey, companyId) {
  const safe = (s) => String(s).replace(/[^A-Za-z0-9_-]/g, "_");
  const prefix = searchDir.hash32(companyId).toString(16);
  return `${prefix}-${job}-${safe(runKey)}-${safe(companyId)}`;
}

/** Le chef : une tâche par structure dans la file. */
async function dispatchCompanyJobs(job, companyIds, runKey) {
  await ensureCompanyJobsQueue();
  const parent = tasksClient.queuePath(
    PROJECT_ID, SCHEDULER_REGION, COMPANY_JOBS_QUEUE,
  );
  const secret = process.env.TASK_AUTH_SECRET;
  let created = 0;
  let failed = 0;
  const CHUNK = 50;
  for (let i = 0; i < companyIds.length; i += CHUNK) {
    await Promise.all(companyIds.slice(i, i + CHUNK).map(async (companyId) => {
      try {
        await tasksClient.createTask({
          parent,
          task: {
            name: `${parent}/tasks/${companyJobTaskName(job, runKey, companyId)}`,
            httpRequest: {
              httpMethod: "POST",
              url: COMPANY_JOB_URL,
              headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${secret}`,
              },
              body: Buffer.from(JSON.stringify({ job, companyId }))
                .toString("base64"),
            },
          },
        });
        created++;
      } catch (e) {
        if (e.code === 6) return; // déjà déposée pour ce passage
        failed++;
        console.error(`❌ Tâche ${job} ${companyId}:`, e.message);
      }
    }));
  }
  console.log(
    `📨 ${job} (${runKey}) : ${created} tâche(s) déposée(s)` +
    (failed ? `, ${failed} en erreur` : ""),
  );
  if (failed) throw new Error(`${failed} tâche(s) ${job} non déposée(s)`);
}

// Réglages communs des fonctions planifiées (2e génération).
const DISPATCH_OPTS = {
  region: SCHEDULER_REGION,
  secrets: ["TASK_AUTH_SECRET"],
  timeoutSeconds: 300,
};

// ── Fuseaux utilisés par les structures ─────────────────────────────
// Liste tenue à jour par syncSearchDirectory (nouvelle structure ou
// fuseau modifié) et recalculée chaque nuit par rebuildSearchDirectory :
// le chef horloge sait ainsi quels fuseaux interroger sans relire toutes
// les fiches à chaque passage.
const timeZonesRef = () => db.collection("platformMeta").doc("timeZones");

async function timeZonesInUse() {
  const snap = await timeZonesRef().get();
  const zones = snap.exists ? snap.get("zones") : null;
  return Array.isArray(zones) && zones.length ? zones : [zone.DEFAULT_TZ];
}

/** Identifiants des structures d'un fuseau (sans lire leur contenu). */
async function companyIdsInZone(tz) {
  const snap = await db.collection("companies")
    .where("timeZone", "==", tz)
    .select()
    .get();
  return snap.docs.map((d) => d.id);
}

// Rendez-vous à l'HEURE LOCALE de chaque structure.
const LOCAL_JOBS = [
  { job: "planDay", hour: 0 }, // planification des réveils du jour
  { job: "nightly", hour: 2 }, // maintenance de nuit
  { job: "weeklyReview", hour: 6, weekday: 1 }, // bilan hebdo du lundi
  { job: "dayDigest", hour: 7 }, // résumé du matin
];

// ── Le chef horloge (toutes les 15 min) ─────────────────────────────
// 1. Réveils arrivés à terme (instants absolus : bilan du jour, coup
//    d'œil, ajouts de l'équipe) — une seule requête sur companyWake.
// 2. Pour chaque fuseau utilisé où il est 0h, 2h, 7h (ou lundi 6h) en ce
//    moment : une tâche par structure de ce fuseau. Le nom de la tâche
//    porte le jour LOCAL : un passage relancé ne double rien.
exports.clockDispatch = onSchedule(
  { ...DISPATCH_OPTS, schedule: "*/15 * * * *", timeZone: "UTC" },
  async () => {
    const now = new Date();
    const errors = [];

    const dueSnap = await db.collection("companyWake")
      .where("wakeAt", "<=", admin.firestore.Timestamp.fromDate(now))
      .select()
      .get();
    if (!dueSnap.empty) {
      const tickKey = now.toISOString().slice(0, 16).replace(/[-:T]/g, "");
      try {
        await dispatchCompanyJobs("wake", dueSnap.docs.map((d) => d.id), tickKey);
      } catch (e) {
        errors.push(e.message);
      }
    }

    for (const tz of await timeZonesInUse()) {
      const jobs = LOCAL_JOBS.filter(
        (j) => zone.isLocalSlot(now, tz, j.hour, j.weekday),
      );
      if (jobs.length === 0) continue;
      const ids = await companyIdsInZone(tz);
      if (ids.length === 0) continue;
      const localDay = zone.ymdIn(now, tz);
      for (const { job } of jobs) {
        try {
          await dispatchCompanyJobs(job, ids, localDay);
        } catch (e) {
          errors.push(e.message);
        }
      }
    }

    if (errors.length) throw new Error(errors.join(" · "));
  });

// ── L'ouvrier : traite UNE structure (appelé par Cloud Tasks) ───────
// Réponse 200 = terminé ; 500 = Cloud Tasks réessaiera plus tard.
exports.companyJob = onRequest(
  {
    region: DB_REGION,
    secrets: ["TASK_AUTH_SECRET"],
    timeoutSeconds: 540,
    memory: "512MiB",
    concurrency: 10,
    // File company-jobs : 20 tâches en parallèle max → 2 instances suffisent.
    maxInstances: 4,
  },
  async (req, res) => {
    if (req.get("Authorization") !== `Bearer ${process.env.TASK_AUTH_SECRET}`) {
      res.status(401).send("Unauthorized");
      return;
    }
    const { job, companyId } = req.body || {};
    const handler = COMPANY_JOBS[job];
    if (!handler || !companyId) {
      // Tâche invalide : inutile de la réessayer.
      console.error(`❌ companyJob : tâche invalide (${job}, ${companyId})`);
      res.status(200).send("Ignorée");
      return;
    }
    try {
      await handler(companyId);
      res.status(200).send("OK");
    } catch (e) {
      console.error(`❌ companyJob ${job} ${companyId}:`, e.message);
      res.status(500).send("Erreur");
    }
  });

// ── Plage créée / modifiée / supprimée → replanifier la journée ─────
exports.onTimeSlotScheduleChange = v2Written("companies/{companyId}/queues/{queueId}/timeSlots/{timeSlotId}", async (change, context) => {
    // Les marqueurs écrits par les notifs de remplissage / bilan hebdo ne
    // changent pas les horaires : on les ignore (sinon chaque notif
    // « plage complète » relancerait une replanification).
    if (!scheduleFieldsChanged(change, TIMESLOT_NOTIF_MARKERS)) return null;
    try {
      await requestCompanyReplan(context.params.companyId);
    } catch (e) {
      console.error(`❌ requestCompanyReplan ${context.params.companyId}:`, e.message);
    }
    return null;
  });

// ── Résumé du matin (7h locale) — seulement si remplissage ≥ 40 % ───
// Pour UNE structure (lancé par le chef horloge, localClockDispatch).
async function dayDigestForCompany(companyId) {
  const now = new Date();
  const tz = await companyTimeZone(companyId);
  const { start, end } = zone.todayBounds(now, tz);
  const day = zone.ymdIn(now, tz);

  const companyRef = db.collection("companies").doc(companyId);
  const queuesSnap = await companyRef.collection("queues").get();

  for (const queueDoc of queuesSnap.docs) {
    const queueId = queueDoc.id;
    const qd = queueDoc.data();
    if (isQueueClosedNow(qd.closureStart, qd.closureEnd, now)) continue;
    const queueName = qd.name || "votre file";

    const byPlage = await aggregateSlotsByPlage(
      companyId, queueId, start, end,
    );
    if (byPlage.size === 0) continue;

    let totalRes = 0;
    let totalCap = 0;
    let peak = null;
    let peakId = null;
    for (const [tsId, g] of byPlage.entries()) {
      totalRes += g.reservations;
      totalCap += g.capacity;
      if (!peak || g.reservations > peak.reservations) {
        peak = g;
        peakId = tsId;
      }
    }
    if (!totalCap || fillPct(totalRes, totalCap) < 40) continue;

    const tsSnap = await queueDoc.ref.collection("timeSlots").get();
    const tsMap = new Map(tsSnap.docs.map((t) => [t.id, t.data()]));
    const peakLabel = rangeLabel(tsMap.get(peakId)) ||
      `${zone.fmtClock(peak.firstStart, tz)}–${zone.fmtClock(peak.lastEnd, tz)}`;
    const nPlages = byPlage.size;

    await notifyAdminAndStaff(companyId, {
      type: "day_digest",
      title: `☀️ Votre journée · ${queueName}`,
      body:
        `${totalRes} réservations aujourd'hui` +
        (nPlages > 1 ? `, réparties sur ${nPlages} plages` : "") +
        `. Pointe : ${peakLabel} (${peak.reservations}).`,
      payload: { queueId, queueName },
      docId: `day_digest-${queueId}-${day}`,
    });
  }
}

// ── Bilan hebdo (lundi 6h locale) — plages sous-utilisées sur 14 jours
// Pour UNE structure (lancé par le chef horloge, localClockDispatch).
async function weeklyReviewForCompany(companyId) {
  const now = new Date();
  const tz = await companyTimeZone(companyId);
  const day = zone.ymdIn(now, tz);
  const todayStart = zone.dayBounds(day, tz).start;
  const from = zone.dayBounds(zone.addDays(day, -14), tz).start;
  const cooldownBefore = new Date(now.getTime() - 13 * 24 * 3600 * 1000);

  const companyRef = db.collection("companies").doc(companyId);
  const queuesSnap = await companyRef.collection("queues").get();

  for (const queueDoc of queuesSnap.docs) {
    const queueId = queueDoc.id;
    const queueName = queueDoc.data().name || "votre file";

    const byPlage = await aggregateSlotsByPlage(
      companyId, queueId, from, todayStart,
    );
    if (byPlage.size === 0) continue;

    const tsSnap = await queueDoc.ref.collection("timeSlots").get();
    for (const tsDoc of tsSnap.docs) {
      const tsData = tsDoc.data();
      if (tsData.deleteAfter) continue;
      if (
        tsData.underusedNotifiedAt &&
        tsData.underusedNotifiedAt.toDate() > cooldownBefore
      ) {
        continue;
      }

      const g = byPlage.get(tsDoc.id);
      if (!g || !g.capacity) continue;
      // Plage trop jeune : pas de créneau près du début de la fenêtre.
      if (
        !g.firstStart ||
        g.firstStart.getTime() > from.getTime() + 36 * 3600 * 1000
      ) {
        continue;
      }
      if (fillPct(g.reservations, g.capacity) >= UNDERUSED_PCT) continue;

      const label = rangeLabel(tsData) || "une plage";
      await writeCompanyNotification(companyId, {
        type: "plage_underused",
        title: `📉 ${queueName} · plage ${label} peu réservée`,
        body:
          "Moins de 10 % des places ont été réservées ces 2 dernières " +
          "semaines. Vous pouvez la raccourcir, la décaler à un meilleur " +
          "horaire, ou réduire la capacité.",
        audience: "admin",
        payload: { queueId, queueName, timeSlotId: tsDoc.id, range: label },
        docId: `plage_underused-${tsDoc.id}-${day}`,
      });
      await tsDoc.ref.set(
        { underusedNotifiedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// ANNUAIRE DE RECHERCHE PAR PAYS (logique pure : search_directory.js)
// ════════════════════════════════════════════════════════════════════
const SEARCH_DIR_COLLECTION = "searchDirectory";
const searchDirMetaRef = () =>
  db.collection("searchDirectoryMeta").doc("shards");

/** Document d'annuaire qui porte une structure dans un pays. */
async function searchDirShardRef(country, companyId) {
  const meta = await searchDirMetaRef().get();
  const count = (meta.exists && meta.get(country)) || 1;
  const shard = searchDir.shardIndex(companyId, count);
  return {
    ref: db.collection(SEARCH_DIR_COLLECTION)
      .doc(searchDir.shardDocId(country, shard)),
    shard,
  };
}

// ── Fiche structure écrite → ligne d'annuaire à jour ────────────────
// N'écrit que si un champ affiché dans la recherche a changé. Écriture
// « fusion » : la popularité (calculée la nuit) n'est pas écrasée, et
// un champ disparu de la fiche est retiré de la ligne.
// Tient aussi à jour la liste des fuseaux utilisés (chef horloge).
exports.syncSearchDirectory = onDocumentWritten(
  { document: "companies/{companyId}", region: DB_REGION },
  async (event) => {
    const companyId = event.params.companyId;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    for (const op of searchDir.syncOps(before, after)) {
      const { ref, shard } = await searchDirShardRef(op.country, companyId);
      if (op.op === "remove") {
        try {
          await ref.update(
            new admin.firestore.FieldPath("entries", companyId),
            admin.firestore.FieldValue.delete(),
          );
        } catch (e) {
          if (e.code !== 5) throw e; // 5 = NOT_FOUND : rien à retirer
        }
        continue;
      }
      const entry = {};
      for (const [k, v] of Object.entries(op.entry)) {
        entry[k] = v === null ? admin.firestore.FieldValue.delete() : v;
      }
      await ref.set(
        { country: op.country, shard, entries: { [companyId]: entry } },
        { merge: true },
      );
    }

    // Nouvelle structure ou fuseau modifié : le chef horloge doit connaître
    // ce fuseau pour la réveiller à son heure locale.
    if (after && (!before || before.timeZone !== after.timeZone)) {
      await timeZonesRef().set(
        { zones: admin.firestore.FieldValue.arrayUnion(zone.tzOf(after.timeZone)) },
        { merge: true },
      );
    }
    return null;
  });

// ── Reconstruction de nuit (popularité + filet de sécurité) ─────────
// Relit toutes les fiches, compte les réservations confirmées de chaque
// structure (la purge ne garde que ~30 jours → popularité récente), puis
// réécrit l'annuaire complet et supprime les documents devenus inutiles.
// Sert aussi au premier remplissage : « Forcer l'exécution » dans Cloud
// Scheduler (console Google Cloud).
exports.rebuildSearchDirectory = onSchedule(
  {
    schedule: "45 3 * * *",
    timeZone: "Africa/Dakar",
    region: SCHEDULER_REGION,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const companiesSnap = await db.collection("companies").get();
    const companies = companiesSnap.docs.map((d) => ({
      id: d.id, data: d.data(), popularity: 0,
    }));

    // Comptages en parallèle, par paquets (1 lecture par tranche de
    // 1 000 réservations comptées).
    const listed = companies.filter((c) => searchDir.isListed(c.data));
    const CHUNK = 50;
    for (let i = 0; i < listed.length; i += CHUNK) {
      await Promise.all(listed.slice(i, i + CHUNK).map(async (c) => {
        try {
          const agg = await db.collection("companies").doc(c.id)
            .collection("reservations")
            .where("status", "==", "confirmed")
            .count().get();
          c.popularity = agg.data().count;
        } catch (e) {
          console.error(`❌ popularité ${c.id}:`, e.message);
        }
      }));
    }

    const { docs, shardCounts } = searchDir.planDirectory(companies);
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Méta d'abord : une mise à jour en direct pendant la reconstruction
    // vise déjà la bonne répartition.
    await searchDirMetaRef().set(shardCounts);
    for (const [docId, d] of docs) {
      await db.collection(SEARCH_DIR_COLLECTION).doc(docId)
        .set({ ...d, updatedAt: now });
    }

    const existing = await db.collection(SEARCH_DIR_COLLECTION)
      .select().get();
    for (const doc of existing.docs) {
      if (!docs.has(doc.id)) await doc.ref.delete();
    }

    // Fuseaux : une fiche sans `timeZone` valide (créée avant son ajout)
    // reçoit le fuseau par défaut — le chef horloge interroge les
    // structures par fuseau — puis la liste des fuseaux est recalculée.
    const zones = new Set();
    let batch = db.batch();
    let pending = 0;
    let filled = 0;
    for (const c of companies) {
      const tz = zone.tzOf(c.data.timeZone);
      zones.add(tz);
      if (c.data.timeZone !== tz) {
        batch.update(db.collection("companies").doc(c.id), { timeZone: tz });
        filled++;
        if (++pending >= 400) {
          await batch.commit();
          batch = db.batch();
          pending = 0;
        }
      }
    }
    if (pending > 0) await batch.commit();
    await timeZonesRef().set({ zones: [...zones].sort() });

    console.log(
      `📇 Annuaire : ${listed.length} structure(s), ` +
      `${docs.size} document(s) — ${JSON.stringify(shardCounts)} · ` +
      `fuseaux : ${[...zones].join(", ")}` +
      (filled ? ` (${filled} fiche(s) complétée(s))` : ""),
    );
  });
