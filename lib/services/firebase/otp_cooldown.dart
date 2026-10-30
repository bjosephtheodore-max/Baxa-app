/// Délai minimum entre deux SMS de code vers un même numéro.
///
/// Chaque SMS est facturé : sans ce délai, un utilisateur impatient (ou un
/// double tap) pouvait redemander un code en boucle. Retenu pour toute la
/// session de l'app, donc quitter l'écran et revenir ne le contourne pas.
class OtpCooldown {
  OtpCooldown._();

  static const Duration delay = Duration(seconds: 60);
  static final Map<String, DateTime> _lastSent = {};

  /// Secondes restantes avant de pouvoir redemander un code pour [phone]
  /// (0 = possible tout de suite).
  static int secondsLeft(String phone) {
    final last = _lastSent[phone];
    if (last == null) return 0;
    final left = delay - DateTime.now().difference(last);
    return left.isNegative ? 0 : left.inSeconds + 1;
  }

  /// À appeler quand le SMS est parti (callback `codeSent`).
  static void markSent(String phone) => _lastSent[phone] = DateTime.now();

  static String waitMessage(int seconds) =>
      'Patientez $seconds s avant de demander un nouveau code.';
}
