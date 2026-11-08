// ════════════════════════════════════════════════════════════════════
// RÉSERVATIONS GÉRÉES PAR LA STRUCTURE — le serveur est l'arbitre
//
// Une seule fonction appelable `companyBooking` (2e génération), pour tout
// ce que la structure (admin) ou son équipe fait sur les réservations :
//   • addManual    : inscrire un client au guichet (admin + équipe)
//   • removeManual : retirer une inscription manuelle (admin : toutes ;
//                    membre : seulement les siennes)
//   • block        : bloquer une plage / la journée (incident) — admin
//   • unblock      : la débloquer — admin
//   • close        : fermer des files (programmée ou « Stopper ») — admin
//   • leave        : quitter Baxa (demande + fermeture + annulations) — admin
//
// Avant, l'app écrivait elle-même réservations et compteurs, en plusieurs
// écritures séparées : surbooking possible (aucune vérification de place au
// moment d'écrire) et compteurs faussés à la moindre coupure. Ici, chaque
// inscription est vérifiée puis écrite en une seule transaction.
//
// Les notifications clients ne changent pas : on écrit les MÊMES champs
// qu'avant (status, cancellationSource, suspended…), auxquels réagissent
// déjà onReservationCancelledByCompany / onReservationBlockChange.
//
// Région africa-south1 : à côté de la base Firestore (Johannesburg).
// ════════════════════════════════════════════════════════════════════
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const zone = require("./zone");

const REGION = "africa-south1";
const MINUTE = 60 * 1000;
const DAY = 24 * 60 * MINUTE;

// MIROIR de `_graceDays` (company_settings_page.dart, « Quitter Baxa »).
const LEAVE_GRACE_DAYS = 7;
// Opérations par lot d'écriture (limite Firestore : 500).
const BATCH_LIMIT = 450;

const refuse = (reason, message) =>
  new HttpsError("failed-precondition", message, {reason});

// ── Utilitaires ─────────────────────────────────────────────────────

function toDate(v) {
  if (!v) return null;
  return v.toDate ? v.toDate() : new Date(v);
}

function requireString(data, key, {max = 200} = {}) {
  const v = data ? data[key] : undefined;
  if (typeof v !== "string" || !v.trim()) {
    throw new HttpsError("invalid-argument", `Champ manquant : ${key}.`);
  }
  const t = v.trim();
  if (t.length > max) {
    throw new HttpsError("invalid-argument", `Champ trop long : ${key}.`);
  }
  return t;
}

function optionalString(data, key, {max = 200} = {}) {
  const v = data ? data[key] : undefined;
  if (v === undefined || v === null) return null;
  if (typeof v !== "string") {
    throw new HttpsError("invalid-argument", `Champ invalide : ${key}.`);
  }
  const t = v.trim();
  if (t.length > max) {
    throw new HttpsError("invalid-argument", `Champ trop long : ${key}.`);
  }
  return t || null;
}

/** Jour « AAAA-MM-JJ » (format strict). */
function requireDay(data, key) {
  const v = requireString(data, key, {max: 10});
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) {
    throw new HttpsError("invalid-argument", `Date invalide : ${key}.`);
  }
  return v;
}

/** Instant envoyé par l'app en millisecondes. */
function millis(data, key, {required = true} = {}) {
  const v = data ? data[key] : undefined;
  if (v === undefined || v === null) {
    if (required) {
      throw new HttpsError("invalid-argument", `Champ manquant : ${key}.`);
    }
    return null;
  }
  if (typeof v !== "number" || !Number.isFinite(v)) {
    throw new HttpsError("invalid-argument", `Date invalide : ${key}.`);
  }
  return new Date(v);
}

// MIROIRS de lib/services/booking_constants.dart
function isQueueClosedNow(closureStart, closureEnd, now) {
  const cs = toDate(closureStart);
  if (!cs || now < cs) return false;
  const ce = toDate(closureEnd);
  return !(ce && now > ce);
}

function isSlotInClosure(closureStart, closureEnd, slotStart) {
  const cs = toDate(closureStart);
  if (!cs || slotStart < cs) return false;
  const ce = toDate(closureEnd);
  return !ce || slotStart <= ce;
}

function hasClosureScheduled(closureStart, closureEnd, now) {
  if (!closureStart) return false;
  const ce = toDate(closureEnd);
  return !ce || now <= ce;
}

const companyRef = (db, companyId) =>
  db.collection("companies").doc(companyId);
const queueRef = (db, companyId, queueId) =>
  companyRef(db, companyId).collection("queues").doc(queueId);

function statsRef(db, companyId, queueId, date, tz) {
  return queueRef(db, companyId, queueId)
    .collection("dailyStats").doc(zone.ymdIn(date, tz));
}

// Regroupe les +1/-1 par document (créneau, places du jour) : plusieurs
// réservations d'un même créneau ou d'un même jour ne font qu'UNE écriture.
class Deltas {
  constructor() {
    this.byPath = new Map();
  }
  add(ref, delta, {merge = false} = {}) {
    const cur = this.byPath.get(ref.path) || {ref, delta: {}, merge};
    for (const [k, v] of Object.entries(delta)) {
      cur.delta[k] = (cur.delta[k] || 0) + v;
    }
    this.byPath.set(ref.path, cur);
  }
  get size() {
    return this.byPath.size;
  }
  /** Applique à une transaction ou un lot. */
  apply(w) {
    for (const {ref, delta, merge} of this.byPath.values()) {
      const inc = {};
      for (const [k, v] of Object.entries(delta)) {
        if (v !== 0) inc[k] = FieldValue.increment(v);
      }
      if (!Object.keys(inc).length) continue;
      if (merge) w.set(ref, inc, {merge: true});
      else w.update(ref, inc);
    }
  }
}

// Écrit une suite d'opérations en lots successifs (au-delà de 500
// opérations, une seule transaction n'est pas possible). Chaque opération
// est idempotente ou protégée par son statut : relancer après une coupure
// ne compte rien deux fois.
async function commitInBatches(db, ops) {
  let batch = db.batch();
  let n = 0;
  for (const op of ops) {
    op(batch);
    if (++n >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n > 0) await batch.commit();
}

// ── Qui agit ? ──────────────────────────────────────────────────────
// Admin : son uid EST l'identifiant de la structure, et la fiche existe.
// Membre : profil `staff` rattaché à cette structure ET fiche d'équipe
// active (même définition que isStaff dans firestore.rules).
async function companyAccess(db, uid, companyId, {adminOnly = false} = {}) {
  const cRef = companyRef(db, companyId);
  if (uid === companyId) {
    const c = await cRef.get();
    if (!c.exists) {
      throw new HttpsError("permission-denied", "Structure introuvable.");
    }
    return {isAdmin: true, tz: zone.tzOf(c.get("timeZone")), company: c};
  }
  if (adminOnly) {
    throw new HttpsError("permission-denied",
      "Seul le responsable de la structure peut faire cette action.");
  }
  const [u, s, c] = await Promise.all([
    db.collection("users").doc(uid).get(),
    cRef.collection("staff").doc(uid).get(),
    cRef.get(),
  ]);
  const ok = u.exists && u.get("role") === "staff" &&
    u.get("companyId") === companyId &&
    s.exists && s.get("isActive") === true && c.exists;
  if (!ok) {
    throw new HttpsError("permission-denied",
      "Vous n'avez pas accès à cette structure.");
  }
  return {
    isAdmin: false,
    staffName: (s.get("displayName") || "").trim(),
    tz: zone.tzOf(c.get("timeZone")),
    company: c,
  };
}

// ── Annulation en masse (fermeture, départ) ─────────────────────────
// Statut `cancelled` + source, et les compteurs : créneau reserved -1 /
// cancelled +1, places du jour reserved -1 / available +1 / cancelled +1
// (comme une annulation client). Le client est prévenu par
// onReservationCancelledByCompany.
async function cancelReservations(db, companyId, docs, source, tz,
  extra = {}) {
  // Par paquets de réservations : statut + compteurs regroupés du paquet
  // dans le même lot (tout-ou-rien pour chaque paquet).
  const PER_BATCH = 120;
  let cancelled = 0;
  for (let i = 0; i < docs.length; i += PER_BATCH) {
    const chunk = docs.slice(i, i + PER_BATCH);
    const batch = db.batch();
    const deltas = new Deltas();
    for (const d of chunk) {
      const r = d.data();
      batch.update(d.ref, {
        status: "cancelled",
        cancelledAt: FieldValue.serverTimestamp(),
        cancellationSource: source,
        ...extra,
      });
      if (r.queueId && r.slotId) {
        const qRef = queueRef(db, companyId, r.queueId);
        deltas.add(qRef.collection("slots").doc(r.slotId),
          {reserved: -1, cancelled: 1});
        const start = toDate(r.slotStart);
        if (start) {
          deltas.add(statsRef(db, companyId, r.queueId, start, tz),
            {reserved: -1, available: 1, cancelled: 1}, {merge: true});
        }
      }
      cancelled++;
    }
    // Un créneau supprimé entre-temps ferait échouer tout le lot : on ne
    // touche qu'aux créneaux qui existent encore.
    const slotPaths = [...deltas.byPath.values()]
      .filter((e) => !e.merge).map((e) => e.ref);
    if (slotPaths.length) {
      const snaps = await db.getAll(...slotPaths);
      for (const s of snaps) {
        if (!s.exists) deltas.byPath.delete(s.ref.path);
      }
    }
    deltas.apply(batch);
    await batch.commit();
  }
  return cancelled;
}

// ── INSCRIRE UN CLIENT AU GUICHET ───────────────────────────────────
async function addManual(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const queueId = requireString(data, "queueId");
  const slotId = requireString(data, "slotId");
  const clientName = requireString(data, "clientName", {max: 80});
  const requestId = optionalString(data, "requestId", {max: 40});
  if (requestId && !/^[A-Za-z0-9]{10,40}$/.test(requestId)) {
    throw new HttpsError("invalid-argument", "Identifiant de demande invalide.");
  }

  const access = await companyAccess(db, user.uid, companyId);
  const qRef = queueRef(db, companyId, queueId);
  const slotRef = qRef.collection("slots").doc(slotId);
  const resCol = companyRef(db, companyId).collection("reservations");
  // Identifiant fourni par l'app : une nouvelle tentative après une
  // coupure retombe sur la même réservation au lieu d'en créer une 2e.
  const resRef = requestId ? resCol.doc(requestId) : resCol.doc();

  return db.runTransaction(async (tx) => {
    const [slotSnap, queueSnap, existing] = await Promise.all([
      tx.get(slotRef), tx.get(qRef), tx.get(resRef),
    ]);
    if (existing.exists) {
      if (existing.get("createdBy") === user.uid &&
          existing.get("slotId") === slotId) {
        return {reservationId: resRef.id, alreadyDone: true};
      }
      throw new HttpsError("already-exists", "Demande déjà utilisée.");
    }
    if (!slotSnap.exists) {
      throw refuse("slotGone", "Ce créneau n'existe plus.");
    }
    const slot = slotSnap.data();
    const queue = queueSnap.data() || {};
    let timeSlot = {};
    if (slot.timeSlotId) {
      const ts = await tx.get(qRef.collection("timeSlots").doc(slot.timeSlotId));
      timeSlot = ts.data() || {};
    }

    const start = toDate(slot.start);
    const end = toDate(slot.end);
    if (isQueueClosedNow(queue.closureStart, queue.closureEnd, now)) {
      throw refuse("queueClosed", "Cette file est fermée aux réservations.");
    }
    if (isSlotInClosure(queue.closureStart, queue.closureEnd, start)) {
      throw refuse("closedOnDay", "La structure est fermée ce jour-là.");
    }
    if (timeSlot.deleteAfter) {
      throw refuse("timeSlotClosing",
        "Cette plage est en cours de suppression, plus de réservation " +
        "possible.");
    }
    if ((slot.status || "open") !== "open") {
      throw refuse("slotBlocked", "Ce créneau est bloqué.");
    }
    if (end && end <= now) {
      throw refuse("slotEnded", "Ce créneau est déjà terminé.");
    }
    if ((slot.reserved || 0) >= (slot.capacity || 1)) {
      throw refuse("slotFull",
        "Ce créneau vient d'être complété. Choisissez-en un autre.");
    }

    tx.set(resRef, {
      customerId: "manual_booking",
      customerName: clientName,
      companyId,
      queueId,
      queueName: queue.name || optionalString(data, "queueName") || "",
      slotId,
      ...(slot.timeSlotId ? {timeSlotId: slot.timeSlotId} : {}),
      slotStart: Timestamp.fromDate(start),
      slotEnd: Timestamp.fromDate(end),
      status: "confirmed",
      createdAt: FieldValue.serverTimestamp(),
      source: "company_manual",
      // Auteur : décide qui peut la retirer et alimente « Ajouté par … ».
      createdBy: user.uid,
      createdByRole: access.isAdmin ? "admin" : "staff",
      ...(!access.isAdmin && access.staffName ?
        {createdByName: access.staffName} : {}),
    });
    tx.update(slotRef, {reserved: FieldValue.increment(1)});
    // Une place de moins ce jour-là (avant : seul `reserved` bougeait, et
    // les places libres dérivaient à chaque ajout puis retrait).
    tx.set(statsRef(db, companyId, queueId, start, access.tz), {
      reserved: FieldValue.increment(1),
      available: FieldValue.increment(-1),
    }, {merge: true});
    return {reservationId: resRef.id};
  });
}

// ── RETIRER UNE INSCRIPTION MANUELLE ────────────────────────────────
async function removeManual(db, user, data) {
  const companyId = requireString(data, "companyId");
  const reservationId = requireString(data, "reservationId");
  const access = await companyAccess(db, user.uid, companyId);
  const resRef = companyRef(db, companyId)
    .collection("reservations").doc(reservationId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(resRef);
    // Déjà retirée (double appui, nouvelle tentative) : rien à faire.
    if (!snap.exists) return {ok: true, alreadyDone: true};
    const r = snap.data();
    if (r.source !== "company_manual") {
      throw refuse("notManual",
        "Seules les inscriptions faites par la structure peuvent être " +
        "retirées.");
    }
    if (!access.isAdmin && r.createdBy !== user.uid) {
      throw new HttpsError("permission-denied",
        "Vous ne pouvez retirer que les inscriptions que vous avez faites.");
    }
    const slotRef = queueRef(db, companyId, r.queueId)
      .collection("slots").doc(r.slotId);
    const slotSnap = await tx.get(slotRef);

    tx.delete(resRef);
    // Compteurs seulement si la réservation comptait encore.
    if (r.status === "confirmed") {
      if (slotSnap.exists) {
        tx.update(slotRef, {reserved: FieldValue.increment(-1)});
      }
      const start = toDate(r.slotStart);
      if (start) {
        tx.set(statsRef(db, companyId, r.queueId, start, access.tz), {
          reserved: FieldValue.increment(-1),
          available: FieldValue.increment(1),
        }, {merge: true});
      }
    }
    return {ok: true};
  });
}

// ── BLOQUER (incident) ──────────────────────────────────────────────
// Seuls les créneaux pas encore terminés sont bloqués (un créneau passé a
// déjà eu lieu). Un créneau déjà bloqué garde sa raison d'origine. Les
// réservations confirmées passent « suspendues » : le client est prévenu
// par onReservationBlockChange.
async function block(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const queueId = requireString(data, "queueId");
  const day = requireDay(data, "day");
  const timeSlotId = optionalString(data, "timeSlotId", {max: 100});
  const reasonRaw = optionalString(data, "reason", {max: 2000}) || "";
  // La raison part telle quelle dans une notification client.
  const reason = reasonRaw.length > 120 ?
    `${reasonRaw.slice(0, 117)}…` : reasonRaw;
  const access = await companyAccess(db, user.uid, companyId,
    {adminOnly: true});

  const {start, end} = zone.dayBounds(day, access.tz);
  const qRef = queueRef(db, companyId, queueId);
  const slotsSnap = await qRef.collection("slots")
    .where("start", ">=", start).where("start", "<", end).get();
  const toBlock = slotsSnap.docs.filter((d) => {
    const s = d.data();
    if (timeSlotId && s.timeSlotId !== timeSlotId) return false;
    if (s.status === "blocked") return false;
    const e = toDate(s.end);
    return e && e > now;
  });
  if (!toBlock.length) {
    throw refuse("nothingToBlock",
      "Aucun créneau à venir à bloquer sur cette plage.");
  }

  const reserved = toBlock.filter((d) => (d.get("reserved") || 0) > 0)
    .map((d) => d.id);
  const resDocs = await confirmedForSlots(db, companyId, reserved);

  const ops = [];
  for (const d of toBlock) {
    ops.push((b) => b.update(d.ref, {
      status: "blocked",
      blockReason: reason || null,
      blockedAt: FieldValue.serverTimestamp(),
    }));
  }
  for (const r of resDocs) {
    ops.push((b) => b.update(r.ref, {
      suspended: true,
      suspendedReason: reason || null,
      suspendedAt: FieldValue.serverTimestamp(),
    }));
  }
  await commitInBatches(db, ops);
  return {blocked: toBlock.length, suspended: resDocs.length};
}

/** Réservations confirmées des créneaux [slotIds] (par paquets de 30). */
async function confirmedForSlots(db, companyId, slotIds) {
  const col = companyRef(db, companyId).collection("reservations");
  const out = [];
  for (let i = 0; i < slotIds.length; i += 30) {
    const snap = await col
      .where("slotId", "in", slotIds.slice(i, i + 30))
      .where("status", "==", "confirmed").get();
    out.push(...snap.docs);
  }
  return out;
}

// ── DÉBLOQUER ───────────────────────────────────────────────────────
// Créneaux encore à venir : rouverts. Réservations suspendues du jour :
// rétablies si leur créneau est encore à venir ; annulées sinon
// (`company_block_unresolved`, le client est invité à re-réserver) — avec,
// désormais, les compteurs du créneau et du jour corrigés.
async function unblock(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const queueId = requireString(data, "queueId");
  const day = requireDay(data, "day");
  const access = await companyAccess(db, user.uid, companyId,
    {adminOnly: true});

  const {start, end} = zone.dayBounds(day, access.tz);
  const qRef = queueRef(db, companyId, queueId);
  const [slotsSnap, resSnap] = await Promise.all([
    qRef.collection("slots").where("start", ">=", start)
      .where("start", "<", end).get(),
    companyRef(db, companyId).collection("reservations")
      .where("queueId", "==", queueId)
      .where("status", "==", "confirmed").get(),
  ]);

  const toOpen = slotsSnap.docs.filter((d) => {
    if (d.get("status") !== "blocked") return false;
    const e = toDate(d.get("end"));
    return e && e > now;
  });

  const suspended = resSnap.docs.filter((d) => {
    if (d.get("suspended") !== true) return false;
    const ss = toDate(d.get("slotStart"));
    return ss && ss >= start && ss < end;
  });
  const passed = suspended.filter((d) => {
    const se = toDate(d.get("slotEnd"));
    return se && se < now;
  });
  const passedIds = new Set(passed.map((d) => d.id));
  const restored = suspended.filter((d) => !passedIds.has(d.id));

  const clearSuspension = {
    suspended: FieldValue.delete(),
    suspendedReason: FieldValue.delete(),
    suspendedAt: FieldValue.delete(),
  };
  const ops = [];
  for (const d of toOpen) {
    ops.push((b) => b.update(d.ref, {
      status: "open",
      blockReason: null,
      unblockedAt: FieldValue.serverTimestamp(),
    }));
  }
  for (const d of restored) {
    ops.push((b) => b.update(d.ref, clearSuspension));
  }
  await commitInBatches(db, ops);

  // Créneau déjà passé pendant le blocage : annulation + compteurs.
  if (passed.length) {
    await cancelReservations(db, companyId, passed,
      "company_block_unresolved", access.tz, clearSuspension);
  }
  return {
    unblocked: toOpen.length,
    restored: restored.length,
    cancelled: passed.length,
  };
}

// ── FERMER DES FILES ────────────────────────────────────────────────
// Fermeture programmée (dates) ou « Stopper les réservations » (dès
// maintenant, sans fin). Une file n'a qu'UNE fermeture : on refuse d'en
// poser une seconde (sauf `replaceExisting`, utilisé par « Stopper »,
// comme avant). Option : annuler les réservations prises dans la période.
async function close(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const queueIds = data && Array.isArray(data.queueIds) ?
    [...new Set(data.queueIds.filter((x) => typeof x === "string" && x))] :
    [];
  if (!queueIds.length || queueIds.length > 20) {
    throw new HttpsError("invalid-argument", "Files invalides.");
  }
  const start = millis(data, "start");
  const endAt = millis(data, "end", {required: false});
  if (endAt && endAt < start) {
    throw new HttpsError("invalid-argument",
      "La fin de la fermeture doit suivre son début.");
  }
  const cancelCaught = data.cancelCaught === true;
  const replaceExisting = data.replaceExisting === true;
  const access = await companyAccess(db, user.uid, companyId,
    {adminOnly: true});

  const refs = queueIds.map((id) => queueRef(db, companyId, id));
  await db.runTransaction(async (tx) => {
    const snaps = await Promise.all(refs.map((r) => tx.get(r)));
    if (snaps.some((s) => !s.exists)) {
      throw refuse("queueGone", "Une des files n'existe plus.");
    }
    if (!replaceExisting && snaps.some((s) =>
      hasClosureScheduled(s.get("closureStart"), s.get("closureEnd"), now))) {
      throw refuse("alreadyClosed",
        "Une des files a déjà une fermeture. Rien n'a été modifié.");
    }
    for (const r of refs) {
      tx.update(r, {
        closureStart: Timestamp.fromDate(start),
        closureEnd: endAt ? Timestamp.fromDate(endAt) : FieldValue.delete(),
      });
    }
  });

  let cancelled = 0;
  if (cancelCaught) {
    const snap = await companyRef(db, companyId).collection("reservations")
      .where("status", "==", "confirmed").get();
    const ids = new Set(queueIds);
    const caught = snap.docs.filter((d) => {
      if (!ids.has(d.get("queueId"))) return false;
      const ss = toDate(d.get("slotStart"));
      if (!ss || ss < start) return false;
      return !(endAt && ss > endAt);
    });
    cancelled = await cancelReservations(db, companyId, caught,
      "company_closure", access.tz);
  }
  return {cancelled};
}

// ── QUITTER BAXA ────────────────────────────────────────────────────
// Demande de suppression (délai de grâce), fermeture indéterminée de toutes
// les files dès maintenant, et annulation des réservations à venir. L'accès
// du staff est coupé par onDeletionRequestCreated, APRÈS la notification
// « quitte Baxa ».
async function leave(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const reason = optionalString(data, "reason", {max: 1000}) || "";
  const access = await companyAccess(db, user.uid, companyId,
    {adminOnly: true});
  const c = access.company;

  await db.collection("deletionRequests").doc(companyId).set({
    companyId,
    companyName: c.get("nom") || "",
    email: user.email || c.get("email") || "",
    phone: c.get("telephone") || c.get("phone") || "",
    reason,
    requestedAt: FieldValue.serverTimestamp(),
    requestedBy: user.uid,
    status: "scheduled",
    executeAfter: Timestamp.fromDate(new Date(now.getTime() +
      LEAVE_GRACE_DAYS * DAY)),
  });

  const queues = await companyRef(db, companyId).collection("queues").get();
  await commitInBatches(db, queues.docs.map((q) => (b) => b.update(q.ref, {
    closureStart: Timestamp.fromDate(now),
    closureEnd: FieldValue.delete(),
  })));

  const resSnap = await companyRef(db, companyId).collection("reservations")
    .where("status", "==", "confirmed").get();
  const upcoming = resSnap.docs.filter((d) => {
    const ss = toDate(d.get("slotStart"));
    return ss && ss > now;
  });
  const cancelled = await cancelReservations(db, companyId, upcoming,
    "company_closure", access.tz);
  return {
    cancelled,
    executeAfter: now.getTime() + LEAVE_GRACE_DAYS * DAY,
  };
}

// ── Point d'entrée ──────────────────────────────────────────────────
const ACTIONS = {addManual, removeManual, block, unblock, close, leave};

const companyBooking = onCall({region: REGION, enforceAppCheck: true},
  async (request) => {
  const action = request.data && request.data.action;
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
    email: (request.auth.token && request.auth.token.email) || null,
  };
  return handler(admin.firestore(), user, request.data);
});

module.exports = {
  companyBooking,
  // Exposés pour les tests (émulateur).
  addManual, removeManual, block, unblock, close, leave,
  LEAVE_GRACE_DAYS,
  // Outils partagés avec company_schedule.js.
  shared: {
    refuse, toDate, requireString, optionalString, requireDay, millis,
    isQueueClosedNow, companyAccess, cancelReservations, commitInBatches,
    companyRef, queueRef, BATCH_LIMIT,
  },
};
