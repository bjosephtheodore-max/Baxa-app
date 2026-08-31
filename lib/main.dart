import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:baxa/page%20d-d%C3%A9but/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // ── Garde la main sur le splash natif au lieu de le laisser disparaître
  //    dès la 1ère frame (durée sinon imprévisible sur cold start) ─────────
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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

  // ── 4. L'app s'affiche immédiatement, sur l'écran "Chargement..." ───────
  runApp(
    AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: const MyApp()),
  );

  // ── 5. Splash natif affiché 0,6s max, puis place à l'écran Flutter ──────
  Future.delayed(const Duration(milliseconds: 600), () {
    FlutterNativeSplash.remove();
  });

  // ── 6. Permission alarme exacte — fire and forget, non bloquant ─────────
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _requestExactAlarmPermission();
  });
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
      // SplashScreen affiche "Chargement..." puis navigue vers ChoosePage
      home: const SplashScreen(),
    );
  }
}
