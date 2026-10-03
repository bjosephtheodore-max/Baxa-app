import 'package:baxa/page%20b-acceuil/company/company_page.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class SigninPage extends StatefulWidget {
  final String? nomEntreprise;
  final String? typeEntreprise;
  final String? typeCategorie;
  final String? ville;
  final String? country;
  final String? language;
  final String? locale;

  const SigninPage({
    super.key,
    this.nomEntreprise,
    this.typeEntreprise,
    this.typeCategorie,
    this.ville,
    this.country,
    this.language,
    this.locale,
  });

  @override
  State<SigninPage> createState() => SigninPageState();
}

class SigninPageState extends State<SigninPage> {
  final _formkey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isObscure = true;
  bool _isLoadingLogin = false;
  bool _isLoadingSignup = false;
  bool _isLoginMode = false; // Pour basculer entre connexion et inscription
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email ou mot de passe incorrect.';
      case 'email-already-in-use':
        return 'Un compte existe déjà avec cette adresse email.';
      case 'invalid-email':
        return 'Adresse email invalide.';
      case 'weak-password':
        return 'Mot de passe trop faible. Minimum 6 caractères.';
      case 'network-request-failed':
        return 'Vérifiez votre connexion internet.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez dans quelques minutes.';
      case 'user-disabled':
        return 'Ce compte a été désactivé.';
      default:
        return 'Une erreur est survenue. Réessayez.';
    }
  }

  void _setError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  // Méthode de connexion
  Future<void> _handleLogin() async {
    _clearError();
    if (!_formkey.currentState!.validate()) return;
    if (!mounted) return;
    setState(() => _isLoadingLogin = true);

    try {
      await Auth().loginWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CompanyPage()),
      );
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoadingLogin = false);
    }
  }

  // Méthode d'inscription
  Future<void> _handleSignup() async {
    _clearError();
    if (!mounted) return;
    setState(() => _isLoadingSignup = true);

    try {
      if (!_formkey.currentState!.validate()) {
        setState(() => _isLoadingSignup = false);
        return;
      }

      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final uid = userCredential.user?.uid;
      if (uid != null) {
        final entrepriseData = {
          "email": _emailController.text.trim(),
          "createdAt": FieldValue.serverTimestamp(),
        };

        if (widget.nomEntreprise != null) {
          entrepriseData["nom"] = widget.nomEntreprise!;
        }
        if (widget.typeEntreprise != null) {
          entrepriseData["type"] = widget.typeEntreprise!;
        }
        if (widget.typeCategorie != null) {
          entrepriseData["typeCategorie"] = widget.typeCategorie!;
        }
        if (widget.ville != null) {
          entrepriseData["ville"] = widget.ville!;
        }
        if (widget.country != null) {
          entrepriseData["country"] = widget.country!;
        }
        if (widget.language != null) {
          entrepriseData["language"] = widget.language!;
        }
        if (widget.locale != null) {
          entrepriseData["locale"] = widget.locale!;
        }

        await FirebaseFirestore.instance
            .collection("companies")
            .doc(uid)
            .set(entrepriseData, SetOptions(merge: true));

        // On envoie toujours `typeCategorie` (jamais `type`) : c'est le
        // champ qui reste toujours propre ('Autre' quand l'entreprise a
        // saisi un texte libre), pour ne jamais faire exploser cette
        // dimension Analytics avec du texte libre non normalisé.
        if (widget.typeCategorie != null) {
          await FirebaseAnalytics.instance.setUserProperty(
            name: 'company_category',
            value: widget.typeCategorie!,
          );
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CompanyPage()),
      );
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e));
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: ${e.code} ${e.message}');
      _setError('Une erreur est survenue. Réessayez.');
    } catch (e, st) {
      debugPrint("SIGNUP ▶ Erreur inattendue: $e\n$st");
      _setError('Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoadingSignup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            controller: _scrollController,
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
                        : (widget.nomEntreprise != null
                              ? 'Bienvenue ${widget.nomEntreprise} !'
                              : 'Créer un compte entreprise'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _isLoginMode
                        ? 'Connectez-vous pour gérer vos files'
                        : 'Dernière étape pour rejoindre Baxa',
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
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formkey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Bannière d'erreur inline
                          if (_errorMessage != null) ...[
                            Container(
                              key: const ValueKey('company-signin-error-banner'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE57373),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.error_rounded,
                                    color: Color(0xFFD32F2F),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF7B1111),
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Champ Email
                          TextFormField(
                            key: const ValueKey('company-signin-email'),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            onTap: _scrollToBottom,
                            onChanged: (_) => _clearError(),
                            decoration: InputDecoration(
                              labelText: 'Adresse e-mail professionnelle',
                              hintText: 'entreprise@email.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color.fromARGB(255, 75, 139, 94),
                                  width: 1.5,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Veuillez entrer votre e-mail";
                              } else if (!value.contains("@")) {
                                return "Veuillez entrer un e-mail valide";
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Champ Mot de passe
                          TextFormField(
                            key: const ValueKey('company-signin-password'),
                            controller: _passwordController,
                            obscureText: _isObscure,
                            // Toujours désactivés : évite que le basculement de
                            // l'œil ne renégocie le clavier Android et ne vide
                            // le champ.
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [
                              _isLoginMode
                                  ? AutofillHints.password
                                  : AutofillHints.newPassword,
                            ],
                            onTap: _scrollToBottom,
                            onChanged: (_) => _clearError(),
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              hintText: 'Minimum 6 caractères',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color.fromARGB(255, 75, 139, 94),
                                  width: 1.5,
                                ),
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
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Veuillez entrer un mot de passe";
                              }
                              if (value.length < 6) {
                                return "Minimum 6 caractères";
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // Bouton principal
                          SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              onPressed: (_isLoadingLogin || _isLoadingSignup)
                                  ? null
                                  : (_isLoginMode
                                        ? _handleLogin
                                        : _handleSignup),
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
                                          : 'Créer mon entreprise',
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
                      Flexible(
                        child: Text(
                          _isLoginMode
                              ? 'Première fois sur Baxa ?'
                              : 'Vous avez déjà un compte ?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoginMode = !_isLoginMode;
                            // Pas de reset() : l'email et le mot de passe sont
                            // les mêmes champs dans les deux modes — les vider à
                            // la bascule oblige à tout retaper.
                            _errorMessage = null;
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

                  // Message de sécurité
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.security_outlined,
                          size: 16,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Vos données sont sécurisées et protégées',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),  // SingleChildScrollView
        ),  // Center
      ),     // SafeArea
    ),     // Scaffold
    );     // AnnotatedRegion
  }
}
