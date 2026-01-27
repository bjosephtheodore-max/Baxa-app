import 'package:baxa/page%20b-acceuil/customer/customer_page.dart';
import 'package:flutter/material.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class SigninePage extends StatefulWidget {
  final String? nom;
  final String? prenom;
  final String? profession;

  const SigninePage({super.key, this.nom, this.prenom, this.profession});

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
  bool _isLoginMode = true; // Pour basculer entre connexion et inscription

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _postAuthActions(User user) async {
    final usersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    try {
      final userData = {
        'email': user.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'customer',
      };

      // Ajouter les données de pré-inscription si disponibles
      if (widget.nom != null) userData['nom'] = widget.nom!;
      if (widget.prenom != null) userData['prenom'] = widget.prenom!;
      if (widget.profession != null && widget.profession!.isNotEmpty) {
        userData['profession'] = widget.profession!;
      }

      await usersRef.set(userData, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint('Firestore users set failed: ${e.code} ${e.message}');
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur authentification'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('Login error: $e');
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur inscription'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('Signup error: $e');
      if (!mounted) return;
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
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo et titre
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 75, 139, 94),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Baxa",
                      style: GoogleFonts.pacifico(
                        fontSize: 36,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Titre de la section avec nom personnalisé si disponible
                  Text(
                    _isLoginMode
                        ? 'Bon retour !'
                        : (widget.prenom != null
                              ? 'Enchanté ${widget.prenom} !'
                              : 'Créer un compte'),
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _isLoginMode
                        ? 'Connectez-vous pour continuer'
                        : 'Rejoignez Baxa dès aujourd\'hui',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 40),

                  // Carte du formulaire
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Champ Email
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Adresse e-mail',
                              hintText: 'exemple@email.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty || !v.contains('@'))
                                ? 'Entrez un e-mail valide'
                                : null,
                          ),

                          const SizedBox(height: 20),

                          // Champ Mot de passe
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _isObscure,
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              hintText: 'Minimum 6 caractères',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isObscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _isObscure = !_isObscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Mot de passe >= 6 caractères'
                                : null,
                          ),

                          const SizedBox(height: 24),

                          // Bouton principal
                          SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              onPressed: (_isLoadingLogin || _isLoadingSignup)
                                  ? null
                                  : (_isLoginMode ? _login : _signup),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color.fromARGB(
                                  255,
                                  75,
                                  139,
                                  94,
                                ),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child:
                                  (_isLoginMode
                                      ? _isLoadingLogin
                                      : _isLoadingSignup)
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isLoginMode
                                          ? 'Se connecter'
                                          : 'Créer mon compte',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Basculer entre connexion et inscription
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLoginMode
                            ? 'Pas encore de compte ?'
                            : 'Vous avez déjà un compte ?',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoginMode = !_isLoginMode;
                            _formKey.currentState?.reset();
                          });
                        },
                        child: Text(
                          _isLoginMode ? 'S\'inscrire' : 'Se connecter',
                          style: const TextStyle(
                            color: Color.fromARGB(255, 75, 139, 94),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
