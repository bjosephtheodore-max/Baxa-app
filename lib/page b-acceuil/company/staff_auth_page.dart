import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:baxa/page b-acceuil/company/staff_page.dart';
import 'package:baxa/services/booking_constants.dart';
import 'package:baxa/services/firebase/auth.dart';

// ============================================================
// STAFF AUTH PAGE — deux parcours :
//  • Rejoindre une équipe : code → tél ou Google → OTP
//  • Déjà membre (simple déconnexion) : tél ou Google → OTP, sans code
// L'adhésion elle-même est faite côté serveur (joinTeamWithCode) : les
// règles Firestore interdisent au client de créer son document staff.
// ============================================================
class StaffAuthPage extends StatefulWidget {
  const StaffAuthPage({super.key});

  @override
  State<StaffAuthPage> createState() => _StaffAuthPageState();
}

class _StaffAuthPageState extends State<StaffAuthPage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);

  int _step = 0;

  // true = parcours « Déjà membre ? Se reconnecter » (pas de code).
  bool _reconnect = false;

  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;
  String? _verificationId;
  String? _inviteCode;
  String? _companyName;

  @override
  void dispose() {
    _codeController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _setError(String msg) {
    if (mounted) setState(() => _errorMessage = msg);
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  HttpsCallable _callable(String name) =>
      FirebaseFunctions.instance.httpsCallable(name);

  // Message lisible pour une erreur renvoyée par les fonctions d'équipe.
  String _teamErrorMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'Code invalide. Demandez un nouveau code a votre responsable.';
      case 'failed-precondition':
        if (e.message?.contains('entreprise') == true) {
          return 'Ce compte est un compte entreprise, il ne peut pas '
              'rejoindre une equipe.';
        }
        return 'Ce code a deja ete utilise. Demandez un nouveau code a '
            'votre responsable.';
      case 'resource-exhausted':
        return 'L\'equipe est complete ($kMaxActiveStaff membres maximum). '
            'Contactez votre responsable.';
      default:
        return 'Erreur de connexion. Veuillez réessayer.';
    }
  }

  // Ferme la session ouverte pour rien (adhésion refusée, pas membre...)
  // pour ne pas laisser un compte connecté sans rôle sur l'appareil.
  Future<void> _abortSession() => Auth().logout();

  // Passer au parcours « Déjà membre » / revenir au code d'invitation.
  void _startReconnect() {
    setState(() {
      _reconnect = true;
      _step = 1;
      _errorMessage = null;
    });
  }

  void _goBack() {
    setState(() {
      _errorMessage = null;
      if (_reconnect && _step == 1) {
        _reconnect = false;
        _step = 0;
      } else {
        _step--;
      }
    });
  }

  // ==============================================================
  // ETAPE 0 — Verifier le code d'invitation (côté serveur)
  // ==============================================================
  Future<void> _verifyInviteCode() async {
    _clearError();
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _setError('Veuillez entrer le code d\'invitation.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _callable('checkInviteCode').call({'code': code});
      final data = Map<String, dynamic>.from(res.data as Map);
      if (mounted) {
        setState(() {
          _inviteCode = code;
          final name = data['companyName'] as String? ?? '';
          _companyName = name.isNotEmpty ? name : 'l\'entreprise';
          _step = 1;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      _setError(_teamErrorMessage(e));
    } catch (e) {
      _setError('Erreur de connexion. Veuillez réessayer.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==============================================================
  // ETAPE 1a — Envoyer l'OTP par SMS
  // ==============================================================
  Future<void> _sendOtp() async {
    _clearError();
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 8) {
      _setError('Entrez un numero de telephone valide.');
      return;
    }

    final formatted = phone.startsWith('+') ? phone : '+221$phone';

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formatted,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithPhoneCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (e.code == 'invalid-phone-number') {
            _setError('Numero de telephone invalide.');
          } else if (e.code == 'too-many-requests') {
            _setError('Trop de tentatives. Reessayez dans quelques minutes.');
          } else {
            _setError('Erreur d\'envoi du SMS. Reessayez.');
          }
          if (mounted) setState(() => _isLoading = false);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _step = 2;
              _isLoading = false;
            });
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      _setError('Erreur. Verifiez votre connexion.');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==============================================================
  // ETAPE 1b — Connexion via Google
  // ==============================================================
  Future<void> _signInWithGoogle() async {
    _clearError();
    setState(() => _isGoogleLoading = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // Annule par l'utilisateur
        setState(() => _isGoogleLoading = false);
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
      await _afterSignIn(userCred);
    } catch (e) {
      _setError('Erreur Google. Reessayez.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // ==============================================================
  // ETAPE 2 — Verifier l'OTP
  // ==============================================================
  Future<void> _verifyOtp() async {
    _clearError();
    final code = _otpController.text.trim();
    if (code.length != 6) {
      _setError('Le code doit contenir 6 chiffres.');
      return;
    }
    if (_verificationId == null) {
      _setError('Session expiree. Recommencez.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _signInWithPhoneCredential(credential);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Appelé par la saisie manuelle de l'OTP ET par la validation
  // automatique Android : ne laisse jamais remonter d'exception.
  Future<void> _signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    UserCredential userCred;
    try {
      userCred = await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        _setError('Code incorrect. Verifiez le SMS et reessayez.');
      } else if (e.code == 'session-expired') {
        _setError('Session expiree. Revenez a l\'etape precedente.');
      } else {
        _setError('Erreur de verification. Reessayez.');
      }
      return;
    } catch (e) {
      _setError('Erreur lors de la connexion. Reessayez.');
      return;
    }
    await _afterSignIn(userCred);
  }

  // Une fois connecté : rejoindre avec le code, ou retrouver son équipe.
  Future<void> _afterSignIn(UserCredential userCred) async {
    if (userCred.user == null) return;
    if (_reconnect) {
      await _resumeMembership(userCred.user!.uid);
    } else {
      await _joinWithCode();
    }
  }

  // ==============================================================
  // REJOINDRE : adhésion faite par le serveur (code + limite vérifiés)
  // ==============================================================
  Future<void> _joinWithCode() async {
    if (_inviteCode == null) return;
    try {
      final res = await _callable(
        'joinTeamWithCode',
      ).call({'code': _inviteCode});
      final data = Map<String, dynamic>.from(res.data as Map);
      await _openStaffSpace(
        companyId: data['companyId'] as String,
        companyName: data['companyName'] as String? ?? _companyName ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      await _abortSession();
      _setError(_teamErrorMessage(e));
    } catch (e) {
      await _abortSession();
      _setError('Erreur lors de la creation du profil. Reessayez.');
    }
  }

  // ==============================================================
  // SE RECONNECTER : le compte doit être membre ACTIF d'une équipe
  // ==============================================================
  Future<void> _resumeMembership(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      final userDoc = await db.collection('users').doc(uid).get();
      final data = userDoc.data() ?? const {};
      final companyId = data['companyId'] as String?;

      var isActiveMember = false;
      if (data['role'] == 'staff' && companyId != null) {
        final staffDoc = await db
            .collection('companies')
            .doc(companyId)
            .collection('staff')
            .doc(uid)
            .get();
        isActiveMember = staffDoc.data()?['isActive'] == true;
      }

      if (!isActiveMember) {
        await _abortSession();
        _setError(
          'Ce compte ne fait partie d\'aucune equipe. Verifiez que vous '
          'utilisez le meme numero ou compte Google qu\'a votre premiere '
          'connexion, sinon demandez un code a votre responsable.',
        );
        return;
      }

      await _openStaffSpace(
        companyId: companyId!,
        companyName: data['companyName'] as String? ?? '',
      );
    } catch (e) {
      await _abortSession();
      _setError('Erreur de connexion. Veuillez réessayer.');
    }
  }

  Future<void> _openStaffSpace({
    required String companyId,
    required String companyName,
  }) async {
    await FirebaseAnalytics.instance.setUserProperty(
      name: 'role',
      value: 'staff',
    );
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StaffPage(companyId: companyId, companyName: companyName),
      ),
      (route) => false,
    );
  }

  // ==============================================================
  // BUILD
  // ==============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            if (_step > 0) {
              _goBack();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _reconnect ? 'Se reconnecter' : 'Rejoindre une equipe',
          style: const TextStyle(
            color: _green,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildStepIndicator(),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(28),
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
                        if (_step == 0) _buildCodeStep(),
                        if (_step == 1) _buildAuthStep(),
                        if (_step == 2) _buildOtpStep(),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFFCDD2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFE53935),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFB71C1C),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Indicateur d'etapes ──────────────────────────────────
  Widget _buildStepIndicator() {
    // Le parcours « Déjà membre » saute l'étape du code : 2 étapes.
    final count = _reconnect ? 2 : 3;
    final current = _reconnect ? _step - 1 : _step;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        final isDone = i < current;
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isActive ? 28 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: isDone || isActive ? _green : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            if (i < count - 1) const SizedBox(width: 6),
          ],
        );
      }),
    );
  }

  // ── Etape 0 : Code d'invitation ──────────────────────────
  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _greenLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.group_add_rounded, color: _green, size: 36),
        ),
        const SizedBox(height: 20),
        Text(
          'Code d\'invitation',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Entrez le code que votre responsable vous a partage.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          // Pas d'ouverture automatique du clavier : il masquerait le lien
          // « Déjà membre ? Se reconnecter » dès l'arrivée sur l'écran.
          onChanged: (_) => _clearError(),
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
          decoration: InputDecoration(
            hintText: 'EX : BAXA12',
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 18,
              letterSpacing: 2,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyInviteCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Continuer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 12),
        // Membre simplement déconnecté : pas besoin d'un nouveau code.
        TextButton(
          onPressed: _isLoading ? null : _startReconnect,
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              children: const [
                TextSpan(text: 'Deja membre ? '),
                TextSpan(
                  text: 'Se reconnecter',
                  style: TextStyle(color: _green, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Etape 1 : Telephone ou Google ────────────────────────
  Widget _buildAuthStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _greenLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.phone_android_rounded,
            color: _green,
            size: 36,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _reconnect ? 'Bon retour !' : 'Votre compte',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (_reconnect)
          Text(
            'Utilisez le meme numero ou le meme compte Google qu\'a votre '
            'premiere connexion.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          )
        else
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              children: [
                const TextSpan(text: 'Vous rejoignez l\'equipe de '),
                TextSpan(
                  text: _companyName ?? 'l\'entreprise',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _green,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        // Champ telephone
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          // Pas d'ouverture automatique : le bouton Google doit rester visible.
          onChanged: (_) => _clearError(),
          decoration: InputDecoration(
            labelText: 'Numero de telephone',
            hintText: '77 000 00 00',
            prefixIcon: const Icon(Icons.phone_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Un SMS de verification vous sera envoye.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Envoyer le code SMS',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),

        // Separateur
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ou',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
        ),

        // Bouton Google
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: _isGoogleLoading ? null : _signInWithGoogle,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isGoogleLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'G',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4285F4),
                        ),
                      ),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Continuer avec Google',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Etape 2 : OTP ────────────────────────────────────────
  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _greenLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.sms_rounded, color: _green, size: 36),
        ),
        const SizedBox(height: 20),
        Text(
          'Code SMS',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Entrez le code a 6 chiffres recu par SMS.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofocus: true,
          maxLength: 6,
          onChanged: (_) => _clearError(),
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: '------',
            hintStyle: TextStyle(color: Colors.grey.shade400, letterSpacing: 8),
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Acceder a mon espace',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() {
                  _step = 1;
                  _clearError();
                }),
          child: Text(
            'Renvoyer le code',
            style: TextStyle(color: _green, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
