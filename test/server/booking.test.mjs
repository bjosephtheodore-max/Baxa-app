// ============================================================
// TESTS DE LA FONCTION SERVEUR DE RÉSERVATION (functions/booking.js)
// Exécutés contre l'ÉMULATEUR Firestore local (données fictives).
// Lancer avec : node test/firestore_rules/run.mjs
// ============================================================
import {describe, it, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";

// Modules chargés depuis functions/ (mêmes dépendances que le serveur).
const require = createRequire(new URL("../../functions/", import.meta.url));
const admin = require("firebase-admin");
const booking = require("./booking.js");

const PROJECT = "demo-baxa-rules";
const HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const CLIENT = {uid: "cust1", email: "client1@mail.com"};
const CLIENT_2 = {uid: "cust2", email: null};

let db;
const now = new Date();
const MIN = 60 * 1000;
const tomorrow10 = (() => {
  const d = new Date(now.getTime() + 24 * 60 * MIN);
  d.setUTCHours(10, 0, 0, 0);
  return d;
})();
const at = (base, minutes) => new Date(base.getTime() + minutes * MIN);

const Q = (c = "compA", q = "q1") => `companies/${c}/queues/${q}`;
const doc = (path) => db.doc(path);
const read = async (path) => (await doc(path).get()).data();
const statsPath = (date, c = "compA", q = "q1") =>
  `${Q(c, q)}/dailyStats/${booking.ymd(date)}`;

async function slot(id, start, {capacity = 2, reserved = 0, minutes = 30,
  c = "compA", q = "q1", ts = "t1", deadline = 0} = {}) {
  await doc(`${Q(c, q)}/slots/${id}`).set({
    start: start, end: at(start, minutes), capacity, reserved,
    cancelled: 0, status: "open", timeSlotId: ts,
    reservationDeadlineMinutes: deadline,
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

const reserve = (user, slotId, extra = {}) => booking.reserve(db, user,
  {companyId: "compA", queueId: "q1", slotId, ...extra}, now);

before(() => {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
  db = admin.firestore();
});

beforeEach(async () => {
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}` +
    "/databases/(default)/documents", {method: "DELETE"});
  await Promise.all([
    doc(Q()).set({nom: "Coiffure"}),
    doc(Q("compA", "q2")).set({nom: "Barbe"}),
    doc(Q("compB")).set({nom: "Ailleurs"}),
    doc(`${Q()}/timeSlots/t1`).set({startTime: "09:00"}),
    doc("users/cust1").set({prenom: "Awa", nom: "Diop"}),
    doc(statsPath(tomorrow10)).set({reserved: 0, available: 10}),
  ]);
});

// ============================================================
describe("Réserver", () => {
  it("crée la réservation et met à jour tous les compteurs", async () => {
    await slot("s1", tomorrow10);
    const {reservationId} = await reserve(CLIENT, "s1",
      {companyName: "Salon A", queueName: "Coiffure"});

    const r = await read(`companies/compA/reservations/${reservationId}`);
    assert.equal(r.customerId, "cust1");
    assert.equal(r.customerName, "Awa Diop");
    assert.equal(r.customerEmail, "client1@mail.com");
    assert.equal(r.status, "confirmed");
    assert.equal(r.timeSlotId, "t1");
    assert.equal(r.slotId, "s1");
    assert.equal(r.companyName, "Salon A");
    assert.equal(r.slotStart.toDate().getTime(), tomorrow10.getTime());

    assert.equal((await read(`${Q()}/slots/s1`)).reserved, 1);
    const stats = await read(statsPath(tomorrow10));
    assert.equal(stats.reserved, 1);
    assert.equal(stats.available, 9);
    const u = await read("users/cust1");
    assert.equal(u.dailyBookingCount, 1);
    assert.equal(u.lastBookingDate, booking.ymd(now));
  });

  it("crée les places du jour si elles manquent (ancien bug 9)", async () => {
    const day = at(tomorrow10, 24 * 60);
    await slot("s1", day);
    await reserve(CLIENT, "s1");
    assert.equal((await read(statsPath(day))).reserved, 1);
  });

  it("créneau complet → refusé", async () => {
    await slot("s1", tomorrow10, {capacity: 1, reserved: 1});
    await expectRefused(reserve(CLIENT, "s1"), "slotFull");
  });

  it("dernière place disputée : un seul des deux clients l'obtient",
    async () => {
      await slot("s1", tomorrow10, {capacity: 1});
      const results = await Promise.allSettled([
        reserve(CLIENT, "s1"), reserve(CLIENT_2, "s1"),
      ]);
      assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
      assert.equal((await read(`${Q()}/slots/s1`)).reserved, 1);
    });

  it("file fermée → refusé", async () => {
    await doc(Q()).set({closureStart: at(now, -60)}, {merge: true});
    await slot("s1", tomorrow10);
    await expectRefused(reserve(CLIENT, "s1"), "queueClosed");
  });

  it("plage en cours de suppression → refusé", async () => {
    await doc(`${Q()}/timeSlots/t1`).set({deleteAfter: now}, {merge: true});
    await slot("s1", tomorrow10);
    await expectRefused(reserve(CLIENT, "s1"), "timeSlotClosing");
  });

  it("créneau déjà commencé → refusé", async () => {
    await slot("s1", at(now, -5));
    await expectRefused(reserve(CLIENT, "s1"), "slotAlreadyStarted");
  });

  it("trop tard (délai minimum de la file) → refusé", async () => {
    await slot("s1", at(now, 30), {deadline: 60});
    await expectRefused(reserve(CLIENT, "s1"), "tooLate");
  });

  it("trop loin dans le temps → refusé", async () => {
    await doc(Q()).set({maxAdvanceDays: 1}, {merge: true});
    await slot("s1", at(tomorrow10, 3 * 24 * 60));
    await expectRefused(reserve(CLIENT, "s1"), "tooFarInAdvance");
  });
});

// ============================================================
describe("Quota de réservations par jour", () => {
  it(`limite de ${booking.MAX_DAILY_RESERVATIONS} atteinte → refusé`,
    async () => {
      await doc("users/cust1").set({
        dailyBookingCount: booking.MAX_DAILY_RESERVATIONS,
        lastBookingDate: booking.ymd(now),
      }, {merge: true});
      await slot("s1", tomorrow10);
      await expectRefused(reserve(CLIENT, "s1"), "globalLimitReached");
    });

  it("le compteur d'hier ne compte plus", async () => {
    await doc("users/cust1").set({
      dailyBookingCount: booking.MAX_DAILY_RESERVATIONS,
      lastBookingDate: booking.ymd(at(now, -24 * 60)),
    }, {merge: true});
    await slot("s1", tomorrow10);
    await reserve(CLIENT, "s1");
    assert.equal((await read("users/cust1")).dailyBookingCount, 1);
  });
});

// ============================================================
describe("Écarts entre rendez-vous", () => {
  async function existing(c, q, start, ts = "t1") {
    await doc(`companies/${c}/reservations/old`).set({
      customerId: "cust1", status: "confirmed", companyId: c, queueId: q,
      timeSlotId: ts, slotId: "x", slotStart: start,
      slotEnd: at(start, 30),
    });
  }

  it("autre entreprise, 20 min après → refusé", async () => {
    await existing("compB", "q1", tomorrow10);
    await slot("s1", at(tomorrow10, 50));
    await expectRefused(reserve(CLIENT, "s1"), "gapDifferentCompany");
  });

  it("autre entreprise, 30 min après → autorisé", async () => {
    await existing("compB", "q1", tomorrow10);
    await slot("s1", at(tomorrow10, 60));
    await reserve(CLIENT, "s1");
  });

  it("même entreprise, autre file, horaires qui se chevauchent → refusé",
    async () => {
      await existing("compA", "q2", tomorrow10);
      await slot("s1", at(tomorrow10, 15));
      await expectRefused(reserve(CLIENT, "s1"), "overlapInSameCompany");
    });

  it("même file, réservation active → refusé", async () => {
    await existing("compA", "q1", tomorrow10);
    await slot("s1", at(tomorrow10, 180));
    await expectRefused(reserve(CLIENT, "s1"), "activeInSameQueue");
  });

  it("réglage « plusieurs par jour » : autre plage → autorisé", async () => {
    await doc(Q()).set({allowMultiplePerPlage: true}, {merge: true});
    await existing("compA", "q1", tomorrow10, "t1");
    await slot("s1", at(tomorrow10, 240), {ts: "t2"});
    await reserve(CLIENT, "s1");
  });

  it("un créneau terminé à l'instant ne bloque pas (règle des 5 min " +
    "supprimée)", async () => {
    await existing("compA", "q1", at(now, -32));
    await slot("s1", tomorrow10);
    await reserve(CLIENT, "s1");
  });
});

// ============================================================
describe("Annuler", () => {
  async function booked() {
    await slot("s1", tomorrow10);
    return (await reserve(CLIENT, "s1")).reservationId;
  }
  const cancel = (user, id, source) => booking.cancel(db, user,
    {companyId: "compA", reservationId: id, source});

  it("annule et libère la place", async () => {
    const id = await booked();
    await cancel(CLIENT, id, "notification");
    const r = await read(`companies/compA/reservations/${id}`);
    assert.equal(r.status, "cancelled");
    assert.equal(r.cancellationSource, "notification");
    const s = await read(`${Q()}/slots/s1`);
    assert.equal(s.reserved, 0);
    assert.equal(s.cancelled, 1);
    const stats = await read(statsPath(tomorrow10));
    assert.equal(stats.reserved, 0);
    assert.equal(stats.available, 10);
    assert.equal(stats.cancelled, 1);
  });

  it("annuler deux fois ne libère pas deux places", async () => {
    const id = await booked();
    await cancel(CLIENT, id);
    await expectRefused(cancel(CLIENT, id), "notActive");
    assert.equal((await read(`${Q()}/slots/s1`)).reserved, 0);
  });

  it("l'annulation ne rend pas de quota", async () => {
    const id = await booked();
    await cancel(CLIENT, id);
    assert.equal((await read("users/cust1")).dailyBookingCount, 1);
  });

  it("impossible d'annuler la réservation d'un autre", async () => {
    const id = await booked();
    await assert.rejects(cancel(CLIENT_2, id), /introuvable/);
    assert.equal(
      (await read(`companies/compA/reservations/${id}`)).status, "confirmed");
  });
});

// ============================================================
describe("Remplacer", () => {
  const replace = (user, oldId, slotId) => booking.replace(db, user, {
    oldCompanyId: "compA", oldReservationId: oldId,
    companyId: "compA", queueId: "q1", slotId,
  }, now);

  it("annule l'ancienne, crée la nouvelle, compteurs justes", async () => {
    await slot("s1", tomorrow10);
    await slot("s2", at(tomorrow10, 120));
    const oldId = (await reserve(CLIENT, "s1")).reservationId;
    const {reservationId} = await replace(CLIENT, oldId, "s2");

    assert.equal(
      (await read(`companies/compA/reservations/${oldId}`)).status,
      "cancelled");
    const r = await read(`companies/compA/reservations/${reservationId}`);
    assert.equal(r.status, "confirmed");
    assert.equal(r.replacedReservationId, oldId);
    assert.equal((await read(`${Q()}/slots/s1`)).reserved, 0);
    assert.equal((await read(`${Q()}/slots/s2`)).reserved, 1);
    const stats = await read(statsPath(tomorrow10));
    assert.equal(stats.reserved, 1);
    assert.equal(stats.available, 9);
  });

  it("vers un autre jour : les places des DEUX jours sont justes",
    async () => {
      const nextDay = at(tomorrow10, 24 * 60);
      await doc(statsPath(nextDay)).set({reserved: 0, available: 10});
      await slot("s1", tomorrow10);
      await slot("s2", nextDay);
      const oldId = (await reserve(CLIENT, "s1")).reservationId;
      await replace(CLIENT, oldId, "s2");
      assert.equal((await read(statsPath(tomorrow10))).available, 10);
      assert.equal((await read(statsPath(nextDay))).available, 9);
    });

  it("un remplacement ne consomme pas de quota", async () => {
    await slot("s1", tomorrow10);
    await slot("s2", at(tomorrow10, 120));
    const oldId = (await reserve(CLIENT, "s1")).reservationId;
    await replace(CLIENT, oldId, "s2");
    assert.equal((await read("users/cust1")).dailyBookingCount, 1);
  });

  it("impossible de remplacer la réservation d'un autre", async () => {
    await slot("s1", tomorrow10);
    await slot("s2", at(tomorrow10, 120));
    const oldId = (await reserve(CLIENT, "s1")).reservationId;
    await assert.rejects(replace(CLIENT_2, oldId, "s2"), /introuvable/);
  });

  it("remplacer par le même créneau → refusé", async () => {
    await slot("s1", tomorrow10);
    const oldId = (await reserve(CLIENT, "s1")).reservationId;
    await expectRefused(replace(CLIENT, oldId, "s1"), "sameSlot");
  });
});
