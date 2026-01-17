import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ---- INITIALISATION ----
  Future<void> init() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);
  }

  // ---- API PUBLIQUE ----
  Future<void> scheduleReservationNotifications({
    required int waitMinutes,
    required int slotDurationMinutes,
  }) async {
    await cancelAll(); // sécurité

    _scheduleReminderNotifications(waitMinutes);
    _scheduleValidationNotification(waitMinutes);
    _scheduleSlotPassedNotification(waitMinutes, slotDurationMinutes);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ---- LOGIQUE MÉTIER ----

  void _scheduleReminderNotifications(int waitMinutes) {
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

        _scheduleNotification(
          id: id++,
          title: 'Rappel',
          body: 'Ton tour est dans ${reminder.label}',
          delay: delay,
        );
      }
    }
  }

  void _scheduleValidationNotification(int waitMinutes) {
    _scheduleNotification(
      id: 2000,
      title: '🟢 Validation',
      body: 'C’est ton tour, présente-toi maintenant',
      delay: Duration(minutes: waitMinutes),
    );
  }

  void _scheduleSlotPassedNotification(
    int waitMinutes,
    int slotDurationMinutes,
  ) {
    final delay = Duration(minutes: waitMinutes + slotDurationMinutes);

    _scheduleNotification(
      id: 2001,
      title: '🟠 Créneau passé',
      body: 'Ton créneau est terminé',
      delay: delay,
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
  }) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(delay);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reservation_channel',
          'Réservations',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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
}

class _Reminder {
  final int threshold;
  final String label;

  _Reminder({required this.threshold, required this.label});
}
