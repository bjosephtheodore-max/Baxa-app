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
                      GoogleGLogo(size: 20),
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

/// Le « G » officiel de Google, en 4 couleurs (règles d'affichage de
/// Google pour un bouton « Continuer avec Google »). Dessiné à partir du
/// tracé officiel (repère 48 × 48) : pas d'image, net à toutes les tailles.
class GoogleGLogo extends StatelessWidget {
  final double size;
  const GoogleGLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  // Tracé officiel du « G » (viewBox 0 0 48 48), une couleur par partie.
  static const List<(int, String)> _parts = [
    (
      0xFFEA4335, // rouge
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
          '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 '
          '9.5z',
    ),
    (
      0xFF4285F4, // bleu
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
          '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
    ),
    (
      0xFFFBBC05, // jaune
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
          'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
    ),
    (
      0xFF34A853, // vert
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
          '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 '
          '24 48z',
    ),
  ];

  static final List<(Color, Path)> _paths = [
    for (final (color, d) in _parts) (Color(color), svgPathToPath(d)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (final (color, path) in _paths) {
      canvas.drawPath(path, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Convertit un tracé SVG simple (M L H V C S Z, absolus et relatifs) en
/// [Path]. Suffisant pour le logo ci-dessus ; exposé pour les tests.
Path svgPathToPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var cmd = '';
  double x = 0, y = 0, startX = 0, startY = 0;
  double? lastCtrlX, lastCtrlY;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = (rel ? x : 0) + next();
        y = (rel ? y : 0) + next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        cmd = rel ? 'l' : 'L'; // coordonnées suivantes = lignes
        lastCtrlX = null;
      case 'L':
        x = (rel ? x : 0) + next();
        y = (rel ? y : 0) + next();
        path.lineTo(x, y);
        lastCtrlX = null;
      case 'H':
        x = (rel ? x : 0) + next();
        path.lineTo(x, y);
        lastCtrlX = null;
      case 'V':
        y = (rel ? y : 0) + next();
        path.lineTo(x, y);
        lastCtrlX = null;
      case 'C':
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final x1 = ox + next(), y1 = oy + next();
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
      case 'S':
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final x1 = lastCtrlX == null ? x : 2 * x - lastCtrlX;
        final y1 = lastCtrlY == null || lastCtrlX == null ? y : 2 * y - lastCtrlY;
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        lastCtrlX = null;
      default:
        i++; // jeton inattendu : ignoré
    }
  }
  return path;
}
