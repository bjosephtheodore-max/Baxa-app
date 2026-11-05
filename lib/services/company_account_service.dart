import 'package:baxa/services/firebase/cloud_functions_region.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ════════════════════════════════════════════════════════════════════
// Compte structure : inscription et rôle, arbitrés par le serveur
// (Cloud Function `companyAccount`, functions/company_account.js).
//
//  • createCompany : crée la fiche `companies/{uid}` (l'app ne l'écrit
//    plus elle-même) et pose l'étiquette « structure » sur le compte.
//  • resolveRole   : structure, membre d'équipe, ou rien. Lit d'abord
//    l'étiquette dans le jeton (aucun appel réseau) ; sinon demande au
//    serveur, qui rattrape au passage les structures créées avant ce
//    mécanisme.
// ════════════════════════════════════════════════════════════════════

enum CompanyRole { company, staff, none }

/// Erreur lisible d'une opération de compte structure.
class CompanyAccountException implements Exception {
  final String message;

  /// Motif renvoyé par le serveur (`customerAccount`, `staffAccount`…).
  final String? reason;

  /// Vrai si l'échec vient du réseau (pas de connexion, délai dépassé).
  final bool isNetwork;

  const CompanyAccountException(
    this.message, {
    this.reason,
    this.isNetwork = false,
  });

  @override
  String toString() => message;
}

const String kNoConnectionMessage =
    'Pas de connexion. Vérifiez votre réseau, puis réessayez.';

class CompanyAccountService {
  CompanyAccountService._();

  static HttpsCallable get _callable =>
      baxaFunctions.httpsCallable('companyAccount');

  /// Réveille la fonction en avance (écran d'inscription ouvert) : le vrai
  /// appel répond ensuite plus vite. Sans effet en cas d'échec.
  static Future<void> warmup() async {
    try {
      await _callable.call({'action': 'warmup'});
    } catch (_) {}
  }

  /// Crée la structure du compte connecté. [fields] : champs du formulaire
  /// (nom, type, typeCategorie, ville, country, language, locale, timeZone).
  /// Sans danger à rappeler après une coupure : le serveur ne réécrit rien
  /// si la fiche existe déjà.
  static Future<void> createCompany(Map<String, dynamic> fields) async {
    await _call({...fields, 'action': 'create'});
    await _refreshToken();
  }

  /// Rôle du compte connecté dans l'espace structure.
  static Future<({CompanyRole role, String? companyId})> resolveRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (role: CompanyRole.none, companyId: null);

    // Étiquette déjà présente dans le jeton : réponse immédiate.
    try {
      final token = await user.getIdTokenResult();
      if (token.claims?['role'] == 'company') {
        return (role: CompanyRole.company, companyId: user.uid);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        throw const CompanyAccountException(
          kNoConnectionMessage,
          isNetwork: true,
        );
      }
      rethrow;
    }

    final res = await _call({'action': 'resolveRole'});
    switch (res['role']) {
      case 'company':
        await _refreshToken();
        return (role: CompanyRole.company, companyId: user.uid);
      case 'staff':
        return (
          role: CompanyRole.staff,
          companyId: res['companyId'] as String?,
        );
      default:
        return (role: CompanyRole.none, companyId: null);
    }
  }

  // Nouveau jeton : l'étiquette posée par le serveur y apparaît, et les
  // prochains appels n'ont plus besoin du réseau pour la lire.
  static Future<void> _refreshToken() async {
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (e) {
      // Non bloquant : le serveur a déjà tranché, le jeton se rafraîchira
      // de lui-même (au plus tard dans l'heure).
      debugPrint('CompanyAccountService: jeton non rafraîchi ($e)');
    }
  }

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> data) async {
    try {
      final res = await _callable.call(data);
      final out = res.data;
      return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw _fromFunctions(e);
    }
  }

  static CompanyAccountException _fromFunctions(FirebaseFunctionsException e) {
    final details = e.details;
    final reason = details is Map ? details['reason'] as String? : null;
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return const CompanyAccountException(
          kNoConnectionMessage,
          isNetwork: true,
        );
      case 'failed-precondition':
      case 'invalid-argument':
        return CompanyAccountException(
          e.message?.isNotEmpty == true
              ? e.message!
              : 'Ces informations ne sont pas valides.',
          reason: reason,
        );
      case 'unauthenticated':
        return const CompanyAccountException(
          'Votre session a expiré. Reconnectez-vous.',
        );
      default:
        return const CompanyAccountException(
          'Une erreur est survenue. Réessayez.',
        );
    }
  }
}
