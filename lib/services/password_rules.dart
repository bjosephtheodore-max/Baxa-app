// ════════════════════════════════════════════════════════════════════
// Règle des mots de passe Baxa — UN seul endroit pour toute l'app.
//
// 8 caractères minimum, au moins une lettre et au moins un chiffre. Pas de
// majuscule ni de caractère spécial obligatoire : sur téléphone, ce sont ces
// règles-là qui font abandonner une inscription.
//
// À appliquer UNIQUEMENT quand un mot de passe est CHOISI (inscription,
// changement de mot de passe) — jamais à la connexion : les comptes créés
// avant cette règle continuent de se connecter avec leur mot de passe.
//
// MIROIR de la politique de mot de passe Firebase (console : Authentication
// › Settings › Password policy : 8 caractères, une minuscule, un chiffre),
// qui l'impose aussi sur la page web « Mot de passe oublié ».
// ════════════════════════════════════════════════════════════════════

const int kPasswordMinLength = 8;

final RegExp _letter = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]');
final RegExp _digit = RegExp(r'[0-9]');

/// Les trois critères, dans l'ordre affiché sous le champ.
List<({String label, bool ok})> passwordCriteria(String value) => [
  (
    label: '$kPasswordMinLength caractères minimum',
    ok: value.length >= kPasswordMinLength,
  ),
  (label: 'Au moins une lettre', ok: _letter.hasMatch(value)),
  (label: 'Au moins un chiffre', ok: _digit.hasMatch(value)),
];

bool isPasswordValid(String value) => passwordCriteria(value).every((c) => c.ok);

/// Validateur de formulaire pour un NOUVEAU mot de passe (null si valide).
String? validateNewPassword(String? value) {
  final v = value ?? '';
  if (v.isEmpty) return 'Veuillez entrer un mot de passe';
  if (isPasswordValid(v)) return null;
  final missing = passwordCriteria(
    v,
  ).where((c) => !c.ok).map((c) => c.label.toLowerCase());
  return 'Il manque : ${missing.join(', ')}';
}
