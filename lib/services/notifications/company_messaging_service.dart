import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Enregistrement du jeton FCM + gestion du tap sur notification pour les
/// espaces ENTREPRISE (admin) et STAFF.
///
/// Miroir de ce que fait `_initializeCustomerServices` côté client : sans
/// jeton enregistré, les Cloud Functions ne peuvent envoyer aucun push à
/// l'entreprise. Le jeton est écrit dans `users/{uid}.fcmToken` — le même
/// champ que le client (un compte n'a qu'un seul rôle).
///
/// Les push entreprise sont livrés par la Cloud Function `sendCompanyPush`.
class CompanyMessagingService {
  CompanyMessagingService._();
  static final CompanyMessagingService instance = CompanyMessagingService._();

  bool _listenersAttached = false;
  VoidCallback? _onOpen;

  /// À appeler à l'ouverture d'un espace entreprise ou staff. Sans danger si
  /// appelé plusieurs fois (au changement de compte notamment) : le jeton est
  /// resynchronisé à chaque fois, les écouteurs ne sont posés qu'une fois.
  ///
  /// [onOpenNotifications] est déclenché quand l'utilisateur ouvre l'app en
  /// tapant une notification push (app en arrière-plan ou fermée).
  Future<void> start({VoidCallback? onOpenNotifications}) async {
    _onOpen = onOpenNotifications;
    try {
      await FirebaseMessaging.instance.requestPermission();
      await _syncToken();

      if (_listenersAttached) return;
      _listenersAttached = true;

      FirebaseMessaging.instance.onTokenRefresh.listen(_writeToken);
      FirebaseMessaging.onMessageOpenedApp.listen((_) => _onOpen?.call());

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _onOpen?.call();
    } catch (e) {
      debugPrint('CompanyMessagingService.start: $e');
    }
  }

  Future<void> _syncToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _writeToken(token);
  }

  Future<void> _writeToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('CompanyMessagingService._writeToken: $e');
    }
  }
}
