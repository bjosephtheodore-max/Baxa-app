// ============================================================
// TESTS DES PLAGES ET CRÉNEAUX (functions/company_schedule.js)
// Exécutés contre l'ÉMULATEUR Firestore local (données fictives).
// Lancer avec : node test/firestore_rules/run.mjs
//
// Fuseau des tests : Africa/Dakar (= UTC), pour des heures lisibles.
// ============================================================
import {describe, it, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";

const require = createRequire(new URL("../../functions/", import.meta.url));
const admin = require("firebase-admin");
const sc = require("./company_schedule.js");
const zone = require("./zone.js");

const PROJECT = "demo-baxa-rules";
const HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const TZ = "Africa/Dakar";
const ADMIN = {uid: "compA"};
const STAFF = {uid: "staff1"};

let db;
const MIN = 60 * 1000;
// « Maintenant » fixe : un lundi à 07:00 (avant toute plage du jour).
const now = new Date(Date.UTC(2030, 0, 7, 7, 0)); // lundi 7 janvier 2030
const TODAY = "2030-01-07";
const day = (n) => zone.addDays(TODAY, n);
const at = (d, hm) => zone.zonedTime(d, hm, TZ);

const A = "companies/compA";
const Q = `${A}/queues/q1`;
const doc = (p) => db.doc(p);
const read = async (p) => (await doc(p).get()).data();

async function slotsOf(d, ts = null) {
  const {start, end} = zone.dayBounds(d, TZ);
  const snap = await db.collection(`${Q}/slots`)
    .where("start", ">=", start).where("start", "<", end).get();
  return snap.docs
    .filter((x) => !ts || x.get("timeSlotId") === ts)
    .map((x) => ({id: x.id, ...x.data(),
      start: x.get("start").toDate(), end: x.get("end").toDate()}))
    .sort((a, b) => a.start - b.start);
}

async function putSlot(id, d, hm, {minutes = 30, ts = "t1", reserved = 0,
  capacity = 2, status = "open"} = {}) {
  const start = at(d, hm);
  await doc(`${Q}/slots/${id}`).set({
    start, end: new Date(start.getTime() + minutes * MIN), timeSlotId: ts,
    reserved, capacity, cancelled: 0, status, duration: minutes,
  });
}

async function putResa(id, slotId, d, hm, {minutes = 30, customerId = "cust1",
  status = "confirmed"} = {}) {
  const start = at(d, hm);
  await doc(`${A}/reservations/${id}`).set({
    companyId: "compA", queueId: "q1", slotId, customerId, status,
    slotStart: start, slotEnd: new Date(start.getTime() + minutes * MIN),
    source: customerId === "manual_booking" ? "company_manual" : "app",
  });
}

const form = (extra = {}) => ({
  companyId: "compA", queueId: "q1", startTime: "09:00", endTime: "10:00",
  duration: 30, capacity: 2, workingDays: [1, 2, 3, 4, 5], ...extra,
});

async function expectRefused(promise, reason) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.details && e.details.reason, reason,
      `motif attendu « ${reason} », reçu « ${e.details && e.details.reason} » ` +
      `(${e.message})`);
    return true;
  });
}

before(() => {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
  db = admin.firestore();
});

beforeEach(async () => {
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}` +
    "/databases/(default)/documents", {method: "DELETE"});
  await Promise.all([
    doc(A).set({nom: "Salon A", timeZone: TZ}),
    doc(Q).set({name: "Coiffure", maxAdvanceDays: 2}),
    doc("users/staff1").set({role: "staff", companyId: "compA"}),
    doc(`${A}/staff/staff1`).set({isActive: true}),
  ]);
});

// ============================================================
describe("Moteur (fonctions pures)", () => {
  it("heures « HH:mm », minuit en fin de plage", () => {
    assert.equal(sc.toMinutes("09:30"), 570);
    assert.equal(sc.toMinutes("24:00"), 1440);
    assert.equal(sc.toMinutes("24:30"), null);
    assert.equal(sc.toMinutes("9:30"), null);
  });

  it("espaces libres autour des créneaux conservés", () => {
    const d = (h) => at(TODAY, h);
    const free = sc.freeIntervals([{start: d("10:00"), end: d("10:30")}],
      d("09:00"), d("12:00"));
    assert.deepEqual(free.map((s) => [s.start, s.end]),
      [[d("09:00"), d("10:00")], [d("10:30"), d("12:00")]]);
  });

  it("plage finissant à 24:00 : le dernier créneau finit à minuit", () => {
    const slots = sc.buildDaySlots({day: day(1), tz: TZ, timeSlotId: "t",
      cfg: {startTime: "23:00", endTime: "24:00", duration: 30, capacity: 1},
      existing: [], now});
    assert.equal(slots.length, 2);
    assert.equal(slots[1].end.getTime(), at(day(2), "00:00").getTime());
  });

  it("aujourd'hui : aucun créneau déjà commencé", () => {
    const at8 = at(TODAY, "08:10");
    const slots = sc.buildDaySlots({day: TODAY, tz: TZ, timeSlotId: "t",
      cfg: {startTime: "08:00", endTime: "09:00", duration: 15, capacity: 1},
      existing: [], now: at8});
    assert.deepEqual(slots.map((s) => s.start.getTime()),
      [at(TODAY, "08:15"), at(TODAY, "08:30"), at(TODAY, "08:45")]
        .map((x) => x.getTime()));
  });

  it("créneau créé avec le délai de réservation de la plage", () => {
    const [s] = sc.buildDaySlots({day: day(1), tz: TZ, timeSlotId: "t",
      cfg: {startTime: "09:00", endTime: "09:30", duration: 30, capacity: 3,
        reservationDeadlineMinutes: 20}, existing: [], now});
    assert.equal(s.reservationDeadlineMinutes, 20);
    assert.equal(s.capacity, 3);
    assert.equal(s.timeSlotId, "t");
  });

  it("fermeture : suspendue, sauf 48 h avant une réouverture datée", () => {
    const h = 3600 * 1000;
    assert.equal(sc.shouldSkipGeneration(new Date(now - h), null, now), true);
    assert.equal(sc.shouldSkipGeneration(new Date(now - h),
      new Date(now.getTime() + 24 * h), now), false);
    assert.equal(sc.shouldSkipGeneration(new Date(now - h),
      new Date(now.getTime() + 72 * h), now), true);
  });

  it("date d'effet : après la dernière réservation, au plus tôt J+anticipation+1",
    () => {
      assert.equal(sc.scheduledEffectiveDay(now, TZ, 2, null), day(3));
      assert.equal(sc.scheduledEffectiveDay(now, TZ, 2, at(day(5), "10:00")),
        day(6));
    });
});

// ============================================================
describe("Créer une plage", () => {
  it("crée la plage, ses créneaux sur 8 jours ouvrés et les places",
    async () => {
      const res = await sc.saveTimeSlot(db, ADMIN, form(), now);
      assert.ok(res.timeSlotId);
      const ts = await read(`${Q}/timeSlots/${res.timeSlotId}`);
      assert.equal(ts.startTime, "09:00");
      assert.equal(ts.capacityPerSlot, 2);
      // Lun 7 → lun 14 : 6 jours ouvrés (lun–ven + lun), 2 créneaux chacun.
      assert.equal(res.created, 12);
      assert.equal((await slotsOf(TODAY)).length, 2);
      assert.equal((await slotsOf(day(5))).length, 0, "samedi : rien");
      const st = await read(`${Q}/dailyStats/${TODAY}`);
      assert.equal(st.totalSlots, 2);
      assert.equal(st.totalCapacity, 4);
      assert.equal(st.available, 4);
      assert.ok((await read(Q)).slotsLastGenerated);
    });

  it("chevauchement avec une autre plage : refusé", async () => {
    await doc(`${Q}/timeSlots/t0`).set({startTime: "09:30",
      endTime: "11:00", workingDays: [1]});
    await expectRefused(sc.saveTimeSlot(db, ADMIN, form(), now), "overlap");
  });

  it("autres jours que la plage existante : accepté", async () => {
    await doc(`${Q}/timeSlots/t0`).set({startTime: "09:30",
      endTime: "11:00", workingDays: [6]});
    await sc.saveTimeSlot(db, ADMIN, form(), now);
  });

  it("fin avant le début : refusé", () => expectRefused(
    sc.saveTimeSlot(db, ADMIN, form({endTime: "08:00"}), now),
    "endBeforeStart"));

  it("file fermée : plage créée, aucun créneau", async () => {
    await doc(Q).update({closureStart: new Date(now - 3600 * 1000)});
    const res = await sc.saveTimeSlot(db, ADMIN, form(), now);
    assert.equal(res.created, 0);
  });

  it("un membre de l'équipe ne peut pas créer de plage", () =>
    assert.rejects(sc.saveTimeSlot(db, STAFF, form(), now),
      (e) => e.code === "permission-denied"));
});

// ============================================================
describe("Modifier une plage", () => {
  async function existing() {
    await doc(`${Q}/timeSlots/t1`).set({startTime: "09:00", endTime: "10:00",
      serviceDurationMinutes: 30, capacityPerSlot: 2,
      workingDays: [1, 2, 3, 4, 5], reservationDeadlineMinutes: 0});
  }

  it("capacité seule : créneaux ouverts mis à jour, jamais sous les réservés",
    async () => {
      await existing();
      await putSlot("a", day(1), "09:00", {reserved: 2});
      await putSlot("b", day(1), "09:30");
      const res = await sc.saveTimeSlot(db, ADMIN,
        form({timeSlotId: "t1", capacity: 1}), now);
      assert.equal(res.updated, 2);
      assert.equal((await read(`${Q}/slots/a`)).capacity, 2);
      assert.equal((await read(`${Q}/slots/b`)).capacity, 1);
    });

  it("aucun changement : rien n'est écrit", async () => {
    await existing();
    const res = await sc.saveTimeSlot(db, ADMIN, form({timeSlotId: "t1"}),
      now);
    assert.equal(res.unchanged, true);
  });

  it("horaires changés sans réservation : créneaux refaits", async () => {
    await existing();
    await putSlot("a", day(1), "09:00");
    await putSlot("b", day(1), "09:30");
    await sc.saveTimeSlot(db, ADMIN,
      form({timeSlotId: "t1", endTime: "11:00"}), now);
    const s = await slotsOf(day(1), "t1");
    assert.equal(s.length, 4);
    assert.equal(s[3].start.getTime(), at(day(1), "10:30").getTime());
  });

  it("aperçu : réservation hors des nouveaux horaires = conflit", async () => {
    await existing();
    await putSlot("a", day(1), "09:30", {reserved: 1});
    await putResa("r1", "a", day(1), "09:30");
    const p = await sc.previewTimeSlot(db, ADMIN,
      form({timeSlotId: "t1", endTime: "09:30"}), now);
    assert.equal(p.conflictSlots, 1);
    assert.equal(p.reservations, 1);
    assert.equal(p.hasBaxaClients, true);
    assert.equal(p.hasManualClients, false);
    assert.equal(p.effectiveDate, zone.dayBounds(day(3), TZ).start.getTime());
  });

  it("conflit apparu depuis l'aperçu : refus, rien n'est modifié", async () => {
    await existing();
    await putSlot("a", day(1), "09:30", {reserved: 1});
    await putResa("r1", "a", day(1), "09:30");
    await expectRefused(sc.saveTimeSlot(db, ADMIN,
      form({timeSlotId: "t1", endTime: "09:30", conflictMode: "none"}), now),
    "conflictsChanged");
    assert.equal((await read(`${Q}/timeSlots/t1`)).endTime, "10:00");
  });

  it("appliquer maintenant : réservation en conflit annulée, créneau retiré",
    async () => {
      await existing();
      await putSlot("a", day(1), "09:30", {reserved: 1});
      await putResa("r1", "a", day(1), "09:30");
      const res = await sc.saveTimeSlot(db, ADMIN,
        form({timeSlotId: "t1", endTime: "09:30", conflictMode: "now"}), now);
      assert.equal(res.cancelled, 1);
      const r1 = await read(`${A}/reservations/r1`);
      assert.equal(r1.status, "cancelled");
      assert.equal(r1.cancellationSource, "company_edit");
      assert.equal((await doc(`${Q}/slots/a`).get()).exists, false);
      assert.equal((await read(`${Q}/timeSlots/t1`)).endTime, "09:30");
    });

  it("programmer : config actuelle gardée, nouvelle config en attente",
    async () => {
      await existing();
      await putSlot("a", day(1), "09:30", {reserved: 1});
      await putResa("r1", "a", day(1), "09:30");
      const res = await sc.saveTimeSlot(db, ADMIN, form({timeSlotId: "t1",
        endTime: "09:30", conflictMode: "schedule"}), now);
      const eff = zone.dayBounds(day(3), TZ).start.getTime();
      assert.equal(res.scheduled, eff);
      const ts = await read(`${Q}/timeSlots/t1`);
      assert.equal(ts.endTime, "10:00", "config actuelle intacte");
      assert.equal(ts.pendingEndTime, "09:30");
      assert.equal(ts.pendingEffectiveDate.toDate().getTime(), eff);
      assert.equal((await read(`${A}/reservations/r1`)).status, "confirmed");
      // Mercredi (J+2) : avant la date d'effet, rien n'est touché ; jeudi
      // (J+3) : un seul créneau de 30 min sous la nouvelle config.
      assert.equal((await slotsOf(day(3), "t1")).length, 1);
    });

  it("enregistrer une plage programmée : la programmation est annulée",
    async () => {
      await existing();
      await doc(`${Q}/timeSlots/t1`).update({pendingStartTime: "09:00",
        pendingEndTime: "09:30", pendingEffectiveDate: at(day(3), "00:00")});
      await putSlot("p", day(3), "09:00");
      await sc.saveTimeSlot(db, ADMIN, form({timeSlotId: "t1"}), now);
      const ts = await read(`${Q}/timeSlots/t1`);
      assert.equal("pendingEndTime" in ts, false);
      assert.equal((await slotsOf(day(3), "t1")).length, 2,
        "jour régénéré sous la config actuelle");
    });

  it("jour bloqué : jamais touché par la modification", async () => {
    await existing();
    await putSlot("blk", day(1), "09:00", {status: "blocked"});
    await sc.saveTimeSlot(db, ADMIN,
      form({timeSlotId: "t1", endTime: "11:00"}), now);
    const s = await slotsOf(day(1), "t1");
    assert.deepEqual(s.map((x) => x.id), ["blk"]);
  });

  it("plage en suppression programmée : refusée", async () => {
    await existing();
    await doc(`${Q}/timeSlots/t1`).update({deleteAfter: at(day(5), "00:00")});
    await expectRefused(sc.saveTimeSlot(db, ADMIN,
      form({timeSlotId: "t1", capacity: 3}), now), "timeSlotLocked");
  });
});

// ============================================================
describe("Supprimer / restituer une plage", () => {
  beforeEach(async () => {
    await doc(`${Q}/timeSlots/t1`).set({startTime: "09:00", endTime: "10:00",
      serviceDurationMinutes: 30, capacityPerSlot: 2,
      workingDays: [1, 2, 3, 4, 5]});
  });

  it("aperçu : réservations à venir et date d'effet", async () => {
    await putSlot("a", day(4), "09:00", {reserved: 2});
    await putResa("r1", "a", day(4), "09:00", {customerId: "manual_booking"});
    const p = await sc.previewDeleteTimeSlot(db, ADMIN,
      {companyId: "compA", queueId: "q1", timeSlotId: "t1"}, now);
    assert.equal(p.reservations, 2);
    assert.equal(p.hasManualClients, true);
    assert.equal(p.effectiveDate, zone.dayBounds(day(5), TZ).start.getTime());
  });

  it("supprimer maintenant : annulations, plage et créneaux supprimés",
    async () => {
      await putSlot("a", day(1), "09:00", {reserved: 1});
      await putSlot("b", day(1), "09:30");
      await putResa("r1", "a", day(1), "09:00");
      const res = await sc.deleteTimeSlot(db, ADMIN, {companyId: "compA",
        queueId: "q1", timeSlotId: "t1", mode: "now"}, now);
      assert.equal(res.cancelled, 1);
      assert.equal((await read(`${A}/reservations/r1`)).cancellationSource,
        "company_delete_timeslot");
      assert.equal((await doc(`${Q}/timeSlots/t1`).get()).exists, false);
      assert.equal((await slotsOf(day(1))).length, 0);
      assert.equal((await read(`${Q}/dailyStats/${day(1)}`)).totalSlots, 0);
    });

  it("programmer : vides retirés, réservés gardés, marqueur posé", async () => {
    await putSlot("a", day(1), "09:00", {reserved: 1});
    await putSlot("b", day(1), "09:30");
    const res = await sc.deleteTimeSlot(db, ADMIN, {companyId: "compA",
      queueId: "q1", timeSlotId: "t1", mode: "schedule"}, now);
    assert.equal(res.scheduled, zone.dayBounds(day(2), TZ).start.getTime());
    assert.deepEqual((await slotsOf(day(1))).map((s) => s.id), ["a"]);
    assert.ok((await read(`${Q}/timeSlots/t1`)).deleteAfter);
  });

  it("restituer : marqueurs levés, créneaux recréés", async () => {
    await doc(`${Q}/timeSlots/t1`).update({deleteAfter: at(day(3), "00:00")});
    await doc(Q).update({deleteAfter: at(day(3), "00:00")});
    const res = await sc.restoreTimeSlot(db, ADMIN,
      {companyId: "compA", queueId: "q1", timeSlotId: "t1"}, now);
    assert.equal(res.created, 12);
    assert.equal("deleteAfter" in (await read(`${Q}/timeSlots/t1`)), false);
    assert.equal("deleteAfter" in (await read(Q)), false);
  });
});

// ============================================================
describe("Accueil : durée et capacité du jour", () => {
  beforeEach(async () => {
    await doc(`${Q}/timeSlots/t1`).set({startTime: "09:00", endTime: "10:00",
      serviceDurationMinutes: 30, capacityPerSlot: 2,
      workingDays: [1, 2, 3, 4, 5], reservationDeadlineMinutes: 10});
  });
  const change = (extra = {}) => sc.changeDayDuration(db, ADMIN, {
    companyId: "compA", queueId: "q1", timeSlotId: "t1", day: day(1),
    duration: 20, capacity: 2, ...extra}, now);

  it("vides remplacés, réservés gardés, espaces libres remplis", async () => {
    await putSlot("a", day(1), "09:00", {reserved: 1});
    await putSlot("b", day(1), "09:30");
    const res = await change();
    assert.equal(res.created, 1); // 09:30–09:50 (09:50–10:10 dépasse)
    const s = await slotsOf(day(1), "t1");
    assert.deepEqual(s.map((x) => [x.start.getTime(), x.end.getTime()]), [
      [at(day(1), "09:00").getTime(), at(day(1), "09:30").getTime()],
      [at(day(1), "09:30").getTime(), at(day(1), "09:50").getTime()],
    ]);
    assert.equal(s[1].reservationDeadlineMinutes, 10);
    assert.equal((await read(`${Q}/dailyStats/${day(1)}`)).totalSlots, 2);
  });

  it("plage bloquée ce jour : refusé", async () => {
    await putSlot("a", day(1), "09:00", {status: "blocked"});
    await expectRefused(change(), "plageBlocked");
  });

  it("aucun créneau ce jour : refusé", () =>
    expectRefused(change(), "noSlots"));

  it("capacité du jour : créneaux ouverts à venir, jamais sous les réservés",
    async () => {
      await putSlot("a", day(1), "09:00", {reserved: 3, capacity: 3});
      await putSlot("b", day(1), "09:30");
      await putSlot("c", day(1), "09:30", {ts: "t2", status: "blocked"});
      const res = await sc.changeDayCapacity(db, ADMIN, {companyId: "compA",
        queueId: "q1", day: day(1), capacity: 1, timeSlotId: "t1"}, now);
      assert.equal(res.affected, 2);
      assert.equal((await read(`${Q}/slots/a`)).capacity, 3);
      assert.equal((await read(`${Q}/slots/b`)).capacity, 1);
      assert.equal((await read(`${Q}/dailyStats/${day(1)}`)).totalCapacity,
        3 + 1 + 2);
    });
});

// ============================================================
describe("Files : création et suppression", () => {
  const settings = (extra = {}) => ({companyId: "compA", name: "Barbe",
    maxAdvanceDays: 2, reservationDeadlineMinutes: 0,
    allowMultiplePerPlage: false, ...extra});

  it("crée une file avec ses réglages et les jours par défaut", async () => {
    const {queueId} = await sc.createQueue(db, ADMIN, settings());
    const q = await read(`${A}/queues/${queueId}`);
    assert.equal(q.name, "Barbe");
    assert.deepEqual(q.weekdays, [1, 2, 3, 4, 5]);
    assert.equal(q.allowMultiplePerPlage, false);
    assert.ok(q.createdAt);
  });

  it("au plus 5 files", async () => {
    for (let i = 2; i <= 5; i++) {
      await doc(`${A}/queues/q${i}`).set({name: `F${i}`});
    }
    await expectRefused(sc.createQueue(db, ADMIN, settings()), "maxQueues");
  });

  it("réglages hors liste : refusés", () => assert.rejects(
    sc.createQueue(db, ADMIN, settings({maxAdvanceDays: 30})),
    (e) => e.code === "invalid-argument"));

  it("un membre ne crée pas de file", () => assert.rejects(
    sc.createQueue(db, STAFF, settings()),
    (e) => e.code === "permission-denied"));

  it("supprime une file vide et ses restes", async () => {
    await putSlot("old", day(-3), "09:00");
    await doc(`${Q}/dailyStats/${day(-3)}`).set({totalSlots: 1});
    await sc.deleteQueue(db, ADMIN, {companyId: "compA", queueId: "q1"}, now);
    assert.equal((await doc(Q).get()).exists, false);
    assert.equal((await doc(`${Q}/slots/old`).get()).exists, false);
    assert.equal((await doc(`${Q}/dailyStats/${day(-3)}`).get()).exists,
      false);
  });

  it("refuse tant qu'il reste une plage", async () => {
    await doc(`${Q}/timeSlots/t1`).set({startTime: "09:00"});
    await expectRefused(sc.deleteQueue(db, ADMIN,
      {companyId: "compA", queueId: "q1"}, now), "hasTimeSlots");
  });

  it("refuse tant qu'une réservation est à venir", async () => {
    await putResa("r1", "s1", day(1), "09:00");
    await expectRefused(sc.deleteQueue(db, ADMIN,
      {companyId: "compA", queueId: "q1"}, now), "hasReservations");
  });

  it("programmer : seulement si toutes les plages partent, à la dernière date",
    async () => {
      await doc(`${Q}/timeSlots/t1`).set({deleteAfter: at(day(3), "00:00")});
      await doc(`${Q}/timeSlots/t2`).set({startTime: "14:00"});
      const ids = {companyId: "compA", queueId: "q1"};
      await expectRefused(sc.scheduleQueueDeletion(db, ADMIN, ids, now),
        "notAllDeferred");
      await doc(`${Q}/timeSlots/t2`).set({deleteAfter: at(day(5), "00:00")});
      const res = await sc.scheduleQueueDeletion(db, ADMIN, ids, now);
      assert.equal(res.deleteAfter, at(day(5), "00:00").getTime());
      await sc.restoreQueueDeletion(db, ADMIN, ids, now);
      assert.equal("deleteAfter" in (await read(Q)), false);
    });
});

// ============================================================
describe("Rouvrir / revenir sur Baxa", () => {
  beforeEach(async () => {
    await doc(`${Q}/timeSlots/t1`).set({startTime: "09:00", endTime: "10:00",
      serviceDurationMinutes: 30, capacityPerSlot: 2,
      workingDays: [1, 2, 3, 4, 5]});
  });

  it("rouvrir une file fermée : fermeture effacée, créneaux recréés",
    async () => {
      await doc(Q).update({closureStart: new Date(now - 3600 * 1000)});
      const res = await sc.reopen(db, ADMIN,
        {companyId: "compA", queueIds: ["q1"]}, now);
      assert.equal(res.wasActive, true);
      assert.equal(res.created, 12);
      assert.equal("closureStart" in (await read(Q)), false);
    });

  it("annuler une fermeture programmée : rien à régénérer", async () => {
    await doc(Q).update({closureStart: at(day(10), "00:00")});
    const res = await sc.reopen(db, ADMIN,
      {companyId: "compA", queueIds: ["q1"]}, now);
    assert.equal(res.wasActive, false);
    assert.equal(res.created, 0);
  });

  it("revenir sur Baxa : demande supprimée, files rouvertes, créneaux",
    async () => {
      await doc(Q).update({closureStart: new Date(now - 3600 * 1000)});
      await doc("deletionRequests/compA").set({status: "scheduled"});
      const res = await sc.returnToBaxa(db, ADMIN, {companyId: "compA"}, now);
      assert.equal(res.created, 12);
      assert.equal((await doc("deletionRequests/compA").get()).exists, false);
      assert.equal("closureStart" in (await read(Q)), false);
    });
});
