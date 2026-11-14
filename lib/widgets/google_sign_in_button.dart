import 'package:flutter/material.dart';

// ============================================================
// « Continuer avec Google » — mis en avant sur les écrans de connexion
// staff (staff_auth_page) et client (signine_page).
// ============================================================
// Choix du 14/11/2026 : Google passe en premier. Pas de SMS → pas de
// blocage selon l'opérateur (numéros Yas refusés par Firebase), pas de
// spam, gratuit. Le numéro de téléphone reste proposé en dessous.

/// Bouton blanc (couleurs Google) suivi d'une courte phrase qui dit
/// pourquoi le choisir.
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: OutlinedButton(
            onPressed: loading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              backgroundColor: Colors.white,
              side: BorderSide(color: Colors.grey.shade300, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: loading
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
                          fontSize: 21,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Le plus rapide : un seul appui, aucun code à recevoir.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

/// Séparateur « ou … » entre Google et les autres façons de se connecter.
class SignInOrDivider extends StatelessWidget {
  final String label;
  const SignInOrDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}
