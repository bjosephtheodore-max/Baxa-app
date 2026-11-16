// ════════════════════════════════════════════════════════════════════
// CODES D'INVITATION D'ÉQUIPE — durée de validité
//
// Un code sert à UNE personne (désactivé dès qu'il est utilisé, voir
// joinTeamWithCode) et n'est valable que 48 h : un code partagé puis
// oublié (WhatsApp…) ne doit pas rester utilisable indéfiniment. L'écran
// « Mon équipe » (lib/page b-acceuil/company/team_page.dart) affiche la
// même durée : MIROIR de kInviteValidity.
// Fonctions pures — testées dans test/invite.test.js.
// ════════════════════════════════════════════════════════════════════

const INVITE_VALIDITY_MS = 48 * 60 * 60 * 1000;

function toMillis(v) {
  if (!v) return null;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/**
 * Vrai si le code a dépassé sa durée de validité. Un code sans date de
 * création (anciens codes) n'expire pas.
 */
function isInviteExpired(createdAt, now = new Date()) {
  const created = toMillis(createdAt);
  if (created == null) return false;
  return toMillis(now) - created > INVITE_VALIDITY_MS;
}

module.exports = {INVITE_VALIDITY_MS, isInviteExpired};
