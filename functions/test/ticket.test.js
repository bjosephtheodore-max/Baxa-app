// Tests des numéros de passage (functions/ticket.js).
// Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  ticketCounterRef,
  nextTicketNumber,
  counterUpdate,
  manualCustomerName,
  keptTicketNumber,
} = require("../ticket");

test("premier numéro du jour : 1 (compteur absent ou vide)", () => {
  assert.equal(nextTicketNumber(undefined), 1);
  assert.equal(nextTicketNumber({}), 1);
});

test("les numéros se suivent", () => {
  assert.equal(nextTicketNumber({last: 1}), 2);
  assert.equal(nextTicketNumber({last: 41}), 42);
});

test("compteur abîmé : on repart proprement, jamais de numéro ≤ 0", () => {
  assert.equal(nextTicketNumber({last: -3}), 1);
  assert.equal(nextTicketNumber({last: "abc"}), 1);
  assert.equal(nextTicketNumber({last: 4.7}), 5);
});

test("écriture du compteur : dernier numéro attribué + horodatage", () => {
  assert.deepEqual(counterUpdate(42, {serverTimestamp: () => "TS"}), {
    last: 42,
    updatedAt: "TS",
  });
});

test("guichet : nom saisi gardé, sinon « Client n°X »", () => {
  assert.equal(manualCustomerName("  Awa Diop ", 7), "Awa Diop");
  assert.equal(manualCustomerName("", 42), "Client n°42");
  assert.equal(manualCustomerName("   ", 42), "Client n°42");
  assert.equal(manualCustomerName(null, 3), "Client n°3");
});

test("compteur rangé à part de dailyStats, par file et par jour", () => {
  const calls = [];
  const queueDocRef = {
    collection: (name) => {
      calls.push(name);
      return {doc: (id) => ({path: `${name}/${id}`})};
    },
  };
  assert.equal(
    ticketCounterRef(queueDocRef, "2026-11-10").path,
    "ticketCounters/2026-11-10",
  );
  assert.deepEqual(calls, ["ticketCounters"]);
});

const old = {companyId: "c1", queueId: "q1", ticketNumber: 12};

test("remplacement même file, même jour : numéro gardé", () => {
  assert.equal(keptTicketNumber(old, {
    companyId: "c1", queueId: "q1",
    oldDayKey: "2026-11-10", newDayKey: "2026-11-10",
  }), 12);
});

test("remplacement autre jour, autre file ou autre structure : nouveau numéro",
  () => {
    const base = {companyId: "c1", queueId: "q1",
      oldDayKey: "2026-11-10", newDayKey: "2026-11-10"};
    assert.equal(keptTicketNumber(old, {...base, newDayKey: "2026-11-11"}),
      null);
    assert.equal(keptTicketNumber(old, {...base, queueId: "q2"}), null);
    assert.equal(keptTicketNumber(old, {...base, companyId: "c2"}), null);
  });

test("ancienne réservation sans numéro : nouveau numéro", () => {
  assert.equal(keptTicketNumber({companyId: "c1", queueId: "q1"}, {
    companyId: "c1", queueId: "q1",
    oldDayKey: "2026-11-10", newDayKey: "2026-11-10",
  }), null);
});
