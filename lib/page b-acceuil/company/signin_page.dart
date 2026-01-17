import 'package:baxa/page%20b-acceuil/company/company_page.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class SigninPage extends StatefulWidget {
  const SigninPage({super.key});

  @override
  State<SigninPage> createState() => SigninPageState();
}

class SigninPageState extends State<SigninPage> {
  final _formkey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final TextEditingController _nomEntrepriseController =
      TextEditingController();
  bool _isObscure = true;
  bool _isLoadingLogin = false;
  bool _isLoadingSignup = false;

  // méthode d'inscription (à l'intérieur de la classe)
  Future<void> _handleApply() async {
    if (!mounted) return;
    setState(() => _isLoadingSignup = true);
    try {
      // Validation (optionnel si déjà vérifié avant appel)
      if (!_formkey.currentState!.validate()) return;

      // Création du compte
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final uid = userCredential.user?.uid;
      if (uid != null) {
        // Enregistrement entreprise (doc id = uid)
        await FirebaseFirestore.instance
            .collection("Entreprises")
            .doc(uid)
            .set({
              "nom": _nomEntrepriseController.text.trim(),
              "email": _emailController.text.trim(),
              "createdAt": FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CompanyPage()),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Erreur auth'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: ${e.code} ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur Firestore: ${e.message ?? e.code}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, st) {
      debugPrint("SIGNUP ▶ Erreur inattendue: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSignup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 12,
        title: Text(
          "Baxa",
          style: GoogleFonts.pacifico(
            fontSize: 40,
            fontWeight: FontWeight.w400,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text(
              "Help",
              style: TextStyle(color: Colors.black, fontSize: 18),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Form(
          key: _formkey,
          child: Column(
            children: [
              const SizedBox(height: 60),
              TextFormField(
                controller: _nomEntrepriseController,
                decoration: InputDecoration(
                  labelText: "Nom de l'entreprise",
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5.0),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Veuillez entrer le nom de l'entreprise";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 60),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: "E-mail Address",
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5.0),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "please enter your e-mail";
                  } else if (!value.contains("@")) {
                    return "please enter valid e-mail";
                  } else {
                    return null;
                  }
                },
              ),
              const SizedBox(height: 25),
              TextFormField(
                controller: _passwordController,
                obscureText: _isObscure,
                decoration: InputDecoration(
                  labelText: "Password",
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5.0),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _isObscure = !_isObscure;
                      });
                    },
                    icon: Icon(
                      _isObscure ? Icons.visibility : Icons.visibility_off,
                      color: Colors.black54,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "please enter password";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoadingLogin
                      ? null
                      : () async {
                          if (_formkey.currentState!.validate()) {
                            setState(() {
                              _isLoadingLogin = true;
                            });
                            try {
                              await Auth().loginWithEmailAndPassword(
                                _emailController.text,
                                _passwordController.text,
                              );
                              setState(() {
                                _isLoadingLogin = false;
                              });
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CompanyPage(),
                                ),
                              );
                            } on FirebaseAuthException catch (e) {
                              setState(() {
                                _isLoadingLogin = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("${e.message}"),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0),
                    ),
                  ),
                  child: _isLoadingLogin
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          "Se connecter",
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "OR",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoadingSignup ? null : _handleApply,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0),
                    ),
                  ),
                  child: _isLoadingSignup
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          "S'inscrire",
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ),
              const SizedBox(height: 25),
              const Text(
                "Sign in is protected by google reCAPTCHA to ensure you're are not bot. Learn more",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
