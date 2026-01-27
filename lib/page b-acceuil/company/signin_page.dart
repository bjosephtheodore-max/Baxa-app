import 'package:baxa/page%20b-acceuil/company/company_page.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class SigninPage extends StatefulWidget {
  final String? nomEntreprise;
  final String? typeEntreprise;

  const SigninPage({super.key, this.nomEntreprise, this.typeEntreprise});

  @override
  State<SigninPage> createState() => SigninPageState();
}

class SigninPageState extends State<SigninPage> {
  final _formkey = GlobalKey<FormState>();
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

  // Méthode de connexion
  Future<void> _handleLogin() async {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur authentification'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingLogin = false);
    }
  }

  // Méthode d'inscription
  Future<void> _handleSignup() async {
    if (!mounted) return;
    setState(() => _isLoadingSignup = true);

    try {
      if (!_formkey.currentState!.validate()) {
        setState(() => _isLoadingSignup = false);
        return;
      }

      // Création du compte
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final uid = userCredential.user?.uid;
      if (uid != null) {
        // Préparation des données
        final entrepriseData = {
          "email": _emailController.text.trim(),
          "createdAt": FieldValue.serverTimestamp(),
        };

        // Ajouter les données de pré-inscription si disponibles
        if (widget.nomEntreprise != null) {
          entrepriseData["nom"] = widget.nomEntreprise!;
        }
        if (widget.typeEntreprise != null) {
          entrepriseData["type"] = widget.typeEntreprise!;
        }

        // Enregistrement entreprise (doc id = uid)
        await FirebaseFirestore.instance
            .collection("Entreprises")
            .doc(uid)
            .set(entrepriseData, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CompanyPage()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur auth'),
          backgroundColor: Colors.red,
        ),
      );
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: ${e.code} ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur Firestore: ${e.message ?? e.code}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e, st) {
      debugPrint("SIGNUP ▶ Erreur inattendue: $e\n$st");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
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
                          color: Colors.black.withOpacity(0.08),
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
                          // Champ Email
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Adresse e-mail professionnelle',
                              hintText: 'entreprise@email.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
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
                      Text(
                        _isLoginMode
                            ? 'Première fois sur Baxa ?'
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
                            _formkey.currentState?.reset();
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
          ),
        ),
      ),
    );
  }
}
