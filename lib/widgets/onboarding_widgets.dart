import 'package:flutter/material.dart';

const Color _kGreen = Color(0xFF4B8B5E);

// ── Point vert clignotant pour icônes de tab bar ──────────────────────────────
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(const Color(0xFF2E7D48), const Color(0xFF6DD68A), _anim.value),
          boxShadow: [
            BoxShadow(
              color: _kGreen.withValues(alpha: 0.65 + _anim.value * 0.35),
              blurRadius: 8 + _anim.value * 12,
              spreadRadius: 2 + _anim.value * 5,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Auréole verte pulsante autour d'un widget (FAB, bouton, carte) ────────────
// [active] à false éteint l'auréole SANS retirer le widget de l'arbre : on peut
// donc l'envelopper en permanence autour d'un enfant qui porte un état (ex. un
// StreamBuilder) sans que l'activer/désactiver ne détruise et recrée cet enfant.
class PulsingGlow extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool active;

  const PulsingGlow({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(30)),
    this.active = true,
  });

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(PulsingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: widget.active
              ? [
                  BoxShadow(
                    color: _kGreen.withValues(alpha: 0.45 + _anim.value * 0.55),
                    blurRadius: 20 + _anim.value * 24,
                    spreadRadius: 5 + _anim.value * 12,
                  ),
                ]
              : const [],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ── Bulle flottante animée pointant vers un élément ─────────────────────────
class PulsingHint extends StatefulWidget {
  final String text;
  final IconData icon;
  const PulsingHint({super.key, required this.text, required this.icon});

  @override
  State<PulsingHint> createState() => _PulsingHintState();
}

class _PulsingHintState extends State<PulsingHint>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const Color _dark = Color(0xFF1A1C2E);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, -5 * _anim.value),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: _dark,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30 + _anim.value * 0.20),
                  blurRadius: 14 + _anim.value * 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(
                  widget.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dialogue de célébration aux étapes clés de l'onboarding ─────────────────
Future<void> showOnboardingCelebration(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 58)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1C2E),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Super !',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Spotlight ponctuel : présente une icône découverte pour la 1ère fois ────
// Écran assombri + mockup de l'icône (auréole pulsante) + explication +
// bouton de fermeture. Contrairement à showOnboardingCelebration, ce n'est
// pas rattaché à la séquence numérotée de OnboardingService — c'est un
// indice indépendant, déclenché par un événement qui peut survenir bien
// après la configuration initiale (ex: 1ère modification en direct).
Future<void> showIconDiscoverySpotlight(
  BuildContext context, {
  required IconData mockIcon,
  required IconData badgeIcon,
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingGlow(
            borderRadius: BorderRadius.circular(30),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange.shade300, width: 1.5),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(mockIcon, size: 26, color: _kGreen),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(badgeIcon, size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1C2E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Compris !',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
