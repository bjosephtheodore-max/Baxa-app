import 'package:cloud_functions/cloud_functions.dart';

/// Région de toutes les Cloud Functions appelées par l'app : à côté de la
/// base Firestore (Johannesburg). Miroir de `DB_REGION` dans
/// functions/index.js — à changer aux deux endroits ensemble.
const String kFunctionsRegion = 'africa-south1';

/// Instance Cloud Functions à utiliser pour tout appel depuis l'app
/// (`FirebaseFunctions.instance` viserait us-central1, où plus rien ne
/// tourne).
FirebaseFunctions get baxaFunctions =>
    FirebaseFunctions.instanceFor(region: kFunctionsRegion);
