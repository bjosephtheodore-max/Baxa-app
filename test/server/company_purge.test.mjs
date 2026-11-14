// ============================================================
// TESTS DE LA SUPPRESSION COMPLÈTE D'UNE STRUCTURE (functions/company_purge.js)
// Exécutés contre l'ÉMULATEUR Firestore local (données fictives).
// Lancer avec : node test/firestore_rules/run.mjs
// La suppression du compte de connexion est simulée.
// ============================================================
import {describe, it, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";

const require = createRequire(new URL("../../functions/", import.meta.url));
const admin = require("firebase-admin");
const purge = require("./company_purge.js");

const PROJECT = "demo-baxa-rules";
const HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const C = "compGone";
const now = new Date();
const MIN = 60 * 1000;

let db;
const deletedAuth = [];
const opts = {
  now,
  deleteAuthUser: async (uid) => {
    deletedAuth.push(uid);
  },
};

const doc = (path) => db.doc(path);
const exists = async (path) => (await doc(path).get()).exists;
const read = async (path) => (await doc(path).get()).data();

before(() => {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
  db = admin.firestore();
});

beforeEach(async () => {
  deletedAuth.length = 0;
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}` +
    "/databases/(default)/documents", {method: "DELETE"});
});

/** Une structure complète, comme en production. */
async function seedCompany() {
  const q = `companies/${C}/queues/q1`;
  await Promise.all([
    doc(`companies/${C}`).set({
      nom: "Pharmacie Zali", email: "zali@mail.sn", type: "Pharmacie",
      ville: "Ziguinchor", timeZone: "Africa/Dakar",
    }),
    doc(q).set({name: "Comptoir"}),
    doc(`${q}/timeSlots/t1`).set({startTime: "09:00"}),
    doc(`${q}/slots/s1`).set({reserved: 1}),
    doc(`${q}/dailyStats/2026-11-20`).set({reserved: 1}),
    doc(`companies/${C}/reservations/upcoming`).set({
      customerId: "cust1", status: "confirmed", queueName: "Comptoir",
      slotStart: new Date(now.getTime() + 60 * MIN),
    }),
    doc(`companies/${C}/reservations/past`).set({
      customerId: "cust2", status: "confirmed",
      slotStart: new Date(now.getTime() - 60 * MIN),
    }),
    doc(`companies/${C}/staff/staff1`).set({
      nom: "Moussa", phone: "+221770000000", isActive: false,
      revokedReason: "company_leaving",
    }),
    doc(`companies/${C}/invitations/i1`).set({code: "ABC123"}),
    doc(`companies/${C}/companyNotifications/n1`).set({type: "day_digest"}),
    doc(`companies/${C}/ticketCounters/2026-11-20`).set({next: 4}),
    doc(`companyWake/${C}`).set({events: []}),
    doc(`deletionRequests/${C}`).set({
      companyId: C, companyName: "Pharmacie Zali", email: "zali@mail.sn",
      phone: "+221770000001", reason: "Fermeture", status: "approved",
    }),
    doc("adminAlerts/a1").set({
      type: "deletion_request", companyId: C, companyName: "Pharmacie Zali",
      email: "zali@mail.sn", phone: "+221770000001", reason: "Fermeture",
      status: "unread",
    }),
    doc("adminAlerts/other").set({companyId: "autre", email: "x@y.sn"}),
    doc("users/staff1").set({role: "staff", companyId: C}),
    doc("companies/autre").set({nom: "Autre structure"}),
  ]);
}

describe("Supprimer complètement une structure", () => {
  it("efface la fiche, tout son contenu, le réveil et le compte", async () => {
    await seedCompany();
    const {cancelled} = await purge.purgeCompany(db, C, opts);
    assert.equal(cancelled, 1);

    for (const p of [
      `companies/${C}`, `companies/${C}/queues/q1`,
      `companies/${C}/queues/q1/timeSlots/t1`,
      `companies/${C}/queues/q1/slots/s1`,
      `companies/${C}/queues/q1/dailyStats/2026-11-20`,
      `companies/${C}/reservations/upcoming`,
      `companies/${C}/reservations/past`,
      `companies/${C}/staff/staff1`, `companies/${C}/invitations/i1`,
      `companies/${C}/companyNotifications/n1`,
      `companies/${C}/ticketCounters/2026-11-20`, `companyWake/${C}`,
    ]) {
      assert.equal(await exists(p), false, p);
    }
    assert.deepEqual(deletedAuth, [C]);
  });

  it("prévient le client attendu, pas celui déjà passé", async () => {
    await seedCompany();
    await purge.purgeCompany(db, C, opts);
    const n1 = await db.collection("customers/cust1/notifications").get();
    const n2 = await db.collection("customers/cust2/notifications").get();
    assert.equal(n1.size, 1);
    assert.match(n1.docs[0].get("body"), /n'est plus disponible sur Baxa/);
    assert.equal(n2.size, 0);
  });

  it("ne garde que des traces sans donnée personnelle", async () => {
    await seedCompany();
    await purge.purgeCompany(db, C, opts);

    const req = await read(`deletionRequests/${C}`);
    assert.deepEqual(Object.keys(req).sort(), ["completedAt", "status"]);
    assert.equal(req.status, "completed");

    const alert = await read("adminAlerts/a1");
    assert.equal(alert.reason, "Fermeture");
    assert.equal(alert.email, undefined);
    assert.equal(alert.phone, undefined);
    assert.equal(alert.companyName, undefined);
  });

  it("ne touche ni aux autres structures ni au compte des membres",
    async () => {
      await seedCompany();
      await purge.purgeCompany(db, C, opts);
      assert.equal(await exists("companies/autre"), true);
      assert.equal((await read("adminAlerts/other")).email, "x@y.sn");
      // Le membre garde son compte (il pourra rejoindre une autre équipe) ;
      // l'app lui affiche « l'établissement quitte Baxa ».
      assert.equal(await exists("users/staff1"), true);
    });

  it("efface aussi un ancien profil client sur le même compte", async () => {
    await seedCompany();
    await doc(`users/${C}`).set({role: "customer", prenom: "Awa"});
    await doc(`users/${C}/favorites/x`).set({nom: "X"});
    await doc(`customers/${C}/notifications/n`).set({title: "x"});
    await purge.purgeCompany(db, C, opts);
    for (const p of [`users/${C}`, `users/${C}/favorites/x`,
      `customers/${C}/notifications/n`]) {
      assert.equal(await exists(p), false, p);
    }
  });

  it("rejouable : un 2e passage ne casse rien", async () => {
    await seedCompany();
    await purge.purgeCompany(db, C, opts);
    const again = await purge.purgeCompany(db, C, opts);
    assert.equal(again.cancelled, 0);
    assert.equal(await exists(`companies/${C}`), false);
    assert.equal((await read(`deletionRequests/${C}`)).status, "completed");
  });
});

describe("Rattrapage de nuit", () => {
  it("trouve les fiches fantômes et les suppressions en erreur", async () => {
    await Promise.all([
      doc("companies/ghost").set({nom: "Ancienne", status: "deleted",
        email: "old@mail.sn"}),
      doc("deletionRequests/failed").set({status: "error"}),
      doc("deletionRequests/waiting").set({status: "scheduled"}),
      doc("companies/alive").set({nom: "Vivante"}),
    ]);
    const ids = (await purge.purgeBacklog(db)).sort();
    assert.deepEqual(ids, ["failed", "ghost"]);
  });

  it("une fiche fantôme d'avant est entièrement effacée", async () => {
    await doc("companies/ghost").set({nom: "Ancienne", status: "deleted",
      email: "old@mail.sn"});
    await doc("companies/ghost/staff/s").set({nom: "Ancien membre"});
    await doc("deletionRequests/ghost").set({status: "completed",
      email: "old@mail.sn", reason: "x"});
    await purge.purgeCompany(db, "ghost", opts);
    assert.equal(await exists("companies/ghost"), false);
    assert.equal(await exists("companies/ghost/staff/s"), false);
    assert.equal((await read("deletionRequests/ghost")).email, undefined);
    assert.deepEqual(deletedAuth, ["ghost"]);
  });
});
