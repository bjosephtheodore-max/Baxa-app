// Tests de la logique pure des réveils (functions/wake.js).
// Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const wake = require("../wake");

const D = (iso) => new Date(iso);
const at = (iso) => D(iso).getTime();

/** Plages agrégées comme les rend aggregateSlotsByPlage. */
function plages(...ranges) {
  const m = new Map();
  ranges.forEach(([from, to], i) => {
    m.set(`ts${i}`, {firstStart: D(from), lastEnd: D(to)});
  });
  return m;
}

test("récap à la fin du dernier créneau, coup d'œil au milieu de chaque plage", () => {
  const ev = wake.planQueueEvents({
    queueId: "q1", day: "2026-10-07",
    plages: plages(
      ["2026-10-07T08:00:00Z", "2026-10-07T12:00:00Z"],
      ["2026-10-07T14:00:00Z", "2026-10-07T18:00:00Z"],
    ),
    now: D("2026-10-07T00:05:00Z"), sent: {},
  });
  const recap = ev.filter((e) => e.kind === "recap");
  const checkins = ev.filter((e) => e.kind === "checkin");
  assert.equal(recap.length, 1);
  assert.equal(recap[0].at, at("2026-10-07T18:00:00Z"));
  assert.deepEqual(checkins.map((e) => e.at), [
    at("2026-10-07T10:00:00Z"), at("2026-10-07T16:00:00Z"),
  ]);
});

test("replanification en cours de journée : pas de coup d'œil pour une plage terminée", () => {
  const ev = wake.planQueueEvents({
    queueId: "q1", day: "2026-10-07",
    plages: plages(
      ["2026-10-07T08:00:00Z", "2026-10-07T12:00:00Z"],
      ["2026-10-07T14:00:00Z", "2026-10-07T18:00:00Z"],
    ),
    now: D("2026-10-07T13:00:00Z"), sent: {},
  });
  assert.deepEqual(
    ev.filter((e) => e.kind === "checkin").map((e) => e.from),
    [at("2026-10-07T14:00:00Z")],
  );
});

test("déjà envoyés ce jour-là : ni récap ni coup d'œil replanifiés", () => {
  const ev = wake.planQueueEvents({
    queueId: "q1", day: "2026-10-07",
    plages: plages(["2026-10-07T08:00:00Z", "2026-10-07T12:00:00Z"]),
    now: D("2026-10-07T09:00:00Z"),
    sent: {"recap:q1": "2026-10-07", "checkin:q1": "2026-10-07"},
  });
  assert.deepEqual(ev, []);
});

test("un envoi de la veille ne bloque pas le jour suivant", () => {
  const ev = wake.planQueueEvents({
    queueId: "q1", day: "2026-10-07",
    plages: plages(["2026-10-07T08:00:00Z", "2026-10-07T12:00:00Z"]),
    now: D("2026-10-07T00:05:00Z"),
    sent: {"recap:q1": "2026-10-06"},
  });
  assert.equal(ev.filter((e) => e.kind === "recap").length, 1);
});

test("file sans créneau ce jour-là : aucune échéance", () => {
  const ev = wake.planQueueEvents({
    queueId: "q1", day: "2026-10-07", plages: new Map(),
    now: D("2026-10-07T00:05:00Z"), sent: {},
  });
  assert.deepEqual(ev, []);
});

test("ajouts équipe : à la fin de la DERNIÈRE file de la structure", () => {
  const queueEvents = [
    ...wake.planQueueEvents({
      queueId: "a", day: "2026-10-07",
      plages: plages(["2026-10-07T08:00:00Z", "2026-10-07T18:00:00Z"]),
      now: D("2026-10-07T00:05:00Z"), sent: {},
    }),
    ...wake.planQueueEvents({
      queueId: "b", day: "2026-10-07",
      plages: plages(["2026-10-07T10:00:00Z", "2026-10-07T21:30:00Z"]),
      now: D("2026-10-07T00:05:00Z"), sent: {},
    }),
  ];
  const team = wake.planTeamEvent({day: "2026-10-07", queueEvents, sent: {}});
  assert.equal(team.at, at("2026-10-07T21:30:00Z"));
});

test("ajouts équipe : aucune file ouverte → pas d'échéance ; déjà envoyé → pas d'échéance", () => {
  assert.equal(wake.planTeamEvent({day: "2026-10-07", queueEvents: [], sent: {}}), null);
  const queueEvents = [{kind: "recap", queueId: "a", day: "2026-10-07", at: 1}];
  assert.equal(
    wake.planTeamEvent({day: "2026-10-07", queueEvents, sent: {team: "2026-10-07"}}),
    null,
  );
});

test("file qui ferme à minuit : échéance datée du lendemain 00:00 mais portant sur la veille", () => {
  const ev = wake.planQueueEvents({
    queueId: "salon", day: "2026-10-07",
    plages: plages(["2026-10-07T14:00:00Z", "2026-10-08T00:00:00Z"]),
    now: D("2026-10-07T00:05:00Z"), sent: {},
  });
  const recap = ev.find((e) => e.kind === "recap");
  assert.equal(recap.day, "2026-10-07");
  assert.equal(recap.at, at("2026-10-08T00:00:00Z"));
  // Passage de 00:00 le 8 : l'échéance est due, et le texte dit « hier ».
  const {due} = wake.splitDue(ev, D("2026-10-08T00:00:00Z"));
  assert.ok(due.some((e) => e.kind === "recap"));
  assert.equal(wake.dayWord(recap.day, "2026-10-08"), "hier");
  assert.equal(wake.dayWord("2026-10-08", "2026-10-08"), "aujourd'hui");
});

test("planifier le nouveau jour garde les échéances encore en attente de la veille", () => {
  const pendingYesterday = {
    kind: "recap", queueId: "salon", day: "2026-10-07", at: at("2026-10-08T00:00:00Z"),
  };
  const staleToday = {kind: "recap", queueId: "x", day: "2026-10-08", at: 5};
  const fresh = [{kind: "recap", queueId: "x", day: "2026-10-08", at: at("2026-10-08T18:00:00Z")}];
  const merged = wake.mergeDayEvents([pendingYesterday, staleToday], "2026-10-08", fresh);
  assert.deepEqual(merged, [pendingYesterday, fresh[0]]);
  assert.equal(wake.nextWakeAt(merged), pendingYesterday.at);
});

test("nextWakeAt / splitDue", () => {
  assert.equal(wake.nextWakeAt([]), null);
  const events = [{at: 30}, {at: 10}, {at: 20}];
  assert.equal(wake.nextWakeAt(events), 10);
  const {due, later} = wake.splitDue(events, new Date(20));
  assert.deepEqual(due.map((e) => e.at), [10, 20]);
  assert.deepEqual(later.map((e) => e.at), [30]);
});

test("comptage : seuls les ajouts manuels du staff encore actifs", () => {
  const base = {source: "company_manual", createdByRole: "staff", status: "confirmed"};
  assert.equal(wake.isStaffManualAdd(base), true);
  assert.equal(wake.isStaffManualAdd({...base, createdByRole: "admin"}), false);
  assert.equal(wake.isStaffManualAdd({...base, source: undefined}), false);
  assert.equal(wake.isStaffManualAdd({...base, status: "cancelled"}), false);
  assert.equal(wake.isStaffManualAdd(null), false);
});

test("texte de la notif équipe (singulier / pluriel, aujourd'hui / hier)", () => {
  assert.equal(
    wake.teamAddsBody(1, "aujourd'hui"),
    "1 client inscrit aujourd'hui par les membres de votre équipe.",
  );
  assert.equal(
    wake.teamAddsBody(20, "hier"),
    "20 clients inscrits hier par les membres de votre équipe.",
  );
});

test("purge du registre anti-doublon", () => {
  const sent = {"recap:a": "2026-10-01", "recap:b": "2026-10-06", team: "2026-10-07"};
  assert.deepEqual(wake.pruneSent(sent, "2026-10-05"), {
    "recap:b": "2026-10-06", team: "2026-10-07",
  });
});
