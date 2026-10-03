// ════════════════════════════════════════════════════════════════════
// RÉSERVATIONS CLIENT — le serveur est l'arbitre
//
// Une seule fonction appelable `booking` (2e génération) gère les quatre
// actions du client : warmup / reserve / replace / cancel. Le client ne
// peut plus écrire lui-même réservations, compteurs de créneaux, places
// par jour ni quota (voir firestore.rules) : tout passe par ici, vérifié
// puis écrit en une seule transaction.
//
// Région africa-south1 : à côté de la base Firestore (Johannesburg). Une
// réservation enchaîne plusieurs lectures/écritures ; les faire au plus
// près de la base est ce qui compte le plus pour le temps de réponse.
//
// Les règles métier sont le MIROIR de lib/services/reservation_rules_service.dart
// (pré-vérification côté app, pour les messages immédiats) : toute règle
// modifiée ici doit l'être là-bas aussi.
// ════════════════════════════════════════════════════════════════════
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");

const REGION = "africa-south1";

// MIROIRS de lib/services/booking_constants.dart
const MAX_DAILY_RESERVATIONS = 5;
const MIN_GAP_SAME_COMPANY_MINUTES = 5;
const MIN_GAP_DIFFERENT_COMPANY_MINUTES = 30;

// Fuseau des dates « jour » (quota, places par jour) — identique à celui
// des téléphones au Sénégal et au calcul actuel des dailyStats.
const BOOKING_TZ = "Africa/Dakar";

const MINUTE = 60 * 1000;

// ── Utilitaires ─────────────────────────────────────────────────────

/** Date « AAAA-MM-JJ » dans le fuseau de réservation. */
function ymd(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: BOOKING_TZ, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(date);
  return parts; // en-CA formate déjà en AAAA-MM-JJ
}

/** « AAAA-MM-JJ » + n jours. */
function addDays(ymdStr, n) {
  const [y, m, d] = ymdStr.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

function toDate(v) {
  if (!v) return null;
  return v.toDate ? v.toDate() : new Date(v);
}

function isQueueClosedNow(closureStart, closureEnd, now) {
  const cs = toDate(closureStart);
  if (!cs) return false;
  if (now < cs) return false;
  const ce = toDate(closureEnd);
  if (ce && now > ce) return false;
  return true;
}

function fullName(userData) {
  const prenom = String(userData.prenom || "").trim();
  const nom = String(userData.nom || "").trim();
  const full = [prenom, nom].filter((s) => s).join(" ");
  return full || null;
}

function requireString(data, key) {
  const v = data && data[key];
  if (typeof v !== "string" || v.length === 0 || v.length > 200 ||
      v.includes("/")) {
    throw new HttpsError("invalid-argument", `Paramètre « ${key} » invalide.`);
  }
  return v;
}

function optionalLabel(data, key) {
  const v = data && data[key];
  return typeof v === "string" && v.trim() ? v.trim().slice(0, 120) : null;
}

const refuse = (reason, message) =>
  new HttpsError("failed-precondition", message, {reason});

// Regroupe les +1/-1 par document de places du jour : un remplacement
// dans la même file le même jour touche deux fois le même document.
class StatsDelta {
  constructor() {
    this.byPath = new Map();
  }
  add(ref, delta) {
    const cur = this.byPath.get(ref.path) || {ref, delta: {}};
    for (const [k, v] of Object.entries(delta)) {
      cur.delta[k] = (cur.delta[k] || 0) + v;
    }
    this.byPath.set(ref.path, cur);
  }
  apply(tx) {
    for (const {ref, delta} of this.byPath.values()) {
      const inc = {};
      for (const [k, v] of Object.entries(delta)) {
        if (v !== 0) inc[k] = FieldValue.increment(v);
      }
      if (Object.keys(inc).length) tx.set(ref, inc, {merge: true});
    }
  }
}

function dailyStatsRef(db, companyId, queueId, date) {
  return db.collection("companies").doc(companyId)
    .collection("queues").doc(queueId)
    .collection("dailyStats").doc(ymd(date));
}

// ── Vérification d'un créneau cible (réserver / remplacer) ─────────
// Lit tout ce qu'il faut dans la transaction et lève un refus explicite.
async function loadTargetSlot(tx, db, target, now) {
  const {companyId, queueId, slotId, fallbackTimeSlotId} = target;
  const queueRef = db.collection("companies").doc(companyId)
    .collection("queues").doc(queueId);
  const slotRef = queueRef.collection("slots").doc(slotId);
  const [slotSnap, queueSnap] = await Promise.all([
    tx.get(slotRef), tx.get(queueRef),
  ]);
  if (!slotSnap.exists) {
    throw new HttpsError("not-found", "Ce créneau n'existe plus.");
  }
  const slot = slotSnap.data();
  const queue = queueSnap.data() || {};

  let timeSlot = {};
  if (slot.timeSlotId) {
    const tsSnap = await tx.get(
      queueRef.collection("timeSlots").doc(slot.timeSlotId));
    timeSlot = tsSnap.data() || {};
  }

  if (isQueueClosedNow(queue.closureStart, queue.closureEnd, now)) {
    throw refuse("queueClosed",
      "Les réservations pour cette file sont fermées pour le moment.");
  }
  if (timeSlot.deleteAfter) {
    throw refuse("timeSlotClosing",
      "Cette plage horaire n'accepte plus de nouvelles réservations.");
  }
  if ((slot.status || "open") !== "open") {
    throw refuse("slotUnavailable", "Ce créneau n'est plus disponible.");
  }
  if ((slot.reserved || 0) >= (slot.capacity || 1)) {
    throw refuse("slotFull", "Ce créneau est complet.");
  }

  const start = toDate(slot.start);
  const end = toDate(slot.end);
  if (start - now < MINUTE) {
    throw refuse("slotAlreadyStarted",
      "Ce créneau a déjà commencé et ne peut plus être réservé.");
  }
  if (queue.maxAdvanceDays != null) {
    const lastDay = addDays(ymd(now), Number(queue.maxAdvanceDays));
    if (ymd(start) > lastDay) {
      throw refuse("tooFarInAdvance",
        "Ce créneau dépasse le délai de réservation autorisé par cet " +
        "établissement.");
    }
  }
  const deadline = Number(slot.reservationDeadlineMinutes || 0);
  if (deadline > 0 && start - now < deadline * MINUTE) {
    throw refuse("tooLate", "Il est trop tard pour réserver ce créneau.");
  }

  return {
    slotRef, start, end,
    // Anciens créneaux sans timeSlotId : repli sur la plage transmise.
    timeSlotId: slot.timeSlotId || fallbackTimeSlotId || "",
    allowMultiplePerPlage: queue.allowMultiplePerPlage === true,
  };
}

// ── Règles d'écart entre rendez-vous (miroir de checkCanReserve) ────
function checkConflicts(active, target, {companyId, queueId}) {
  const {start, end, timeSlotId, allowMultiplePerPlage} = target;
  const minutes = (ms) => Math.floor(ms / MINUTE);

  for (const r of active) {
    const rStart = toDate(r.slotStart);
    const rEnd = toDate(r.slotEnd);
    const gapAfter = minutes(start - rEnd);
    const gapBefore = minutes(rStart - end);

    if (r.companyId !== companyId) {
      if (gapAfter < MIN_GAP_DIFFERENT_COMPANY_MINUTES &&
          gapBefore < MIN_GAP_DIFFERENT_COMPANY_MINUTES) {
        throw refuse("gapDifferentCompany",
          `Un délai de ${MIN_GAP_DIFFERENT_COMPANY_MINUTES} minutes est ` +
          "requis entre deux établissements. Choisissez un autre créneau.");
      }
    } else if (r.queueId !== queueId) {
      if (gapAfter < MIN_GAP_SAME_COMPANY_MINUTES &&
          gapBefore < MIN_GAP_SAME_COMPANY_MINUTES) {
        throw refuse("overlapInSameCompany",
          "Vous avez déjà un rendez-vous prévu à cet horaire.");
      }
    }
  }

  const sameQueue = active.filter(
    (r) => r.companyId === companyId && r.queueId === queueId);
  const blocking = allowMultiplePerPlage ?
    sameQueue.filter((r) => r.timeSlotId === timeSlotId) :
    sameQueue;
  if (blocking.length) {
    throw refuse("activeInSameQueue",
      "Vous avez déjà une réservation active dans cette file.");
  }
}

/** Réservations confirmées et non terminées du client. */
async function loadActive(tx, db, uid, now, excludePath) {
  const snap = await tx.get(db.collectionGroup("reservations")
    .where("customerId", "==", uid)
    .where("status", "==", "confirmed"));
  return snap.docs
    .filter((d) => d.ref.path !== excludePath)
    .map((d) => d.data())
    .filter((r) => toDate(r.slotEnd) > now);
}

function reservationData({user, userData, target, companyId, queueId,
  slotId, companyName, queueName}) {
  const name = fullName(userData);
  return {
    companyId,
    queueId,
    timeSlotId: target.timeSlotId,
    slotId,
    customerId: user.uid,
    customerEmail: user.email || null,
    ...(name ? {customerName: name} : {}),
    slotStart: Timestamp.fromDate(target.start),
    slotEnd: Timestamp.fromDate(target.end),
    createdAt: FieldValue.serverTimestamp(),
    status: "confirmed",
    ...(companyName ? {companyName} : {}),
    ...(queueName ? {queueName} : {}),
  };
}

// ── RÉSERVER ────────────────────────────────────────────────────────
async function reserve(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const queueId = requireString(data, "queueId");
  const slotId = requireString(data, "slotId");
  const userRef = db.collection("users").doc(user.uid);
  const resRef = db.collection("companies").doc(companyId)
    .collection("reservations").doc();

  await db.runTransaction(async (tx) => {
    const target = await loadTargetSlot(tx, db, {companyId, queueId, slotId,
      fallbackTimeSlotId: optionalLabel(data, "timeSlotId")}, now);
    const userSnap = await tx.get(userRef);
    const active = await loadActive(tx, db, user.uid, now, null);

    const userData = userSnap.data() || {};
    const today = ymd(now);
    const used = userData.lastBookingDate === today ?
      Number(userData.dailyBookingCount || 0) : 0;
    if (used >= MAX_DAILY_RESERVATIONS) {
      throw refuse("globalLimitReached",
        `Vous avez atteint votre limite de ${MAX_DAILY_RESERVATIONS} ` +
        "réservations pour aujourd'hui. Revenez demain pour réserver à " +
        "nouveau.");
    }
    checkConflicts(active, target, {companyId, queueId});

    tx.set(resRef, reservationData({
      user, userData, target, companyId, queueId, slotId,
      companyName: optionalLabel(data, "companyName"),
      queueName: optionalLabel(data, "queueName"),
    }));
    tx.update(target.slotRef, {reserved: FieldValue.increment(1)});
    const stats = new StatsDelta();
    stats.add(dailyStatsRef(db, companyId, queueId, target.start),
      {reserved: 1, available: -1});
    stats.apply(tx);
    // Quota du jour (les annulations ne le restituent pas).
    tx.set(userRef, {
      lastBookingDate: today,
      dailyBookingCount: used + 1,
    }, {merge: true});
  });

  return {reservationId: resRef.id};
}

// ── REMPLACER (annule l'ancienne + crée la nouvelle, atomique) ──────
async function replace(db, user, data, now = new Date()) {
  const oldCompanyId = requireString(data, "oldCompanyId");
  const oldReservationId = requireString(data, "oldReservationId");
  const companyId = requireString(data, "companyId");
  const queueId = requireString(data, "queueId");
  const slotId = requireString(data, "slotId");
  const oldResRef = db.collection("companies").doc(oldCompanyId)
    .collection("reservations").doc(oldReservationId);
  const userRef = db.collection("users").doc(user.uid);
  const newResRef = db.collection("companies").doc(companyId)
    .collection("reservations").doc();

  await db.runTransaction(async (tx) => {
    const oldSnap = await tx.get(oldResRef);
    const old = oldSnap.data();
    if (!oldSnap.exists || old.customerId !== user.uid) {
      throw new HttpsError("not-found", "Réservation introuvable.");
    }
    if (old.status !== "confirmed") {
      throw refuse("notActive", "Cette réservation n'est plus active.");
    }
    if (old.companyId === companyId && old.queueId === queueId &&
        old.slotId === slotId) {
      throw refuse("sameSlot", "Vous avez déjà réservé ce créneau.");
    }

    const target = await loadTargetSlot(tx, db, {companyId, queueId, slotId,
      fallbackTimeSlotId: optionalLabel(data, "timeSlotId")}, now);
    const oldSlotRef = db.collection("companies").doc(old.companyId)
      .collection("queues").doc(old.queueId)
      .collection("slots").doc(old.slotId);
    const [oldSlotSnap, userSnap] = await Promise.all([
      tx.get(oldSlotRef), tx.get(userRef),
    ]);
    const active = await loadActive(tx, db, user.uid, now, oldResRef.path);
    checkConflicts(active, target, {companyId, queueId});

    // Ancienne réservation : annulée (un remplacement n'est pas compté
    // comme une annulation dans les statistiques, comme avant).
    tx.update(oldResRef, {
      status: "cancelled",
      cancelledAt: FieldValue.serverTimestamp(),
    });
    if (oldSlotSnap.exists) {
      tx.update(oldSlotRef, {reserved: FieldValue.increment(-1)});
    }

    tx.set(newResRef, {
      ...reservationData({
        user, userData: userSnap.data() || {}, target, companyId, queueId,
        slotId,
        companyName: optionalLabel(data, "companyName"),
        queueName: optionalLabel(data, "queueName"),
      }),
      replacedReservationId: oldReservationId,
    });
    tx.update(target.slotRef, {reserved: FieldValue.increment(1)});

    const stats = new StatsDelta();
    // Date de l'ANCIEN créneau (l'ancienne version prenait à tort celle
    // du nouveau).
    stats.add(dailyStatsRef(db, old.companyId, old.queueId,
      toDate(old.slotStart)), {reserved: -1, available: 1});
    stats.add(dailyStatsRef(db, companyId, queueId, target.start),
      {reserved: 1, available: -1});
    stats.apply(tx);
  });

  return {reservationId: newResRef.id};
}

// ── ANNULER ─────────────────────────────────────────────────────────
async function cancel(db, user, data) {
  const companyId = requireString(data, "companyId");
  const reservationId = requireString(data, "reservationId");
  const source = data && data.source === "notification" ? "notification" :
    null;
  const resRef = db.collection("companies").doc(companyId)
    .collection("reservations").doc(reservationId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(resRef);
    const res = snap.data();
    if (!snap.exists || res.customerId !== user.uid) {
      throw new HttpsError("not-found", "Réservation introuvable.");
    }
    // Évite la double annulation (double appui, réseau lent) qui libérait
    // deux places au lieu d'une.
    if (res.status !== "confirmed") {
      throw refuse("notActive", "Cette réservation est déjà annulée.");
    }
    const slotRef = db.collection("companies").doc(companyId)
      .collection("queues").doc(res.queueId)
      .collection("slots").doc(res.slotId);
    const slotSnap = await tx.get(slotRef);

    tx.update(resRef, {
      status: "cancelled",
      cancelledAt: FieldValue.serverTimestamp(),
      ...(source ? {cancellationSource: source} : {}),
    });
    if (slotSnap.exists) {
      tx.update(slotRef, {
        reserved: FieldValue.increment(-1),
        cancelled: FieldValue.increment(1),
      });
    }
    const stats = new StatsDelta();
    stats.add(dailyStatsRef(db, companyId, res.queueId,
      toDate(res.slotStart)), {reserved: -1, available: 1, cancelled: 1});
    stats.apply(tx);
  });

  return {ok: true};
}

// ── Point d'entrée ──────────────────────────────────────────────────
const ACTIONS = {reserve, replace, cancel};

const booking = onCall({region: REGION}, async (request) => {
  const action = request.data && request.data.action;
  // Réveil anticipé (page créneaux ouverte) : répond sans rien faire.
  if (action === "warmup") return {ok: true};

  const handler = ACTIONS[action];
  if (!handler) {
    throw new HttpsError("invalid-argument", "Action inconnue.");
  }
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  const user = {
    uid: request.auth.uid,
    email: request.auth.token.email || null,
  };
  return handler(admin.firestore(), user, request.data);
});

module.exports = {
  booking,
  // Exposés pour les tests (émulateur).
  reserve, replace, cancel, ymd, MAX_DAILY_RESERVATIONS,
};
