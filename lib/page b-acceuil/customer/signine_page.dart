import 'package:baxa/page%20b-acceuil/customer/customer_page.dart';
import 'package:flutter/material.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:baxa/services/locale_service.dart';

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
  bool _isLoadingGoogle = false;
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
        // ── Données locale silencieuses ──────────────────────────────
        ...LocaleService.toFirestoreMap(),
      };

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

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoadingGoogle = true);
    try {
      // Popup natif Google — reste dans l'app
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoadingGoogle = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCred.user;
      if (user == null) throw Exception('Utilisateur introuvable');

      // Post-auth : écriture Firestore
      final usersRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final nameParts = (user.displayName ?? '').split(' ');
      final prenom = nameParts.isNotEmpty ? nameParts.first : '';
      final nom = nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : (widget.nom ?? '');

      await usersRef.set({
        'email': user.email ?? '',
        'nom': widget.nom ?? nom,
        'prenom': widget.prenom ?? prenom,
        if (widget.profession != null && widget.profession!.isNotEmpty)
          'profession': widget.profession!,
        'role': 'customer',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // FCM token
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await usersRef.set({'fcmToken': token}, SetOptions(merge: true));
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerPage()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur Google Sign-In'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la connexion Google'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingGoogle = false);
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

                  // ── Séparateur "ou" ──────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'ou',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Bouton Google ────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed:
                          (_isLoadingLogin ||
                              _isLoadingSignup ||
                              _isLoadingGoogle)
                          ? null
                          : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      child: _isLoadingGoogle
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4B8B5E),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Logo Google SVG inline
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CustomPaint(
                                    painter: _GoogleLogoPainter(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Continuer avec Google',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
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

// ── Logo Google dessiné en code (pas besoin d'image externe) ─────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Bleu
    final blue = Paint()..color = const Color(0xFF4285F4);
    // Rouge
    final red = Paint()..color = const Color(0xFFEA4335);
    // Jaune
    final yellow = Paint()..color = const Color(0xFFFBBC05);
    // Vert
    final green = Paint()..color = const Color(0xFF34A853);

    final center = Offset(w / 2, h / 2);
    final radius = w / 2;
    final strokeW = w * 0.22;

    // Arc rouge (haut-gauche → bas-gauche)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeW / 2),
      2.36,
      1.57,
      false,
      red
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );
    // Arc jaune (bas-gauche → bas-droite)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeW / 2),
      3.93,
      0.79,
      false,
      yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );
    // Arc vert (bas-droite → haut-droite)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeW / 2),
      4.71,
      1.18,
      false,
      green
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );
    // Arc bleu (haut-droite → haut-gauche)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeW / 2),
      5.89,
      0.84,
      false,
      blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // Barre horizontale bleue (le "G")
    canvas.drawRect(
      Rect.fromLTWH(w * 0.5, h * 0.38, w * 0.48, h * 0.24),
      blue..style = PaintingStyle.fill,
    );
    // Cache la partie intérieure de la barre
    canvas.drawRect(
      Rect.fromLTWH(w * 0.5, h * 0.44, w * 0.22, h * 0.12),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter old) => false;
}
