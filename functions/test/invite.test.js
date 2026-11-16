// Tests de la validité des codes d'invitation (functions/invite.js).
// Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const {INVITE_VALIDITY_MS, isInviteExpired} = require("../invite");

const now = new Date("2026-11-16T12:00:00Z");
const hoursAgo = (h) => new Date(now.getTime() - h * 3600 * 1000);

test("validité : 48 heures", () => {
  assert.equal(INVITE_VALIDITY_MS, 48 * 3600 * 1000);
});

test("code récent : valable", () => {
  assert.equal(isInviteExpired(hoursAgo(1), now), false);
  assert.equal(isInviteExpired(hoursAgo(47.9), now), false);
});

test("pile 48 h : encore valable, au-delà : expiré", () => {
  assert.equal(isInviteExpired(hoursAgo(48), now), false);
  assert.equal(isInviteExpired(hoursAgo(48.01), now), true);
  assert.equal(isInviteExpired(hoursAgo(24 * 30), now), true);
});

test("ancien code sans date de création : n'expire pas", () => {
  assert.equal(isInviteExpired(undefined, now), false);
  assert.equal(isInviteExpired(null, now), false);
});

test("accepte un Timestamp Firestore (toMillis)", () => {
  const ts = {toMillis: () => hoursAgo(50).getTime()};
  assert.equal(isInviteExpired(ts, now), true);
});
