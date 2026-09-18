import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:baxa/page%20d-d%C3%A9but/splash_screen.dart';
import 'package:baxa/services/firebase/remote_config_service.dart';
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';

final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // ── Garde la main sur le splash natif : on le retire nous-mêmes dès que
  //    l'écran Flutter a peint sa 1ère frame (voir addPostFrameCallback). ──
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // ── 1. Firebase — désormais attendu avant runApp : le splash natif reste
  //    affiché pendant ce court délai (init locale, sans appel réseau), donc
  //    aucun retard visible. On en profite pour brancher Crashlytics le plus
  //    tôt possible afin qu'il capte aussi les erreurs de démarrage. ───────
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  _setupCrashlytics();

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

  // ── 5. Dès la 1ère frame Flutter peinte : on retire le splash natif (sans
  //    minuterie fixe) et on démarre les services qui ne sont pas
  //    nécessaires à l'affichage du premier écran. ────────────────────────
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
    _initDeferredServices();
  });
}

/// Branche Crashlytics sur les erreurs Flutter et Dart non interceptées.
/// Désactivé en debug pour ne pas polluer les rapports de prod avec des
/// crashs de développement.
void _setupCrashlytics() {
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  analytics.setAnalyticsCollectionEnabled(!kDebugMode);
}

/// Services qui n'ont pas besoin d'être prêts pour peindre le premier écran.
/// Lancés après la 1ère frame pour ne pas retarder le démarrage.
Future<void> _initDeferredServices() async {
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Init notifications différée: $e');
  }
  try {
    await RemoteConfigService.instance.init();
  } catch (e) {
    debugPrint('Init Remote Config différée: $e');
  }
  await _requestExactAlarmPermission();
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
        // Material 3 teinte par défaut les dialogues avec la couleur primaire
        // (seed vert) — d'où un fond verdâtre non voulu. On neutralise.
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        // Barres de navigation basses (client / entreprise / staff) : reste
        // dans les limites du composant standard `NavigationBar` — seule
        // l'icône devient verte quand l'onglet est actif (le libellé reste
        // noir dans les deux cas, jamais gris), avec la pastille pâle de
        // Material 3 derrière l'icône active.
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          // Pas d'ombre : la séparation avec le contenu vient d'un fin
          // trait posé sur chaque barre (voir les 3 pages), pas d'une
          // élévation Material.
          elevation: 0,
          indicatorColor: const Color(0xFFE8F5ED),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: Colors.black87,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 26,
              color: selected
                  ? const Color(0xFF4B8B5E)
                  : Colors.black87,
            );
          }),
        ),
      ),
      navigatorObservers: [
        routeObserver,
        FirebaseAnalyticsObserver(analytics: analytics),
      ],
      // SplashScreen affiche "Chargement..." puis navigue vers ChoosePage
      home: const SplashScreen(),
    );
  }
}
