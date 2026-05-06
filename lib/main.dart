import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';
import 'package:baxa/services/notifications/notification_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Firebase démarre en arrière-plan — ne bloque PAS runApp ──────────
  Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── 2. Orientation portrait uniquement ──────────────────────────────────
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // ── 3. UI système — instantané ───────────────────────────────────────────
  const style = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(style);

  // ── 4. L'app s'affiche immédiatement ────────────────────────────────────
  runApp(
    AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: const MyApp()),
  );

  // ── 5. Services non critiques — après le premier frame ──────────────────
  // L'utilisateur voit déjà l'UI pendant que cela charge en arrière-plan
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.wait([
      initializeDateFormatting('fr_FR', null),
      NotificationService().init(),
      _initTimezone(),
    ]);
    _requestExactAlarmPermission(); // fire and forget
  });
}

Future<void> _initTimezone() async {
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.local);
}

Future<void> _requestExactAlarmPermission() async {
  try {
    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  } catch (e) {
    debugPrint('Permission exact alarm: $e');
  }
}

// ── RouteObserver global (used by HousePage for RouteAware refresh) ───────
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

// ── App ───────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // ── Localisation française ─────────────────────────────────────────
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr', 'FR'), Locale('en', 'US')],
      locale: const Locale('fr', 'FR'),
      // ──────────────────────────────────────────────────────────────────
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color.fromARGB(255, 178, 211, 194),
        scaffoldBackgroundColor: Colors.white,
      ),
      navigatorObservers: [routeObserver],
      // Direct vers ChoosePage — plus de InitPage qui bloque l'affichage
      home: const ChoosePage(),
    );
  }
}
