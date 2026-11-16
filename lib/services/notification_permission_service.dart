import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// AUTORISATION DES NOTIFICATIONS — état réel et réactivation
/// ============================================================
/// Android ne montre sa fenêtre d'autorisation qu'une ou deux fois : après
/// un refus, l'app ne peut plus la faire réapparaître. Sans ce service, un
/// client qui avait dit « non » ne recevait plus jamais « c'est bientôt
/// votre tour », sans que personne ne s'en aperçoive.
/// On lit donc l'état réel et, s'il le faut, on propose NOTRE message
/// (après une réservation côté client, bandeau sur l'accueil côté
/// structure / staff) ; « Activer » rouvre la fenêtre d'Android si elle
/// est encore possible, sinon la page de Baxa dans les réglages.
class NotificationPermissionService {
  NotificationPermissionService._();

  /// Les notifications peuvent-elles s'afficher sur ce téléphone ?
  static Future<bool> isEnabled() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Notifications : état illisible ($e)');
      return true; // dans le doute, on ne dérange pas
    }
  }

  /// Essaie d'activer les notifications. Renvoie true si elles le sont.
  /// Si Android répond aussitôt « refusé » (il ne montre plus sa fenêtre),
  /// on ouvre la page de Baxa dans les réglages du téléphone.
  static Future<bool> enable() async {
    final watch = Stopwatch()..start();
    try {
      final s = await FirebaseMessaging.instance.requestPermission();
      if (s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional) {
        return true;
      }
    } catch (_) {}
    // Une vraie fenêtre système prend toujours plus d'une demi-seconde
    // (le temps de lire et répondre) : une réponse immédiate veut dire
    // qu'Android ne l'a pas montrée.
    if (watch.elapsedMilliseconds < 600) {
      try {
        await Geolocator.openAppSettings();
      } catch (_) {}
    }
    return false;
  }

  /// Vrai si le message lié à [key] n'a pas été montré depuis [every].
  static Future<bool> isDue(String key, Duration every) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(key);
      if (last == null) return true;
      final since = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(last),
      );
      return since >= every;
    } catch (_) {
      return true;
    }
  }

  /// Mémorise que le message lié à [key] vient d'être montré (ou masqué).
  static Future<void> markShown(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
