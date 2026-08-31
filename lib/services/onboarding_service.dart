import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Singleton qui pilote le parcours guidé de premier lancement.
///
/// Étapes :
///   1 → pulse sur l'onglet "Réglages"
///   2 → pulse sur "Gérer les files d'attente"
///   3 → pulse sur le FAB "+ Nouvelle file"
///   4 → pulse sur la carte de la file créée (l'utilisateur doit taper la carte)
///   5 → pulse sur le FAB "+ Ajouter une plage"
///   6 → célébration plage créée → complete() → firstSetupDone: true
///
/// Quand step == 0 : inactif (utilisateur déjà configuré ou pas encore vérifié).
class OnboardingService extends ChangeNotifier {
  static final OnboardingService _i = OnboardingService._();
  factory OnboardingService() => _i;
  OnboardingService._();

  int _step = 0;
  int get step => _step;
  bool get isActive => _step >= 1 && _step <= 6;

  /// Vérifie Firestore et démarre l'onboarding si firstSetupDone == false.
  Future<void> checkAndInit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;
      final done = doc.data()?['firstSetupDone'] as bool? ?? false;
      if (!done && _step == 0) {
        _step = 1;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Passe à l'étape suivante seulement si on est bien à [from].
  void advance(int from) {
    if (_step == from) {
      _step++;
      notifyListeners();
    }
  }

  /// Termine l'onboarding et écrit firstSetupDone: true dans Firestore.
  Future<void> complete() async {
    _step = 0;
    notifyListeners();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(user.uid)
          .update({'firstSetupDone': true});
    } catch (_) {}
  }
}
