/// ============================================================
/// CONSTANTES GLOBALES DE RÉSERVATION — MVP
/// Modifier ici uniquement pour changer les règles globales.
/// ============================================================

/// Nombre maximum de réservations actives sur toute l'app
/// (toutes entreprises + toutes files confondues)
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

/// Valeur par défaut du champ maxActivePerUser dans une file
const int kDefaultMaxActivePerUser = 1;

/// Valeur par défaut du champ maxReservationsPerPerson dans une plage
const int kDefaultMaxReservationsPerPerson = 2;
