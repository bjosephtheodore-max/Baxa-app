// ════════════════════════════════════════════════════════════════════
// NUMÉRO DE PASSAGE (« ticket ») — un par réservation
//
// Chaque réservation reçoit un numéro, par file et par jour, dans l'ordre
// des inscriptions : 1, 2, 3… — comme le ticket d'une file d'attente.
// Attribué côté serveur, dans la MÊME transaction que l'inscription
// (réservation client `booking`, inscription au guichet `companyBooking`) :
// deux inscriptions simultanées ne peuvent pas recevoir le même numéro. Un
// numéro annulé n'est jamais réutilisé (un trou dans la suite est normal).
//
// Compteur : companies/{c}/queues/{q}/ticketCounters/{AAAA-MM-JJ} = {last}
// — un document À PART, pas un champ de `dailyStats` : la maintenance de
// nuit réécrit entièrement `dailyStats` (recomptage), ce qui remettrait le
// compteur à zéro et donnerait des numéros en double. Écrit uniquement par
// le serveur (aucune règle ne l'ouvre à l'app).
//
// Inscription au guichet SANS nom : le serveur enregistre « Client n°42 »
// comme nom, pour que tout ce qui lit `customerName` continue de marcher.
// Fonctions pures — testées dans test/ticket.test.js.
// ════════════════════════════════════════════════════════════════════

/** Document compteur d'une file pour le jour `dayKey` (« AAAA-MM-JJ »). */
function ticketCounterRef(queueDocRef, dayKey) {
  return queueDocRef.collection("ticketCounters").doc(dayKey);
}

/** Numéro suivant, d'après les données du compteur (absent → 1). */
function nextTicketNumber(counterData) {
  const last = Number(counterData && counterData.last);
  const base = Number.isFinite(last) && last > 0 ? Math.floor(last) : 0;
  return base + 1;
}

/** Écriture du compteur après attribution de `number`. */
function counterUpdate(number, FieldValue) {
  return {last: number, updatedAt: FieldValue.serverTimestamp()};
}

/** Nom enregistré pour une inscription au guichet. */
function manualCustomerName(clientName, number) {
  const name = typeof clientName === "string" ? clientName.trim() : "";
  return name || `Client n°${number}`;
}

/**
 * Remplacement d'une réservation client : le numéro est GARDÉ si le client
 * reste dans la même file le même jour (il change seulement d'horaire) ;
 * sinon (autre file, autre jour, ancienne réservation sans numéro) → null,
 * un nouveau numéro sera pris dans le compteur du jour visé.
 */
function keptTicketNumber(old, {companyId, queueId, oldDayKey, newDayKey}) {
  if (!old || old.companyId !== companyId || old.queueId !== queueId) {
    return null;
  }
  if (oldDayKey !== newDayKey) return null;
  const n = Number(old.ticketNumber);
  return Number.isInteger(n) && n > 0 ? n : null;
}

module.exports = {
  ticketCounterRef,
  nextTicketNumber,
  counterUpdate,
  manualCustomerName,
  keptTicketNumber,
};
