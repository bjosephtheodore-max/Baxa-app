// ============================================================
// TESTS DES RÈGLES DE SÉCURITÉ FIRESTORE (firestore.rules)
// Exécutés contre l'ÉMULATEUR local, sur un projet fictif : aucune donnée
// réelle n'est lue ni modifiée. Lancer avec : node test/firestore_rules/run.mjs
//
// Chaque test décrit le comportement VOULU. Un test marqué `todo` décrit
// une faille connue, pas encore corrigée : il est exécuté et affiché, mais
// ne fait pas échouer la suite.
// ============================================================
import {describe, it, beforeEach} from "node:test";
import assert from "node:assert/strict";

const PROJECT = "demo-baxa-rules";
const HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const B = `http://${HOST}/v1/${ROOT}`;

// ── Acteurs ──────────────────────────────────────────────────
const ANON = null; // visiteur non connecté
const ADMIN = "compA"; // admin de l'entreprise A (uid == companyId)
const ADMIN_B = "compB"; // admin d'une autre entreprise
const STAFF = "staff1"; // membre actif de A
const STAFF_OUT = "staff2"; // membre retiré de A
const STAFF_2 = "staff3"; // autre membre actif de A
const STAFF_B = "staffB"; // membre actif de B
const CLIENT = "cust1";
const CLIENT_2 = "cust2";
const TODAY = "2026-09-26";

// ── Outils HTTP ──────────────────────────────────────────────
function token(uid) {
  if (uid === "owner") return "owner"; // contourne les règles (amorçage)
  const now = Math.floor(Date.now() / 1000);
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return enc({alg: "none", typ: "JWT"}) + "." + enc({
    sub: uid, user_id: uid, iat: now, exp: now + 3600, auth_time: now,
    aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
  }) + ".";
}

function value(v) {
  if (v instanceof Date) return {timestampValue: v.toISOString()};
  if (typeof v === "boolean") return {booleanValue: v};
  if (typeof v === "number") return {integerValue: String(v)};
  if (v === null) return {nullValue: null};
  return {stringValue: String(v)};
}

function fields(obj) {
  const f = {};
  for (const [k, v] of Object.entries(obj)) f[k] = value(v);
  return {fields: f};
}

async function call(method, url, uid, body) {
  const headers = {"Content-Type": "application/json"};
  if (uid) headers.Authorization = "Bearer " + token(uid);
  const r = await fetch(url, {
    method, headers, body: body ? JSON.stringify(body) : undefined,
  });
  return r.status;
}

const mask = (obj) =>
  Object.keys(obj).map((k) => "updateMask.fieldPaths=" + k).join("&");

// Opérations élémentaires (chemin relatif à la racine de la base).
const op = {
  get: (path, uid) => call("GET", `${B}/${path}`, uid),
  list: (col, uid) => call("GET", `${B}/${col}`, uid),
  create: (col, id, obj, uid) =>
    call("POST", `${B}/${col}?documentId=${id}`, uid, fields(obj)),
  // Mise à jour de champs d'un document EXISTANT.
  update: (path, obj, uid) => call("PATCH",
    `${B}/${path}?${mask(obj)}&currentDocument.exists=true`, uid,
    fields(obj)),
  // Écriture « fusion » (crée le document s'il n'existe pas).
  merge: (path, obj, uid) =>
    call("PATCH", `${B}/${path}?${mask(obj)}`, uid, fields(obj)),
  del: (path, uid) => call("DELETE", `${B}/${path}`, uid),
  // Requête sur toutes les sous-collections `col` de la base.
  group: (col, where, uid) => query("", col, where, uid, true),
  // Requête filtrée sur la sous-collection `col` d'un document parent.
  query: (parent, col, where, uid) => query(parent, col, where, uid, false),
};

function query(parent, col, where, uid, allDescendants) {
  const url = parent ? `${B}/${parent}:runQuery` : `${B}:runQuery`;
  return call("POST", url, uid, {
    structuredQuery: {
      from: [{collectionId: col, allDescendants}],
      ...(where ? {where: {fieldFilter: {
        field: {fieldPath: where[0]}, op: "EQUAL", value: value(where[1]),
      }}} : {}),
    },
  });
}

async function allowed(p) {
  const s = await p;
  assert.equal(s, 200, `autorisé attendu, reçu HTTP ${s}`);
}
async function denied(p) {
  const s = await p;
  assert.equal(s, 403, `refus attendu, reçu HTTP ${s}`);
}

// ── Jeu de données fictif, remis à zéro avant chaque test ────
const seed = (path, obj) => op.merge(path, obj, "owner");
const A = "companies/compA";
const Q = `${A}/queues/q1`;

beforeEach(async () => {
  await fetch(`http://${HOST}/emulator/v1/${ROOT}`, {method: "DELETE"});
  await Promise.all([
    seed(A, {nom: "Salon A"}),
    seed("companies/compB", {nom: "Salon B"}),
    seed("users/staff1", {role: "staff", companyId: "compA"}),
    seed("users/staff2", {role: "staff", companyId: "compA"}),
    seed("users/staff3", {role: "staff", companyId: "compA"}),
    seed("users/staffB", {role: "staff", companyId: "compB"}),
    seed("users/cust1", {role: "customer", dailyBookingCount: 5,
      lastBookingDate: TODAY}),
    seed("users/cust2", {role: "customer"}),
    seed(`${A}/staff/staff1`, {isActive: true, phone: "+221700000001"}),
    seed(`${A}/staff/staff2`, {isActive: false, phone: "+221700000002"}),
    seed(`${A}/staff/staff3`, {isActive: true, phone: "+221700000003"}),
    seed("companies/compB/staff/staffB", {isActive: true}),
    seed(`${A}/invitations/inv1`, {code: "ABC234", active: true}),
    seed(Q, {nom: "Coiffure"}),
    seed(`${Q}/slots/s1`, {capacity: 3, reserved: 1, cancelled: 0}),
    seed(`${Q}/timeSlots/t1`, {startTime: "09:00", endTime: "12:00"}),
    seed(`${Q}/dailyStats/${TODAY}`, {reserved: 1, available: 9}),
    seed(`${A}/reservations/r1`, {customerId: CLIENT, source: "app",
      status: "confirmed", customerEmail: "client1@mail.com",
      customerName: "Awa Diop"}),
    seed(`${A}/reservations/r2`, {customerId: CLIENT_2, source: "app",
      status: "confirmed"}),
    seed(`${A}/reservations/rm`, {customerId: "", source: "company_manual",
      status: "confirmed"}),
    seed(`${A}/reservations/mAdmin`, {source: "company_manual",
      customerId: "manual_booking", createdBy: ADMIN, createdByRole: "admin"}),
    seed(`${A}/reservations/mStaff`, {source: "company_manual",
      customerId: "manual_booking", createdBy: STAFF, createdByRole: "staff"}),
    seed(`${A}/reservations/mOut`, {source: "company_manual",
      customerId: "manual_booking", createdBy: STAFF_OUT,
      createdByRole: "staff"}),
    seed(`${A}/companyNotifications/n1`, {type: "staff_joined"}),
    seed(`${A}/notificationsHistory/h1`, {title: "ancien"}),
    seed(`${A}/prereception/p1`, {x: 1}),
    seed("customers/cust1/notifications/cn1", {title: "Annulation"}),
    seed("users/cust1/favorites/compA", {nom: "Salon A"}),
    seed("users/cust1/recentCompanies/compA", {nom: "Salon A"}),
    seed("deletionRequests/compA", {status: "pending"}),
    seed("adminAlerts/a1", {type: "deletion"}),
  ]);
});

// ============================================================
describe("Fiche entreprise", () => {
  it("tout le monde peut la consulter", () => allowed(op.get(A, ANON)));
  it("un client crée sa fiche entreprise (inscription admin)", () =>
    allowed(op.create("companies", CLIENT, {nom: "Nouveau"}, CLIENT)));
  it("l'admin la modifie", () =>
    allowed(op.update(A, {nom: "Salon A+"}, ADMIN)));
  it("un membre actif la modifie", () =>
    allowed(op.update(A, {nom: "Salon A+"}, STAFF)));
  it("un visiteur ne peut pas la modifier", () =>
    denied(op.update(A, {nom: "X"}, ANON)));
  it("un client ne peut pas la modifier", () =>
    denied(op.update(A, {nom: "X"}, CLIENT)));
  it("un membre retiré ne peut plus la modifier", () =>
    denied(op.update(A, {nom: "X"}, STAFF_OUT)));
  it("le membre d'une autre entreprise ne peut pas la modifier", () =>
    denied(op.update(A, {nom: "X"}, STAFF_B)));
  it("l'admin d'une autre entreprise ne peut pas la modifier", () =>
    denied(op.update(A, {nom: "X"}, ADMIN_B)));
  it("un membre ne peut pas la supprimer", () => denied(op.del(A, STAFF)));
});

// ============================================================
describe("Files d'attente et plages horaires", () => {
  it("un visiteur consulte les files", () =>
    allowed(op.list(`${A}/queues`, ANON)));
  it("un visiteur consulte les plages", () =>
    allowed(op.list(`${Q}/timeSlots`, ANON)));
  it("l'admin crée une file", () =>
    allowed(op.create(`${A}/queues`, "q2", {nom: "Barbe"}, ADMIN)));
  it("un membre actif crée une file", () =>
    allowed(op.create(`${A}/queues`, "q2", {nom: "Barbe"}, STAFF)));
  it("l'admin supprime une file", () => allowed(op.del(Q, ADMIN)));
  it("l'admin supprime une plage", () =>
    allowed(op.del(`${Q}/timeSlots/t1`, ADMIN)));
  it("un client ne peut pas créer de file", () =>
    denied(op.create(`${A}/queues`, "q2", {nom: "X"}, CLIENT)));
  it("un membre retiré ne peut plus créer de file", () =>
    denied(op.create(`${A}/queues`, "q2", {nom: "X"}, STAFF_OUT)));
  it("le membre d'une autre entreprise ne peut pas supprimer une file", () =>
    denied(op.del(Q, STAFF_B)));
  it("un client ne peut pas modifier une plage", () =>
    denied(op.update(`${Q}/timeSlots/t1`, {endTime: "23:00"}, CLIENT)));
});

// ============================================================
describe("Créneaux (compteurs de places)", () => {
  const S = `${Q}/slots/s1`;
  it("un visiteur consulte les créneaux", () =>
    allowed(op.list(`${Q}/slots`, ANON)));
  it("un client ne peut pas toucher aux compteurs (serveur uniquement)",
    () => denied(op.update(S, {reserved: 2}, CLIENT)));
  it("un client ne peut pas remettre les compteurs à zéro", () =>
    denied(op.update(S, {reserved: 0}, CLIENT)));
  it("un client ne peut pas compter une annulation", () =>
    denied(op.update(S, {cancelled: 1}, CLIENT)));
  it("un visiteur ne peut pas toucher aux compteurs", () =>
    denied(op.update(S, {reserved: 2}, ANON)));
  it("un client ne peut pas changer la capacité", () =>
    denied(op.update(S, {capacity: 50}, CLIENT)));
  it("un client ne peut pas créer de créneau", () =>
    denied(op.create(`${Q}/slots`, "s9", {capacity: 1}, CLIENT)));
  it("un client ne peut pas supprimer un créneau", () =>
    denied(op.del(S, CLIENT)));
  it("l'admin crée un créneau", () =>
    allowed(op.create(`${Q}/slots`, "s9", {capacity: 1}, ADMIN)));
});

// ============================================================
describe("Places libres par jour (dailyStats)", () => {
  const D = `${Q}/dailyStats/${TODAY}`;
  it("un visiteur consulte les places par jour", () =>
    allowed(op.list(`${Q}/dailyStats`, ANON)));
  it("un client ne peut pas modifier les places d'un jour", () =>
    denied(op.update(D, {reserved: 2, available: 8}, CLIENT)));
  it("un client ne peut pas créer les places d'un jour", () =>
    denied(op.merge(`${Q}/dailyStats/2026-10-01`,
      {reserved: 1, available: -1}, CLIENT)));
  it("un visiteur ne peut pas écrire", () =>
    denied(op.update(D, {reserved: 5}, ANON)));
  it("un membre actif écrit librement", () =>
    allowed(op.update(D, {bonus: 1}, STAFF)));
});

// ============================================================
describe("Réservations", () => {
  const R1 = `${A}/reservations/r1`;
  it("un client ne peut pas créer de réservation (serveur uniquement)",
    () => denied(op.create(`${A}/reservations`, "r9",
      {customerId: CLIENT, status: "confirmed"}, CLIENT)));
  it("un visiteur ne peut pas réserver", () =>
    denied(op.create(`${A}/reservations`, "r9",
      {customerId: "x", status: "confirmed"}, ANON)));
  it("un client ne peut pas annuler lui-même (serveur uniquement)", () =>
    denied(op.update(R1, {status: "cancelled"}, CLIENT)));
  it("un client ne peut pas modifier sa réservation", () =>
    denied(op.update(R1, {source: "company_manual"}, CLIENT)));
  it("un membre actif annule une réservation de son entreprise", () =>
    allowed(op.update(R1, {status: "cancelled"}, STAFF)));
  it("un client ne peut pas supprimer sa réservation", () =>
    denied(op.del(R1, CLIENT)));
  it("un client lit SA réservation", () => allowed(op.get(R1, CLIENT)));
  it("un client retrouve ses réservations (page Mes réservations)", () =>
    allowed(op.group("reservations", ["customerId", CLIENT], CLIENT)));
  it("l'admin liste les réservations de son entreprise", () =>
    allowed(op.list(`${A}/reservations`, ADMIN)));
  it("un membre actif ajoute un client sur place", () => allowed(op.create(
    `${A}/reservations`, "r9", {customerId: "", source: "company_manual"},
    STAFF)));
  it("un membre retiré ne peut plus rien modifier", () =>
    denied(op.update(`${A}/reservations/r2`, {status: "done"}, STAFF_OUT)));
  it("l'admin supprime un ajout manuel", () =>
    allowed(op.del(`${A}/reservations/rm`, ADMIN)));
  it("l'admin ne peut pas supprimer une réservation client", () =>
    denied(op.del(R1, ADMIN)));
  it("un client retrouve ses réservations dans une file (page créneaux)",
    () => allowed(op.query(A, "reservations", ["customerId", CLIENT],
      CLIENT)));
  it("un membre actif lit les réservations de son entreprise", () =>
    allowed(op.get(R1, STAFF)));
  it("un visiteur ne peut pas lire une réservation", () =>
    denied(op.get(R1, ANON)));
  it("un client ne peut pas lire la réservation d'un autre", () =>
    denied(op.get(R1, CLIENT_2)));
  it("un client ne peut pas lister toutes les réservations de la base", () =>
    denied(op.group("reservations", null, CLIENT_2)));
  it("un client ne peut pas lister les réservations d'une entreprise", () =>
    denied(op.list(`${A}/reservations`, CLIENT)));
  it("un client ne peut pas demander les réservations d'un autre", () =>
    denied(op.group("reservations", ["customerId", CLIENT], CLIENT_2)));
  it("un membre retiré ne lit plus les réservations", () =>
    denied(op.get(R1, STAFF_OUT)));
  it("l'admin d'une autre entreprise ne lit pas les réservations", () =>
    denied(op.list(`${A}/reservations`, ADMIN_B)));
});

// ============================================================
describe("Inscriptions manuelles : qui peut supprimer", () => {
  const R = `${A}/reservations`;
  const manual = (by, role) => ({source: "company_manual",
    customerId: "manual_booking", createdBy: by, createdByRole: role});
  it("l'admin supprime l'inscription d'un membre", () =>
    allowed(op.del(`${R}/mStaff`, ADMIN)));
  it("l'admin supprime sa propre inscription", () =>
    allowed(op.del(`${R}/mAdmin`, ADMIN)));
  it("un membre supprime sa propre inscription", () =>
    allowed(op.del(`${R}/mStaff`, STAFF)));
  it("un membre ne peut pas supprimer l'inscription de l'admin", () =>
    denied(op.del(`${R}/mAdmin`, STAFF)));
  it("un membre ne peut pas supprimer l'inscription d'un autre membre", () =>
    denied(op.del(`${R}/mStaff`, STAFF_2)));
  it("un membre ne peut pas supprimer une inscription sans auteur", () =>
    denied(op.del(`${R}/rm`, STAFF)));
  it("un membre retiré ne peut plus supprimer la sienne", () =>
    denied(op.del(`${R}/mOut`, STAFF_OUT)));
  it("un membre inscrit un client à son nom", () =>
    allowed(op.create(R, "m9", manual(STAFF, "staff"), STAFF)));
  it("l'admin inscrit un client à son nom", () =>
    allowed(op.create(R, "m9", manual(ADMIN, "admin"), ADMIN)));
  it("un membre ne peut pas inscrire au nom d'un autre", () =>
    denied(op.create(R, "m9", manual(ADMIN, "admin"), STAFF)));
  it("un membre ne peut pas se faire passer pour le responsable", () =>
    denied(op.create(R, "m9", manual(STAFF, "admin"), STAFF)));
  it("un membre ne peut pas s'attribuer l'inscription de l'admin", () =>
    denied(op.update(`${R}/mAdmin`, {createdBy: STAFF}, STAFF)));
  it("l'admin ne peut pas non plus changer l'auteur d'une inscription", () =>
    denied(op.update(`${R}/mStaff`, {createdBy: ADMIN}, ADMIN)));
});

// ============================================================
describe("Équipe et codes d'invitation", () => {
  const S1 = `${A}/staff/staff1`;
  it("un visiteur ne voit pas l'équipe", () =>
    denied(op.list(`${A}/staff`, ANON)));
  it("un client ne voit pas une fiche staff", () =>
    denied(op.get(S1, CLIENT)));
  it("un visiteur ne voit pas les codes", () =>
    denied(op.list(`${A}/invitations`, ANON)));
  it("un client ne voit pas les codes", () =>
    denied(op.get(`${A}/invitations/inv1`, CLIENT)));
  it("un client ne peut pas se déclarer membre", () =>
    denied(op.create(`${A}/staff`, CLIENT, {isActive: true}, CLIENT)));
  it("un client ne peut pas désactiver un code", () =>
    denied(op.update(`${A}/invitations/inv1`, {active: false}, CLIENT)));
  it("l'admin voit son équipe", () =>
    allowed(op.list(`${A}/staff`, ADMIN)));
  it("l'admin voit ses codes", () =>
    allowed(op.list(`${A}/invitations`, ADMIN)));
  it("l'admin crée un code", () => allowed(op.create(
    `${A}/invitations`, "inv2", {code: "XYZ789", active: true}, ADMIN)));
  it("l'admin retire un membre", () =>
    allowed(op.update(S1, {isActive: false}, ADMIN)));
  it("l'admin d'une autre entreprise ne voit pas l'équipe", () =>
    denied(op.list(`${A}/staff`, ADMIN_B)));
  it("un membre actif voit sa fiche", () => allowed(op.get(S1, STAFF)));
  it("un membre actif met à jour sa dernière activité", () =>
    allowed(op.update(S1, {lastSeenAt: new Date()}, STAFF)));
  it("un membre ne peut pas modifier autre chose sur sa fiche", () =>
    denied(op.update(S1, {displayName: "Chef"}, STAFF)));
  it("un membre ne peut pas réactiver un collègue retiré", () =>
    denied(op.update(`${A}/staff/staff2`, {isActive: true}, STAFF)));
  it("un membre ne peut pas créer de fiche staff", () =>
    denied(op.create(`${A}/staff`, "s9", {isActive: true}, STAFF)));
  it("un membre retiré lit sa fiche (détection du retrait)", () =>
    allowed(op.get(`${A}/staff/staff2`, STAFF_OUT)));
  it("un membre retiré ne voit plus l'équipe", () =>
    denied(op.list(`${A}/staff`, STAFF_OUT)));
  it("un membre retiré ne peut pas se réactiver", () =>
    denied(op.update(`${A}/staff/staff2`, {isActive: true}, STAFF_OUT)));
  it("un client qui se déclare « staff » dans son profil n'obtient rien", async () => {
    await allowed(op.update("users/cust1",
      {role: "staff", companyId: "compA"}, CLIENT));
    await denied(op.create(`${A}/queues`, "q9", {nom: "X"}, CLIENT));
  });
});

// ============================================================
describe("Notifications de l'entreprise", () => {
  const N = `${A}/companyNotifications`;
  it("l'admin les lit", () => allowed(op.list(N, ADMIN)));
  it("un membre actif les lit", () => allowed(op.list(N, STAFF)));
  it("l'admin en supprime une", () => allowed(op.del(`${N}/n1`, ADMIN)));
  it("un client ne peut pas en supprimer", () =>
    denied(op.del(`${N}/n1`, CLIENT)));
  it("un client ne peut pas en créer", () =>
    denied(op.create(N, "n9", {type: "x"}, CLIENT)));
  it("un visiteur ne peut pas les lire", () => denied(op.list(N, ANON)));
  it("un client ne peut pas les lire", () => denied(op.list(N, CLIENT)));
  it("l'admin d'une autre entreprise ne peut pas les lire", () =>
    denied(op.list(N, ADMIN_B)));
  it("l'app ne peut pas en créer (serveur uniquement)", () =>
    denied(op.create(N, "n9", {type: "x"}, ADMIN)));
  it("un membre ne peut pas en créer", () =>
    denied(op.create(N, "n9", {type: "x"}, STAFF)));
  it("l'admin lit l'ancien historique", () =>
    allowed(op.list(`${A}/notificationsHistory`, ADMIN)));
  it("un visiteur ne lit pas l'ancien historique", () =>
    denied(op.list(`${A}/notificationsHistory`, ANON)));
});

// ============================================================
describe("Autres données d'entreprise (privées par défaut)", () => {
  it("l'admin les lit", () =>
    allowed(op.get(`${A}/prereception/p1`, ADMIN)));
  it("un membre actif les lit", () =>
    allowed(op.list(`${A}/prereception`, STAFF)));
  it("un visiteur ne peut pas les lire", () =>
    denied(op.get(`${A}/prereception/p1`, ANON)));
  it("un client ne peut pas les lire", () =>
    denied(op.list(`${A}/prereception`, CLIENT)));
  it("l'admin les modifie", () =>
    allowed(op.update(`${A}/prereception/p1`, {x: 2}, ADMIN)));
  it("un client ne peut pas les modifier", () =>
    denied(op.update(`${A}/prereception/p1`, {x: 2}, CLIENT)));
  it("personne ne peut les supprimer par ce bloc", () =>
    denied(op.del(`${A}/prereception/p1`, ADMIN)));
});

// ============================================================
describe("Espace client (profil, favoris, notifications)", () => {
  it("un client lit son profil", () =>
    allowed(op.get("users/cust1", CLIENT)));
  it("un client ne lit pas le profil d'un autre", () =>
    denied(op.get("users/cust1", CLIENT_2)));
  it("l'admin ne lit pas le profil d'un client", () =>
    denied(op.get("users/cust1", ADMIN)));
  it("un client gère ses favoris", () => allowed(op.create(
    "users/cust1/favorites", "compB", {nom: "Salon B"}, CLIENT)));
  it("un client ne voit pas les favoris d'un autre", () =>
    denied(op.list("users/cust1/favorites", CLIENT_2)));
  it("un client voit ses entreprises récentes", () =>
    allowed(op.list("users/cust1/recentCompanies", CLIENT)));
  it("un client lit ses notifications", () =>
    allowed(op.list("customers/cust1/notifications", CLIENT)));
  it("un client ne lit pas les notifications d'un autre", () =>
    denied(op.list("customers/cust1/notifications", CLIENT_2)));
  it("l'admin ne lit pas les notifications d'un client", () =>
    denied(op.list("customers/cust1/notifications", ADMIN)));
  it("un visiteur ne lit rien de l'espace client", () =>
    denied(op.get("users/cust1", ANON)));
  it("un client modifie son profil (prénom…)", () =>
    allowed(op.update("users/cust1", {prenom: "Awa"}, CLIENT)));
  it("un client compte ses réservations (invitation à s'inscrire)", () =>
    allowed(op.update("users/cust1", {totalReservations: 3}, CLIENT)));
  it("un nouveau client crée son profil", () =>
    allowed(op.create("users", "cust9", {role: "customer"}, "cust9")));
  it("un client ne peut pas remettre à zéro son quota du jour", () =>
    denied(op.update("users/cust1", {dailyBookingCount: 0}, CLIENT)));
  it("un client ne peut pas changer la date de son quota", () =>
    denied(op.update("users/cust1", {lastBookingDate: "2020-01-01"},
      CLIENT)));
  it("un nouveau profil ne peut pas arriver avec un quota", () =>
    denied(op.create("users", "cust9", {dailyBookingCount: 0}, "cust9")));
  it("un client ne peut pas supprimer son profil (remise à zéro du quota)",
    () => denied(op.del("users/cust1", CLIENT)));
});

// ============================================================
describe("Départ de Baxa et alertes internes", () => {
  const DR = "deletionRequests/compA";
  it("l'admin consulte sa demande de départ", () =>
    allowed(op.get(DR, ADMIN)));
  it("l'admin annule sa demande (suppression)", () =>
    allowed(op.del(DR, ADMIN)));
  it("l'admin crée une demande", () => allowed(op.create(
    "deletionRequests", "compB", {status: "pending"}, ADMIN_B)));
  it("l'admin ne peut pas valider lui-même sa demande", () =>
    denied(op.update(DR, {status: "approved"}, ADMIN)));
  it("un membre ne peut pas demander le départ", () => denied(op.create(
    "deletionRequests", "compB", {status: "pending"}, STAFF_B)));
  it("un client ne voit pas les demandes", () =>
    denied(op.get(DR, CLIENT)));
  it("personne ne lit les alertes internes", () =>
    denied(op.list("adminAlerts", ADMIN)));
  it("personne n'écrit d'alerte interne", () =>
    denied(op.create("adminAlerts", "a9", {type: "x"}, ADMIN)));
});
