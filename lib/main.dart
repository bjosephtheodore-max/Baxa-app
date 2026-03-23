import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:baxa/page d-d%C3%A9but/choose_page.dart';
import 'package:baxa/services/notifications/notification_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // UI uniquement → rapide
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  const style = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(style);

  runApp(
    AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: const MyApp()),
  );
}

// ✅ PERMISSION NOTIF
Future<void> requestExactAlarmPermission() async {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestExactAlarmsPermission();
}

// 🔥 APP
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color.fromARGB(255, 178, 211, 194),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const InitPage(), // 👈 IMPORTANT
    );
  }
}

// 🚀 PAGE D'INITIALISATION (clé de la vitesse)
class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    try {
      await Future.wait([
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
        initializeDateFormatting('fr_FR', null),
        _initNotifications(),
        _initTimezone(),
      ]);
    } catch (e) {
      debugPrint("Erreur init: $e");
    }

    // Redirection vers ton app
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ChoosePage()),
    );
  }

  Future<void> _initNotifications() async {
    await NotificationService().init();
    await requestExactAlarmPermission();
  }

  Future<void> _initTimezone() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.local);
    debugPrint('Timezone set to tz.local');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
