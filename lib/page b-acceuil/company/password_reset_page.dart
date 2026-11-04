import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================
// MOT DE PASSE OUBLIÉ — structure
// ============================================================
// Ouverte depuis le lien « Mot de passe oublié ? » de SigninPage (mode
// connexion uniquement). Deux états sur la même page :
//   1. Demande : l'e-mail (pré-rempli depuis la connexion) → « Recevoir le lien »
//   2. Lien envoyé : message neutre + « Renvoyer » bloqué 60 s
//
// Le message est le même que le compte existe ou non : on ne révèle jamais
// si une adresse est inscrite sur Baxa. La page renvoie l'e-mail utilisé à
// la fermeture, pour pré-remplir la connexion.

// Palette de l'onboarding structure (identique à signin_page.dart).
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

const int _resendCooldownSeconds = 60;

class CompanyPasswordResetPage extends StatefulWidget {
  final String? initialEmail;

  const CompanyPasswordResetPage({super.key, this.initialEmail});

  @override
  State<CompanyPasswordResetPage> createState() =>
      _CompanyPasswordResetPageState();
}

class _CompanyPasswordResetPageState extends State<CompanyPasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  bool _isSending = false;
  bool _sent = false;
  String? _errorMessage;

  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim();

  // Retour à la connexion avec l'e-mail saisi.
  void _close() => Navigator.pop(context, _email);

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeft = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) t.cancel();
    });
  }

  Future<void> _sendLink({bool isResend = false}) async {
    if (_isSending) return;
    if (!isResend && !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    var delivered = false;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _email);
      delivered = true;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        // Adresse inconnue ou compte désactivé : même écran que si l'envoi
        // avait eu lieu (ne pas révéler quelles adresses sont inscrites).
        case 'user-not-found':
        case 'user-disabled':
          delivered = true;
        case 'invalid-email':
        case 'missing-email':
          _errorMessage = 'Adresse e-mail invalide.';
        case 'network-request-failed':
          _errorMessage = 'Vérifiez votre connexion internet.';
        case 'too-many-requests':
          _errorMessage =
              'Trop de tentatives. Réessayez dans quelques minutes.';
        default:
          _errorMessage = 'Une erreur est survenue. Réessayez.';
      }
    } catch (e) {
      debugPrint('PASSWORD RESET ▶ Erreur inattendue : $e');
      _errorMessage = 'Une erreur est survenue. Réessayez.';
    }

    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (delivered) _sent = true;
    });
    if (delivered) {
      _startCooldown();
      if (isResend) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nouveau lien envoyé')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                    // Chevron sur la demande ; rien sur la confirmation, où
                    // « Retour à la connexion » est le bouton principal.
                    SizedBox(
                      height: 56,
                      child: _sent
                          ? null
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  onPressed: _close,
                                  tooltip: 'Retour',
                                  icon: const Icon(
                                    Icons.chevron_left_rounded,
                                    color: _green,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        child: _sent ? _buildSentBody() : _buildRequestBody(),
                      ),
                    ),
                    _buildBottomBar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 1. Demande ─────────────────────────────────────────────────────────────
  Widget _buildRequestBody() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _greenSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.key_rounded, color: _green, size: 28),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Mot de passe oublié ?', style: _titleStyle),
          const SizedBox(height: 8),
          const Text(
            'Pas de souci. Indiquez l\'e-mail de votre structure, nous vous '
            'envoyons un lien pour en choisir un nouveau.',
            style: _subtitleStyle,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 24),
            _ErrorBanner(message: _errorMessage!),
          ],
          SizedBox(height: _errorMessage != null ? 20 : 28),
          const Text(
            'Adresse e-mail',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _labelDark,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('company-reset-email'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.send,
            onFieldSubmitted: (_) => _sendLink(),
            onChanged: (_) {
              if (_errorMessage != null) setState(() => _errorMessage = null);
            },
            style: const TextStyle(fontSize: 15, color: _dark),
            decoration: _inputDecoration(
              hint: 'vous@structure.com',
              icon: Icons.mail_outline_rounded,
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Veuillez entrer votre e-mail';
              if (!v.contains('@')) return 'Veuillez entrer un e-mail valide';
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── 2. Lien envoyé ─────────────────────────────────────────────────────────
  Widget _buildSentBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: _greenSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mail_outline_rounded,
                    color: _green,
                    size: 34,
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Vérifiez votre boîte mail.', style: _titleStyle),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: _subtitleStyle.copyWith(height: 1.5),
            children: [
              const TextSpan(text: 'Si un compte Baxa existe pour '),
              TextSpan(
                text: _email,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _dark,
                ),
              ),
              const TextSpan(
                text:
                    ', vous allez recevoir un lien pour choisir un nouveau '
                    'mot de passe.',
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 20),
          _ErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _greenSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            children: [
              _SentStep(
                number: 1,
                text: 'Ouvrez l\'e-mail de Baxa et touchez le lien.',
              ),
              SizedBox(height: 12),
              _SentStep(number: 2, text: 'Choisissez un nouveau mot de passe.'),
              SizedBox(height: 12),
              _SentStep(number: 3, text: 'Revenez ici et connectez-vous.'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Rien reçu ? Regardez dans vos spams. Le lien est valable 1 heure.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: _muted),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final canResend = _cooldownLeft <= 0 && !_isSending;
    final seconds = _cooldownLeft.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _sent
                  ? _close
                  : (_isSending ? null : () => _sendLink()),
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
              child: !_sent && _isSending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _sent ? 'Retour à la connexion' : 'Recevoir le lien',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _sent
                ? (canResend ? () => _sendLink(isResend: true) : null)
                : _close,
            style: TextButton.styleFrom(
              foregroundColor: _greenText,
              disabledForegroundColor: const Color(0xFF8A938D),
              minimumSize: const Size(0, 44),
            ),
            child: Text(
              !_sent
                  ? 'Retour à la connexion'
                  : (_cooldownLeft > 0
                        ? 'Renvoyer le lien dans 0:$seconds'
                        : 'Renvoyer le lien'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
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
        if (states.contains(WidgetState.error)) return _errorRed;
        if (states.contains(WidgetState.focused)) return _green;
        return _iconIdle;
      }),
      filled: true,
      fillColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.focused) ||
                states.contains(WidgetState.error)
            ? Colors.white
            : _fieldFill,
      ),
      hoverColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: outline(_border, 1.5),
      enabledBorder: outline(_border, 1.5),
      focusedBorder: outline(_green, 2),
      errorBorder: outline(_errorRed, 2),
      focusedErrorBorder: outline(_errorRed, 2),
      errorStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: _errorRed,
      ),
    );
  }
}

const TextStyle _titleStyle = TextStyle(
  fontSize: 28,
  height: 1.15,
  fontWeight: FontWeight.w800,
  color: _dark,
  letterSpacing: -0.5,
);

const TextStyle _subtitleStyle = TextStyle(
  fontSize: 16,
  height: 1.45,
  fontWeight: FontWeight.w500,
  color: _subtle,
);

// ── Étape numérotée de la carte « que faire maintenant » ────────────────────
class _SentStep extends StatelessWidget {
  final int number;
  final String text;

  const _SentStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _green,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: _dark,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Bannière d'erreur inline (même style que la connexion) ──────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('company-reset-error-banner'),
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
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: _errorText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
