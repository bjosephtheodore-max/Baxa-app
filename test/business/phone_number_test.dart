// Lecture d'un numéro avant l'envoi d'un code SMS (lib/services/phone_number.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/services/phone_number.dart';

void main() {
  const expected = '+221781779837';

  group('Numéros sénégalais acceptés, quelle que soit la saisie', () {
    for (final input in [
      '781779837',
      '78 177 98 37',
      '+221781779837',
      '+221 78 177 98 37',
      '221781779837',
      '221 78 177 98 37',
      '00221781779837',
      '00 221 78 177 98 37',
      '+221-78-177-98-37',
      '(+221) 78.177.98.37',
      ' +221 78 177 98 37 ', // espaces insécables (copier-coller)
    ]) {
      test('« $input »', () {
        final r = parsePhoneNumber(input);
        expect(r.error, isNull);
        expect(r.e164, expected);
      });
    }
  });

  group('Refusés avant tout envoi de SMS', () {
    for (final input in [
      '', // vide
      '7817798', // trop court
      '78177983712', // trop long sans indicatif
      '+22178177983', // 8 chiffres après +221
      '+221331234567', // fixe (pas de SMS)
      '0781779837', // 0 en tête : pas un format sénégalais
      '78 177 98 3a', // lettre
      '+221 78 177 98 37 0', // un chiffre de trop
    ]) {
      test('« $input »', () {
        final r = parsePhoneNumber(input);
        expect(r.isValid, isFalse);
        expect(r.error, isNotEmpty);
      });
    }
  });

  test('Autre pays avec son indicatif → accepté tel quel', () {
    expect(parsePhoneNumber('+33 6 12 34 56 78').e164, '+33612345678');
    expect(parsePhoneNumber('0033612345678').e164, '+33612345678');
  });

  test('Affichage lisible', () {
    expect(formatPhoneForDisplay('+221781779837'), '+221 78 177 98 37');
    expect(formatPhoneForDisplay('+33612345678'), '+33612345678');
  });

  test('Messages des erreurs Firebase', () {
    expect(phoneAuthErrorMessage('too-many-requests'), contains('Trop de codes'));
    expect(phoneAuthErrorMessage('invalid-phone-number'), isNotNull);
    expect(phoneAuthErrorMessage('autre-chose'), isNull);
  });

  test('SMS impossible (ex. numéros Yas, code interne 39) → renvoi vers Google', () {
    for (final code in ['internal-error', 'unknown', 'operation-not-allowed']) {
      expect(phoneAuthErrorMessage(code), kSmsUnavailableMessage);
    }
    expect(kSmsUnavailableMessage, contains('Google'));
    expect(phoneAuthErrorMessage('web-context-cancelled'), contains('Google'));
  });
}
