// Tests de la résolution des réservations suspendues (functions/suspension.js).
// Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isStillSuspended,
  shouldResolveAtSlotEnd,
  unresolvedSuspensionUpdate,
} = require("../suspension");

const suspended = {status: "confirmed", suspended: true};

test("fin de créneau d'une réservation encore suspendue → annulation", () => {
  assert.equal(shouldResolveAtSlotEnd("passed", suspended), true);
});

test("les autres étapes ne résolvent jamais une suspension", () => {
  for (const kind of ["reminder_1", "reminder_2", "reminder_3", "validation"]) {
    assert.equal(shouldResolveAtSlotEnd(kind, suspended), false, kind);
  }
});

test("réservation non suspendue, déjà annulée ou absente → rien à faire", () => {
  assert.equal(shouldResolveAtSlotEnd("passed", {status: "confirmed"}), false);
  assert.equal(
    shouldResolveAtSlotEnd("passed", {status: "cancelled", suspended: true}),
    false,
  );
  assert.equal(shouldResolveAtSlotEnd("passed", undefined), false);
  assert.equal(isStillSuspended(null), false);
});

test("mise à jour : annulée « company_block_unresolved », suspension effacée",
  () => {
    const fv = {
      serverTimestamp: () => "TS",
      delete: () => "DEL",
    };
    assert.deepEqual(unresolvedSuspensionUpdate(fv), {
      status: "cancelled",
      cancelledAt: "TS",
      cancellationSource: "company_block_unresolved",
      suspended: "DEL",
      suspendedReason: "DEL",
      suspendedAt: "DEL",
    });
  });
