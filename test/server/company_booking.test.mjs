// ============================================================
// TESTS DES RÉSERVATIONS GÉRÉES PAR LA STRUCTURE
// (functions/company_booking.js) — sur l'ÉMULATEUR Firestore local.
// Lancer avec : node test/firestore_rules/run.mjs
// ============================================================
import {describe, it, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";

const require = createRequire(new URL("../../functions/", import.meta.url));
const admin = require("firebase-admin");
const cb = require("./company_booking.js");

const PROJECT = "demo-baxa-rules";
const HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

const ADMIN = {uid: "compA", email: "admin@salon.sn"};
const STAFF = {uid: "staff1", email: null};
const STAFF_2 = {uid: "staff3", email: null};
const STAFF_OUT = {uid: "staff2", email: null};
const CLIENT = {uid: "cust1", email: "client@mail.com"};
const ADMIN_B = {uid: "compB", email: null};

let db;
const now = new Date();
const MIN = 60 * 1000;
const at = (base, minutes) => new Date(base.getTime() + minutes * MIN);
// Demain 10h (UTC = heure de Dakar) et son jour « AAAA-MM-JJ ».
const tomorrow10 = (() => {
  const d = new Date(now.getTime() + 24 * 60 * MIN);
  d.setUTCHours(10, 0, 0, 0);
  return d;
})();
const ymd = (d) => d.toISOString().slice(0, 10);
const TOMORROW = ymd(tomorrow10);

const A = "companies/compA";
const Q = `${A}/queues/q1`;
const doc = (path) => db.doc(path);
const read = async (path) => (await doc(path).get()).data();
const stats = (date = tomorrow10) => `${Q}/dailyStats/${ymd(date)}`;

async function slot(id, start, {capacity = 2, reserved = 0, minutes = 30,
  status = "open", ts = "t1"} = {}) {
  await doc(`${Q}/slots/${id}`).set({
    start, end: at(start, minutes), capacity, reserved, cancelled: 0,
    status, timeSlotId: ts,
  });
}

async function resa(id, {slotId = "s1", start = tomorrow10, minutes = 30,
  status = "confirmed", source = "app", customerId = "cust1",
  createdBy, queueId = "q1", suspended} = {}) {
  await doc(`${A}/reservations/${id}`).set({
    companyId: "compA", queueId, slotId, customerId, source, status,
    slotStart: start, slotEnd: at(start, minutes),
    ...(createdBy ? {createdBy} : {}),
    ...(suspended ? {suspended: true} : {}),
  });
}

async function expectRefused(promise, reason) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.details && e.details.reason, reason,
      `motif attendu « ${reason} », reçu « ${e.details && e.details.reason} » ` +
      `(${e.message})`);
    return true;
  });
}

async function expectDenied(promise) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.code, "permission-denied", e.message);
    return true;
  });
}

const add = (user, slotId, extra = {}) => cb.addManual(db, user,
  {companyId: "compA", queueId: "q1", slotId, clientName: "Awa", ...extra},
  now);

before(() => {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
  db = admin.firestore();
});

beforeEach(async () => {
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}` +
    "/databases/(default)/documents", {method: "DELETE"});
  await Promise.all([
    doc(A).set({nom: "Salon A", timeZone: "Africa/Dakar"}),
    doc("companies/compB").set({nom: "Salon B"}),
    doc(Q).set({name: "Coiffure"}),
    doc(`${A}/queues/q2`).set({name: "Barbe"}),
    doc(`${Q}/timeSlots/t1`).set({startTime: "09:00", endTime: "12:00"}),
    doc("users/staff1").set({role: "staff", companyId: "compA"}),
    doc("users/staff2").set({role: "staff", companyId: "compA"}),
    doc("users/staff3").set({role: "staff", companyId: "compA"}),
    doc("users/cust1").set({role: "customer"}),
    doc(`${A}/staff/staff1`).set({isActive: true, displayName: "Moussa"}),
    doc(`${A}/staff/staff2`).set({isActive: false, displayName: "Ancien"}),
    doc(`${A}/staff/staff3`).set({isActive: true, displayName: "Fatou"}),
    doc(stats()).set({reserved: 0, available: 10}),
  ]);
});

// ============================================================
describe("Inscrire un client au guichet", () => {
  it("crée l'inscription et met à jour tous les compteurs", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await add(ADMIN, "s1");
    const r = await read(`${A}/reservations/${reservationId}`);
    assert.equal(r.customerId, "manual_booking");
    assert.equal(r.customerName, "Awa");
    assert.equal(r.source, "company_manual");
    assert.equal(r.status, "confirmed");
    assert.equal(r.queueName, "Coiffure");
    assert.equal(r.timeSlotId, "t1");
    assert.equal(r.createdBy, "compA");
    assert.equal(r.createdByRole, "admin");
    assert.equal("createdByName" in r, false);
    assert.equal((await read(`${Q}/slots/s1`)).reserved, 1);
    const st = await read(stats());
    assert.equal(st.reserved, 1);
    assert.equal(st.available, 9, "une place libre de moins");
  });

  it("un membre actif inscrit, avec son nom", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await add(STAFF, "s1");
    const r = await read(`${A}/reservations/${reservationId}`);
    assert.equal(r.createdBy, "staff1");
    assert.equal(r.createdByRole, "staff");
    assert.equal(r.createdByName, "Moussa");
  });

  it("créneau complet : refusé", async () => {
    await slot("s1", tomorrow10, {capacity: 1, reserved: 1});
    await expectRefused(add(ADMIN, "s1"), "slotFull");
  });

  it("deux inscriptions simultanées sur la dernière place : une seule passe",
    async () => {
      await slot("s1", tomorrow10, {capacity: 1});
      const results = await Promise.allSettled([
        add(ADMIN, "s1"), add(STAFF, "s1"),
      ]);
      assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
      assert.equal((await read(`${Q}/slots/s1`)).reserved, 1);
    });

  it("nouvelle tentative avec le même identifiant : pas de doublon",
    async () => {
      await slot("s1", tomorrow10);
      const first = await add(ADMIN, "s1", {requestId: "abcdefghij12345"});
      const second = await add(ADMIN, "s1", {requestId: "abcdefghij12345"});
      assert.equal(first.reservationId, "abcdefghij12345");
      assert.equal(second.alreadyDone, true);
      assert.equal((await read(`${Q}/slots/s1`)).reserved, 1);
    });

  it("créneau bloqué : refusé", async () => {
    await slot("s1", tomorrow10, {status: "blocked"});
    await expectRefused(add(ADMIN, "s1"), "slotBlocked");
  });

  it("créneau terminé : refusé", async () => {
    await slot("s1", at(now, -60), {minutes: 30});
    await expectRefused(add(ADMIN, "s1"), "slotEnded");
  });

  it("file fermée : refusé", async () => {
    await slot("s1", tomorrow10);
    await doc(Q).update({closureStart: at(now, -60)});
    await expectRefused(add(ADMIN, "s1"), "queueClosed");
  });

  it("fermeture programmée sur ce jour : refusé", async () => {
    await slot("s1", tomorrow10);
    await doc(Q).update({closureStart: at(tomorrow10, -120)});
    await expectRefused(add(ADMIN, "s1"), "closedOnDay");
  });

  it("plage en suppression programmée : refusé", async () => {
    await slot("s1", tomorrow10);
    await doc(`${Q}/timeSlots/t1`).update({deleteAfter: tomorrow10});
    await expectRefused(add(ADMIN, "s1"), "timeSlotClosing");
  });

  it("créneau disparu : refusé", () =>
    expectRefused(add(ADMIN, "absent"), "slotGone"));

  it("un membre retiré ne peut plus inscrire", async () => {
    await slot("s1", tomorrow10);
    await expectDenied(add(STAFF_OUT, "s1"));
  });

  it("un client ne peut pas inscrire", async () => {
    await slot("s1", tomorrow10);
    await expectDenied(add(CLIENT, "s1"));
  });

  it("l'admin d'une autre structure ne peut pas inscrire", async () => {
    await slot("s1", tomorrow10);
    await expectDenied(add(ADMIN_B, "s1"));
  });

  it("nom du client manquant : refusé", async () => {
    await slot("s1", tomorrow10);
    await assert.rejects(add(ADMIN, "s1", {clientName: "  "}),
      (e) => e.code === "invalid-argument");
  });
});

// ============================================================
describe("Retirer une inscription manuelle", () => {
  const remove = (user, id) => cb.removeManual(db, user,
    {companyId: "compA", reservationId: id});

  it("supprime et rend la place", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await add(ADMIN, "s1");
    await remove(ADMIN, reservationId);
    assert.equal((await doc(`${A}/reservations/${reservationId}`).get()).exists,
      false);
    assert.equal((await read(`${Q}/slots/s1`)).reserved, 0);
    const st = await read(stats());
    assert.equal(st.reserved, 0);
    assert.equal(st.available, 10, "ajout puis retrait : aucune dérive");
  });

  it("deux retraits : la place n'est rendue qu'une fois", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await add(ADMIN, "s1");
    await remove(ADMIN, reservationId);
    const again = await remove(ADMIN, reservationId);
    assert.equal(again.alreadyDone, true);
    assert.equal((await read(`${Q}/slots/s1`)).reserved, 0);
  });

  it("un membre retire les siennes", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await add(STAFF, "s1");
    await remove(STAFF, reservationId);
  });

  it("un membre ne retire pas celles d'un autre", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await add(STAFF_2, "s1");
    await expectDenied(remove(STAFF, reservationId));
  });

  it("l'admin retire celles d'un membre", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await add(STAFF, "s1");
    await remove(ADMIN, reservationId);
  });

  it("une réservation client ne se retire pas ainsi", async () => {
    await slot("s1", tomorrow10, {reserved: 1});
    await resa("r1");
    await expectRefused(remove(ADMIN, "r1"), "notManual");
  });

  it("inscription déjà annulée : supprimée sans toucher aux compteurs",
    async () => {
      await slot("s1", tomorrow10, {reserved: 0});
      await resa("m1", {source: "company_manual", status: "cancelled",
        createdBy: "compA"});
      await remove(ADMIN, "m1");
      assert.equal((await read(`${Q}/slots/s1`)).reserved, 0);
    });
});

// ============================================================
describe("Bloquer / débloquer", () => {
  const blockIt = (user, extra = {}) => cb.block(db, user,
    {companyId: "compA", queueId: "q1", day: TOMORROW, reason: "Panne",
      ...extra}, now);
  const unblockIt = (user, nowAt = now, day = TOMORROW) => cb.unblock(db,
    user, {companyId: "compA", queueId: "q1", day}, nowAt);

  it("bloque les créneaux du jour et suspend leurs réservations",
    async () => {
      await slot("s1", tomorrow10, {reserved: 1});
      await slot("s2", at(tomorrow10, 30));
      await resa("r1");
      const res = await blockIt(ADMIN);
      assert.deepEqual(res, {blocked: 2, suspended: 1});
      const s1 = await read(`${Q}/slots/s1`);
      assert.equal(s1.status, "blocked");
      assert.equal(s1.blockReason, "Panne");
      const r1 = await read(`${A}/reservations/r1`);
      assert.equal(r1.suspended, true);
      assert.equal(r1.suspendedReason, "Panne");
      assert.equal(r1.status, "confirmed");
    });

  it("une seule plage si demandé", async () => {
    await slot("s1", tomorrow10);
    await slot("s2", at(tomorrow10, 30), {ts: "t2"});
    await blockIt(ADMIN, {timeSlotId: "t1"});
    assert.equal((await read(`${Q}/slots/s2`)).status, "open");
  });

  it("créneau déjà bloqué : garde sa raison d'origine", async () => {
    await slot("s1", tomorrow10, {status: "blocked"});
    await doc(`${Q}/slots/s1`).update({blockReason: "Avant"});
    await slot("s2", at(tomorrow10, 30));
    await blockIt(ADMIN);
    assert.equal((await read(`${Q}/slots/s1`)).blockReason, "Avant");
  });

  it("rien à bloquer : refus clair", () =>
    expectRefused(blockIt(ADMIN), "nothingToBlock"));

  it("raison trop longue : coupée pour la notification", async () => {
    await slot("s1", tomorrow10);
    await blockIt(ADMIN, {reason: "x".repeat(200)});
    assert.equal((await read(`${Q}/slots/s1`)).blockReason.length, 118);
  });

  it("un membre ne peut pas bloquer", async () => {
    await slot("s1", tomorrow10);
    await expectDenied(blockIt(STAFF));
  });

  it("débloque : créneaux rouverts, réservations rétablies", async () => {
    await slot("s1", tomorrow10, {reserved: 1});
    await resa("r1");
    await blockIt(ADMIN);
    const res = await unblockIt(ADMIN);
    assert.deepEqual(res, {unblocked: 1, restored: 1, cancelled: 0});
    assert.equal((await read(`${Q}/slots/s1`)).status, "open");
    const r1 = await read(`${A}/reservations/r1`);
    assert.equal("suspended" in r1, false);
    assert.equal(r1.status, "confirmed");
  });

  it("créneau passé pendant le blocage : annulé, compteurs corrigés",
    async () => {
      await slot("s1", tomorrow10, {reserved: 1});
      await resa("r1");
      await blockIt(ADMIN);
      const later = at(tomorrow10, 120); // le créneau de 10h est passé
      const res = await unblockIt(ADMIN, later);
      assert.equal(res.cancelled, 1);
      const r1 = await read(`${A}/reservations/r1`);
      assert.equal(r1.status, "cancelled");
      assert.equal(r1.cancellationSource, "company_block_unresolved");
      assert.equal("suspended" in r1, false);
      const s1 = await read(`${Q}/slots/s1`);
      assert.equal(s1.reserved, 0);
      assert.equal(s1.cancelled, 1);
      assert.equal(s1.status, "blocked", "un créneau passé reste marqué");
    });
});

// ============================================================
describe("Fermer des files", () => {
  const closeIt = (user, extra = {}) => cb.close(db, user, {
    companyId: "compA", queueIds: ["q1"], start: at(tomorrow10, -600).getTime(),
    end: null, cancelCaught: false, ...extra,
  }, now);

  it("pose la fermeture sans toucher aux réservations", async () => {
    await slot("s1", tomorrow10, {reserved: 1});
    await resa("r1");
    const res = await closeIt(ADMIN);
    assert.equal(res.cancelled, 0);
    const q = await read(Q);
    assert.ok(q.closureStart);
    assert.equal("closureEnd" in q, false);
    assert.equal((await read(`${A}/reservations/r1`)).status, "confirmed");
  });

  it("annule seulement les réservations prises dans la période", async () => {
    await slot("s1", tomorrow10, {reserved: 1});
    await slot("s9", at(tomorrow10, 3 * 24 * 60), {reserved: 1});
    await resa("r1");
    await resa("r9", {slotId: "s9", start: at(tomorrow10, 3 * 24 * 60)});
    await resa("rq2", {queueId: "q2"});
    const res = await closeIt(ADMIN, {
      end: at(tomorrow10, 24 * 60).getTime(), cancelCaught: true,
    });
    assert.equal(res.cancelled, 1);
    const r1 = await read(`${A}/reservations/r1`);
    assert.equal(r1.status, "cancelled");
    assert.equal(r1.cancellationSource, "company_closure");
    assert.equal((await read(`${A}/reservations/r9`)).status, "confirmed");
    assert.equal((await read(`${A}/reservations/rq2`)).status, "confirmed");
    const s1 = await read(`${Q}/slots/s1`);
    assert.equal(s1.reserved, 0);
    assert.equal(s1.cancelled, 1);
    const st = await read(stats());
    assert.equal(st.available, 11);
  });

  it("une file déjà fermée : rien n'est modifié", async () => {
    await doc(Q).update({closureStart: at(now, 60)});
    await expectRefused(closeIt(ADMIN), "alreadyClosed");
  });

  it("« Stopper » remplace une fermeture existante", async () => {
    await doc(Q).update({closureStart: at(now, 60 * 24 * 5),
      closureEnd: at(now, 60 * 24 * 6)});
    await closeIt(ADMIN, {start: now.getTime(), replaceExisting: true});
    assert.equal("closureEnd" in (await read(Q)), false);
  });

  it("fin avant le début : refusé", () => assert.rejects(closeIt(ADMIN, {
    start: tomorrow10.getTime(), end: at(tomorrow10, -60).getTime(),
  }), (e) => e.code === "invalid-argument"));

  it("un membre ne peut pas fermer", () => expectDenied(closeIt(STAFF)));
});

// ============================================================
describe("Quitter Baxa", () => {
  it("demande + fermeture de toutes les files + annulations à venir",
    async () => {
      await slot("s1", tomorrow10, {reserved: 1});
      await resa("r1");
      await resa("rPast", {start: at(now, -120)});
      const res = await cb.leave(db, ADMIN,
        {companyId: "compA", reason: "Je ferme"}, now);
      assert.equal(res.cancelled, 1);

      const dr = await read("deletionRequests/compA");
      assert.equal(dr.status, "scheduled");
      assert.equal(dr.companyName, "Salon A");
      assert.equal(dr.reason, "Je ferme");
      assert.equal(dr.requestedBy, "compA");
      assert.equal(dr.email, "admin@salon.sn");
      const days = (dr.executeAfter.toDate() - now) / (24 * 60 * MIN);
      assert.equal(Math.round(days), cb.LEAVE_GRACE_DAYS);

      for (const q of [Q, `${A}/queues/q2`]) {
        assert.ok((await read(q)).closureStart, `${q} fermée`);
      }
      assert.equal((await read(`${A}/reservations/r1`)).status, "cancelled");
      assert.equal((await read(`${A}/reservations/rPast`)).status,
        "confirmed", "le passé n'est pas touché");
    });

  it("un membre ne peut pas faire partir la structure", () =>
    expectDenied(cb.leave(db, STAFF, {companyId: "compA"}, now)));
});
