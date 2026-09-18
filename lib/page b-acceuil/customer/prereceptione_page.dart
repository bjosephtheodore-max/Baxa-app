import 'dart:async';
import 'package:baxa/page%20b-acceuil/customer/customer_page.dart';
import 'package:baxa/services/locale_service.dart';
import 'package:baxa/services/location_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class PrereceptionePage extends StatefulWidget {
  const PrereceptionePage({super.key});

  @override
  State<PrereceptionePage> createState() => _PrereceptionePageState();
}

class _PrereceptionePageState extends State<PrereceptionePage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _textDark = Color(0xFF1A2E1F);

  final _formKey = GlobalKey<FormState>();
  final _prenomController = TextEditingController();
  final _nomController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    super.dispose();
  }

  Future<void> _commencer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      final user = cred.user!;
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await ref.set({
        'prenom': _prenomController.text.trim(),
        'nom': _nomController.text.trim(),
        'role': 'customer',
        'isAnonymous': true,
        'totalReservations': 0,
        'createdAt': FieldValue.serverTimestamp(),
        ...LocaleService.toFirestoreMap(),
      }, SetOptions(merge: true));
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

      // Pays : `LocaleService` a déjà posé un `country` par défaut
      // (locale du téléphone). On demande ici la permission GPS (le
      // dialogue s'affiche sur cet écran, à la suite de celui des
      // notifications) ; la position + le géocodage se font ensuite en
      // tâche de fond, sans retarder l'entrée dans l'app.
      try {
        final perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          unawaited(_refineCountryFromGps(ref));
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerPage()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Fire-and-forget : demande la permission GPS et, si accordée, écrase le
  // `country` (déduit de la locale) par le pays réel du client. Silencieux.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Contenu ─────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tagline en haut
                  const Text(
                    'Réservez votre place,\non vous prévient\nquand c\'est votre tour.',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                      height: 1.35,
                      letterSpacing: -0.5,
                    ),
                  ),

                  // Illustration Lottie au centre
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Lottie.asset(
                          'assets/animations/walking.json',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),

                  // Formulaire + bouton en bas
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildField(
                              controller: _prenomController,
                              hint: 'Prénom',
                              icon: Icons.person_outline_rounded,
                            ),
                            const SizedBox(height: 12),
                            _buildField(
                              controller: _nomController,
                              hint: 'Nom de famille',
                              icon: Icons.badge_outlined,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _commencer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            disabledBackgroundColor:
                                _green.withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Commencer',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(
        color: _textDark,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
        ),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
    );
  }
}
