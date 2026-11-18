// ════════════════════════════════════════════════════════════════════
// COMPTES INVITÉS INACTIFS — suppression après 12 mois
//
// Un invité = un client sans inscription (connexion anonyme : ni Google,
// ni téléphone, ni e-mail). Sans bouton « Supprimer mon compte », ses
// données resteraient pour toujours. Annoncé sur getbaxa.com
// (confidentialité § 5, conditions § 4, suppression) : après 12 mois
// sans utilisation de l'app, son compte et ses données sont supprimés.
//
// Inactivité : dates tenues par Firebase Authentication (dernier
// renouvellement de connexion — l'app le fait régulièrement tant qu'elle
// est utilisée —, dernière connexion, création). Rien à écrire côté app.
// La suppression elle-même est celle de « Supprimer mon compte »
// (booking.deleteAccount : réservations à venir annulées, historique
// anonymisé, fiche et compte effacés ; refuse structure et staff).
// Fonctions testées dans test/guest_purge.test.js.
// ════════════════════════════════════════════════════════════════════

const GUEST_INACTIVITY_MS = 365 * 24 * 60 * 60 * 1000;

/** Compte invité : aucune méthode de connexion (Google, téléphone…). */
function isGuest(userRecord) {
  return !!userRecord &&
    (userRecord.providerData || []).length === 0 &&
    !userRecord.email &&
    !userRecord.phoneNumber;
}

/** Dernière trace d'utilisation connue (ms), ou null. */
function lastActivityMs(userRecord) {
  const m = (userRecord && userRecord.metadata) || {};
  const times = [m.lastRefreshTime, m.lastSignInTime, m.creationTime]
    .map((t) => (t ? Date.parse(t) : NaN))
    .filter((t) => Number.isFinite(t));
  return times.length ? Math.max(...times) : null;
}

/** Invité sans aucune utilisation depuis plus de 12 mois ? */
function isInactiveGuest(userRecord, now = new Date()) {
  if (!isGuest(userRecord)) return false;
  const last = lastActivityMs(userRecord);
  if (last == null) return false; // date inconnue : on ne touche à rien
  return now.getTime() - last > GUEST_INACTIVITY_MS;
}

/**
 * Parcourt tous les comptes (par pages de 1 000) et supprime les invités
 * inactifs avec [deleteAccount]. Un échec sur un compte n'arrête pas les
 * autres. Renvoie {deleted, failed}.
 */
async function purgeInactiveGuests({auth, db, deleteAccount, now = new Date(),
  log = () => {}}) {
  let pageToken;
  let deleted = 0;
  let failed = 0;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const u of page.users) {
      if (!isInactiveGuest(u, now)) continue;
      try {
        await deleteAccount(db, {uid: u.uid}, {}, now);
        deleted++;
      } catch (e) {
        failed++;
        log(`Invité ${u.uid} non supprimé : ${e.message}`);
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return {deleted, failed};
}

module.exports = {
  GUEST_INACTIVITY_MS,
  isGuest,
  lastActivityMs,
  isInactiveGuest,
  purgeInactiveGuests,
};
