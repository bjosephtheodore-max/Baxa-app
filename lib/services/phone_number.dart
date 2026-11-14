// ============================================================
// NUMÉRO DE TÉLÉPHONE — lecture et vérification avant l'envoi d'un SMS
// ============================================================
// Partagé par la connexion staff (staff_auth_page) et client
// (signine_page). Firebase attend un numéro complet au format
// international (« +221781779837 ») : on accepte ici les façons courantes
// de le taper ou de le coller, et on refuse AVANT d'envoyer un SMS
// (facturé) ce qui ne peut pas être un numéro mobile valide.

/// Indicatif utilisé quand l'utilisateur tape un numéro sans indicatif.
const String kDefaultDialCode = '221'; // Sénégal

/// Résultat de la lecture : soit [e164] (« +221781779837 »), soit [error]
/// (message prêt à afficher).
class PhoneParseResult {
  final String? e164;
  final String? error;
  const PhoneParseResult._(this.e164, this.error);
  const PhoneParseResult.ok(String value) : this._(value, null);
  const PhoneParseResult.fail(String message) : this._(null, message);
  bool get isValid => e164 != null;
}

const String _senegalMobileHint =
    'Numéro sénégalais : 9 chiffres commençant par 7 (ex. 78 177 98 37).';

/// Lit [raw] tel que tapé ou collé. Acceptés, entre autres :
///  781779837 · 78 177 98 37 · +221781779837 · +221 78 177 98 37 ·
///  221781779837 · 00221781779837 · numéro d'un autre pays avec son « + ».
PhoneParseResult parsePhoneNumber(String raw) {
  // Espaces (y compris insécables), tirets, points, parenthèses, barres.
  var s = raw.trim().replaceAll(RegExp(r'[\s \-\.\(\)/]'), '');
  if (s.isEmpty) {
    return const PhoneParseResult.fail('Entrez votre numéro de téléphone.');
  }

  if (s.startsWith('00')) s = '+${s.substring(2)}';

  String digits;
  if (s.startsWith('+')) {
    digits = s.substring(1);
  } else {
    if (!RegExp(r'^\d+$').hasMatch(s)) {
      return const PhoneParseResult.fail(
        'Le numéro ne doit contenir que des chiffres.',
      );
    }
    if (s.length == 9) {
      digits = '$kDefaultDialCode$s'; // numéro local sénégalais
    } else if (s.length == 12 && s.startsWith(kDefaultDialCode)) {
      digits = s; // « 221… » tapé sans le +
    } else {
      return const PhoneParseResult.fail(
        'Numéro incomplet. $_senegalMobileHint Pour un autre pays, '
        'commencez par + et l\'indicatif.',
      );
    }
  }

  if (!RegExp(r'^\d+$').hasMatch(digits)) {
    return const PhoneParseResult.fail(
      'Le numéro ne doit contenir que des chiffres.',
    );
  }

  if (digits.startsWith(kDefaultDialCode)) {
    final national = digits.substring(kDefaultDialCode.length);
    // Mobiles sénégalais : 9 chiffres commençant par 7 (les fixes en 3
    // ne reçoivent pas de SMS).
    if (!RegExp(r'^7\d{8}$').hasMatch(national)) {
      return const PhoneParseResult.fail(_senegalMobileHint);
    }
  } else if (digits.length < 8 || digits.length > 15) {
    // Autre pays : longueur d'un numéro international (norme E.164).
    return const PhoneParseResult.fail(
      'Numéro invalide. Vérifiez l\'indicatif et le nombre de chiffres.',
    );
  }

  return PhoneParseResult.ok('+$digits');
}

/// Affichage lisible : « +221 78 177 98 37 » pour le Sénégal, sinon le
/// numéro international tel quel.
String formatPhoneForDisplay(String e164) {
  final m = RegExp(r'^\+221(\d{2})(\d{3})(\d{2})(\d{2})$').firstMatch(e164);
  if (m == null) return e164;
  return '+221 ${m[1]} ${m[2]} ${m[3]} ${m[4]}';
}

/// Message quand Firebase n'envoie pas le SMS sans raison exploitable. Cas
/// connu (14/11/2026) : numéros Yas (76) refusés par Firebase avec le code
/// interne 39 (« 17499 Error code:39 »), ce que l'app ne peut pas corriger.
/// On oriente vers Google, qui ne dépend pas de l'opérateur.
const String kSmsUnavailableMessage =
    'Impossible d\'envoyer un SMS à ce numéro pour le moment. '
    'Continuez avec Google, c\'est plus rapide.';

/// Message lisible pour une erreur Firebase lors de l'envoi d'un code SMS
/// (null = code inconnu : l'appelant affiche [kSmsUnavailableMessage]).
String? phoneAuthErrorMessage(String code) {
  switch (code) {
    case 'invalid-phone-number':
      return 'Ce numéro n\'est pas reconnu. Vérifiez-le et réessayez.';
    case 'too-many-requests':
      return 'Trop de codes demandés pour ce numéro. Réessayez dans '
          'quelques heures, ou continuez avec Google.';
    case 'quota-exceeded':
      return 'Le service SMS est momentanément saturé. Réessayez plus tard, '
          'ou continuez avec Google.';
    case 'network-request-failed':
      return 'Vérifiez votre connexion internet.';
    case 'web-context-cancelled':
      // Page de vérification « je ne suis pas un robot » fermée.
      return 'Vérification annulée. Réessayez, ou continuez avec Google.';
    case 'captcha-check-failed':
    case 'app-not-authorized':
    case 'missing-client-identifier':
    case 'web-internal-error':
      return 'Vérification de l\'appareil impossible. Réessayez, ou '
          'continuez avec Google.';
    case 'internal-error':
    case 'unknown':
    case 'operation-not-allowed':
      return kSmsUnavailableMessage;
    default:
      return null;
  }
}
