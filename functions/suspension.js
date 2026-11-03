// ════════════════════════════════════════════════════════════════════
// RÉSERVATIONS SUSPENDUES (blocage d'une plage par l'entreprise)
//
// Quand l'entreprise bloque une plage (incident), les réservations de ses
// créneaux passent `suspended: true`. Si le créneau se TERMINE alors qu'il
// est toujours bloqué, le client ne peut plus être servi : sa réservation
// est annulée (`company_block_unresolved`) et FONCTION 6bis l'invite à
// re-réserver.
//
// Qui fait cette annulation :
//  1. la tâche « créneau passé » (Cloud Tasks, programmée à la fin de
//     chaque créneau réservé) → le client est prévenu à la minute près ;
//  2. le déblocage depuis l'app (créneaux déjà passés) ;
//  3. le filet de sécurité de nuit (`resolveCompanySuspensions`), pour ce
//     qui aurait échappé aux deux premiers (ex. ajouts sur place, sans
//     tâche programmée).
// Les trois appliquent la même mise à jour : ci-dessous.
// Fonctions pures — testées dans test/suspension.test.js.
// ════════════════════════════════════════════════════════════════════

/** La réservation est-elle encore suspendue et active ? */
function isStillSuspended(data) {
  return !!data && data.status === "confirmed" && data.suspended === true;
}

/**
 * La tâche d'étape `kind` doit-elle annuler cette réservation ? Seule
 * l'étape « passed » (fin du créneau) le fait.
 */
function shouldResolveAtSlotEnd(kind, data) {
  return kind === "passed" && isStillSuspended(data);
}

/** Mise à jour d'annulation d'une suspension non résolue. */
function unresolvedSuspensionUpdate(FieldValue) {
  return {
    status: "cancelled",
    cancelledAt: FieldValue.serverTimestamp(),
    cancellationSource: "company_block_unresolved",
    suspended: FieldValue.delete(),
    suspendedReason: FieldValue.delete(),
    suspendedAt: FieldValue.delete(),
  };
}

module.exports = {
  isStillSuspended,
  shouldResolveAtSlotEnd,
  unresolvedSuspensionUpdate,
};
