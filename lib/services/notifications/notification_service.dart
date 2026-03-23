import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
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
  Future<void> scheduleReservationNotifications({
    required int waitMinutes,
    required int slotDurationMinutes,
    required String reservationId,
    required String companyId,
    required String queueId,
    required String slotId,
  }) async {
    await cancelAll(); // sécurité

    // Créer le payload avec toutes les infos nécessaires
    final payload = '$reservationId|$companyId|$queueId|$slotId';

    _scheduleReminderNotifications(waitMinutes, payload);
    _scheduleValidationNotification(waitMinutes, payload);
    _scheduleSlotPassedNotification(waitMinutes, slotDurationMinutes, payload);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<void> cancelReservationNotifications() async {
    // Annuler toutes les notifications de réservation
    await _plugin.cancel(1000);
    await _plugin.cancel(1001);
    await _plugin.cancel(1002);
    await _plugin.cancel(1003);
    await _plugin.cancel(1004);
    await _plugin.cancel(2000);
    await _plugin.cancel(2001);
  }

  // Envoyer une notification de remerciement après annulation
  Future<void> sendThankYouNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'cancellation_channel',
      'Annulations',
      channelDescription: 'Notifications de confirmation d\'annulation',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
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

  // ---- LOGIQUE MÉTIER ----

  void _scheduleReminderNotifications(int waitMinutes, String payload) {
    final reminders = [
      _Reminder(threshold: 1440, label: '24 heures'),
      _Reminder(threshold: 120, label: '2 heures'),
      _Reminder(threshold: 60, label: '1 heure'),
      _Reminder(threshold: 30, label: '30 minutes'),
      _Reminder(threshold: 5, label: '5 minutes'),
    ];

    int id = 1000;

    for (final reminder in reminders) {
      if (waitMinutes > reminder.threshold) {
        final delay = Duration(minutes: waitMinutes - reminder.threshold);

        _scheduleNotificationWithActions(
          id: id++,
          title: 'Rappel',
          body: 'Ton tour est dans ${reminder.label}',
          delay: delay,
          payload: payload,
          withCancelAction: true,
        );
      }
    }
  }

  void _scheduleValidationNotification(int waitMinutes, String payload) {
    _scheduleNotificationWithActions(
      id: 2000,
      title: '🟢 Validation',
      body: 'C\'est ton tour, présente-toi maintenant',
      delay: Duration(minutes: waitMinutes),
      payload: payload,
      withCancelAction: false, // Pas de bouton d'annulation à ce stade
    );
  }

  void _scheduleSlotPassedNotification(
    int waitMinutes,
    int slotDurationMinutes,
    String payload,
  ) {
    final delay = Duration(minutes: waitMinutes + slotDurationMinutes);

    _scheduleNotification(
      id: 2001,
      title: '🟠 Créneau passé',
      body: 'Ton créneau est terminé',
      delay: delay,
      payload: payload,
    );

    // Annule explicitement la validation verte au même moment
    _scheduleCancelNotification(targetNotificationId: 2000, delay: delay);
  }

  // ---- BAS NIVEAU ----

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required Duration delay,
    String? payload,
  }) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(delay);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'reservation_channel',
          'Réservations',
          channelDescription: 'Notifications pour vos réservations',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  // Nouvelle méthode pour programmer des notifications avec boutons d'action
  Future<void> _scheduleNotificationWithActions({
    required int id,
    required String title,
    required String body,
    required Duration delay,
    required String payload,
    required bool withCancelAction,
  }) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(delay);

    // Créer les actions Android
    final androidActions = withCancelAction
        ? <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'cancel_reservation',
              'Je ne viendrai pas',
              showsUserInterface: true,
              icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            ),
            const AndroidNotificationAction(
              'keep_reservation',
              'Je garde ma réservation',
              showsUserInterface: false,
            ),
          ]
        : <AndroidNotificationAction>[];

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'reservation_channel',
          'Réservations',
          channelDescription: 'Notifications pour vos réservations',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          actions: androidActions,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: withCancelAction ? 'RESERVATION_CATEGORY' : null,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// Astuce propre : on programme une "annulation différée"
  Future<void> _scheduleCancelNotification({
    required int targetNotificationId,
    required Duration delay,
  }) async {
    Future.delayed(delay, () {
      _plugin.cancel(targetNotificationId);
    });
  }

  // Configuration iOS pour les catégories de notifications avec actions
  Future<void> requestIOSPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Définir les catégories iOS avec actions
    // ignore: unused_local_variable
    final List<DarwinNotificationCategory> darwinCategories = [
      DarwinNotificationCategory(
        'RESERVATION_CATEGORY',
        actions: [
          DarwinNotificationAction.plain(
            'cancel_reservation',
            'Je ne viendrai pas',
            options: {DarwinNotificationActionOption.foreground},
          ),
          DarwinNotificationAction.plain(
            'keep_reservation',
            'Je garde ma réservation',
          ),
        ],
      ),
    ];

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.initialize(
          const DarwinInitializationSettings(),
          onDidReceiveNotificationResponse: _onNotificationResponse,
        );
  }
}

class _Reminder {
  final int threshold;
  final String label;

  _Reminder({required this.threshold, required this.label});
}
