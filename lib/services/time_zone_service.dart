import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fuseau horaire (nom IANA, ex. « Africa/Dakar ») enregistré pour le
/// serveur, qui raisonne en heure LOCALE (functions/zone.js) :
///  • `companies/{id}.timeZone` : jours et heures de la structure (créneaux
///    générés la nuit, résumé du matin à 7h, textes des notifications) ;
///  • `users/{uid}.timeZone` : jour du client pour son quota journalier.
///
/// Rien n'est affiché à l'utilisateur : le fuseau vient du téléphone.
class TimeZoneService {
  TimeZoneService._();

  /// Fuseau du téléphone, ou null s'il n'a pas pu être lu.
  static Future<String?> deviceTimeZone() async {
    try {
      final id = (await FlutterTimezone.getLocalTimezone()).identifier;
      return id.trim().isEmpty ? null : id;
    } catch (e) {
      debugPrint('⚠️ Fuseau du téléphone illisible : $e');
      return null;
    }
  }

  /// Profil du client : suit le téléphone (un client qui voyage compte ses
  /// réservations du jour là où il se trouve). Écrit seulement quand le
  /// fuseau change — mémorisé localement pour ne pas réécrire à chaque
  /// ouverture de l'app.
  static Future<void> syncUserTimeZone() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final tz = await deviceTimeZone();
    if (tz == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'synced_time_zone_$uid';
      if (prefs.getString(key) == tz) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'timeZone': tz,
      }, SetOptions(merge: true));
      await prefs.setString(key, tz);
    } catch (e) {
      debugPrint('⚠️ Fuseau du profil non enregistré : $e');
    }
  }

  /// Fiche structure : fixée UNE fois (à l'inscription, ou ici si elle n'en
  /// a pas encore) — un admin en déplacement ne doit pas décaler les
  /// horaires de sa structure.
  static Future<void> ensureCompanyTimeZone(String companyId) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId);
      final snap = await ref.get();
      if (!snap.exists) return;
      final current = snap.data()?['timeZone'];
      if (current is String && current.trim().isNotEmpty) return;
      final tz = await deviceTimeZone();
      if (tz == null) return;
      await ref.set({'timeZone': tz}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ Fuseau de la structure non enregistré : $e');
    }
  }
}
