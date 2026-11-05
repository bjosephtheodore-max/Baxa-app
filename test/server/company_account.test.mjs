// ============================================================
// TESTS DU COMPTE STRUCTURE (functions/company_account.js)
// Exécutés contre l'ÉMULATEUR Firestore local (données fictives).
// Lancer avec : node test/firestore_rules/run.mjs
//
// L'authentification est simulée (FakeAuth) : on vérifie l'étiquette
// `role: "company"` posée sur le compte sans émulateur Auth.
// ============================================================
import {describe, it, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";

const require = createRequire(new URL("../../functions/", import.meta.url));
const admin = require("firebase-admin");
const account = require("./company_account.js");

const PROJECT = "demo-baxa-rules";
const HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

let db;

class FakeAuth {
  constructor() {
    this.claims = new Map();
  }
  async getUser(uid) {
    return {uid, customClaims: this.claims.get(uid) || null};
  }
  async setCustomUserClaims(uid, claims) {
    this.claims.set(uid, claims);
  }
}

const NEW = {uid: "newco", email: "contact@salon.sn", provider: "password"};
const FORM = {
  nom: "  Salon Awa  ", type: "Coiffure", typeCategorie: "Commerce",
  ville: "Thiès", country: "SN", language: "fr", locale: "fr_SN",
  timeZone: "Africa/Dakar",
};

const read = async (path) => (await db.doc(path).get()).data();

async function expectRefused(promise, reason) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.details && e.details.reason, reason,
      `motif attendu « ${reason} », reçu « ${e.details && e.details.reason} » ` +
      `(${e.message})`);
    return true;
  });
}

async function expectInvalid(promise) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.code, "invalid-argument", e.message);
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
});

// ============================================================
describe("Créer une structure", () => {
  it("crée la fiche avec les champs du formulaire et pose l'étiquette",
    async () => {
      const auth = new FakeAuth();
      const res = await account.create(db, auth, NEW, FORM);
      assert.deepEqual(res, {role: "company", created: true});

      const c = await read("companies/newco");
      assert.equal(c.nom, "Salon Awa"); // espaces retirés
      assert.equal(c.type, "Coiffure");
      assert.equal(c.typeCategorie, "Commerce");
      assert.equal(c.ville, "Thiès");
      assert.equal(c.country, "SN");
      assert.equal(c.language, "fr");
      assert.equal(c.locale, "fr_SN");
      assert.equal(c.timeZone, "Africa/Dakar");
      assert.equal(c.email, "contact@salon.sn");
      assert.ok(c.createdAt, "createdAt posé par le serveur");
      assert.deepEqual(auth.claims.get("newco"), {role: "company"});
    });

  it("garde les autres étiquettes déjà présentes sur le compte", async () => {
    const auth = new FakeAuth();
    auth.claims.set("newco", {beta: true});
    await account.create(db, auth, NEW, FORM);
    assert.deepEqual(auth.claims.get("newco"), {beta: true, role: "company"});
  });

  it("deuxième appel (nouvelle tentative) : rien n'est réécrit", async () => {
    const auth = new FakeAuth();
    await account.create(db, auth, NEW, FORM);
    const res = await account.create(db, auth, NEW, {...FORM, nom: "Autre"});
    assert.deepEqual(res, {role: "company", created: false});
    assert.equal((await read("companies/newco")).nom, "Salon Awa");
  });

  it("champs facultatifs absents : fiche sans champ vide", async () => {
    const auth = new FakeAuth();
    await account.create(db, auth, {...NEW, email: null}, {nom: "Mairie"});
    const c = await read("companies/newco");
    assert.equal(c.nom, "Mairie");
    for (const k of ["type", "typeCategorie", "ville", "country", "language",
      "locale", "timeZone", "email"]) {
      assert.equal(k in c, false, `${k} ne doit pas être écrit`);
    }
  });

  it("fuseau inconnu : ignoré plutôt qu'enregistré", async () => {
    await account.create(db, new FakeAuth(), NEW,
      {...FORM, timeZone: "Mars/Olympus"});
    assert.equal("timeZone" in (await read("companies/newco")), false);
  });

  it("structure déjà inscrite avec un profil « client » : rien de réécrit, " +
    "étiquette reposée", async () => {
    await db.doc("companies/newco").set({nom: "Salon Awa"});
    await db.doc("users/newco").set({role: "customer"});
    const auth = new FakeAuth();
    const res = await account.create(db, auth, NEW, {nom: "Autre"});
    assert.deepEqual(res, {role: "company", created: false});
    assert.equal((await read("companies/newco")).nom, "Salon Awa");
    assert.deepEqual(auth.claims.get("newco"), {role: "company"});
  });

  it("fiche fantôme sans nom : complétée par l'inscription", async () => {
    await db.doc("companies/newco").set({queueCount: 0});
    const res = await account.create(db, new FakeAuth(), NEW, FORM);
    assert.equal(res.created, true);
    const c = await read("companies/newco");
    assert.equal(c.nom, "Salon Awa");
    assert.equal(c.queueCount, 0, "les champs existants sont gardés");
  });

  it("refuse un compte anonyme", () => expectRefused(
    account.create(db, new FakeAuth(), {...NEW, provider: "anonymous"}, FORM),
    "anonymous"));

  it("refuse un compte client", async () => {
    await db.doc("users/newco").set({role: "customer"});
    const auth = new FakeAuth();
    await expectRefused(account.create(db, auth, NEW, FORM),
      "customerAccount");
    assert.equal((await db.doc("companies/newco").get()).exists, false);
    assert.equal(auth.claims.has("newco"), false);
  });

  it("refuse un membre d'équipe", async () => {
    await db.doc("users/newco").set({role: "staff", companyId: "compA"});
    await expectRefused(account.create(db, new FakeAuth(), NEW, FORM),
      "staffAccount");
    assert.equal((await db.doc("companies/newco").get()).exists, false);
  });

  it("un profil sans rôle (fuseau seul) n'empêche pas l'inscription",
    async () => {
      await db.doc("users/newco").set({timeZone: "Africa/Dakar"});
      const res = await account.create(db, new FakeAuth(), NEW, FORM);
      assert.equal(res.created, true);
    });

  it("refuse un nom manquant ou vide", async () => {
    await expectInvalid(account.create(db, new FakeAuth(), NEW, {}));
    await expectInvalid(account.create(db, new FakeAuth(), NEW, {nom: "   "}));
  });

  it("refuse un nom trop long", () => expectInvalid(account.create(
    db, new FakeAuth(), NEW, {nom: "x".repeat(81)})));

  it("refuse un type de structure inconnu", () => expectInvalid(
    account.create(db, new FakeAuth(), NEW, {nom: "A", typeCategorie: "Spa"})));

  it("refuse un champ qui n'est pas du texte", () => expectInvalid(
    account.create(db, new FakeAuth(), NEW, {nom: {x: 1}})));

  it("pays ou langue mal formés : ignorés", async () => {
    await account.create(db, new FakeAuth(), NEW,
      {nom: "A", country: "Sénégal", language: "FR-fr"});
    const c = await read("companies/newco");
    assert.equal("country" in c, false);
    assert.equal("language" in c, false);
  });
});

// ============================================================
describe("Quel est ce compte ?", () => {
  it("structure existante sans étiquette : rattrapée", async () => {
    await db.doc("companies/oldco").set({nom: "Ancienne"});
    const auth = new FakeAuth();
    const res = await account.resolveRole(db, auth,
      {uid: "oldco", provider: "password"});
    assert.deepEqual(res, {role: "company"});
    assert.deepEqual(auth.claims.get("oldco"), {role: "company"});
  });

  it("membre d'équipe : reconnu, sans étiquette structure", async () => {
    await db.doc("users/staff1").set({role: "staff", companyId: "compA"});
    const auth = new FakeAuth();
    const res = await account.resolveRole(db, auth,
      {uid: "staff1", provider: "google.com"});
    assert.deepEqual(res, {role: "staff", companyId: "compA"});
    assert.equal(auth.claims.has("staff1"), false);
  });

  it("compte client : aucun espace structure", async () => {
    await db.doc("users/cust1").set({role: "customer"});
    const res = await account.resolveRole(db, new FakeAuth(),
      {uid: "cust1", provider: "google.com"});
    assert.deepEqual(res, {role: "none"});
  });

  it("client avec une fiche fantôme : toujours refusé", async () => {
    await db.doc("users/cust1").set({role: "customer"});
    await db.doc("companies/cust1").set({queueCount: 1});
    const auth = new FakeAuth();
    const res = await account.resolveRole(db, auth,
      {uid: "cust1", provider: "password"});
    assert.deepEqual(res, {role: "none"});
    assert.equal(auth.claims.has("cust1"), false);
  });

  it("structure dont le profil porte « client » (connexion côté client " +
    "avec la même adresse) : reste une structure", async () => {
    await db.doc("companies/oldco").set({nom: "Ancienne"});
    await db.doc("users/oldco").set({role: "customer"});
    const auth = new FakeAuth();
    const res = await account.resolveRole(db, auth,
      {uid: "oldco", provider: "password"});
    assert.deepEqual(res, {role: "company"});
    assert.deepEqual(auth.claims.get("oldco"), {role: "company"});
  });

  it("compte sans fiche ni profil : aucun espace", async () => {
    const res = await account.resolveRole(db, new FakeAuth(),
      {uid: "ghost", provider: "password"});
    assert.deepEqual(res, {role: "none"});
  });

  it("compte anonyme : aucun espace, même avec une fiche", async () => {
    await db.doc("companies/anon1").set({nom: "X"});
    const res = await account.resolveRole(db, new FakeAuth(),
      {uid: "anon1", provider: "anonymous"});
    assert.deepEqual(res, {role: "none"});
  });
});
