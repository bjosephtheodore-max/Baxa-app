import 'package:baxa/services/company_functions.dart';
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
//
// Erreurs : CompanyActionException (voir company_functions.dart).
// ════════════════════════════════════════════════════════════════════

enum CompanyRole { company, staff, none }

class CompanyAccountService {
  CompanyAccountService._();

  static const String _function = 'companyAccount';

  /// Réveille la fonction en avance (écran d'inscription ouvert).
  static Future<void> warmup() => warmupCompanyFunction(_function);

  /// Crée la structure du compte connecté. [fields] : champs du formulaire
  /// (nom, type, typeCategorie, ville, country, language, locale, timeZone).
  /// Sans danger à rappeler après une coupure : le serveur ne réécrit rien
  /// si la fiche existe déjà.
  static Future<void> createCompany(Map<String, dynamic> fields) async {
    await callCompanyFunction(_function, {...fields, 'action': 'create'});
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
        throw const CompanyActionException(
          kNoConnectionMessage,
          isNetwork: true,
        );
      }
      rethrow;
    }

    final res = await callCompanyFunction(_function, {'action': 'resolveRole'});
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
}
