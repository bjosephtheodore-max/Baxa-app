import 'package:baxa/services/password_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Règle des mots de passe (8 caractères, une lettre, un chiffre)', () {
    test('valide : lettres + chiffre, 8 caractères', () {
      expect(isPasswordValid('baxa2026'), isTrue);
      expect(validateNewPassword('baxa2026'), isNull);
    });

    test('lettre accentuée acceptée comme lettre', () {
      expect(isPasswordValid('été12345'), isTrue);
    });

    test('trop court', () {
      expect(isPasswordValid('baxa202'), isFalse);
      expect(validateNewPassword('baxa202'), contains('8 caractères'));
    });

    test('sans chiffre / sans lettre', () {
      expect(validateNewPassword('baxabaxa'), contains('un chiffre'));
      expect(validateNewPassword('12345678'), contains('une lettre'));
    });

    test('vide', () {
      expect(validateNewPassword(''), 'Veuillez entrer un mot de passe');
      expect(validateNewPassword(null), 'Veuillez entrer un mot de passe');
    });

    test('critères cochés un à un', () {
      final c = passwordCriteria('abc');
      expect(c.map((e) => e.ok).toList(), [false, true, false]);
    });
  });
}
