// ============================================================
// CONSTANTES GLOBALES DE RÉSERVATION — MVP
// Modifier ici uniquement pour changer les règles globales.
// ============================================================

/// Nombre maximum de réservations qu'un customer peut CRÉER par jour
/// calendaire (minuit → minuit). S'applique toutes entreprises confondues.
/// Les annulations ne restituent pas de quota.
const int kMaxDailyReservations = 5;

/// Délai minimum (en minutes) à attendre après la fin d'un créneau
/// avant de pouvoir réserver à nouveau dans la MÊME file
const int kCooldownSameQueueMinutes = 5;

/// Écart minimum (en minutes) requis entre deux créneaux
/// dans des files DIFFÉRENTES de la MÊME entreprise
const int kMinGapSameCompanyMinutes = 5;

/// Écart minimum (en minutes) requis entre deux créneaux
/// dans des ENTREPRISES DIFFÉRENTES
const int kMinGapDifferentCompanyMinutes = 30;

/// ============================================================
/// FERMETURE D'UNE FILE
/// ============================================================
/// Une file porte `closureStart` (+ `closureEnd` optionnel = fermeture
/// indéterminée) dès qu'une fermeture la concerne — planifiée ou immédiate,
/// un seul service ou toute la structure. Ce prédicat est LE point unique
/// qui décide si une file accepte encore de nouvelles réservations.
bool isQueueClosedNow(
  DateTime? closureStart,
  DateTime? closureEnd, {
  DateTime? now,
}) {
  if (closureStart == null) return false;
  final n = now ?? DateTime.now();
  if (n.isBefore(closureStart)) return false; // fermeture planifiée, pas encore
  if (closureEnd != null && n.isAfter(closureEnd)) return false; // terminée
  return true;
}
