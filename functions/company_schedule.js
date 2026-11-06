// ════════════════════════════════════════════════════════════════════
// PLAGES HORAIRES ET CRÉNEAUX — le serveur est l'arbitre
//
// Une seule fonction appelable `companySchedule` (2e génération), réservée
// au responsable de la structure :
//   • previewTimeSlot   : conflits qu'entraînerait une modification de
//                         plage (pour le choix « Programmer / Appliquer »)
//   • saveTimeSlot      : créer / modifier une plage (appliquer maintenant
//                         ou programmer), créneaux et compteurs compris
//   • previewDeleteTimeSlot / deleteTimeSlot / restoreTimeSlot
//   • changeDayDuration : durée des créneaux du jour (accueil)
//   • changeDayCapacity : capacité des créneaux du jour (accueil)
//   • reopen            : rouvrir des files fermées (+ créneaux)
//   • returnToBaxa      : annuler un départ de Baxa (+ créneaux)
//
// Avant, le téléphone enchaînait lui-même 4 ou 5 étapes (écrire la plage,
// vider, annuler les conflits, générer, mettre à jour) : une coupure au
// milieu laissait une plage à moitié faite. Le moteur de génération est
// aussi celui de la génération de nuit (functions/index.js), dans le
// FUSEAU DE LA STRUCTURE.
//
// Règles reprises à l'identique de l'ancienne génération côté app (et de
// lib/services/plage_rules.dart, toujours utilisé pour l'affichage) :
//  • un jour où la plage a un créneau bloqué à venir n'est JAMAIS touché ;
//  • on ne remplit que les espaces libres, jamais par-dessus un créneau ;
//  • file fermée → pas de génération (sauf 48 h avant une réouverture
//    datée) ;
//  • aujourd'hui, pas de créneau déjà commencé.
// ════════════════════════════════════════════════════════════════════
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const zone = require("./zone");
const {shared} = require("./company_booking");

const {
  refuse, toDate, requireString, requireDay, isQueueClosedNow,
  companyAccess, cancelReservations, commitInBatches, companyRef, queueRef,
  BATCH_LIMIT,
} = shared;

const REGION = "africa-south1";
const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;

// Horizon de génération immédiate : aujourd'hui + 7 jours (comme la nuit).
const HORIZON_DAYS = 7;
// Préchauffage avant une réouverture datée (MIROIR de la génération de nuit).
const REOPEN_PREHEAT_MS = 48 * HOUR;
const DEFAULT_WEEKDAYS = [1, 2, 3, 4, 5];

// ════════════════════════════════════════════════════════════════════
// MOTEUR — fonctions pures (testées seules)
// ════════════════════════════════════════════════════════════════════

/** « HH:mm » → minutes depuis minuit (« 24:00 » → 1440), sinon null. */
function toMinutes(hm) {
  if (typeof hm !== "string") return null;
  const m = /^(\d{2}):(\d{2})$/.exec(hm.trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (min > 59 || h > 24 || (h === 24 && min !== 0)) return null;
  return h * 60 + min;
}

/** Espaces libres de [rangeStart, rangeEnd[ une fois retirés les
 * intervalles `occupied` ({start, end}). MIROIR de freeIntervals. */
function freeIntervals(occupied, rangeStart, rangeEnd) {
  const busy = occupied
    .filter((o) => o.start < rangeEnd && o.end > rangeStart)
    .sort((a, b) => a.start - b.start);
  const spans = [];
  let cursor = rangeStart;
  for (const o of busy) {
    if (cursor < o.start) spans.push({start: cursor, end: o.start});
    if (o.end > cursor) cursor = o.end;
  }
  if (cursor < rangeEnd) spans.push({start: cursor, end: rangeEnd});
  return spans;
}

/** Vrai si la génération doit être suspendue : file fermée, sauf
 * réouverture datée dans moins de 48 h. */
function shouldSkipGeneration(closureStart, closureEnd, now) {
  if (!isQueueClosedNow(closureStart, closureEnd, now)) return false;
  const ce = toDate(closureEnd);
  return !(ce && ce - now < REOPEN_PREHEAT_MS);
}

/** Vue minimale d'un créneau (ou null sans horaires). */
function slotLite(data) {
  const start = toDate(data.start);
  const end = toDate(data.end);
  if (!start || !end) return null;
  return {
    timeSlotId: data.timeSlotId || "",
    status: data.status || "open",
    start, end,
    reserved: Number(data.reserved || 0),
    capacity: Number(data.capacity || 0),
  };
}

/** Jours (« AAAA-MM-JJ », fuseau `tz`) où la plage a encore un créneau
 * bloqué à venir : ces jours-là, elle ne reçoit AUCUNE modification. */
function activeBlockedDays(slots, timeSlotId, now, tz) {
  const days = new Set();
  for (const s of slots) {
    if (s && s.timeSlotId === timeSlotId && s.status === "blocked" &&
        s.end > now) {
      days.add(zone.ymdIn(s.start, tz));
    }
  }
  return days;
}

/** Créneaux à créer pour la plage `cfg` le jour `day` : espaces libres
 * autour des créneaux `existing`, jamais deux créneaux à la même heure,
 * et aujourd'hui rien de déjà commencé. */
function buildDaySlots({day, tz, cfg, timeSlotId, existing, now}) {
  const plageStart = zone.zonedTime(day, cfg.startTime, tz);
  const plageEnd = zone.zonedTime(day, cfg.endTime, tz);
  if (!(plageEnd > plageStart)) return [];
  const step = cfg.duration * MINUTE;
  const taken = new Set(existing.map((s) => s.start.getTime()));
  const isToday = day === zone.ymdIn(now, tz);
  const out = [];
  for (const span of freeIntervals(existing, plageStart, plageEnd)) {
    let cursor = span.start.getTime();
    const spanEnd = span.end.getTime();
    if (isToday) {
      while (cursor < now.getTime() && cursor + step <= spanEnd) {
        cursor += step;
      }
    }
    while (cursor + step <= spanEnd) {
      if (!taken.has(cursor)) {
        out.push({
          start: new Date(cursor),
          end: new Date(cursor + step),
          capacity: cfg.capacity,
          reserved: 0,
          cancelled: 0,
          status: "open",
          duration: cfg.duration,
          isLegacy: false,
          timeSlotId,
          reservationDeadlineMinutes: cfg.reservationDeadlineMinutes || 0,
        });
      }
      cursor += step;
    }
  }
  return out;
}

/** Valeur la plus fréquente (à égalité, la plus grande), ou null. */
function mostFrequent(values) {
  const counts = new Map();
  for (const v of values) counts.set(v, (counts.get(v) || 0) + 1);
  let best = null;
  let bestCount = 0;
  for (const [v, c] of counts) {
    if (c > bestCount || (c === bestCount && best !== null && v > best)) {
      best = v;
      bestCount = c;
    }
  }
  return best;
}

/** Configuration d'une plage lue sur son document. */
function configOf(ts, queue, pending = false) {
  const p = (k, fallback) => pending && ts[`pending${k}`] !== undefined ?
    ts[`pending${k}`] : fallback;
  const days = Array.isArray(ts.workingDays) ? ts.workingDays :
    (queue.weekdays || queue.defaultWorkingDays || DEFAULT_WEEKDAYS);
  return {
    startTime: p("StartTime", ts.startTime || "09:00"),
    endTime: p("EndTime", ts.endTime || "17:00"),
    duration: Number(p("ServiceDurationMinutes",
      ts.serviceDurationMinutes || 15)),
    capacity: Number(p("CapacityPerSlot", ts.capacityPerSlot || 1)),
    workingDays: p("WorkingDays", days),
    reservationDeadlineMinutes: Number(p("ReservationDeadlineMinutes",
      ts.reservationDeadlineMinutes || 0)),
  };
}

// ════════════════════════════════════════════════════════════════════
// MOTEUR — opérations sur la base
// ════════════════════════════════════════════════════════════════════

async function slotsOfDay(qRef, day, tz) {
  const {start, end} = zone.dayBounds(day, tz);
  const snap = await qRef.collection("slots")
    .where("start", ">=", start).where("start", "<", end).get();
  return snap.docs;
}

async function slotsFrom(qRef, from) {
  const snap = await qRef.collection("slots").where("start", ">=", from).get();
  return snap.docs;
}

/** Génère les créneaux de la plage sur [fromDay, fromDay + 7 j] (jours
 * ouvrés, hors jours bloqués). Renvoie le nombre créé et les jours. */
async function generateForTimeSlot(db, {qRef, tz, timeSlotId, cfg, fromDay,
  queue, now}) {
  if (shouldSkipGeneration(queue.closureStart, queue.closureEnd, now)) {
    return {created: 0, days: []};
  }
  const days = [];
  for (let i = 0; i <= HORIZON_DAYS; i++) {
    const day = zone.addDays(fromDay, i);
    if (cfg.workingDays.includes(zone.weekdayOf(day))) days.push(day);
  }
  const perDay = await Promise.all(days.map((d) => slotsOfDay(qRef, d, tz)));
  const ops = [];
  const touched = [];
  let created = 0;
  days.forEach((day, i) => {
    const existing = perDay[i].map((d) => slotLite(d.data())).filter(Boolean);
    if (activeBlockedDays(existing, timeSlotId, now, tz).has(day)) return;
    const fresh = buildDaySlots({day, tz, cfg, timeSlotId, existing, now});
    for (const s of fresh) {
      const ref = qRef.collection("slots").doc();
      ops.push((b) => b.set(ref, s));
    }
    if (fresh.length) touched.push(day);
    created += fresh.length;
  });
  await commitInBatches(db, ops);
  return {created, days: touched};
}

/** Recalcule les places de chaque jour depuis les vrais créneaux (y compris
 * un jour vidé, remis à zéro). */
async function recountDays(db, qRef, days, tz) {
  const unique = [...new Set(days)];
  const perDay = await Promise.all(unique.map((d) => slotsOfDay(qRef, d, tz)));
  const ops = unique.map((day, i) => {
    let totalSlots = 0;
    let totalCapacity = 0;
    let reserved = 0;
    let cancelled = 0;
    for (const doc of perDay[i]) {
      const s = doc.data();
      totalSlots++;
      totalCapacity += Number(s.capacity || 0);
      reserved += Number(s.reserved || 0);
      cancelled += Number(s.cancelled || 0);
    }
    return (b) => b.set(qRef.collection("dailyStats").doc(day), {
      date: day, totalSlots, totalCapacity,
      available: totalCapacity - reserved, reserved, cancelled,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await commitInBatches(db, ops);
}

const horizonDays = (fromDay, extra = 0) => Array.from(
  {length: HORIZON_DAYS + 2 + extra}, (_, i) => zone.addDays(fromDay, i));

/** Supprime des créneaux SEULEMENT s'ils sont encore vides et ouverts :
 * un client qui réserve au même instant ne perd jamais sa place. */
async function deleteIfStillEmpty(db, docs) {
  let deleted = 0;
  for (let i = 0; i < docs.length; i += 200) {
    const chunk = docs.slice(i, i + 200);
    deleted += await db.runTransaction(async (tx) => {
      const snaps = await tx.getAll(...chunk.map((d) => d.ref));
      let n = 0;
      for (const s of snaps) {
        if (!s.exists) continue;
        if (Number(s.get("reserved") || 0) > 0) continue;
        if (s.get("status") === "blocked") continue;
        tx.delete(s.ref);
        n++;
      }
      return n;
    });
  }
  return deleted;
}

/** Annule les réservations confirmées des créneaux `slotDocs` (source
 * donnée, client prévenu par onReservationCancelledByCompany), puis
 * supprime ces créneaux. */
async function cancelSlotsAndDelete(db, companyId, slotDocs, source, tz) {
  if (!slotDocs.length) return 0;
  const col = companyRef(db, companyId).collection("reservations");
  const resDocs = [];
  const ids = slotDocs.map((d) => d.id);
  for (let i = 0; i < ids.length; i += 30) {
    const snap = await col.where("slotId", "in", ids.slice(i, i + 30))
      .where("status", "==", "confirmed").get();
    resDocs.push(...snap.docs);
  }
  const cancelled = await cancelReservations(db, companyId, resDocs, source,
    tz);
  await commitInBatches(db, slotDocs.map((d) => (b) => b.delete(d.ref)));
  return cancelled;
}

/** Créneaux de la plage `timeSlotId` parmi `docs`, hors jours bloqués. */
function relevantSlots(docs, timeSlotId, now, tz) {
  const lites = docs.map((d) => slotLite(d.data()));
  const blocked = activeBlockedDays(lites, timeSlotId, now, tz);
  return docs.filter((d, i) => lites[i] && lites[i].timeSlotId === timeSlotId &&
    !blocked.has(zone.ymdIn(lites[i].start, tz)));
}

const PENDING_FIELDS = ["StartTime", "EndTime", "ServiceDurationMinutes",
  "CapacityPerSlot", "WorkingDays", "MaxAdvanceDays",
  "ReservationDeadlineMinutes", "EffectiveDate"];

/** Annule une modification programmée pas encore appliquée : la période
 * déjà générée sous la nouvelle config est vidée (réservations annulées et
 * notifiées) puis régénérée sous la config ACTUELLE. */
async function revertPendingChange(db, ctx, tsRef, ts) {
  const {companyId, qRef, tz, queue, now} = ctx;
  const effective = toDate(ts.pendingEffectiveDate);
  if (!effective) return;
  const docs = relevantSlots(await slotsFrom(qRef, effective), tsRef.id, now,
    tz);
  const reserved = docs.filter((d) => Number(d.get("reserved") || 0) > 0);
  await cancelSlotsAndDelete(db, companyId, reserved, "company_edit", tz);
  await deleteIfStillEmpty(db,
    docs.filter((d) => Number(d.get("reserved") || 0) === 0));

  const fromDay = zone.ymdIn(effective, tz);
  await generateForTimeSlot(db, {qRef, tz, timeSlotId: tsRef.id,
    cfg: configOf(ts, queue), fromDay, queue, now});
  const clear = {};
  for (const f of PENDING_FIELDS) clear[`pending${f}`] = FieldValue.delete();
  await tsRef.update(clear);
  await recountDays(db, qRef, horizonDays(fromDay), tz);
}

/** Supprime les créneaux vides futurs de la plage (jamais un créneau
 * bloqué, jamais un jour bloqué). */
async function deleteEmptyFuture(db, ctx, timeSlotId) {
  const {qRef, tz, now} = ctx;
  const todayStart = zone.todayBounds(now, tz).start;
  const docs = relevantSlots(await slotsFrom(qRef, todayStart), timeSlotId,
    now, tz).filter((d) => Number(d.get("reserved") || 0) === 0 &&
    d.get("status") !== "blocked");
  return deleteIfStillEmpty(db, docs);
}

// ── Analyse d'une modification de plage ────────────────────────────
// Créneaux réservés (à partir d'aujourd'hui, hors jours bloqués) qui
// sortiraient des nouveaux horaires ou d'un jour retiré, et le début du
// créneau réservé le plus lointain de la plage.
async function analyzeChange(ctx, timeSlotId, newCfg) {
  const {qRef, tz, now} = ctx;
  const todayStart = zone.todayBounds(now, tz).start;
  const docs = relevantSlots(await slotsFrom(qRef, todayStart), timeSlotId,
    now, tz).filter((d) => Number(d.get("reserved") || 0) > 0);
  const newStart = toMinutes(newCfg.startTime);
  const newEnd = toMinutes(newCfg.endTime);
  const conflicts = [];
  let furthest = null;
  for (const d of docs) {
    const s = toDate(d.get("start"));
    const e = toDate(d.get("end"));
    if (!furthest || s > furthest) furthest = s;
    const ps = zone.partsIn(s, tz);
    const pe = zone.partsIn(e, tz);
    const sMin = ps.hour * 60 + ps.minute;
    // Un créneau qui finit à minuit (lendemain) = 1440.
    const eMin = zone.ymdIn(e, tz) !== zone.ymdIn(s, tz) ?
      1440 : pe.hour * 60 + pe.minute;
    const outsideTime = sMin < newStart || eMin > newEnd;
    const outsideDay = !newCfg.workingDays.includes(ps.weekday);
    if (outsideTime || outsideDay) conflicts.push(d);
  }
  return {conflicts, furthest};
}

/** Clients concernés : Baxa (prévenus) et/ou ajoutés au guichet (pas de
 * compte, pas de notification possible). */
async function originsOf(db, companyId, slotDocs) {
  let baxa = false;
  let manual = false;
  const col = companyRef(db, companyId).collection("reservations");
  const ids = slotDocs.map((d) => d.id);
  for (let i = 0; i < ids.length && !(baxa && manual); i += 30) {
    const snap = await col.where("slotId", "in", ids.slice(i, i + 30))
      .where("status", "==", "confirmed").get();
    for (const r of snap.docs) {
      if (r.get("customerId") === "manual_booking") manual = true;
      else if (r.get("customerId")) baxa = true;
    }
  }
  return {hasBaxaClients: baxa, hasManualClients: manual};
}

/** Date d'effet d'une modification programmée : après la réservation la
 * plus lointaine, et au plus tôt aujourd'hui + anticipation + 1 jour. */
function scheduledEffectiveDay(now, tz, anticipationDays, furthest) {
  const today = zone.ymdIn(now, tz);
  const floor = zone.addDays(today, Number(anticipationDays) + 1);
  if (!furthest) return floor;
  const after = zone.addDays(zone.ymdIn(furthest, tz), 1);
  return after > floor ? after : floor;
}

// ════════════════════════════════════════════════════════════════════
// ACTIONS
// ════════════════════════════════════════════════════════════════════

/** Contexte commun : droits (responsable seul), file, fuseau. */
async function contextFor(db, user, data, now) {
  const companyId = requireString(data, "companyId");
  const queueId = requireString(data, "queueId");
  const access = await companyAccess(db, user.uid, companyId,
    {adminOnly: true});
  const qRef = queueRef(db, companyId, queueId);
  const qSnap = await qRef.get();
  if (!qSnap.exists) throw refuse("queueGone", "Cette file n'existe plus.");
  return {companyId, queueId, qRef, queue: qSnap.data(), tz: access.tz, now};
}

function intIn(data, key, min, max, fallback) {
  const v = data ? data[key] : undefined;
  if (v === undefined || v === null) {
    if (fallback !== undefined) return fallback;
    throw new HttpsError("invalid-argument", `Champ manquant : ${key}.`);
  }
  if (!Number.isInteger(v) || v < min || v > max) {
    throw new HttpsError("invalid-argument", `Valeur invalide : ${key}.`);
  }
  return v;
}

/** Configuration envoyée par le formulaire de plage, vérifiée. */
function configFromForm(data, current) {
  const startTime = requireString(data, "startTime", {max: 5});
  const endTime = requireString(data, "endTime", {max: 5});
  const s = toMinutes(startTime);
  const e = toMinutes(endTime);
  if (s === null || e === null || s >= 1440) {
    throw new HttpsError("invalid-argument", "Heures invalides.");
  }
  if (e <= s) {
    throw refuse("endBeforeStart",
      "L'heure de fin doit être après l'heure de début.");
  }
  const days = data && Array.isArray(data.workingDays) ?
    [...new Set(data.workingDays)] : null;
  if (!days || days.some((d) => !Number.isInteger(d) || d < 1 || d > 7)) {
    throw new HttpsError("invalid-argument", "Jours invalides.");
  }
  return {
    startTime, endTime,
    duration: intIn(data, "duration", 5, 240),
    capacity: intIn(data, "capacity", 1, 100),
    workingDays: days.sort((a, b) => a - b),
    reservationDeadlineMinutes: intIn(data, "reservationDeadlineMinutes", 0,
      1440, current ? current.reservationDeadlineMinutes : 0),
  };
}

/** Chevauchement avec une autre plage de la file (jours en commun). */
async function overlapLabel(ctx, cfg, excludeId) {
  const snap = await ctx.qRef.collection("timeSlots").get();
  const queueDays = ctx.queue.weekdays || DEFAULT_WEEKDAYS;
  const s = toMinutes(cfg.startTime);
  const e = toMinutes(cfg.endTime);
  for (const d of snap.docs) {
    if (d.id === excludeId) continue;
    const t = d.data();
    const days = Array.isArray(t.workingDays) ? t.workingDays : queueDays;
    if (!cfg.workingDays.some((x) => days.includes(x))) continue;
    const ts = toMinutes(t.startTime || "00:00");
    const te = toMinutes(t.endTime || "00:00");
    if (ts === null || te === null) continue;
    if (s < te && ts < e) return `${t.startTime} – ${t.endTime}`;
  }
  return null;
}

function changeKind(orig, cfg) {
  const timing = orig.startTime !== cfg.startTime ||
    orig.endTime !== cfg.endTime || orig.duration !== cfg.duration;
  const removed = orig.workingDays.some((d) => !cfg.workingDays.includes(d));
  const added = cfg.workingDays.some((d) => !orig.workingDays.includes(d));
  const unchanged = !timing && !removed && !added &&
    orig.capacity === cfg.capacity &&
    orig.reservationDeadlineMinutes === cfg.reservationDeadlineMinutes;
  return {hard: timing || removed, needsGeneration: timing || removed || added,
    unchanged};
}

async function loadTimeSlot(ctx, timeSlotId) {
  const ref = ctx.qRef.collection("timeSlots").doc(timeSlotId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw refuse("timeSlotGone", "Cette plage n'existe plus.");
  }
  return {ref, ts: snap.data()};
}

const LOCKED_MESSAGE =
  "Cette plage est en cours de suppression — restituez-la d'abord pour la " +
  "modifier.";

// ── APERÇU D'UNE MODIFICATION DE PLAGE ──────────────────────────────
async function previewTimeSlot(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const timeSlotId = requireString(data, "timeSlotId");
  const {ts} = await loadTimeSlot(ctx, timeSlotId);
  const cfg = configFromForm(data, configOf(ts, ctx.queue));
  const kind = changeKind(configOf(ts, ctx.queue), cfg);
  if (!kind.hard) return {conflictSlots: 0, reservations: 0};
  const {conflicts, furthest} = await analyzeChange(ctx, timeSlotId, cfg);
  if (!conflicts.length) return {conflictSlots: 0, reservations: 0};
  const origins = await originsOf(db, ctx.companyId, conflicts);
  const day = scheduledEffectiveDay(now, ctx.tz,
    ctx.queue.maxAdvanceDays != null ? ctx.queue.maxAdvanceDays : 2, furthest);
  return {
    conflictSlots: conflicts.length,
    reservations: conflicts.reduce((n, d) => n + Number(d.get("reserved")), 0),
    ...origins,
    effectiveDate: zone.dayBounds(day, ctx.tz).start.getTime(),
  };
}

// ── CRÉER / MODIFIER UNE PLAGE ──────────────────────────────────────
// `conflictMode` : « none » (l'aperçu n'a trouvé aucun conflit), « now »
// (appliquer : réservations en conflit annulées et notifiées) ou
// « schedule » (programmer après la dernière réservation).
async function saveTimeSlot(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const {companyId, qRef, tz, queue} = ctx;
  const timeSlotId = data && typeof data.timeSlotId === "string" &&
    data.timeSlotId ? data.timeSlotId : null;
  const mode = ["none", "now", "schedule"].includes(data.conflictMode) ?
    data.conflictMode : "none";
  const today = zone.ymdIn(now, tz);

  // ── Création ──
  if (!timeSlotId) {
    const cfg = configFromForm(data, null);
    const overlap = await overlapLabel(ctx, cfg, null);
    if (overlap) {
      throw refuse("overlap",
        `Chevauchement avec la plage ${overlap}. Ajustez les horaires.`);
    }
    const tsRef = qRef.collection("timeSlots").doc();
    await tsRef.set({
      startTime: cfg.startTime, endTime: cfg.endTime,
      serviceDurationMinutes: cfg.duration, capacityPerSlot: cfg.capacity,
      workingDays: cfg.workingDays,
      reservationDeadlineMinutes: cfg.reservationDeadlineMinutes,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const gen = await generateForTimeSlot(db, {qRef, tz, timeSlotId: tsRef.id,
      cfg, fromDay: today, queue, now});
    await recountDays(db, qRef, gen.days, tz);
    await qRef.update({slotsLastGenerated: FieldValue.serverTimestamp()});
    return {timeSlotId: tsRef.id, created: gen.created, updated: 0,
      cancelled: 0};
  }

  // ── Modification ──
  const {ref: tsRef, ts} = await loadTimeSlot(ctx, timeSlotId);
  if (ts.deleteAfter) throw refuse("timeSlotLocked", LOCKED_MESSAGE);
  const orig = configOf(ts, queue);
  const cfg = configFromForm(data, orig);
  const overlap = await overlapLabel(ctx, cfg, timeSlotId);
  if (overlap) {
    throw refuse("overlap",
      `Chevauchement avec la plage ${overlap}. Ajustez les horaires.`);
  }
  const kind = changeKind(orig, cfg);
  const hasPending = !!ts.pendingEffectiveDate;
  if (kind.unchanged && !hasPending) {
    return {timeSlotId, unchanged: true, created: 0, updated: 0,
      cancelled: 0};
  }

  let conflicts = [];
  let furthest = null;
  if (kind.hard) {
    ({conflicts, furthest} = await analyzeChange(ctx, timeSlotId, cfg));
    if (conflicts.length && mode === "none") {
      throw refuse("conflictsChanged",
        "Des clients viennent de réserver sur cette plage. Vérifiez, puis " +
        "réessayez.");
    }
  }

  // Une modification programmée traîne encore : on repart d'une base
  // propre (enregistrer, même sans changement, l'annule toujours).
  if (hasPending) await revertPendingChange(db, ctx, tsRef, ts);

  // ── Programmer : la config actuelle n'est jamais touchée ──
  if (conflicts.length && mode === "schedule") {
    const day = scheduledEffectiveDay(now, tz,
      queue.maxAdvanceDays != null ? queue.maxAdvanceDays : 2, furthest);
    const effective = zone.dayBounds(day, tz).start;
    const docs = relevantSlots(await slotsFrom(qRef, effective), timeSlotId,
      now, tz);
    const reserved = docs.filter((d) => Number(d.get("reserved") || 0) > 0);
    // Vide par construction (après la dernière réservation) : vérifié
    // plutôt que supposé.
    const cancelled = await cancelSlotsAndDelete(db, companyId, reserved,
      "company_edit", tz);
    await deleteIfStillEmpty(db,
      docs.filter((d) => Number(d.get("reserved") || 0) === 0));
    const gen = await generateForTimeSlot(db, {qRef, tz, timeSlotId, cfg,
      fromDay: day, queue, now});
    await tsRef.update({
      pendingStartTime: cfg.startTime,
      pendingEndTime: cfg.endTime,
      pendingServiceDurationMinutes: cfg.duration,
      pendingCapacityPerSlot: cfg.capacity,
      pendingWorkingDays: cfg.workingDays,
      pendingMaxAdvanceDays: queue.maxAdvanceDays != null ?
        queue.maxAdvanceDays : 2,
      pendingReservationDeadlineMinutes: cfg.reservationDeadlineMinutes,
      pendingEffectiveDate: Timestamp.fromDate(effective),
    });
    await recountDays(db, qRef, horizonDays(day), tz);
    await qRef.update({slotsLastGenerated: FieldValue.serverTimestamp()});
    return {timeSlotId, scheduled: effective.getTime(), created: gen.created,
      updated: 0, cancelled};
  }

  // ── Appliquer maintenant ──
  await tsRef.update({
    startTime: cfg.startTime, endTime: cfg.endTime,
    serviceDurationMinutes: cfg.duration, capacityPerSlot: cfg.capacity,
    workingDays: cfg.workingDays,
    reservationDeadlineMinutes: cfg.reservationDeadlineMinutes,
    updatedAt: FieldValue.serverTimestamp(),
  });
  let cancelled = 0;
  if (kind.hard) {
    await deleteEmptyFuture(db, ctx, timeSlotId);
    cancelled = await cancelSlotsAndDelete(db, companyId, conflicts,
      "company_edit", tz);
  }
  let created = 0;
  if (kind.needsGeneration) {
    created = (await generateForTimeSlot(db, {qRef, tz, timeSlotId, cfg,
      fromDay: today, queue, now})).created;
  }
  const updated = await updateSlotParameters(db, ctx, timeSlotId, cfg);
  await recountDays(db, qRef, horizonDays(today), tz);
  await qRef.update({slotsLastGenerated: FieldValue.serverTimestamp()});
  return {timeSlotId, created, updated, cancelled};
}

/** Capacité, durée et délai sur les créneaux ouverts à venir (8 jours) —
 * jamais une capacité sous le nombre de réservations. Lu et écrit en
 * transaction : une réservation simultanée est prise en compte. */
async function updateSlotParameters(db, ctx, timeSlotId, cfg) {
  const {qRef, tz, now} = ctx;
  const from = zone.todayBounds(now, tz).start;
  const to = zone.dayBounds(zone.addDays(zone.ymdIn(now, tz), 8), tz).start;
  const snap = await qRef.collection("slots").where("start", ">=", from)
    .where("start", "<", to).get();
  const docs = relevantSlots(snap.docs, timeSlotId, now, tz)
    .filter((d) => d.get("status") === "open");
  let updated = 0;
  for (let i = 0; i < docs.length; i += 200) {
    const chunk = docs.slice(i, i + 200);
    updated += await db.runTransaction(async (tx) => {
      const snaps = await tx.getAll(...chunk.map((d) => d.ref));
      let n = 0;
      for (const s of snaps) {
        if (!s.exists || s.get("status") !== "open") continue;
        const reserved = Number(s.get("reserved") || 0);
        tx.update(s.ref, {
          capacity: Math.max(cfg.capacity, reserved),
          duration: cfg.duration,
          reservationDeadlineMinutes: cfg.reservationDeadlineMinutes,
        });
        n++;
      }
      return n;
    });
  }
  return updated;
}

// ── SUPPRESSION D'UNE PLAGE ─────────────────────────────────────────
async function futureReserved(ctx, timeSlotId) {
  const snap = await ctx.qRef.collection("slots")
    .where("start", ">", ctx.now).get();
  return snap.docs.filter((d) => d.get("timeSlotId") === timeSlotId &&
    Number(d.get("reserved") || 0) > 0);
}

function deletionEffectiveDay(ctx, reserved) {
  if (!reserved.length) return zone.addDays(zone.ymdIn(ctx.now, ctx.tz), 1);
  let furthest = toDate(reserved[0].get("start"));
  for (const d of reserved) {
    const s = toDate(d.get("start"));
    if (s > furthest) furthest = s;
  }
  return zone.addDays(zone.ymdIn(furthest, ctx.tz), 1);
}

async function previewDeleteTimeSlot(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const timeSlotId = requireString(data, "timeSlotId");
  const reserved = await futureReserved(ctx, timeSlotId);
  if (!reserved.length) return {reservations: 0};
  const origins = await originsOf(db, ctx.companyId, reserved);
  return {
    reservations: reserved.reduce((n, d) => n + Number(d.get("reserved")), 0),
    ...origins,
    effectiveDate: zone.dayBounds(deletionEffectiveDay(ctx, reserved),
      ctx.tz).start.getTime(),
  };
}

// `mode` : « now » (réservations à venir annulées et notifiées, plage et
// créneaux supprimés) ou « schedule » (plus aucune nouvelle réservation ;
// suppression définitive par la maintenance de nuit après la dernière).
async function deleteTimeSlot(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const {companyId, qRef, tz} = ctx;
  const timeSlotId = requireString(data, "timeSlotId");
  const {ref: tsRef, ts} = await loadTimeSlot(ctx, timeSlotId);
  const today = zone.ymdIn(now, tz);

  if (data.mode === "schedule") {
    if (ts.pendingEffectiveDate) await revertPendingChange(db, ctx, tsRef, ts);
    const reserved = await futureReserved(ctx, timeSlotId);
    const day = deletionEffectiveDay(ctx, reserved);
    await deleteEmptyFuture(db, ctx, timeSlotId);
    const effective = zone.dayBounds(day, tz).start;
    await tsRef.update({
      deleteAfter: Timestamp.fromDate(effective),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await recountDays(db, qRef, horizonDays(today), tz);
    await qRef.update({slotsLastGenerated: FieldValue.serverTimestamp()});
    return {scheduled: effective.getTime(), cancelled: 0};
  }

  const reserved = await futureReserved(ctx, timeSlotId);
  const cancelled = await cancelSlotsAndDelete(db, companyId, reserved,
    "company_delete_timeslot", tz);
  await tsRef.delete();
  // Créneaux restants (passés compris) : par paquets.
  for (;;) {
    const snap = await qRef.collection("slots")
      .where("timeSlotId", "==", timeSlotId).limit(BATCH_LIMIT).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    if (snap.size < BATCH_LIMIT) break;
  }
  await recountDays(db, qRef, horizonDays(today), tz);
  await qRef.update({slotsLastGenerated: FieldValue.serverTimestamp()});
  return {cancelled};
}

// ── RESTITUER UNE PLAGE EN SUPPRESSION PROGRAMMÉE ───────────────────
async function restoreTimeSlot(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const {qRef, tz, queue} = ctx;
  const timeSlotId = requireString(data, "timeSlotId");
  const {ref: tsRef, ts} = await loadTimeSlot(ctx, timeSlotId);
  await tsRef.update({
    deleteAfter: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  // La file avait peut-être une suppression programmée fondée sur « toutes
  // les plages en sursis » : ce n'est plus le cas.
  await qRef.update({deleteAfter: FieldValue.delete()});
  const today = zone.ymdIn(now, tz);
  const gen = await generateForTimeSlot(db, {qRef, tz, timeSlotId,
    cfg: configOf(ts, queue), fromDay: today, queue, now});
  await recountDays(db, qRef, gen.days, tz);
  return {created: gen.created};
}

// ── DURÉE DES CRÉNEAUX DU JOUR (accueil) ────────────────────────────
// Créneaux vides de la plage supprimés puis l'espace libre (autour des
// créneaux réservés) rempli avec la nouvelle durée — jamais dans le passé.
// Tout en une transaction : un client qui réserve au même instant n'est
// jamais rattaché à un créneau supprimé.
async function changeDayDuration(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const {qRef, tz} = ctx;
  const timeSlotId = requireString(data, "timeSlotId");
  const day = requireDay(data, "day");
  const duration = intIn(data, "duration", 5, 240);
  const capacity = intIn(data, "capacity", 1, 100);
  // Ancre horaire : celle de la modification d'origine pour une annulation
  // (« retour » sous 5 min), sinon maintenant.
  const anchorMs = data.anchor;
  const anchor = Number.isFinite(anchorMs) && anchorMs <= now.getTime() &&
    now.getTime() - anchorMs < 15 * MINUTE ? new Date(anchorMs) : now;

  const {ts} = await loadTimeSlot(ctx, timeSlotId);
  if (ts.deleteAfter) throw refuse("timeSlotLocked", LOCKED_MESSAGE);
  const plageStart = zone.zonedTime(day, ts.startTime || "09:00", tz);
  const plageEnd = zone.zonedTime(day, ts.endTime || "17:00", tz);
  const {start: dayStart, end: dayEnd} = zone.dayBounds(day, tz);

  const created = await db.runTransaction(async (tx) => {
    const snap = await tx.get(qRef.collection("slots")
      .where("start", ">=", dayStart).where("start", "<", dayEnd));
    const mine = snap.docs.filter((d) => d.get("timeSlotId") === timeSlotId);
    if (!mine.length) {
      throw refuse("noSlots", "Aucun créneau trouvé pour cette plage.");
    }
    const lites = mine.map((d) => slotLite(d.data()));
    if (lites.some((s) => s.status === "blocked" && s.end > now)) {
      throw refuse("plageBlocked",
        "Cette plage est bloquée aujourd'hui — débloquez-la d'abord pour la " +
        "modifier.");
    }
    const kept = lites.filter((s) => s.reserved > 0);
    const spans = freeIntervals(kept, plageStart, plageEnd);
    const step = duration * MINUTE;
    const rounded = Math.ceil(anchor.getTime() / (5 * MINUTE)) * 5 * MINUTE;
    const fresh = [];
    for (const span of spans) {
      let t = span.start < anchor ? rounded : span.start.getTime();
      while (t + step <= span.end.getTime()) {
        fresh.push({start: new Date(t), end: new Date(t + step)});
        t += step;
      }
    }
    const empties = mine.filter((d, i) => lites[i].reserved === 0);
    if (empties.length + fresh.length > BATCH_LIMIT) {
      throw refuse("tooManySlots",
        "Trop de créneaux à modifier d'un coup pour cette plage.");
    }
    for (const d of empties) tx.delete(d.ref);
    for (const f of fresh) {
      tx.set(qRef.collection("slots").doc(), {
        start: f.start, end: f.end, duration, capacity,
        reserved: 0, cancelled: 0, status: "open", isLegacy: false,
        timeSlotId,
        reservationDeadlineMinutes: Number(ts.reservationDeadlineMinutes || 0),
      });
    }
    return fresh.length;
  });
  await recountDays(db, qRef, [day], tz);
  return {created};
}

// ── CAPACITÉ DES CRÉNEAUX DU JOUR (accueil) ─────────────────────────
// Créneaux ouverts et pas encore terminés ; jamais sous le nombre de
// réservations (un créneau complet garde sa capacité).
async function changeDayCapacity(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const {qRef, tz} = ctx;
  const day = requireDay(data, "day");
  const capacity = intIn(data, "capacity", 1, 100);
  const timeSlotId = data && typeof data.timeSlotId === "string" &&
    data.timeSlotId ? data.timeSlotId : null;
  const {start, end} = zone.dayBounds(day, tz);

  const affected = await db.runTransaction(async (tx) => {
    const snap = await tx.get(qRef.collection("slots")
      .where("start", ">=", start).where("start", "<", end));
    let n = 0;
    for (const d of snap.docs) {
      const s = d.data();
      if (s.status !== "open") continue;
      if (timeSlotId && s.timeSlotId !== timeSlotId) continue;
      const e = toDate(s.end);
      if (e && e <= now) continue;
      tx.update(d.ref, {
        capacity: Math.max(capacity, Number(s.reserved || 0)),
      });
      n++;
    }
    return n;
  });
  // Avant, les places du jour restaient fausses jusqu'à la nuit.
  await recountDays(db, qRef, [day], tz);
  return {affected};
}

// ── RÉGÉNÉRATION D'UNE FILE ENTIÈRE ─────────────────────────────────
async function regenerateQueue(db, companyId, queueId, tz, now) {
  const qRef = queueRef(db, companyId, queueId);
  const qSnap = await qRef.get();
  if (!qSnap.exists) return 0;
  const queue = qSnap.data();
  const tsSnap = await qRef.collection("timeSlots").get();
  const today = zone.ymdIn(now, tz);
  let created = 0;
  const days = [];
  for (const t of tsSnap.docs) {
    const ts = t.data();
    if (ts.deleteAfter) continue; // suppression programmée
    const gen = await generateForTimeSlot(db, {qRef, tz, timeSlotId: t.id,
      cfg: configOf(ts, queue), fromDay: today, queue, now});
    created += gen.created;
    days.push(...gen.days);
  }
  await recountDays(db, qRef, days, tz);
  await qRef.update({slotsLastGenerated: FieldValue.serverTimestamp()});
  return created;
}

// ── ROUVRIR DES FILES ───────────────────────────────────────────────
// Efface la fermeture ; si elle était en cours, les créneaux (dont la
// génération était suspendue) sont recréés tout de suite.
async function reopen(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const queueIds = data && Array.isArray(data.queueIds) ?
    [...new Set(data.queueIds.filter((x) => typeof x === "string" && x))] :
    [];
  if (!queueIds.length || queueIds.length > 20) {
    throw new HttpsError("invalid-argument", "Files invalides.");
  }
  const access = await companyAccess(db, user.uid, companyId,
    {adminOnly: true});
  const refs = queueIds.map((id) => queueRef(db, companyId, id));
  const snaps = await db.getAll(...refs);
  const wasActive = snaps.filter((s) => s.exists && isQueueClosedNow(
    s.get("closureStart"), s.get("closureEnd"), now)).map((s) => s.id);
  await commitInBatches(db, snaps.filter((s) => s.exists).map((s) =>
    (b) => b.update(s.ref, {
      closureStart: FieldValue.delete(),
      closureEnd: FieldValue.delete(),
    })));
  let created = 0;
  for (const id of wasActive) {
    created += await regenerateQueue(db, companyId, id, access.tz, now);
  }
  return {reopened: snaps.filter((s) => s.exists).length,
    wasActive: wasActive.length > 0, created};
}

// ── REVENIR SUR BAXA (annuler un départ) ────────────────────────────
// Fermetures effacées AVANT la suppression de la demande : la fonction
// onCompanyStateChange voit alors encore la demande au moment du
// basculement et ne prévient pas l'équipe (déjà déconnectée). Les
// réservations déjà annulées ne sont pas rétablies.
async function returnToBaxa(db, user, data, now = new Date()) {
  const companyId = requireString(data, "companyId");
  const access = await companyAccess(db, user.uid, companyId,
    {adminOnly: true});
  const queues = await companyRef(db, companyId).collection("queues").get();
  await commitInBatches(db, queues.docs.map((q) => (b) => b.update(q.ref, {
    closureStart: FieldValue.delete(),
    closureEnd: FieldValue.delete(),
  })));
  await db.collection("deletionRequests").doc(companyId).delete();
  let created = 0;
  for (const q of queues.docs) {
    created += await regenerateQueue(db, companyId, q.id, access.tz, now);
  }
  return {created};
}

// ════════════════════════════════════════════════════════════════════
// FILES D'ATTENTE (création, suppression)
// ════════════════════════════════════════════════════════════════════

// MIROIRS de settings_page.dart (`_kAdvanceDaysValues`, `_kDeadlineValues`)
// et de la limite de 5 files (avant : vérifiée par l'app seule).
const MAX_QUEUES = 5;
const ADVANCE_DAYS = [1, 2, 3, 4, 5, 6, 7];
const DEADLINE_MINUTES = [0, 5, 10, 15, 20, 25, 30, 40, 50, 60];

/** Réglages d'une file envoyés par le formulaire, vérifiés. */
function queueSettings(data) {
  const name = requireString(data, "name", {max: 60});
  const advance = data.maxAdvanceDays;
  const delay = data.reservationDeadlineMinutes;
  if (!ADVANCE_DAYS.includes(advance) || !DEADLINE_MINUTES.includes(delay)) {
    throw new HttpsError("invalid-argument", "Réglages invalides.");
  }
  return {
    name,
    maxAdvanceDays: advance,
    reservationDeadlineMinutes: delay,
    allowMultiplePerPlage: data.allowMultiplePerPlage === true,
  };
}

// ── CRÉER UNE FILE (au plus 5) ──────────────────────────────────────
async function createQueue(db, user, data) {
  const companyId = requireString(data, "companyId");
  await companyAccess(db, user.uid, companyId, {adminOnly: true});
  const settings = queueSettings(data);
  const col = companyRef(db, companyId).collection("queues");
  const ref = col.doc();
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(col);
    if (existing.size >= MAX_QUEUES) {
      throw refuse("maxQueues",
        `Maximum ${MAX_QUEUES} files d'attente atteint.`);
    }
    tx.set(ref, {
      ...settings,
      weekdays: DEFAULT_WEEKDAYS,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {queueId: ref.id};
}

// ── SUPPRIMER UNE FILE (coquille vide) ──────────────────────────────
// Seulement sans plage ni réservation à venir. Firestore ne supprime pas
// les sous-collections : on balaie d'éventuels restes avant le document.
async function deleteQueue(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const {companyId, queueId, qRef} = ctx;
  const ts = await qRef.collection("timeSlots").limit(1).get();
  if (!ts.empty) {
    throw refuse("hasTimeSlots",
      "Supprimez d'abord les plages de cette file.");
  }
  const upcoming = await companyRef(db, companyId).collection("reservations")
    .where("queueId", "==", queueId).where("status", "==", "confirmed").get();
  if (upcoming.docs.some((d) => toDate(d.get("slotStart")) > now)) {
    throw refuse("hasReservations",
      "Des réservations sont encore à venir sur cette file.");
  }
  for (const sub of ["slots", "timeSlots", "dailyStats"]) {
    for (;;) {
      const snap = await qRef.collection(sub).limit(BATCH_LIMIT).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      if (snap.size < BATCH_LIMIT) break;
    }
  }
  await qRef.delete();
  return {ok: true};
}

// ── PROGRAMMER / ANNULER LA SUPPRESSION D'UNE FILE ──────────────────
// Possible quand TOUTES ses plages sont en suppression programmée : la
// file partira avec la dernière (maintenance de nuit).
async function scheduleQueueDeletion(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  const snap = await ctx.qRef.collection("timeSlots").get();
  const dates = snap.docs.map((d) => toDate(d.get("deleteAfter")));
  if (!dates.length || dates.some((d) => !d)) {
    throw refuse("notAllDeferred",
      "Toutes les plages doivent d'abord être programmées pour suppression.");
  }
  const last = new Date(Math.max(...dates.map((d) => d.getTime())));
  await ctx.qRef.update({deleteAfter: Timestamp.fromDate(last)});
  return {deleteAfter: last.getTime()};
}

async function restoreQueueDeletion(db, user, data, now = new Date()) {
  const ctx = await contextFor(db, user, data, now);
  await ctx.qRef.update({deleteAfter: FieldValue.delete()});
  return {ok: true};
}

// ── Point d'entrée ──────────────────────────────────────────────────
const ACTIONS = {
  previewTimeSlot, saveTimeSlot, previewDeleteTimeSlot, deleteTimeSlot,
  restoreTimeSlot, changeDayDuration, changeDayCapacity, reopen,
  returnToBaxa, createQueue, deleteQueue, scheduleQueueDeletion,
  restoreQueueDeletion,
};

const companySchedule = onCall({region: REGION, timeoutSeconds: 120},
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
    const user = {uid: request.auth.uid};
    return handler(admin.firestore(), user, request.data);
  });

module.exports = {
  companySchedule,
  // Exposés pour les tests et la génération de nuit.
  ...ACTIONS,
  toMinutes, freeIntervals, shouldSkipGeneration, activeBlockedDays,
  buildDaySlots, mostFrequent, configOf, scheduledEffectiveDay,
  generateForTimeSlot, recountDays, slotLite, HORIZON_DAYS, MAX_QUEUES,
};
