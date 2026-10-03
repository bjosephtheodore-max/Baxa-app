import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class Auth {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  //  LOGIN WITH EMAIL-PASSWORD
  Future<void> loginWithEmailAndPassword(String email, String password) async {
    await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // LOGOUT — ferme la session Baxa ET oublie le compte Google choisi. Sans
  // cela, Google reconnecterait silencieusement le dernier compte utilisé
  // (gênant sur un téléphone partagé, ou avec plusieurs comptes Google).
  // Utilisé par les clients et le staff.
  Future<void> logout() async {
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('Auth.logout: Google signOut ignoré ($e)');
    }
    await _firebaseAuth.signOut();
  }

  // CREATE USER WITH EMAIL-PASSWORD
  Future<void> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}
