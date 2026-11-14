import 'dart:async';

import 'package:baxa/page%20b-acceuil/customer/customer_page.dart';
import 'package:flutter/material.dart';
import 'package:baxa/services/firebase/otp_cooldown.dart';
import 'package:baxa/services/phone_number.dart';
import 'package:baxa/services/reservation_rules_service.dart';
import 'package:baxa/widgets/google_sign_in_button.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:baxa/services/locale_service.dart';
import 'package:baxa/services/location_service.dart';
import 'package:baxa/services/password_rules.dart';
import 'package:baxa/widgets/password_checklist.dart';
import 'package:baxa/widgets/profession_picker_sheet.dart';

// ── Modes d'authentification téléphone ────────────────────────────────────────
enum _PhoneStep { enterNumber, enterOtp }

/// Connexion / inscription client.
///  • `loginMode: false` (défaut) : un client sans compte (anonyme) sécurise
///    son compte — ses réservations et favoris sont gardés.
///  • `loginMode: true` : « Se connecter » à un compte existant (écran
///    d'accueil client, ou « Mon profil » d'un client sans compte). Google
///    et le téléphone créent aussi le compte s'il n'existe pas encore.
/// Si les identifiants choisis appartiennent déjà à un autre compte Baxa,
/// le client sans compte peut basculer dessus : ce qu'il avait fait sans
/// compte est abandonné (compte supprimé côté serveur, réservations en
/// cours annulées pour libérer les places) — choix du 14/11/2026.
class SigninePage extends StatefulWidget {
  final bool loginMode;
  const SigninePage({super.key, this.loginMode = false});

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
  // Numéro (format international) auquel le dernier code a été envoyé.
  String? _sentTo;

  bool get _isAnonymous =>
      FirebaseAuth.instance.currentUser?.isAnonymous == true;

  // Client sans compte qui sécurise SON compte (liaison, rien n'est perdu).
  bool get _guestCompletion => _isAnonymous && !widget.loginMode;

  // Active tab: 0 = email, 1 = phone  — phone shown first by default
  int _selectedTab = 1;

  @override
  void initState() {
    super.initState();
    _isLoginMode = widget.loginMode;
  }

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
        return 'Mot de passe trop faible : $kPasswordMinLength caractères '
            'minimum, avec au moins une lettre et un chiffre.';
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

  // ── Fin de connexion (commune à Google, téléphone, e-mail) ─────

  /// Compte professionnel (structure ou membre d'équipe) ? Il ne doit
  /// jamais devenir un compte client : on ne touche pas à sa fiche.
  Future<bool> _isProfessionalAccount(String uid) async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('companies').doc(uid).get(),
      db.collection('users').doc(uid).get(),
    ]);
    if (results[0].exists) return true;
    return results[1].data()?['role'] == 'staff';
  }

  /// Après toute connexion réussie : vérifie le type de compte, complète
  /// la fiche client SANS écraser l'existant, puis entre dans l'espace
  /// client. [previousUid] = compte avant la connexion (null si aucun) :
  /// s'il change, on repart d'un espace client neuf au lieu de revenir à
  /// l'écran d'où l'on vient (qui affichait l'ancien compte).
  Future<void> _finishSignIn(User user, {required String? previousUid}) async {
    if (await _isProfessionalAccount(user.uid)) {
      await _signOutEverywhere();
      _setError(
        'Ce compte est un compte professionnel (structure ou équipe) : '
        'utilisez l\'espace Structure ou Équipe depuis l\'écran d\'accueil.',
      );
      return;
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    Map<String, dynamic> existing = const {};
    try {
      existing = (await ref.get()).data() ?? const {};
    } catch (_) {}

    try {
      final updates = <String, dynamic>{
        'isAnonymous': false,
        'role': 'customer',
        ...LocaleService.toFirestoreMap(),
        if (user.email != null && user.email!.isNotEmpty) 'email': user.email,
        if (existing['createdAt'] == null)
          'createdAt': FieldValue.serverTimestamp(),
      };
      // Nom : celui déjà saisi reste prioritaire ; sinon celui de Google.
      final hasName =
          (existing['prenom'] as String?)?.trim().isNotEmpty == true;
      final display = (user.displayName ?? '').trim();
      if (!hasName && display.isNotEmpty) {
        final parts = display.split(RegExp(r'\s+'));
        updates['prenom'] = parts.first;
        updates['nom'] = parts.length > 1 ? parts.sublist(1).join(' ') : '';
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

    if (!mounted) return;
    await _askNameIfMissing(ref);
    if (!mounted) return;
    await _onSuccess(accountChanged: previousUid != user.uid);
  }

  Future<void> _signOutEverywhere() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  // ── Bascule d'un client sans compte vers un compte existant ─────

  /// Réservations à venir du client sans compte (pour l'avertissement).
  Future<int> _guestActiveReservations(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('reservations')
          .where('customerId', isEqualTo: uid)
          .where('status', isEqualTo: 'confirmed')
          .get();
      final now = DateTime.now();
      return snap.docs.where((d) {
        final end = (d.data()['slotEnd'] as Timestamp?)?.toDate();
        return end != null && end.isAfter(now);
      }).length;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> _confirmSwitchToExisting(int activeCount) async {
    final plural = activeCount > 1 ? 's' : '';
    final lost = activeCount > 0
        ? 'vos $activeCount réservation$plural en cours (annulée$plural) '
              'et vos favoris'
        : 'vos favoris et votre historique';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ce compte Baxa existe déjà'),
        content: Text(
          'Se connecter à ce compte ?\n\n'
          'Ce que vous avez fait sur ce téléphone sans compte sera perdu : '
          '$lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Se connecter'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Le client sans compte veut utiliser des identifiants qui ont déjà un
  /// compte Baxa. Après accord : son compte sans inscription est supprimé
  /// par le serveur (réservations en cours annulées, places libérées), puis
  /// on se connecte au compte existant avec [signIn].
  Future<void> _switchFromGuest(
    Future<UserCredential> Function() signIn,
  ) async {
    final guest = FirebaseAuth.instance.currentUser;
    if (guest == null || !guest.isAnonymous) return;
    final active = await _guestActiveReservations(guest.uid);
    if (!mounted || !await _confirmSwitchToExisting(active)) return;

    try {
      await ReservationRulesService().deleteMyAccount();
    } catch (e) {
      _setError('Impossible de changer de compte pour le moment. '
          'Vérifiez votre connexion et réessayez.');
      return;
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    // L'écran passe en mode connexion (utile si la connexion qui suit échoue).
    if (mounted) setState(() => _isLoginMode = true);

    // À partir d'ici il n'y a plus de compte sur ce téléphone : en cas
    // d'échec, l'écran reste ouvert pour réessayer de se connecter.
    final cred = await signIn();
    final user = cred.user;
    if (user != null) await _finishSignIn(user, previousUid: guest.uid);
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
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final current = FirebaseAuth.instance.currentUser;
    final previousUid = current?.uid;
    Future<UserCredential> signInExisting() => FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    try {
      if (current != null && current.isAnonymous && !_isLoginMode) {
        // Client sans compte qui crée son compte : liaison (rien n'est perdu).
        try {
          final result = await current.linkWithCredential(
            EmailAuthProvider.credential(email: email, password: password),
          );
          await _finishSignIn(result.user!, previousUid: previousUid);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'email-already-in-use') rethrow;
          await _switchFromGuest(signInExisting);
        }
      } else if (_isLoginMode) {
        if (current != null && current.isAnonymous) {
          await _switchFromGuest(signInExisting);
        } else {
          final result = await signInExisting();
          await _finishSignIn(result.user!, previousUid: previousUid);
        }
      } else {
        final result = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await _finishSignIn(result.user!, previousUid: previousUid);
      }
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
      if (googleUser == null) return; // choix annulé
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e));
    } catch (e) {
      _setError('Erreur lors de la connexion Google. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoadingGoogle = false);
    }
  }

  /// Google ou téléphone. Client sans compte : on LIE d'abord (il garde
  /// tout) ; si ces identifiants ont déjà un compte Baxa, on propose de
  /// basculer dessus. Sinon : connexion (ou création si nouveau compte).
  Future<void> _signInWithCredential(AuthCredential credential) async {
    final current = FirebaseAuth.instance.currentUser;
    final previousUid = current?.uid;
    if (current != null && current.isAnonymous) {
      try {
        final result = await current.linkWithCredential(credential);
        await _finishSignIn(result.user!, previousUid: previousUid);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use') rethrow;
        // Firebase renvoie les identifiants vérifiés, réutilisables pour
        // se connecter au compte existant.
        final existing = e.credential ?? credential;
        await _switchFromGuest(
          () => FirebaseAuth.instance.signInWithCredential(existing),
        );
      }
      return;
    }
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    await _finishSignIn(result.user!, previousUid: previousUid);
  }

  // ── Phone / OTP ───────────────────────────────────────────────

  Future<void> _sendOtp() async {
    _clearError();
    // Numéro lu et vérifié avant tout envoi (espaces, +221 oublié…).
    final parsed = parsePhoneNumber(_phoneController.text);
    if (!parsed.isValid) {
      _setError(parsed.error!);
      return;
    }
    final phone = parsed.e164!;
    final wait = OtpCooldown.secondsLeft(phone);
    if (wait > 0) {
      _setError(OtpCooldown.waitMessage(wait));
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
        debugPrint('⚠️ SMS client refusé : ${e.code} — ${e.message}');
        if (mounted) {
          setState(() => _isLoadingPhone = false);
          _setError(phoneAuthErrorMessage(e.code) ?? kSmsUnavailableMessage);
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        OtpCooldown.markSent(phone);
        if (mounted) {
          setState(() {
            _verificationId = verificationId;
            _sentTo = phone;
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
    if (_verificationId == null) {
      _setError('Le code a expiré. Demandez un nouveau.');
      return;
    }
    setState(() => _isLoadingPhone = true);
    final cred = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: _otpController.text.trim(),
    );
    await _linkPhoneCred(cred);
  }

  Future<void> _linkPhoneCred(PhoneAuthCredential cred) async {
    try {
      await _signInWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e));
    } catch (e) {
      _setError('Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoadingPhone = false);
    }
  }

  // ── Navigation on success ─────────────────────────────────────

  Future<void> _onSuccess({required bool accountChanged}) async {
    await _showProfessionSheet();
    if (!mounted) return;

    // Même compte (client sans compte qui vient de le sécuriser) : retour à
    // l'écran d'origine, qui attend ce résultat (ex. favori en attente).
    if (!accountChanged && Navigator.canPop(context)) {
      Navigator.pop(context, true);
      return;
    }
    // Nouveau compte (connexion depuis l'accueil, ou bascule vers un compte
    // existant) : espace client neuf, sans les écrans de l'ancien compte.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CustomerPage()),
      (route) => route.isFirst,
    );
  }

  // ── Prénom et nom (compte créé par téléphone ou e-mail) ────────

  Future<void> _askNameIfMissing(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    Map<String, dynamic> data = const {};
    try {
      data = (await ref.get()).data() ?? const {};
    } catch (_) {
      return;
    }
    if ((data['prenom'] as String?)?.trim().isNotEmpty == true) return;
    if (!mounted) return;

    final prenomCtrl = TextEditingController();
    final nomCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Comment vous appelez-vous ?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Votre nom apparaît sur vos réservations.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: prenomCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDeco(
                  label: 'Prénom',
                  hint: 'Votre prénom',
                  icon: Icons.person_outline_rounded,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Entrez votre prénom'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nomCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDeco(
                  label: 'Nom de famille',
                  hint: 'Votre nom',
                  icon: Icons.badge_outlined,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continuer',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final prenom = prenomCtrl.text.trim();
    final nom = nomCtrl.text.trim();
    prenomCtrl.dispose();
    nomCtrl.dispose();
    if (saved != true || prenom.isEmpty) return;
    try {
      await ref.set({'prenom': prenom, 'nom': nom}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Enregistrement du nom impossible : $e');
    }
  }

  // ── Profession (une seule fois, à la première inscription) ─────
  // Affichée en bottom sheet AVANT le pop/pushReplacement ci-dessus, pour ne
  // jamais casser le flow "favori en attente" de search_dialogs.dart, qui
  // attend que cette page se pop pour reprendre la main. Jamais redemandée
  // à un client qui y a déjà répondu (reconnexion).
  Future<void> _showProfessionSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      final current = (await ref.get()).data()?['profession'];
      if (current is String && current.isNotEmpty) return;
    } catch (_) {}
    if (!mounted) return;
    final selected = await showProfessionPickerSheet(context);
    if (selected == null || !mounted) return; // "Passer" ou fermée
    try {
      await ref.set({'profession': selected}, SetOptions(merge: true));
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
    final isCompletion = _guestCompletion;
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

                  // Google en premier : pas de SMS, donc pas de blocage selon
                  // l'opérateur (voir google_sign_in_button.dart).
                  GoogleSignInButton(
                    onPressed: _isLoadingPhone ? null : _signInWithGoogle,
                    loading: _isLoadingGoogle,
                  ),
                  const SizedBox(height: 22),
                  const SignInOrDivider(
                    label: 'ou avec votre numéro ou votre e-mail',
                  ),
                  const SizedBox(height: 22),

                  // Téléphone / e-mail : dans tous les modes (un client qui
                  // revient peut s'être inscrit par téléphone).
                  _buildTabSwitcher(),
                  const SizedBox(height: 20),

                  // Content
                  if (_selectedTab == 0)
                    _buildEmailSection(isCompletion)
                  else
                    _buildPhoneSection(),

                  // Connexion / inscription par e-mail — hors complétion
                  if (!isCompletion && _selectedTab == 0) ...[
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
                  ? 'Retrouvez votre compte Baxa.\nPas encore de compte ? Google et le '
                        'téléphone le créent pour vous.'
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
                  hint: signingUp
                      ? '8 caractères, une lettre, un chiffre'
                      : 'Votre mot de passe',
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
                // Inscription : règle Baxa. Connexion : non vide seulement
                // (les comptes créés avant la règle se connectent toujours).
                validator: (v) => signingUp
                    ? validateNewPassword(v)
                    : ((v == null || v.isEmpty)
                          ? 'Veuillez entrer un mot de passe'
                          : null),
              ),
              if (signingUp) ...[
                const SizedBox(height: 4),
                PasswordChecklist(
                  controller: _passwordController,
                  okColor: _green,
                ),
              ],
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
                hint: '77 000 00 00',
                icon: Icons.phone_outlined,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Numéro sénégalais : +221 ajouté automatiquement. '
              'Autre pays : commencez par + et l\'indicatif.',
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
                      'Code envoyé au '
                      '${_sentTo != null ? formatPhoneForDisplay(_sentTo!) : _phoneController.text.trim()}',
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

