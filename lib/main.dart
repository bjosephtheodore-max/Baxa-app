// import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart'; // temporarily disabled for debugging
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:baxa/page%20b-acceuil/customer/customer_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initialise Firebase une seule fois
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // initialiser les fuseaux horaires (données puis utiliser tz.local par défaut)
  tzdata.initializeTimeZones();
  // Utiliser tz.local plutôt qu'un plugin natif pour éviter les problèmes de build
  tz.setLocalLocation(tz.local);
  debugPrint('Timezone set to tz.local');

  // initialiser notifications
  await NotificationService().init();

  // edge-to-edge (appliqué avant runApp)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // style global — navigation bar en blanc
  const style = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white, // <-- blanc
    systemNavigationBarDividerColor: Colors.white70,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
  SystemChrome.setSystemUIOverlayStyle(style);

  runApp(
    // AnnotatedRegion garantit que le style est associé à l'arbre widget
    AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: const MyApp()),
  );
}

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
      home: const Scaffold(body: Center(child: Text('Hello'))),
    );
  }
}
