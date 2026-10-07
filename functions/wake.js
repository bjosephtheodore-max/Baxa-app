// ════════════════════════════════════════════════════════════════════
// RÉVEILS DES NOTIFICATIONS DE FIN DE PLAGE / FIN DE JOURNÉE
//
// Remplace l'ancienne boucle « toutes les 30 min, relire tous les créneaux
// de toutes les files ». Chaque structure a un document de réveil
// `companyWake/{companyId}` qui liste ses prochaines échéances datées :
//
//   recap   : fin du dernier créneau d'une file   → « 📊 Bilan du jour »
//   checkin : milieu d'une plage                  → « 👀 Un coup d'œil ? »
//   team    : fin de la DERNIÈRE file du jour     → « 👥 Ajouts de votre équipe »
//
// Le passage régulier ne fait qu'une requête `wakeAt <= maintenant` et ne
// lit les créneaux que des structures réellement à traiter.
//
// Une échéance porte le JOUR qu'elle concerne (`day`, AAAA-MM-JJ) : une
// file qui ferme à minuit a un récap daté du lendemain 00:00 mais qui
// porte sur la veille — le texte dit alors « hier ».
//
// Ce fichier ne contient que de la logique pure (pas de Firestore) : la
// colle avec la base est dans index.js.
// ════════════════════════════════════════════════════════════════════

/** Un coup d'œil traité plus de 30 min après le milieu de plage est
 * périmé (tick manqué, replanification tardive) : on n'envoie pas. */
const CHECKIN_MAX_DELAY_MS = 30 * 60 * 1000;

/** Délai avant de replanifier après une modification (plage, fermeture) :
 * laisse à l'app le temps de (re)générer les créneaux du jour. */
const REPLAN_DEBOUNCE_MS = 2 * 60 * 1000;

function ms(d) {
  if (!d) return null;
  if (d instanceof Date) return d.getTime();
  if (typeof d.toMillis === "function") return d.toMillis();
  if (typeof d.toDate === "function") return d.toDate().getTime();
  return new Date(d).getTime();
}

/** Clés du registre `sent` (une notif par file / structure et par jour). */
function sentKey(kind, queueId) {
  return queueId ? `${kind}:${queueId}` : kind;
}

function alreadySent(sent, kind, queueId, day) {
  return !!sent && sent[sentKey(kind, queueId)] === day;
}

/**
 * Échéances d'une file pour un jour, à partir de ses plages agrégées
 * (sortie de aggregateSlotsByPlage : Map timeSlotId → {firstStart,
 * lastEnd, ...}). Les échéances déjà envoyées ce jour-là sont omises, et un
 * coup d'œil dont la plage est déjà terminée n'est pas planifié.
 */
function planQueueEvents({queueId, day, plages, now, sent}) {
  const events = [];
  const list = [...plages.values()]
    .filter((g) => g.firstStart && g.lastEnd)
    .sort((a, b) => ms(a.firstStart) - ms(b.firstStart));
  if (list.length === 0) return events;

  const lastEnd = Math.max(...list.map((g) => ms(g.lastEnd)));
  if (!alreadySent(sent, "recap", queueId, day)) {
    events.push({kind: "recap", queueId, day, at: lastEnd});
  }

  if (!alreadySent(sent, "checkin", queueId, day)) {
    for (const g of list) {
      const from = ms(g.firstStart);
      const until = ms(g.lastEnd);
      if (until <= ms(now)) continue;
      events.push({
        kind: "checkin", queueId, day,
        at: Math.round((from + until) / 2), from, until,
      });
    }
  }
  return events;
}

/**
 * Échéance « ajouts de l'équipe » : à la fin de la dernière file du jour,
 * c.-à-d. au plus tardif des récaps de ce jour. Null si aucune file n'a de
 * créneau ce jour-là, ou si elle est déjà partie.
 */
function planTeamEvent({day, queueEvents, sent}) {
  if (alreadySent(sent, "team", null, day)) return null;
  const recaps = queueEvents.filter((e) => e.kind === "recap" && e.day === day);
  if (recaps.length === 0) return null;
  return {kind: "team", day, at: Math.max(...recaps.map((e) => e.at))};
}

/**
 * Remplace les échéances du jour `day` par `fresh`, en gardant celles des
 * autres jours (ex. le récap de minuit de la veille encore en attente).
 */
function mergeDayEvents(existing, day, fresh) {
  return [...(existing || []).filter((e) => e.day !== day), ...fresh]
    .sort((a, b) => a.at - b.at);
}

/** Prochain réveil = échéance la plus proche, ou null s'il n'y en a pas. */
function nextWakeAt(events) {
  if (!events || events.length === 0) return null;
  return Math.min(...events.map((e) => e.at));
}

/** Sépare les échéances arrivées à terme (triées) des autres. */
function splitDue(events, now) {
  const t = ms(now);
  const due = [];
  const later = [];
  for (const e of events || []) (e.at <= t ? due : later).push(e);
  due.sort((a, b) => a.at - b.at);
  return {due, later};
}

/** « aujourd'hui » si l'échéance porte sur le jour en cours, « hier »
 * sinon (récap de minuit envoyé au tout début du lendemain). */
function dayWord(eventDay, today) {
  return eventDay === today ? "aujourd'hui" : "hier";
}

/** Texte de la notif « ajouts de l'équipe ». */
function teamAddsBody(count, word) {
  const s = count > 1 ? "s" : "";
  return `${count} client${s} inscrit${s} ${word} par les membres de ` +
    "votre équipe.";
}

/** Une inscription compte si elle est manuelle, faite par un membre du
 * staff (pas l'admin), et toujours active. */
function isStaffManualAdd(resa) {
  return !!resa &&
    resa.source === "company_manual" &&
    resa.createdByRole === "staff" &&
    resa.status === "confirmed";
}

/** Purge du registre `sent` : on ne garde que les jours ≥ `minDay`. */
function pruneSent(sent, minDay) {
  const out = {};
  for (const [k, v] of Object.entries(sent || {})) {
    if (typeof v === "string" && v >= minDay) out[k] = v;
  }
  return out;
}

module.exports = {
  CHECKIN_MAX_DELAY_MS,
  REPLAN_DEBOUNCE_MS,
  sentKey,
  alreadySent,
  planQueueEvents,
  planTeamEvent,
  mergeDayEvents,
  nextWakeAt,
  splitDue,
  dayWord,
  teamAddsBody,
  isStaffManualAdd,
  pruneSent,
};
