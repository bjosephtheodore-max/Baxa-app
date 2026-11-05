// ════════════════════════════════════════════════════════════════════
// COMPTE STRUCTURE — inscription et rôle, le serveur est l'arbitre
//
// Une seule fonction appelable `companyAccount` (2e génération), deux
// actions :
//   • create       : crée la fiche `companies/{uid}` d'une nouvelle
//                    structure et pose l'étiquette `role: "company"` sur
//                    le compte. L'app ne crée plus jamais la fiche
//                    elle-même (voir firestore.rules).
//   • resolveRole  : dit à l'app ce qu'est le compte connecté — structure,
//                    membre d'équipe, ou ni l'un ni l'autre. Pose au
//                    passage l'étiquette sur les structures créées avant
//                    ce mécanisme (rattrapage, une seule fois).
//
// Sans cette vérification, n'importe quel compte (client, ancien client
// Google…) entrait dans l'espace structure et pouvait y créer des files.
//
// Région africa-south1 : à côté de la base Firestore (Johannesburg).
// ════════════════════════════════════════════════════════════════════
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const zone = require("./zone");

const REGION = "africa-south1";
const ROLE_COMPANY = "company";

// MIROIR de la liste de prereception_page.dart (`_typescompanies`).
const CATEGORIES = ["Banque", "Restaurant", "Commerce", "Administration",
  "Autre"];

const refuse = (reason, message) =>
  new HttpsError("failed-precondition", message, {reason});

// ── Validation des champs envoyés par le formulaire ────────────────
function text(data, key, {required = false, max = 80} = {}) {
  const v = data ? data[key] : undefined;
  if (v === undefined || v === null || v === "") {
    if (required) {
      throw new HttpsError("invalid-argument", `Champ manquant : ${key}.`);
    }
    return null;
  }
  if (typeof v !== "string") {
    throw new HttpsError("invalid-argument", `Champ invalide : ${key}.`);
  }
  const t = v.trim();
  if (!t) {
    if (required) {
      throw new HttpsError("invalid-argument", `Champ manquant : ${key}.`);
    }
    return null;
  }
  if (t.length > max) {
    throw new HttpsError("invalid-argument", `Champ trop long : ${key}.`);
  }
  return t;
}

/** Valeur au format attendu, sinon ignorée (c'est `pattern` qui borne la
 * longueur ; la limite large évite seulement un texte démesuré). */
function matching(data, key, pattern) {
  const t = text(data, key, {max: 60});
  return t && pattern.test(t) ? t : null;
}

/** Fiche structure à écrire, à partir des champs du formulaire. */
function companyFields(data, email) {
  const category = text(data, "typeCategorie", {max: 40});
  if (category && !CATEGORIES.includes(category)) {
    throw new HttpsError("invalid-argument", "Type de structure inconnu.");
  }
  const tzRaw = text(data, "timeZone", {max: 60});
  // tzOf renvoie le fuseau par défaut pour une valeur invalide : on ne
  // garde que les fuseaux réellement reconnus.
  const timeZone = tzRaw && zone.tzOf(tzRaw) === tzRaw ? tzRaw : null;

  const fields = {
    nom: text(data, "nom", {required: true, max: 80}),
    type: text(data, "type", {max: 60}),
    typeCategorie: category,
    ville: text(data, "ville", {max: 80}),
    country: matching(data, "country", /^[A-Z]{2}$/),
    language: matching(data, "language", /^[a-z]{2,3}$/),
    locale: matching(data, "locale", /^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8})*$/),
    timeZone,
    email: email || null,
  };
  // Pas de champ vide dans la fiche (comme l'ancienne écriture de l'app).
  for (const k of Object.keys(fields)) {
    if (fields[k] === null) delete fields[k];
  }
  return fields;
}

/** Ajoute l'étiquette structure sans écraser d'autres étiquettes. */
async function setCompanyClaim(auth, uid) {
  const user = await auth.getUser(uid);
  const claims = user.customClaims || {};
  if (claims.role === ROLE_COMPANY) return;
  await auth.setCustomUserClaims(uid, {...claims, role: ROLE_COMPANY});
}

const isAnonymous = (user) => user.provider === "anonymous";

/** Vraie fiche structure : créée par une inscription, donc avec un nom.
 * Une fiche « fantôme » (sans nom — p. ex. compteurs écrits par le serveur
 * pour un compte client entré par erreur dans l'espace structure) ne
 * compte pas. Le rôle `customer` du profil n'est PAS un critère : un
 * responsable qui s'est un jour connecté côté client avec la même adresse
 * le porte aussi, et reste bien une structure. */
const isRealCompany = (snap) => snap.exists &&
  typeof snap.get("nom") === "string" && snap.get("nom").trim() !== "";

// ── CRÉER LA STRUCTURE ──────────────────────────────────────────────
async function create(db, auth, user, data) {
  if (isAnonymous(user)) {
    throw refuse("anonymous",
      "Créez d'abord votre accès avec un e-mail et un mot de passe.");
  }
  const companyRef = db.collection("companies").doc(user.uid);
  const userRef = db.collection("users").doc(user.uid);
  const fields = companyFields(data, user.email);

  const created = await db.runTransaction(async (tx) => {
    const [companySnap, userSnap] = await Promise.all([
      tx.get(companyRef), tx.get(userRef),
    ]);
    // Déjà créée (double appui, nouvelle tentative après une coupure) :
    // on ne réécrit rien, l'étiquette est reposée plus bas.
    if (isRealCompany(companySnap)) return false;

    const role = userSnap.exists ? userSnap.get("role") : null;
    if (role === "customer") {
      throw refuse("customerAccount",
        "Cette adresse est déjà utilisée par un compte client Baxa. " +
        "Utilisez une autre adresse pour votre structure.");
    }
    if (role === "staff") {
      throw refuse("staffAccount",
        "Ce compte fait partie de l'équipe d'une structure. Utilisez une " +
        "autre adresse pour inscrire votre structure.");
    }
    // Fusion : complète une éventuelle fiche fantôme au lieu d'échouer.
    tx.set(companyRef, {...fields, createdAt: FieldValue.serverTimestamp()},
      {merge: true});
    return true;
  });

  await setCompanyClaim(auth, user.uid);
  return {role: ROLE_COMPANY, created};
}

// ── QUEL EST CE COMPTE ? ────────────────────────────────────────────
// Ordre : membre d'équipe d'abord (comme l'app), puis structure.
async function resolveRole(db, auth, user) {
  const [userSnap, companySnap] = await Promise.all([
    db.collection("users").doc(user.uid).get(),
    db.collection("companies").doc(user.uid).get(),
  ]);
  const u = userSnap.exists ? userSnap.data() : {};
  if (u.role === "staff" && u.companyId) {
    return {role: "staff", companyId: u.companyId};
  }
  if (isRealCompany(companySnap) && !isAnonymous(user)) {
    await setCompanyClaim(auth, user.uid);
    return {role: ROLE_COMPANY};
  }
  return {role: "none"};
}

// ── Point d'entrée ──────────────────────────────────────────────────
const ACTIONS = {create, resolveRole};

const companyAccount = onCall({region: REGION}, async (request) => {
  const action = request.data && request.data.action;
  if (action === "warmup") return {ok: true};

  const handler = ACTIONS[action];
  if (!handler) {
    throw new HttpsError("invalid-argument", "Action inconnue.");
  }
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  const token = request.auth.token || {};
  const user = {
    uid: request.auth.uid,
    email: token.email || null,
    provider: (token.firebase && token.firebase.sign_in_provider) || null,
  };
  return handler(admin.firestore(), admin.auth(), user, request.data);
});

module.exports = {
  companyAccount,
  // Exposés pour les tests (émulateur).
  create, resolveRole, companyFields, CATEGORIES,
};
