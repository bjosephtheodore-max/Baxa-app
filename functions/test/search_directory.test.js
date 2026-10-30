// Tests de la logique pure de l'annuaire de recherche
// (functions/search_directory.js). Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const sd = require("../search_directory");

const ts = (ms) => ({toMillis: () => ms});
const geo = (lat, lng) => ({latitude: lat, longitude: lng});

const base = {
  nom: "Boulangerie Diop", type: "Commerce", ville: "Dakar",
  country: "sn", position: geo(14.7, -17.4), queueCount: 2,
  closedNow: false, reservationCount: 12, phone: "77 000 00 00",
};

test("pays : majuscules, vide ou XX → annuaire sans pays", () => {
  assert.equal(sd.countryKey({country: "sn"}), "SN");
  assert.equal(sd.countryKey({country: " "}), sd.NO_COUNTRY);
  assert.equal(sd.countryKey({country: "xx"}), sd.NO_COUNTRY);
  assert.equal(sd.countryKey({}), sd.NO_COUNTRY);
});

test("la ligne ne recopie que les champs affichés", () => {
  const e = sd.buildEntry(base);
  assert.equal(e.nom, "Boulangerie Diop");
  assert.equal(e.adresse, null);
  assert.equal("phone" in e, false);
  assert.equal("reservationCount" in e, false);
});

test("création d'une structure → ajout dans son pays", () => {
  const ops = sd.syncOps(null, base);
  assert.equal(ops.length, 1);
  assert.equal(ops[0].op, "upsert");
  assert.equal(ops[0].country, "SN");
});

test("un champ non affiché change → aucune écriture", () => {
  const ops = sd.syncOps(base, {...base, reservationCount: 13, phone: "x"});
  assert.deepEqual(ops, []);
});

test("Timestamp / GeoPoint identiques mais objets différents → aucune écriture", () => {
  const a = {...base, reopenAt: ts(1000), position: geo(1, 2)};
  const b = {...base, reopenAt: ts(1000), position: geo(1, 2)};
  assert.deepEqual(sd.syncOps(a, b), []);
});

test("fermeture → mise à jour de la ligne", () => {
  const ops = sd.syncOps(base, {...base, closedNow: true, reopenAt: ts(5)});
  assert.equal(ops.length, 1);
  assert.equal(ops[0].op, "upsert");
  assert.equal(ops[0].entry.closedNow, true);
});

test("changement de pays → retrait de l'ancien, ajout au nouveau", () => {
  const ops = sd.syncOps(base, {...base, country: "CI"});
  assert.deepEqual(ops.map((o) => [o.op, o.country]), [
    ["remove", "SN"], ["upsert", "CI"],
  ]);
});

test("structure supprimée (statut ou document) → retrait", () => {
  assert.deepEqual(
    sd.syncOps(base, {...base, status: "deleted"}).map((o) => o.op),
    ["remove"],
  );
  assert.deepEqual(sd.syncOps(base, null).map((o) => o.op), ["remove"]);
  assert.deepEqual(sd.syncOps({...base, status: "deleted"}, null), []);
});

test("répartition stable entre documents", () => {
  assert.equal(sd.shardIndex("abc", 1), 0);
  const i = sd.shardIndex("companyXYZ", 4);
  assert.ok(i >= 0 && i < 4);
  assert.equal(sd.shardIndex("companyXYZ", 4), i);
});

test("nombre de documents par pays selon la taille", () => {
  assert.equal(sd.shardCountFor(0), 1);
  assert.equal(sd.shardCountFor(sd.MAX_ENTRIES_PER_SHARD), 1);
  assert.equal(sd.shardCountFor(sd.MAX_ENTRIES_PER_SHARD + 1), 2);
});

test("reconstruction : pays séparés, supprimées exclues, popularité incluse", () => {
  const {docs, shardCounts} = sd.planDirectory([
    {id: "a", data: base, popularity: 7},
    {id: "b", data: {...base, country: "CI"}, popularity: 0},
    {id: "c", data: {...base, country: null}},
    {id: "d", data: {...base, status: "deleted"}, popularity: 3},
  ]);
  assert.deepEqual(shardCounts, {SN: 1, CI: 1, [sd.NO_COUNTRY]: 1});
  assert.equal(docs.get("SN_0").entries.a.popularity, 7);
  assert.equal(docs.get("SN_0").entries.a.adresse, undefined);
  assert.equal(docs.get(`${sd.NO_COUNTRY}_0`).entries.c.popularity, 0);
  const all = [...docs.values()].flatMap((d) => Object.keys(d.entries));
  assert.equal(all.includes("d"), false);
});

test("reconstruction : un grand pays est réparti sur plusieurs documents", () => {
  const list = [];
  for (let i = 0; i <= sd.MAX_ENTRIES_PER_SHARD; i++) {
    list.push({id: `c${i}`, data: base});
  }
  const {docs, shardCounts} = sd.planDirectory(list);
  assert.equal(shardCounts.SN, 2);
  const total = [...docs.values()]
    .reduce((n, d) => n + Object.keys(d.entries).length, 0);
  assert.equal(total, list.length);
});
