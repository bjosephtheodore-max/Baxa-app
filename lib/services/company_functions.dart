import 'package:baxa/services/firebase/cloud_functions_region.dart';
import 'package:cloud_functions/cloud_functions.dart';

// ════════════════════════════════════════════════════════════════════
// Appels aux fonctions serveur de la structure (companyAccount,
// companyBooking…) : même traduction des erreurs partout, et un message
// clair quand il n'y a pas de réseau — ces actions ne fonctionnent plus
// hors ligne (le serveur vérifie avant d'écrire).
// ════════════════════════════════════════════════════════════════════

const String kNoConnectionMessage =
    'Pas de connexion. Vérifiez votre réseau, puis réessayez.';

/// Erreur lisible d'une action de la structure.
class CompanyActionException implements Exception {
  final String message;

  /// Motif renvoyé par le serveur (`slotFull`, `customerAccount`…).
  final String? reason;

  /// Vrai si l'échec vient du réseau (pas de connexion, délai dépassé).
  final bool isNetwork;

  const CompanyActionException(
    this.message, {
    this.reason,
    this.isNetwork = false,
  });

  @override
  String toString() => message;
}

/// Appelle [function] avec [data] ; renvoie sa réponse, ou lève une
/// [CompanyActionException] au message prêt à afficher.
Future<Map<String, dynamic>> callCompanyFunction(
  String function,
  Map<String, dynamic> data,
) async {
  try {
    final res = await baxaFunctions.httpsCallable(function).call(data);
    final out = res.data;
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  } on FirebaseFunctionsException catch (e) {
    throw _fromFunctions(e);
  }
}

/// Réveille [function] en avance (écran ouvert) : le vrai appel répond
/// ensuite sans le délai du premier démarrage. Sans effet en cas d'échec.
Future<void> warmupCompanyFunction(String function) async {
  try {
    await baxaFunctions.httpsCallable(function).call({'action': 'warmup'});
  } catch (_) {}
}

CompanyActionException _fromFunctions(FirebaseFunctionsException e) {
  final details = e.details;
  final reason = details is Map ? details['reason'] as String? : null;
  final serverMessage = e.message?.isNotEmpty == true ? e.message! : null;
  switch (e.code) {
    case 'unavailable':
    case 'deadline-exceeded':
      return const CompanyActionException(
        kNoConnectionMessage,
        isNetwork: true,
      );
    case 'failed-precondition':
    case 'invalid-argument':
    case 'permission-denied':
    case 'already-exists':
      return CompanyActionException(
        serverMessage ?? 'Cette action n\'est pas possible.',
        reason: reason,
      );
    case 'unauthenticated':
      return const CompanyActionException(
        'Votre session a expiré. Reconnectez-vous.',
      );
    default:
      return const CompanyActionException(
        'Une erreur est survenue. Réessayez.',
      );
  }
}
