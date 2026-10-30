// Tests du module de fuseaux horaires (functions/zone.js).
// Lancer : npm test (dans functions/).
const test = require("node:test");
const assert = require("node:assert/strict");
const zone = require("../zone");

const iso = (d) => d.toISOString();

test("fuseau invalide ou absent → Dakar", () => {
  assert.equal(zone.tzOf(undefined), "Africa/Dakar");
  assert.equal(zone.tzOf(""), "Africa/Dakar");
  assert.equal(zone.tzOf("Pas/UnFuseau"), "Africa/Dakar");
  assert.equal(zone.tzOf("Europe/Paris"), "Europe/Paris");
});

test("Dakar (UTC+0) : 9h locale = 9h UTC", () => {
  assert.equal(iso(zone.zonedTime("2026-10-26", "09:00", "Africa/Dakar")),
    "2026-10-26T09:00:00.000Z");
});

test("Kinshasa (UTC+1) et Nairobi (UTC+3)", () => {
  assert.equal(iso(zone.zonedTime("2026-10-26", "09:00", "Africa/Kinshasa")),
    "2026-10-26T08:00:00.000Z");
  assert.equal(iso(zone.zonedTime("2026-10-26", "09:00", "Africa/Nairobi")),
    "2026-10-26T06:00:00.000Z");
});

test("Paris : heure d'été puis d'hiver (changement le 25/10/2026)", () => {
  // Samedi 24/10 : UTC+2 · lundi 26/10 : UTC+1.
  assert.equal(iso(zone.zonedTime("2026-10-24", "09:00", "Europe/Paris")),
    "2026-10-24T07:00:00.000Z");
  assert.equal(iso(zone.zonedTime("2026-10-26", "09:00", "Europe/Paris")),
    "2026-10-26T08:00:00.000Z");
});

test("Paris : la journée du changement d'heure dure 25 h", () => {
  const {start, end} = zone.dayBounds("2026-10-25", "Europe/Paris");
  assert.equal(iso(start), "2026-10-24T22:00:00.000Z");
  assert.equal(iso(end), "2026-10-25T23:00:00.000Z");
  assert.equal((end - start) / 3600000, 25);
});

test("Paris : heure inexistante au printemps (2h30 le 29/03/2026) → décalée", () => {
  const t = zone.zonedTime("2026-03-29", "02:30", "Europe/Paris");
  assert.equal(zone.fmtHHhMM(t, "Europe/Paris"), "03h30");
});

test("« 24:00 » = minuit du lendemain, heure locale", () => {
  assert.equal(iso(zone.zonedTime("2026-10-26", "24:00", "Africa/Kinshasa")),
    "2026-10-26T23:00:00.000Z");
});

test("jour local : à 23h30 UTC, il est déjà demain à Nairobi", () => {
  const t = new Date("2026-10-26T23:30:00Z");
  assert.equal(zone.ymdIn(t, "Africa/Dakar"), "2026-10-26");
  assert.equal(zone.ymdIn(t, "Africa/Nairobi"), "2026-10-27");
});

test("jours de la semaine (1 = lundi … 7 = dimanche)", () => {
  assert.equal(zone.weekdayOf("2026-10-26"), 1);
  assert.equal(zone.weekdayOf("2026-11-01"), 7);
  assert.equal(zone.addDays("2026-10-31", 1), "2026-11-01");
  assert.equal(zone.addDays("2026-03-01", -1), "2026-02-28");
});

test("formatage dans le fuseau de la structure", () => {
  const t = new Date("2026-10-26T13:30:00Z");
  assert.equal(zone.fmtClock(t, "Africa/Dakar"), "13h30");
  assert.equal(zone.fmtClock(t, "Africa/Kinshasa"), "14h30");
  assert.equal(zone.fmtHHhMM(new Date("2026-10-26T08:05:00Z"), "Africa/Dakar"), "08h05");
  assert.equal(zone.fmtClock(new Date("2026-10-26T08:00:00Z"), "Africa/Dakar"), "8h");
  assert.equal(zone.fmtDdMm(t, "Africa/Nairobi"), "26/10");
  assert.equal(zone.fmtDdMmYyyy(t, "Africa/Dakar"), "26/10/2026");
  assert.equal(zone.fmtDateFr(t, "Africa/Dakar"), "26 octobre");
});

test("rendez-vous local du chef horloge", () => {
  // 06:00 UTC = 7h à Kinshasa, 6h à Dakar.
  const t = new Date("2026-10-26T06:00:00Z");
  assert.equal(zone.isLocalSlot(t, "Africa/Kinshasa", 7), true);
  assert.equal(zone.isLocalSlot(t, "Africa/Dakar", 7), false);
  assert.equal(zone.isLocalSlot(t, "Africa/Dakar", 6, 1), true); // lundi
  assert.equal(zone.isLocalSlot(t, "Africa/Dakar", 6, 2), false);
  // 06:14 encore dans le quart d'heure, 06:15 non.
  assert.equal(zone.isLocalSlot(new Date("2026-10-26T06:14:00Z"), "Africa/Dakar", 6), true);
  assert.equal(zone.isLocalSlot(new Date("2026-10-26T06:15:00Z"), "Africa/Dakar", 6), false);
});

test("Casablanca : décalage lu dans la base de fuseaux (pas codé en dur)", () => {
  const t = zone.zonedTime("2026-10-26", "09:00", "Africa/Casablanca");
  assert.equal(zone.fmtHHhMM(t, "Africa/Casablanca"), "09h00");
  assert.equal(zone.ymdIn(t, "Africa/Casablanca"), "2026-10-26");
});
