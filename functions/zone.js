// ════════════════════════════════════════════════════════════════════
// FUSEAUX HORAIRES
//
// Chaque structure a son fuseau (`timeZone` sur companies/{id}, nom IANA
// comme « Africa/Dakar » ou « Europe/Paris », détecté depuis le téléphone
// de l'admin à l'inscription). Les instants (créneaux, réservations) sont
// stockés en absolu dans Firestore ; ce module ne sert qu'aux endroits où le
// serveur raisonne en heure LOCALE : « aujourd'hui », « minuit », « 9h » d'une
// plage, textes « 14h30 » des notifications, réveils à 7h chez la structure.
//
// Uniquement l'API Intl de Node (changements d'heure été/hiver compris),
// sans dépendance. Logique pure : testée dans test/zone.test.js.
// ════════════════════════════════════════════════════════════════════

/** Fuseau par défaut : structures ou clients enregistrés avant l'ajout du
 * champ `timeZone` (tous au Sénégal à ce moment-là). */
const DEFAULT_TZ = "Africa/Dakar";

const MINUTE = 60 * 1000;

const formatters = new Map();
function formatterFor(tz) {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz, hourCycle: "h23",
      year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
    });
    formatters.set(tz, f);
  }
  return f;
}

/** Nom IANA valide, sinon le fuseau par défaut. */
function tzOf(value) {
  if (typeof value !== "string" || !value.trim()) return DEFAULT_TZ;
  const tz = value.trim();
  try {
    formatterFor(tz);
    return tz;
  } catch (_) {
    return DEFAULT_TZ;
  }
}

/** Composantes de l'heure murale de `date` dans `tz`. weekday : 1 = lundi
 * … 7 = dimanche (convention Dart, comme les `workingDays` des plages). */
function partsIn(date, tz) {
  const p = {};
  for (const {type, value} of formatterFor(tzOf(tz)).formatToParts(date)) {
    p[type] = value;
  }
  const year = Number(p.year);
  const month = Number(p.month);
  const day = Number(p.day);
  const jsDay = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return {
    year, month, day,
    hour: Number(p.hour), minute: Number(p.minute), second: Number(p.second),
    weekday: jsDay === 0 ? 7 : jsDay,
  };
}

/** Décalage (ms) du fuseau par rapport à UTC à l'instant `date`. */
function offsetMs(date, tz) {
  const p = partsIn(date, tz);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - Math.floor(date.getTime() / 1000) * 1000;
}

const pad = (n) => String(n).padStart(2, "0");

/** « AAAA-MM-JJ » du jour local de `date` dans `tz`. */
function ymdIn(date, tz) {
  const p = partsIn(date, tz);
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`;
}

/** « AAAA-MM-JJ » + n jours (calendrier pur, sans fuseau). */
function addDays(ymdStr, n) {
  const [y, m, d] = ymdStr.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** 1 = lundi … 7 = dimanche, pour un jour « AAAA-MM-JJ ». */
function weekdayOf(ymdStr) {
  const [y, m, d] = ymdStr.split("-").map(Number);
  const js = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return js === 0 ? 7 : js;
}

/**
 * Instant absolu correspondant à l'heure murale `hm` (« HH:MM », « 24:00 »
 * accepté = minuit du lendemain) du jour `ymdStr` dans `tz`. Une heure qui
 * n'existe pas (saut d'heure au printemps) est décalée vers l'avant ; une
 * heure qui existe deux fois (recul d'automne) prend la première.
 */
function zonedTime(ymdStr, hm, tz) {
  const zone = tzOf(tz);
  const [hh, mm] = String(hm || "00:00").split(":").map(Number);
  if (hh === 24) return zonedTime(addDays(ymdStr, 1), "00:00", zone);
  const [y, m, d] = ymdStr.split("-").map(Number);
  const wall = Date.UTC(y, m - 1, d, hh, mm || 0);
  // Deux passes : le décalage peut changer entre l'estimation et le résultat.
  let t = wall - offsetMs(new Date(wall), zone);
  t = wall - offsetMs(new Date(t), zone);
  return new Date(t);
}

/** Bornes [minuit, minuit du lendemain[ du jour `ymdStr` dans `tz`. */
function dayBounds(ymdStr, tz) {
  return {
    start: zonedTime(ymdStr, "00:00", tz),
    end: zonedTime(addDays(ymdStr, 1), "00:00", tz),
  };
}

/** Bornes du jour local en cours (« aujourd'hui » chez la structure). */
function todayBounds(now, tz) {
  return dayBounds(ymdIn(now, tz), tz);
}

/** « 8h » · « 8h30 » (heure locale). */
function fmtClock(date, tz) {
  if (!date) return "";
  const p = partsIn(date, tz);
  return p.minute ? `${p.hour}h${pad(p.minute)}` : `${p.hour}h`;
}

/** « 08h30 » (heure locale). */
function fmtHHhMM(date, tz) {
  const p = partsIn(date, tz);
  return `${pad(p.hour)}h${pad(p.minute)}`;
}

/** « 25/10 » (jour local). */
function fmtDdMm(date, tz) {
  const p = partsIn(date, tz);
  return `${pad(p.day)}/${pad(p.month)}`;
}

/** « 25/10/2026 » (jour local). */
function fmtDdMmYyyy(date, tz) {
  const p = partsIn(date, tz);
  return `${pad(p.day)}/${pad(p.month)}/${p.year}`;
}

const MOIS_FR = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];

/** « 15 septembre » (jour local). */
function fmtDateFr(date, tz) {
  if (!date) return "";
  const p = partsIn(date, tz);
  return `${p.day} ${MOIS_FR[p.month - 1]}`;
}

/**
 * Rendez-vous locaux du chef « horloge » (passage toutes les 15 min) :
 * vrai si, dans `tz`, l'heure locale de `now` tombe dans le quart d'heure
 * qui commence à `hour`:00 — et, si `weekday` est donné, ce jour-là.
 */
function isLocalSlot(now, tz, hour, weekday) {
  const p = partsIn(now, tz);
  if (weekday && p.weekday !== weekday) return false;
  return p.hour === hour && p.minute < 15;
}

module.exports = {
  DEFAULT_TZ,
  MINUTE,
  tzOf,
  partsIn,
  offsetMs,
  ymdIn,
  addDays,
  weekdayOf,
  zonedTime,
  dayBounds,
  todayBounds,
  fmtClock,
  fmtHHhMM,
  fmtDdMm,
  fmtDdMmYyyy,
  fmtDateFr,
  isLocalSlot,
};
