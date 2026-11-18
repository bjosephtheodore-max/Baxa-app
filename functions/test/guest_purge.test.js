// Tests de la suppression des invités inactifs (functions/guest_purge.js).
// Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  GUEST_INACTIVITY_MS,
  isGuest,
  isInactiveGuest,
  purgeInactiveGuests,
} = require("../guest_purge");

const now = new Date("2026-11-18T12:00:00Z");
const daysAgo = (d) => new Date(now.getTime() - d * 86400e3).toUTCString();

function guest(uid, lastDaysAgo) {
  return {
    uid, providerData: [],
    metadata: {creationTime: daysAgo(800), lastRefreshTime: daysAgo(lastDaysAgo)},
  };
}

test("12 mois d'inactivité", () => {
  assert.equal(GUEST_INACTIVITY_MS, 365 * 86400e3);
});

test("invité = aucune méthode de connexion", () => {
  assert.equal(isGuest(guest("a", 1)), true);
  assert.equal(isGuest({uid: "g", providerData: [{providerId: "google.com"}]}),
    false);
  assert.equal(isGuest({uid: "p", providerData: [], phoneNumber: "+221781"}),
    false);
  assert.equal(isGuest({uid: "e", providerData: [], email: "a@b.c"}), false);
});

test("invité actif récemment : gardé", () => {
  assert.equal(isInactiveGuest(guest("a", 10), now), false);
  assert.equal(isInactiveGuest(guest("a", 364), now), false);
});

test("invité inactif depuis plus de 12 mois : à supprimer", () => {
  assert.equal(isInactiveGuest(guest("a", 366), now), true);
});

test("la plus récente des dates compte (connexion récente = actif)", () => {
  const u = {
    uid: "a", providerData: [],
    metadata: {creationTime: daysAgo(900), lastSignInTime: daysAgo(5)},
  };
  assert.equal(isInactiveGuest(u, now), false);
});

test("compte inscrit jamais supprimé, même inactif", () => {
  const u = {...guest("a", 900), providerData: [{providerId: "phone"}]};
  assert.equal(isInactiveGuest(u, now), false);
});

test("dates inconnues : on ne touche à rien", () => {
  assert.equal(isInactiveGuest({uid: "a", providerData: []}, now), false);
});

test("parcours de toutes les pages, échec isolé", async () => {
  const pages = {
    undefined: {users: [guest("old1", 400), guest("new", 3)], pageToken: "p2"},
    p2: {users: [guest("old2", 500), guest("boom", 600)]},
  };
  const auth = {listUsers: async (n, token) => pages[token]};
  const deletedIds = [];
  const deleteAccount = async (db, user) => {
    if (user.uid === "boom") throw new Error("refus");
    deletedIds.push(user.uid);
  };
  const res = await purgeInactiveGuests({auth, db: {}, deleteAccount, now});
  assert.deepEqual(deletedIds, ["old1", "old2"]);
  assert.deepEqual(res, {deleted: 2, failed: 1});
});
