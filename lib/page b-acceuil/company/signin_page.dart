import 'package:baxa/page%20b-acceuil/company/company_page.dart';
import 'package:baxa/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Palette de l'onboarding structure (company_onboarding_page.dart) : la page
// d'inscription en est la dernière étape et doit en garder l'esthétique.
const Color _green = Color(0xFF3F7A51);
const Color _greenSoft = Color(0xFFEEF5F0);
const Color _greenText = Color(0xFF2F5E3D);
const Color _dark = Color(0xFF1A2E1F);
const Color _labelDark = Color(0xFF1E2D23);
const Color _muted = Color(0xFF4A564E);
const Color _subtle = Color(0xFF5F6B63);
const Color _border = Color(0xFFD5DED8);
const Color _fieldFill = Color(0xFFF6F8F6);
const Color _iconIdle = Color(0xFF5B6660);
const Color _errorRed = Color(0xFFD93A3A);
const Color _errorText = Color(0xFF7B1111);

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
  // Code FirebaseAuth de la dernière erreur : sert uniquement à l'affichage
  // (champ e-mail en rouge, raccourci « Se connecter à la place »).
  String? _errorCode;

  // Arrivée depuis l'onboarding (formulaire + journée type) : on affiche le
  // rappel de la structure. Ouverte seule (déconnexion,
  // RedirectionPage), la page n'a pas ces informations.
  bool get _fromOnboarding => widget.nomEntreprise != null;

  bool get _emailInError =>
      _errorCode == 'email-already-in-use' || _errorCode == 'invalid-email';

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

  void _setError(String message, {String? code}) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
        _errorCode = code;
      });
    }
  }

  void _clearError() {
    if (_errorMessage != null && mounted) {
      setState(() {
        _errorMessage = null;
        _errorCode = null;
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      // Pas de reset() : l'email et le mot de passe sont les mêmes champs dans
      // les deux modes — les vider à la bascule oblige à tout retaper.
      _errorMessage = null;
      _errorCode = null;
    });
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
      _setError(_friendlyError(e), code: e.code);
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
      _setError(_friendlyError(e), code: e.code);
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

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    bool forcedError = false,
    Widget? suffix,
  }) {
    OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 15, color: Color(0xFF88928B)),
      prefixIcon: Icon(icon, size: 20),
      prefixIconColor: WidgetStateColor.resolveWith((states) {
        if (forcedError || states.contains(WidgetState.error)) return _errorRed;
        if (states.contains(WidgetState.focused)) return _green;
        return _iconIdle;
      }),
      suffixIcon: suffix,
      suffixIconColor: _iconIdle,
      filled: true,
      // Fond légèrement teinté au repos, blanc quand le champ est actif.
      fillColor: WidgetStateColor.resolveWith(
        (states) =>
            forcedError ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.error)
            ? Colors.white
            : _fieldFill,
      ),
      hoverColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: outline(_border, 1.5),
      enabledBorder: forcedError
          ? outline(_errorRed, 2)
          : outline(_border, 1.5),
      focusedBorder: outline(forcedError ? _errorRed : _green, 2),
      errorBorder: outline(_errorRed, 2),
      focusedErrorBorder: outline(_errorRed, 2),
      errorStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: _errorRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final showOnboardingChrome = !_isLoginMode && _fromOnboarding;

    final structureDetail = [
      widget.typeEntreprise ?? widget.typeCategorie,
      widget.ville,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  // Retour vers « Une journée chez… » — absent quand la page
                  // est la racine (RedirectionPage après déconnexion).
                  if (canPop)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          tooltip: 'Retour',
                          icon: const Icon(
                            Icons.chevron_left_rounded,
                            color: _green,
                            size: 30,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 24),

                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Form(
                        key: _formkey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showOnboardingChrome) ...[
                              const _StepTag(),
                              const SizedBox(height: 20),
                            ],
                            if (_isLoginMode) ...[
                              const _AgendaPreview(),
                              const SizedBox(height: 28),
                            ],

                            Text(
                              _isLoginMode
                                  ? 'Bon retour.'
                                  : 'Créez votre accès.',
                              style: const TextStyle(
                                fontSize: 28,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: _dark,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isLoginMode
                                  ? 'Connectez-vous pour retrouver votre agenda.'
                                  : 'Un e-mail, un mot de passe, et votre agenda est prêt.',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                                color: _subtle,
                              ),
                            ),

                            if (showOnboardingChrome) ...[
                              const SizedBox(height: 24),
                              _StructureRecap(
                                name: widget.nomEntreprise!,
                                detail: structureDetail,
                              ),
                            ],

                            if (_errorMessage != null) ...[
                              const SizedBox(height: 24),
                              _ErrorBanner(
                                message: _errorMessage!,
                                onSwitchToLogin:
                                    !_isLoginMode &&
                                        _errorCode == 'email-already-in-use'
                                    ? _toggleMode
                                    : null,
                              ),
                            ],

                            SizedBox(height: _errorMessage != null ? 20 : 24),

                            const _FieldLabel('Adresse e-mail'),
                            const SizedBox(height: 8),
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
                              style: const TextStyle(
                                fontSize: 15,
                                color: _dark,
                              ),
                              decoration: _inputDecoration(
                                hint: 'vous@structure.com',
                                icon: Icons.mail_outline_rounded,
                                forcedError: _emailInError,
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

                            const SizedBox(height: 16),

                            const _FieldLabel('Mot de passe'),
                            const SizedBox(height: 8),
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
                              style: const TextStyle(
                                fontSize: 15,
                                color: _dark,
                              ),
                              decoration: _inputDecoration(
                                hint: _isLoginMode
                                    ? 'Votre mot de passe'
                                    : 'Choisissez un mot de passe',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  tooltip: _isObscure
                                      ? 'Afficher le mot de passe'
                                      : 'Masquer le mot de passe',
                                  icon: Icon(
                                    _isObscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
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

                            if (!_isLoginMode) ...[
                              const SizedBox(height: 8),
                              _PasswordRule(controller: _passwordController),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  _buildBottomBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isBusy = _isLoadingLogin || _isLoadingSignup;
    final isLoading = _isLoginMode ? _isLoadingLogin : _isLoadingSignup;
    // Clavier ouvert : on garde seulement le bouton et la bascule, pour
    // laisser la place aux champs.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!keyboardOpen) ...[
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: _muted),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Vos données sont chiffrées et protégées.',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: isBusy
                  ? null
                  : (_isLoginMode ? _handleLogin : _handleSignup),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _green.withValues(alpha: 0.7),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isLoginMode ? 'Se connecter' : 'Créer mon compte',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _isLoginMode
                      ? 'Première fois sur Baxa ?'
                      : 'Déjà un compte ?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: _subtle),
                ),
              ),
              TextButton(
                onPressed: _toggleMode,
                style: TextButton.styleFrom(foregroundColor: _greenText),
                child: Text(
                  _isLoginMode ? 'S\'inscrire' : 'Se connecter',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pastille « Dernière étape », même forme que les étiquettes de l'onboarding ─
class _StepTag extends StatelessWidget {
  const _StepTag();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              'Dernière étape',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· votre accès',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rappel de la structure saisie dans le formulaire (lecture seule) ─────────
class _StructureRecap extends StatelessWidget {
  final String name;
  final String detail;

  const _StructureRecap({required this.name, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.storefront_outlined,
              size: 24,
              color: _green,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Aperçu d'agenda du mode connexion (reprend l'illustration de l'onboarding)
class _AgendaPreview extends StatelessWidget {
  const _AgendaPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              'VOTRE JOURNÉE VOUS ATTEND',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _greenText,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _AgendaRow(
            time: '08:00 – 08:15',
            label: 'Awa D.',
            labelColor: Colors.blue.shade700,
          ),
          const SizedBox(height: 8),
          _AgendaRow(
            time: '08:15 – 08:30',
            label: 'M. Sarr',
            labelColor: Colors.blue.shade700,
          ),
          const SizedBox(height: 8),
          const Opacity(
            opacity: 0.6,
            child: _AgendaRow(
              time: '08:30 – 08:45',
              label: 'Disponible',
              labelColor: _greenText,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  final String time;
  final String label;
  final Color labelColor;

  const _AgendaRow({
    required this.time,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _dark,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bannière d'erreur inline ─────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  // Non nul seulement pour « compte déjà existant » : bascule en connexion.
  final VoidCallback? onSwitchToLogin;

  const _ErrorBanner({required this.message, this.onSwitchToLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('company-signin-error-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEEEE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFC62828),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: _errorText,
                  ),
                ),
                if (onSwitchToLogin != null)
                  TextButton(
                    onPressed: onSwitchToLogin,
                    style: TextButton.styleFrom(
                      foregroundColor: _errorText,
                      padding: const EdgeInsets.only(top: 6),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text(
                      'Se connecter à la place',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: _errorText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _labelDark,
      ),
    );
  }
}

// ── Règle du mot de passe, cochée dès qu'elle est respectée (affichage seul :
// la validation reste celle du TextFormField) ──────────────────────────────
class _PasswordRule extends StatelessWidget {
  final TextEditingController controller;
  const _PasswordRule({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, _) {
        final ok = value.text.length >= 6;
        final color = ok ? _greenText : _subtle;
        return Row(
          children: [
            Icon(
              ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: ok ? _green : _subtle,
            ),
            const SizedBox(width: 6),
            Text(
              '6 caractères minimum',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}
