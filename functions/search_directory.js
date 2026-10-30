// ════════════════════════════════════════════════════════════════════
// ANNUAIRE DE RECHERCHE PAR PAYS
//
// La page de recherche client n'écoute plus toute la collection
// `companies` (une lecture par structure à chaque ouverture) mais un
// annuaire : quelques documents `searchDirectory/{PAYS}_{n}` qui
// contiennent chacun, dans le champ `entries`, une ligne courte par
// structure (nom, type, ville, position, état…). Une ouverture de la
// recherche = une lecture par document d'annuaire, quel que soit le
// nombre de structures.
//
//   - tenu à jour en direct par le déclencheur sur `companies/{id}`
//     (seulement quand un champ affiché change) ;
//   - reconstruit chaque nuit depuis `companies`, avec la popularité
//     (réservations confirmées encore en base, c.-à-d. ≈ 30 derniers
//     jours grâce à la purge) — le compteur `reservationCount` n'est
//     plus écrit à chaque réservation.
//
// Un pays dont l'annuaire dépasse MAX_ENTRIES_PER_SHARD est réparti sur
// plusieurs documents (limite Firestore : 1 Mo par document). Le nombre
// de documents par pays est fixé par la reconstruction de nuit et noté
// dans `searchDirectoryMeta/shards`.
//
// Ce fichier ne contient que de la logique pure (pas de Firestore) : la
// colle avec la base est dans index.js.
// ════════════════════════════════════════════════════════════════════

/** Pays des structures sans pays renseigné (anciennes inscriptions) :
 * leur annuaire est lu par tous les clients, comme avant. */
const NO_COUNTRY = "_none";

/** ~300 octets par ligne → ~600 Ko par document, marge sous 1 Mo. */
const MAX_ENTRIES_PER_SHARD = 2000;

/** Champs de `companies` recopiés dans l'annuaire, sous le même nom (la
 * page de recherche les lit exactement comme avant). */
const ENTRY_FIELDS = [
  "nom", "type", "typeCategorie", "ville", "adresse", "country",
  "position", "queueCount", "closedNow", "reopenAt",
];

/** Code pays de l'annuaire : ISO en majuscules, ou NO_COUNTRY. */
function countryKey(data) {
  const c = data && typeof data.country === "string"
    ? data.country.trim().toUpperCase()
    : "";
  return c === "" || c === "XX" ? NO_COUNTRY : c;
}

/** Une structure supprimée n'apparaît plus dans la recherche. */
function isListed(data) {
  return !!data && data.status !== "deleted";
}

/** Ligne d'annuaire : champs affichés, `null` quand absents. */
function buildEntry(data) {
  const entry = {};
  for (const f of ENTRY_FIELDS) {
    const v = data ? data[f] : undefined;
    entry[f] = v === undefined ? null : v;
  }
  return entry;
}

/** Valeur comparable (Timestamp → ms, GeoPoint → [lat, lng]). */
function comparable(v) {
  if (v === null || v === undefined) return null;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (typeof v.latitude === "number" && typeof v.longitude === "number") {
    return [v.latitude, v.longitude];
  }
  return v;
}

function entriesEqual(a, b) {
  return ENTRY_FIELDS.every(
    (f) => JSON.stringify(comparable(a[f])) === JSON.stringify(comparable(b[f])),
  );
}

/**
 * Opérations à appliquer à l'annuaire après l'écriture d'une fiche
 * `companies` (before / after = données, ou null si absente).
 * Retourne une liste de {op: "remove"|"upsert", country, entry?}.
 * Liste vide si rien d'affiché n'a changé.
 */
function syncOps(before, after) {
  const ops = [];
  const wasListed = isListed(before);
  const listed = isListed(after);
  const oldCountry = wasListed ? countryKey(before) : null;
  const newCountry = listed ? countryKey(after) : null;

  if (wasListed && (!listed || oldCountry !== newCountry)) {
    ops.push({op: "remove", country: oldCountry});
  }
  if (listed) {
    const entry = buildEntry(after);
    const changed = !wasListed || oldCountry !== newCountry ||
      !entriesEqual(buildEntry(before), entry);
    if (changed) ops.push({op: "upsert", country: newCountry, entry});
  }
  return ops;
}

/** Hachage FNV-1a 32 bits : répartition stable d'une structure entre
 * les documents d'un même pays. */
function hash32(s) {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

function shardIndex(companyId, shardCount) {
  const n = Math.max(1, shardCount || 1);
  return hash32(companyId) % n;
}

function shardCountFor(entryCount) {
  return Math.max(1, Math.ceil(entryCount / MAX_ENTRIES_PER_SHARD));
}

function shardDocId(country, index) {
  return `${country}_${index}`;
}

/** Ligne sans les champs vides (pour une écriture complète du document). */
function compactEntry(entry) {
  const out = {};
  for (const [k, v] of Object.entries(entry)) {
    if (v !== null && v !== undefined) out[k] = v;
  }
  return out;
}

/**
 * Plan complet de l'annuaire (reconstruction de nuit).
 * `companies` : [{id, data, popularity}].
 * Retourne {docs: Map docId → {country, shard, entries}, shardCounts}.
 */
function planDirectory(companies) {
  const byCountry = new Map();
  for (const c of companies) {
    if (!isListed(c.data)) continue;
    const country = countryKey(c.data);
    if (!byCountry.has(country)) byCountry.set(country, []);
    byCountry.get(country).push(c);
  }

  const docs = new Map();
  const shardCounts = {};
  for (const [country, list] of byCountry) {
    const count = shardCountFor(list.length);
    shardCounts[country] = count;
    for (let i = 0; i < count; i++) {
      docs.set(shardDocId(country, i), {country, shard: i, entries: {}});
    }
    for (const c of list) {
      const shard = shardIndex(c.id, count);
      docs.get(shardDocId(country, shard)).entries[c.id] = compactEntry({
        ...buildEntry(c.data),
        popularity: c.popularity || 0,
      });
    }
  }
  return {docs, shardCounts};
}

module.exports = {
  NO_COUNTRY,
  MAX_ENTRIES_PER_SHARD,
  ENTRY_FIELDS,
  countryKey,
  isListed,
  buildEntry,
  entriesEqual,
  syncOps,
  hash32,
  shardIndex,
  shardCountFor,
  shardDocId,
  compactEntry,
  planDirectory,
};
