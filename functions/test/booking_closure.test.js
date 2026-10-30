// Tests de la règle « pas de réservation pendant une fermeture »
// (functions/booking.js, isSlotInClosure). Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const {isSlotInClosure} = require("../booking");

const D = (iso) => new Date(iso);
// Timestamp Firestore simulé.
const ts = (iso) => ({toDate: () => D(iso)});

test("pas de fermeture → créneau autorisé", () => {
  assert.equal(isSlotInClosure(null, null, D("2026-10-25T10:00:00Z")), false);
});

test("fermeture programmée : un créneau avant le début reste autorisé", () => {
  assert.equal(isSlotInClosure(
    ts("2026-10-25T00:00:00Z"), ts("2026-10-27T23:59:59Z"),
    D("2026-10-24T15:00:00Z"),
  ), false);
});

test("fermeture programmée : un créneau dans la période est refusé", () => {
  const start = ts("2026-10-25T00:00:00Z");
  const end = ts("2026-10-27T23:59:59Z");
  assert.equal(isSlotInClosure(start, end, D("2026-10-25T00:00:00Z")), true);
  assert.equal(isSlotInClosure(start, end, D("2026-10-26T09:00:00Z")), true);
  assert.equal(isSlotInClosure(start, end, D("2026-10-27T18:00:00Z")), true);
});

test("le jour de réouverture est de nouveau réservable", () => {
  assert.equal(isSlotInClosure(
    ts("2026-10-25T00:00:00Z"), ts("2026-10-27T23:59:59Z"),
    D("2026-10-28T08:00:00Z"),
  ), false);
});

test("fermeture sans date de fin → tout créneau après le début est refusé", () => {
  assert.equal(isSlotInClosure(
    ts("2026-10-25T00:00:00Z"), null, D("2027-03-01T08:00:00Z"),
  ), true);
});
