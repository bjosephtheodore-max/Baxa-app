import 'package:baxa/page%20b-acceuil/customer/customer_page.dart';
import 'package:flutter/material.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class SigninePage extends StatefulWidget {
  const SigninePage({super.key});

  @override
  State<SigninePage> createState() => _SigninePageState();
}

class _SigninePageState extends State<SigninePage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isObscure = true;
  bool _isLoadingLogin = false;
  bool _isLoadingSignup = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _postAuthActions(User user) async {
    // crée / met à jour le document users/{uid} et ajoute fcmToken si possible
    final usersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    try {
      await usersRef.set({
        'email': user.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'customer',
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint('Firestore users set failed: ${e.code} ${e.message}');
      // on continue malgré l'erreur (permission denied etc.)
    } catch (e) {
      debugPrint('Unexpected error writing users doc: $e');
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        try {
          await usersRef.set({'fcmToken': token}, SetOptions(merge: true));
        } on FirebaseException catch (e) {
          debugPrint('Firestore fcmToken write failed: ${e.code} ${e.message}');
        }
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoadingLogin = true);
    try {
      await Auth().loginWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await _postAuthActions(user);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerPage()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur authentification'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('Login error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la connexion'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingLogin = false);
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoadingSignup = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final user = cred.user ?? FirebaseAuth.instance.currentUser;
      if (user != null) await _postAuthActions(user);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerPage()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur inscription'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('Signup error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de l\'inscription'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSignup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,

        elevation: 12,
        title: Text(
          "Baxa",
          style: GoogleFonts.pacifico(
            fontSize: 40,
            fontWeight: FontWeight.w400,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  filled: true,
                ),
                validator: (v) => (v == null || v.isEmpty || !v.contains('@'))
                    ? 'Entrer un e-mail valide'
                    : null,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _isObscure,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  filled: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _isObscure = !_isObscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? 'Mot de passe >= 6 caractères'
                    : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoadingLogin ? null : _login,
                  child: _isLoadingLogin
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Se connecter'),
                ),
              ),
              const SizedBox(height: 12),
              const Text('OR'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoadingSignup ? null : _signup,
                  child: _isLoadingSignup
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('S\'inscrire'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
