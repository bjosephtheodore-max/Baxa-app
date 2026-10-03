import 'dart:async';

import 'package:baxa/page%20b-acceuil/customer/customer_page.dart';
import 'package:flutter/material.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:baxa/services/locale_service.dart';
import 'package:baxa/services/location_service.dart';
import 'package:baxa/widgets/profession_picker_sheet.dart';

// ── Modes d'authentification téléphone ────────────────────────────────────────
enum _PhoneStep { enterNumber, enterOtp }

class SigninePage extends StatefulWidget {
  const SigninePage({super.key});

  @override
  State<SigninePage> createState() => _SigninePageState();
}

class _SigninePageState extends State<SigninePage> {
  static const _green = Color(0xFF4B8B5E);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isObscure = true;
  bool _isLoadingEmail = false;
  bool _isLoadingGoogle = false;
  bool _isLoadingPhone = false;
  bool _isLoginMode = false; // signup by default
  String? _errorMessage;

  // Phone auth state
  _PhoneStep _phoneStep = _PhoneStep.enterNumber;
  String? _verificationId;

  // true = anonymous user completing their profile
  bool get _isAnonymous =>
      FirebaseAuth.instance.currentUser?.isAnonymous == true;

  // Active tab: 0 = email, 1 = phone  — phone shown first by default
  int _selectedTab = 1;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Error helpers ─────────────────────────────────────────────

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
      case 'credential-already-in-use':
        return 'Ces identifiants sont déjà utilisés par un autre compte.';
      case 'provider-already-linked':
        return 'Ce compte est déjà lié à cette méthode.';
      case 'invalid-phone-number':
        return 'Numéro de téléphone invalide.';
      case 'invalid-verification-code':
        return 'Code incorrect. Vérifiez le SMS reçu.';
      case 'session-expired':
        return 'Le code a expiré. Demandez un nouveau.';
      default:
        return 'Une erreur est survenue. Réessayez.';
    }
  }

  void _setError(String msg) {
    if (mounted) setState(() => _errorMessage = msg);
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  // ── Post-auth Firestore update ────────────────────────────────

  Future<void> _postAuthActions(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      final updates = <String, dynamic>{
        'isAnonymous': false,
        'role': 'customer',
        ...LocaleService.toFirestoreMap(),
      };
      if (user.email != null && user.email!.isNotEmpty) {
        updates['email'] = user.email;
      }
      await ref.set(updates, SetOptions(merge: true));
      await FirebaseAnalytics.instance.setUserProperty(
        name: 'role',
        value: 'customer',
      );
    } catch (e) {
      debugPrint('Firestore update failed: $e');
    }
    try {
      // Sur Android 13+, sans cette demande explicite le système bloque
      // silencieusement l'affichage de toute notification — même si le
      // token FCM est obtenu et les notifications bien envoyées.
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await ref.set({'fcmToken': token}, SetOptions(merge: true));
      }
    } catch (_) {}

    // Pays : la locale a déjà renseigné `country`. On demande la
    // permission GPS ici (dialogue à la suite de celui des notifications)
    // puis on l'affine avec la position réelle en tâche de fond.
    await _requestGpsAndRefineCountry(ref);
  }

  // Demande la permission GPS (bloquant, le temps du dialogue système)
  // puis lance en tâche de fond le géocodage qui remplace le `country`
  // (déduit de la locale) par le pays réel du client. Toujours silencieux.
  Future<void> _requestGpsAndRefineCountry(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      unawaited(_refineCountryFromGps(ref));
    } catch (_) {}
  }

  Future<void> _refineCountryFromGps(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final code = await LocationService().currentCountryCode();
      if (code != null && code.isNotEmpty) {
        await ref.set({'country': code}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  // ── Email / password ──────────────────────────────────────────

  Future<void> _submitEmail() async {
    _clearError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoadingEmail = true);
    try {
      final current = FirebaseAuth.instance.currentUser;
      User? user;

      if (current != null && current.isAnonymous && !_isLoginMode) {
        // Link anonymous → email/password
        final cred = EmailAuthProvider.credential(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        final result = await current.linkWithCredential(cred);
        user = result.user;
      } else if (_isLoginMode) {
        await Auth().loginWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
        user = FirebaseAuth.instance.currentUser;
      } else {
        final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        user = result.user;
      }

      if (user != null) await _postAuthActions(user);
      if (!mounted) return;
      _onSuccess();
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e));
    } catch (e) {
      _setError('Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoadingEmail = false);
    }
  }

  // ── Google ────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    _clearError();
    setState(() => _isLoadingGoogle = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoadingGoogle = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final current = FirebaseAuth.instance.currentUser;
      UserCredential userCred;
      if (current != null && current.isAnonymous) {
        userCred = await current.linkWithCredential(credential);
      } else {
        userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final user = userCred.user;
      if (user == null) throw Exception('Utilisateur introuvable');

      // Preserve name from anonymous registration if already set
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      final existingNom = snap.data()?['nom'] as String?;

      final updates = <String, dynamic>{
        'isAnonymous': false,
        'role': 'customer',
        if (user.email != null) 'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
        ...LocaleService.toFirestoreMap(),
      };
      // Only set name from Google if not already entered manually
      if (existingNom == null || existingNom.isEmpty) {
        final parts = (user.displayName ?? '').split(' ');
        updates['prenom'] = parts.isNotEmpty ? parts.first : '';
        updates['nom'] = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      await ref.set(updates, SetOptions(merge: true));
      await FirebaseAnalytics.instance.setUserProperty(
        name: 'role',
        value: 'customer',
      );

      try {
        await FirebaseMessaging.instance.requestPermission();
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await ref.set({'fcmToken': token}, SetOptions(merge: true));
        }
      } catch (_) {}

      await _requestGpsAndRefineCountry(ref);

      if (!mounted) return;
      _onSuccess();
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e));
    } catch (e) {
      _setError('Erreur lors de la connexion Google. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoadingGoogle = false);
    }
  }

  // ── Phone / OTP ───────────────────────────────────────────────

  Future<void> _sendOtp() async {
    _clearError();
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _setError('Entrez votre numéro de téléphone.');
      return;
    }
    setState(() => _isLoadingPhone = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential cred) async {
        // Android auto-verification
        await _linkPhoneCred(cred);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) {
          setState(() => _isLoadingPhone = false);
          _setError(_friendlyError(e));
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (mounted) {
          setState(() {
            _verificationId = verificationId;
            _phoneStep = _PhoneStep.enterOtp;
            _isLoadingPhone = false;
          });
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _verifyOtp() async {
    _clearError();
    if (_otpController.text.trim().length < 6) {
      _setError('Entrez le code à 6 chiffres.');
      return;
    }
    setState(() => _isLoadingPhone = true);
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      await _linkPhoneCred(cred);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isLoadingPhone = false);
        _setError(_friendlyError(e));
      }
    }
  }

  Future<void> _linkPhoneCred(PhoneAuthCredential cred) async {
    try {
      final current = FirebaseAuth.instance.currentUser;
      User? user;
      if (current != null && current.isAnonymous) {
        final result = await current.linkWithCredential(cred);
        user = result.user;
      } else {
        final result = await FirebaseAuth.instance.signInWithCredential(cred);
        user = result.user;
      }
      if (user != null) await _postAuthActions(user);
      if (!mounted) return;
      _onSuccess();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isLoadingPhone = false);
        _setError(_friendlyError(e));
      }
    }
  }

  // ── Navigation on success ─────────────────────────────────────

  Future<void> _onSuccess() async {
    await _showProfessionSheet();
    if (!mounted) return;

    // If this page is on top of the stack, pop back
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      // Fallback: first-time sign-in without anonymous session
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerPage()),
      );
    }
  }

  // ── Profession (une seule fois, juste après l'inscription) ─────
  // Affichée en bottom sheet AVANT le pop/pushReplacement ci-dessus, pour ne
  // jamais casser le flow "favori en attente" de search_dialogs.dart, qui
  // attend que cette page se pop pour reprendre la main.
  Future<void> _showProfessionSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    final selected = await showProfessionPickerSheet(context);
    if (selected == null || !mounted) return; // "Passer" ou fermée
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'profession': selected}, SetOptions(merge: true));
      unawaited(
        FirebaseAnalytics.instance.setUserProperty(
          name: 'profession',
          value: selected,
        ),
      );
    } catch (e) {
      debugPrint('Erreur enregistrement profession: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isCompletion = _isAnonymous;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.grey.shade800),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Header
                  _buildHeader(isCompletion),
                  const SizedBox(height: 32),

                  // Error banner
                  if (_errorMessage != null) ...[
                    _buildErrorBanner(),
                    const SizedBox(height: 16),
                  ],

                  // Tab switcher (email / phone) — seulement en mode complétion
                  if (isCompletion) ...[
                    _buildTabSwitcher(),
                    const SizedBox(height: 20),
                  ],

                  // Content
                  if (_selectedTab == 0 || !isCompletion)
                    _buildEmailSection(isCompletion)
                  else
                    _buildPhoneSection(),

                  // Google button
                  const SizedBox(height: 20),
                  _buildDivider(),
                  const SizedBox(height: 20),
                  _buildGoogleButton(),

                  // Toggle login/signup — seulement hors mode complétion
                  if (!isCompletion) ...[
                    const SizedBox(height: 20),
                    _buildLoginToggle(),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────

  Widget _buildHeader(bool isCompletion) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCompletion ? Icons.shield_outlined : Icons.lock_outline_rounded,
            color: _green,
            size: 36,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          isCompletion
              ? 'Sécurisez votre compte'
              : (_isLoginMode ? 'Bon retour !' : 'Créer un compte'),
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isCompletion
              ? 'Créez votre compte gratuit en deux clics\npour ne pas perdre vos réservations.'
              : (_isLoginMode
                  ? 'Connectez-vous pour continuer'
                  : 'Rejoignez Baxa dès aujourd\'hui'),
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _tab(label: 'Téléphone', index: 1, icon: Icons.phone_outlined),
          _tab(label: 'Email', index: 0, icon: Icons.email_outlined),
        ],
      ),
    );
  }

  Widget _tab({required String label, required int index, required IconData icon}) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedTab = index;
          _clearError();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 6, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? _green : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _green : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailSection(bool isCompletion) {
    final signingUp = isCompletion || !_isLoginMode;
    // AutofillGroup : rend l'autofill Android déterministe au lieu de le laisser
    // se battre avec la saisie (ré-injection d'un ancien mot de passe, etc.).
    // Clé stable : l'apparition du bandeau d'erreur au-dessus ne doit pas faire
    // réconcilier ce bloc avec un autre `Container` — ce qui réinitialiserait le
    // formulaire et ferait "sauter" les champs.
    return AutofillGroup(
      key: const ValueKey('signin-email-section'),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
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
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                onChanged: (_) => _clearError(),
                decoration: _inputDeco(
                  label: 'Adresse e-mail',
                  hint: 'exemple@email.com',
                  icon: Icons.email_outlined,
                ),
                validator: (v) => (v == null || v.isEmpty || !v.contains('@'))
                    ? 'Entrez un e-mail valide'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _isObscure,
                // Toujours désactivés (même quand le mot de passe est révélé) :
                // évite que le basculement de l'œil ne renégocie le clavier
                // Android et ne vide / réinitialise le champ.
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: [
                  signingUp
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onChanged: (_) => _clearError(),
                decoration: _inputDeco(
                  label: 'Mot de passe',
                  hint: 'Minimum 6 caractères',
                  icon: Icons.lock_outline,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey.shade500,
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
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoadingEmail ? null : _submitEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoadingEmail
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          signingUp ? 'Créer mon compte' : 'Se connecter',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneSection() {
    return Container(
      key: const ValueKey('signin-phone-section'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_phoneStep == _PhoneStep.enterNumber) ...[
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              onChanged: (_) => _clearError(),
              decoration: _inputDeco(
                label: 'Numéro de téléphone',
                hint: '+221 77 000 00 00',
                icon: Icons.phone_outlined,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Incluez le code pays (ex: +221 pour le Sénégal)',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoadingPhone ? null : _sendOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoadingPhone
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Recevoir le code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            // OTP step
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.sms_outlined, color: _green, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Code envoyé au ${_phoneController.text.trim()}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _phoneStep = _PhoneStep.enterNumber;
                      _otpController.clear();
                      _clearError();
                    }),
                    child: Text('Modifier', style: TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 8),
              onChanged: (_) => _clearError(),
              decoration: _inputDeco(
                label: 'Code de vérification',
                hint: '------',
                icon: Icons.pin_outlined,
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoadingPhone ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoadingPhone
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Vérifier', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      key: const ValueKey('signin-error-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFE53935), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB71C1C), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('ou', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _isLoadingGoogle ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
        ),
        child: _isLoadingGoogle
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _green),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'G',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Continuer avec Google',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoginToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            _isLoginMode ? 'Pas encore de compte ?' : 'Vous avez déjà un compte ?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _isLoginMode = !_isLoginMode;
            // Pas de reset() : l'email et le mot de passe sont les mêmes champs
            // dans les deux modes — les vider à la bascule est déroutant et
            // oblige l'utilisateur à tout retaper.
            _clearError();
          }),
          child: Text(
            _isLoginMode ? 'S\'inscrire' : 'Se connecter',
            style: const TextStyle(color: _green, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _green, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}

