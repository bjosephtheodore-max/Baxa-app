import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:baxa/page b-acceuil/company/staff_page.dart';

// ============================================================
// STAFF AUTH PAGE — Rejoindre une equipe via code d'invitation
// Etape 0 : code  |  Etape 1 : tel ou Google  |  Etape 2 : OTP
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

  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;
  String? _verificationId;
  String? _companyId;
  String? _companyName;
  DocumentReference? _inviteDocRef;

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

  // Marquer le code comme utilise (usage unique)
  Future<void> _markInviteUsed() async {
    if (_inviteDocRef == null) return;
    try {
      await _inviteDocRef!.update({'active': false});
    } catch (e) {
      debugPrint('Erreur markInviteUsed: $e');
    }
  }

  // ==============================================================
  // ETAPE 0 — Verifier le code d'invitation
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
      final results = await FirebaseFirestore.instance
          .collectionGroup('invitations')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (results.docs.isEmpty) {
        _setError('Code invalide. Demandez un nouveau code a votre responsable.');
        return;
      }

      final doc = results.docs.first;
      final data = doc.data();

      // Verifier que le code est encore actif (non utilise)
      if (data['active'] != true) {
        _setError('Ce code a deja ete utilise. Demandez un nouveau code a votre responsable.');
        return;
      }
      final companyId = data['companyId'] as String;

      final staffSnap = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('staff')
          .where('isActive', isEqualTo: true)
          .get();

      if (staffSnap.docs.length >= 3) {
        _setError('L\'equipe est complete (3 membres maximum). Contactez votre responsable.');
        return;
      }

      if (mounted) {
        setState(() {
          _companyId = companyId;
          _companyName = data['companyName'] as String? ?? 'l\'entreprise';
          _inviteDocRef = doc.reference;
          _step = 1;
        });
      }
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

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      await _createStaffProfile(userCred);
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
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        _setError('Code incorrect. Verifiez le SMS et reessayez.');
      } else if (e.code == 'session-expired') {
        _setError('Session expiree. Revenez a l\'etape precedente.');
      } else {
        _setError('Erreur de verification. Reessayez.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithPhoneCredential(PhoneAuthCredential credential) async {
    try {
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      await _createStaffProfile(userCred);
    } catch (e) {
      _setError('Erreur lors de la connexion. Reessayez.');
    }
  }

  // ==============================================================
  // CREER LE PROFIL STAFF + MARQUER LE CODE COMME UTILISE
  // ==============================================================
  Future<void> _createStaffProfile(UserCredential userCred) async {
    final uid = userCred.user?.uid;
    if (uid == null || _companyId == null) return;

    try {
      // Sauvegarder le role dans users/{uid} D'ABORD : c'est ce document que
      // les règles Firebase (isStaff) vérifient pour autoriser les écritures
      // suivantes sur companies/{companyId}. Le créer après aurait laissé
      // les écritures ci-dessous sans autorisation au moment où elles se jouent.
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'role': 'staff',
        'companyId': _companyId,
        'companyName': _companyName ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('companies')
          .doc(_companyId)
          .collection('staff')
          .doc(uid)
          .set({
            'uid': uid,
            'phone': userCred.user?.phoneNumber ?? '',
            'email': userCred.user?.email ?? '',
            'displayName': userCred.user?.displayName ?? '',
            'companyId': _companyId,
            'role': 'staff',
            'isActive': true,
            'joinedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Invalider le code (usage unique)
      await _markInviteUsed();

      // Notifier l'admin
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(_companyId)
          .collection('notificationsAdmin')
          .add({
            'type': 'new_staff_member',
            'title': 'Nouveau membre d\'equipe',
            'body': 'Un nouveau membre a rejoint votre equipe via le code d\'invitation.',
            'read': false,
            // Destinataire de la notif : sans ce champ, la liste ET la pastille
            // staff (qui filtrent sur staffId) restaient vides. NB : à terme,
            // un événement "adressé à l'admin" gagnerait un feed distinct.
            'staffId': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => StaffPage(
            companyId: _companyId!,
            companyName: _companyName ?? '',
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      _setError('Erreur lors de la creation du profil. Reessayez.');
    }
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
              setState(() {
                _step--;
                _clearError();
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: const Text(
          'Rejoindre une equipe',
          style: TextStyle(
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
                              border: Border.all(color: const Color(0xFFFFCDD2)),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final isActive = i == _step;
        final isDone = i < _step;
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
            if (i < 2) const SizedBox(width: 6),
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
          autofocus: true,
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
          child: const Icon(Icons.phone_android_rounded, color: _green, size: 36),
        ),
        const SizedBox(height: 20),
        Text(
          'Votre compte',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
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
          autofocus: true,
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
