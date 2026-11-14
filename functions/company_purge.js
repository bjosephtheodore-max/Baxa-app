// ════════════════════════════════════════════════════════════════════
// SUPPRESSION COMPLÈTE D'UNE STRUCTURE — fin du délai de « Quitter Baxa »
//
// Au bout des 7 jours, TOUT disparaît (promesse des pages getbaxa.com/
// suppression et /confidentialite) :
//  • fiche `companies/{id}` et tout ce qu'elle contient (files, plages,
//    créneaux, réservations, équipe, invitations, notifications,
//    compteurs…) — d'un seul coup, y compris ce qu'on ajoutera plus tard ;
//  • réveil des notifications (`companyWake/{id}`) ;
//  • ancien profil client/notifications du même compte, s'il en reste
//    (comptes de test d'avant les protections d'inscription) ;
//  • compte de connexion : la même adresse peut se réinscrire comme une
//    NOUVELLE structure.
// Ne restent que des traces sans donnée personnelle : la demande de départ
// réduite à « terminée » + date (l'app d'une structure encore ouverte au
// moment de la suppression affiche « Cet établissement a été supprimé »),
// et l'alerte admin réduite au motif + dates.
//
// REJOUABLE : chaque étape supporte d'être refaite. Le passage de nuit
// rattrape ainsi les suppressions en erreur et les anciennes fiches
// « fantômes » (`status: "deleted"`) d'avant ce fonctionnement.
// ════════════════════════════════════════════════════════════════════
const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const zone = require("./zone");

const BATCH_LIMIT = 400;

async function defaultDeleteAuthUser(uid) {
  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
  }
}

/** Réservations encore à venir : annulées, et chaque client prévenu. */
async function cancelUpcoming(db, companyRef, companyName, tz, now) {
  const snap = await companyRef.collection("reservations")
    .where("status", "==", "confirmed").get();
  const upcoming = snap.docs.filter((d) => {
    const start = d.get("slotStart");
    return start && start.toDate() > now;
  });

  let batch = db.batch();
  let n = 0;
  const flush = async () => {
    if (n > 0) await batch.commit();
    batch = db.batch();
    n = 0;
  };
  for (const doc of upcoming) {
    const r = doc.data();
    batch.update(doc.ref, {
      status: "cancelled",
      cancelledAt: FieldValue.serverTimestamp(),
      cancellationSource: "company_deleted",
    });
    n++;
    if (r.customerId && r.customerId !== "manual_booking") {
      const start = r.slotStart.toDate();
      batch.set(db.collection("customers").doc(r.customerId)
        .collection("notifications").doc(), {
        title: "📅 Réservation annulée",
        body:
          `Votre réservation du ${zone.fmtDdMmYyyy(start, tz)} ` +
          `à ${zone.fmtHHhMM(start, tz)} chez ` +
          `${r.queueName || companyName} a été annulée. ` +
          `${companyName || "Cet établissement"} n'est plus disponible ` +
          "sur Baxa.",
        createdAt: FieldValue.serverTimestamp(),
        type: "cancellation_by_company",
        payload: null,
      });
      n++;
    }
    if (n >= BATCH_LIMIT) await flush();
  }
  await flush();
  return upcoming.length;
}

/** Alerte admin du départ : on garde le motif et les dates, pas qui. */
async function anonymizeAlerts(db, companyId) {
  const snap = await db.collection("adminAlerts")
    .where("companyId", "==", companyId).get();
  const del = FieldValue.delete();
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.update(doc.ref, {
      companyName: del,
      email: del,
      phone: del,
      anonymizedAt: FieldValue.serverTimestamp(),
    });
  }
  if (!snap.empty) await batch.commit();
}

/**
 * Supprime complètement la structure [companyId] (= uid de son compte).
 * [deleteAuthUser] : injectable pour les tests.
 */
async function purgeCompany(db, companyId, {
  now = new Date(),
  deleteAuthUser = defaultDeleteAuthUser,
} = {}) {
  const companyRef = db.collection("companies").doc(companyId);
  const companySnap = await companyRef.get();
  const company = companySnap.exists ? companySnap.data() : {};

  let cancelled = 0;
  if (companySnap.exists) {
    // 1. D'abord la mention « supprimée » : l'annuaire de recherche la
    //    retire aussitôt, et les réactions automatiques en retard (réveils
    //    replanifiés par la suppression des files…) ne recréent plus rien.
    await companyRef.update({
      status: "deleted",
      deletedAt: FieldValue.serverTimestamp(),
      isActive: false,
    });
    // 2. Clients encore attendus (normalement déjà prévenus à la demande).
    cancelled = await cancelUpcoming(db, companyRef, company.nom || "",
      zone.tzOf(company.timeZone), now);
  }

  // 3. La fiche et tout son contenu.
  await db.recursiveDelete(companyRef);
  // 4. Réveil des notifications.
  await db.collection("companyWake").doc(companyId).delete();
  // 5. Restes d'un ancien profil client sur le même compte.
  await db.recursiveDelete(db.collection("users").doc(companyId));
  await db.recursiveDelete(db.collection("customers").doc(companyId));
  // 6. Alerte admin : motif gardé, identité retirée.
  await anonymizeAlerts(db, companyId);
  // 7. Compte de connexion.
  await deleteAuthUser(companyId);
  // 8. Demande de départ réduite au strict nécessaire (réécrite en entier :
  //    e-mail, nom, téléphone et motif disparaissent).
  await db.collection("deletionRequests").doc(companyId).set({
    status: "completed",
    completedAt: FieldValue.serverTimestamp(),
  });

  return {cancelled};
}

/**
 * Structures à (re)nettoyer au passage de nuit : anciennes fiches
 * « fantômes » et suppressions restées en erreur.
 */
async function purgeBacklog(db) {
  const [ghosts, failed] = await Promise.all([
    db.collection("companies").where("status", "==", "deleted").get(),
    db.collection("deletionRequests").where("status", "==", "error").get(),
  ]);
  return [...new Set([
    ...ghosts.docs.map((d) => d.id),
    ...failed.docs.map((d) => d.id),
  ])];
}

module.exports = {purgeCompany, purgeBacklog};
