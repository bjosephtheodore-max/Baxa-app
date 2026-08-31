import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Icône de la barre de statut Android pour TOUTES les notifications de l'app
/// (locales comme push) — le « B » monochrome, jamais le logo de l'app.
/// Voir android/.../drawable/ic_stat_baxa.xml et le `default_notification_icon`
/// du manifeste : cette constante doit rester alignée avec eux.
const String kNotifAndroidSmallIcon = '@drawable/ic_stat_baxa';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Callback pour gérer les actions de notification
  static Function(String action, String? payload)? onNotificationAction;

  // ---- INITIALISATION ----
  Future<void> init() async {
    // Icône dédiée à la barre de statut (le "B"), pas le logo de l'app —
    // voir android/.../drawable/ic_stat_baxa.xml pour le détail.
    const androidSettings = AndroidInitializationSettings(
      kNotifAndroidSmallIcon,
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
  }

  // Gérer les réponses aux notifications (clic et actions)
  void _onNotificationResponse(NotificationResponse response) {
    final action = response.actionId ?? 'tap';
    final payload = response.payload;

    // Appeler le callback si défini
    if (onNotificationAction != null) {
      onNotificationAction!(action, payload);
    }
  }

  // ---- API PUBLIQUE ----

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // Purge les rappels/validation/créneau-passé qui auraient pu être
  // programmés localement par une version antérieure de l'app (avant le
  // passage au système serveur) — évite les doublons pendant la transition.
  Future<void> cancelReservationNotifications() async {
    await _plugin.cancel(1000);
    await _plugin.cancel(1001);
    await _plugin.cancel(1002);
    await _plugin.cancel(1003);
    await _plugin.cancel(1004);
    await _plugin.cancel(2000);
  }

  // Envoyer une notification de remerciement après annulation
  Future<void> sendThankYouNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'cancellation_channel',
      'Annulations',
      channelDescription: 'Notifications de confirmation d\'annulation',
      importance: Importance.high,
      priority: Priority.high,
      icon: kNotifAndroidSmallIcon,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      9999, // ID unique pour notification de remerciement
      'Merci d\'avoir prévenu 🙏',
      'Tu aides à réduire le gaspillage et à mieux servir les autres.',
      details,
    );
  }

  // Demande les permissions iOS
  Future<void> requestIOSPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }
}
