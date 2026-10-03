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
///
/// Reprise : seul `firstSetupDone` (fin) et `onboardingStartedAt` (1er
/// affichage) sont enregistrés. L'avancement réel est déduit des données à
/// chaque démarrage : une plage existe → parcours terminé ; une file existe
/// → l'étape 3 (créer la file) est sautée.
class OnboardingService extends ChangeNotifier {
  static final OnboardingService _i = OnboardingService._();
  factory OnboardingService() => _i;
  OnboardingService._();

  int _step = 0;
  String? _uid;
  bool _hasQueue = false;
  bool _canSkip = false;

  int get step => _step;
  bool get isActive => _step >= 1 && _step <= 6;

  /// Vrai quand le parcours reprend lors d'une session ultérieure (il avait
  /// déjà été affiché au moins une fois) : le lien « Passer » est alors proposé.
  bool get canSkip => _canSkip && isActive;

  /// Vérifie Firestore et démarre (ou reprend) l'onboarding si
  /// firstSetupDone == false.
  Future<void> checkAndInit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Autre compte que celui du parcours en mémoire : repartir de zéro.
    if (_uid != user.uid) {
      _uid = user.uid;
      _step = 0;
      _hasQueue = false;
      _canSkip = false;
    }
    if (_step != 0) return; // parcours déjà en cours dans cette session
    try {
      final companyRef =
          FirebaseFirestore.instance.collection('companies').doc(user.uid);
      final doc = await companyRef.get();
      if (!doc.exists) return;
      final data = doc.data() ?? const {};
      if (data['firstSetupDone'] as bool? ?? false) return;

      final queues = await companyRef.collection('queues').get();
      for (final q in queues.docs) {
        final plages =
            await q.reference.collection('timeSlots').limit(1).get();
        if (plages.docs.isNotEmpty) {
          // Configuration déjà faite (ex. app fermée pendant la célébration) :
          // rien à guider, on clôt proprement.
          await complete();
          return;
        }
      }

      final alreadyStarted = data['onboardingStartedAt'] != null;
      if (!alreadyStarted) {
        await companyRef.update({
          'onboardingStartedAt': FieldValue.serverTimestamp(),
        });
      }

      if (_uid != user.uid || _step != 0) return; // changé pendant l'attente
      _hasQueue = queues.docs.isNotEmpty;
      _canSkip = alreadyStarted;
      _step = 1;
      notifyListeners();
    } catch (_) {}
  }

  /// Passe à l'étape suivante seulement si on est bien à [from].
  void advance(int from) {
    if (_step != from) return;
    // Une file existe déjà (reprise) : pas d'étape « créer la file », on
    // enchaîne directement sur la carte de la file.
    _step = (from == 2 && _hasQueue) ? 4 : _step + 1;
    if (_step >= 4) _hasQueue = true;
    notifyListeners();
  }

  /// L'utilisateur choisit de configurer plus tard : même fin que complete().
  Future<void> skip() => complete();

  /// Termine l'onboarding et écrit firstSetupDone: true dans Firestore.
  Future<void> complete() async {
    _step = 0;
    _canSkip = false;
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
