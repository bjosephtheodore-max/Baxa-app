import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

// ════════════════════════════════════════════════════════════════════
// Ticket vivant présenté au personnel au moment du créneau ("c'est ton
// tour" / "créneau terminé"). Contrairement à la notification push (texte
// figé, capturable une fois pour toutes), cet écran :
//   - affiche un compteur qui avance en direct, preuve qu'il est consulté
//     maintenant et non montré via une ancienne capture d'écran ;
//   - bloque la capture/l'enregistrement sur Android (FLAG_SECURE) ;
//   - se floute sur iOS pendant un enregistrement d'écran (détection poussée
//     en direct par le plugin, pas de sondage), et lors du passage en
//     arrière-plan (aperçu multitâche).
// Voir la discussion produit sur la fraude aux notifications de créneau.
// ════════════════════════════════════════════════════════════════════
class ReservationTicketPage extends StatefulWidget {
  final String companyName;
  final String queueName;
  final DateTime slotStart;
  final DateTime slotEnd;

  const ReservationTicketPage({
    super.key,
    required this.companyName,
    required this.queueName,
    required this.slotStart,
    required this.slotEnd,
  });

  @override
  State<ReservationTicketPage> createState() => _ReservationTicketPageState();
}

class _ReservationTicketPageState extends State<ReservationTicketPage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _dark = Color(0xFF1A1C2E);

  // Le ticket ne protège plus rien une fois le créneau terminé (voir
  // discussion produit) : il se referme tout seul — un bref instant en
  // orange pour que ce soit lisible, puis une réduction/fondu, comme si
  // l'utilisateur avait appuyé sur retour.
  static const _autoCloseReadDelay = Duration(milliseconds: 1200);
  static const _autoCloseAnimDuration = Duration(milliseconds: 380);

  Timer? _tick;
  DateTime _now = DateTime.now();
  bool _isRecording = false;
  bool _closing = false;
  bool _autoCloseStarted = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _maybeStartAutoClose();
    });
    _enableProtection();
  }

  void _maybeStartAutoClose() {
    if (_autoCloseStarted || !_isOver) return;
    _autoCloseStarted =
        true; // posé tout de suite : jamais reprogrammé deux fois
    Future.delayed(_autoCloseReadDelay, () {
      if (!mounted) return;
      setState(() => _closing = true);
      Future.delayed(_autoCloseAnimDuration, () {
        if (mounted) Navigator.pop(context);
      });
    });
  }

  Future<void> _enableProtection() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await ScreenProtector.protectDataLeakageOn();
      } else if (Platform.isIOS) {
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.protectDataLeakageWithBlur();
        // Écoute en direct (poussée par le natif), pas de sondage périodique :
        // le flou s'applique dès que l'enregistrement démarre, sans latence.
        ScreenProtector.addListener(null, (recording) {
          if (mounted) setState(() => _isRecording = recording);
        });
      }
    } catch (_) {
      // Protection best-effort : un échec (device non supporté, plugin
      // indisponible) ne doit pas empêcher l'affichage du ticket.
    }
  }

  Future<void> _disableProtection() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await ScreenProtector.protectDataLeakageOff();
      } else if (Platform.isIOS) {
        ScreenProtector.removeListener();
        await ScreenProtector.preventScreenshotOff();
        await ScreenProtector.protectDataLeakageWithBlurOff();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    _disableProtection();
    super.dispose();
  }

  bool get _isOver => _now.isAfter(widget.slotEnd);

  String get _elapsedLabel {
    final ref = _isOver ? widget.slotEnd : widget.slotStart;
    final diff = _now.difference(ref).abs();
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatDate(DateTime d) {
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const mois = [
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]}';
  }

  String _formatRange(DateTime start, DateTime end) {
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
    return '${hm(start)} - ${hm(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isOver ? Colors.orange.shade600 : _green;
    final badgeBg = _isOver ? Colors.orange.shade50 : _greenLight;
    final showQueueName =
        widget.queueName.isNotEmpty && widget.queueName != widget.companyName;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Ton créneau',
          style: GoogleFonts.poppins(
            color: _dark,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              // Le compteur vit maintenant DANS le bloc (coin bas-droit),
              // pas flottant au bas de l'écran : même surface, même geste de
              // lecture que le reste (nom → file → date → horaire → tampon
              // dans le coin) — plus besoin de faire l'aller-retour de l'œil.
              child: AnimatedScale(
                scale: _closing ? 0.85 : 1,
                duration: _autoCloseAnimDuration,
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _closing ? 0 : 1,
                  duration: _autoCloseAnimDuration,
                  curve: Curves.easeOut,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _isOver ? 'Créneau terminé' : 'En cours',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              widget.companyName,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: _dark,
                                height: 1.2,
                              ),
                            ),
                            if (showQueueName) ...[
                              const SizedBox(height: 6),
                              Text(
                                widget.queueName,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Divider(color: Colors.grey.shade100),
                            const SizedBox(height: 20),
                            Text(
                              _formatDate(widget.slotStart),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatRange(widget.slotStart, widget.slotEnd),
                              style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: _dark,
                              ),
                            ),
                            // Réserve la place occupée par le tampon en coin
                            // (évite qu'il ne chevauche l'horaire au-dessus sur
                            // les écrans étroits).
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _LiveCounter(
                          label: _elapsedLabel,
                          accent: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!kIsWeb && Platform.isIOS && _isRecording)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
        ],
      ),
    );
  }
}

// Petit indicateur discret en coin du bloc (tampon) : son seul rôle est de
// prouver que l'écran est consulté en direct (les secondes tournent), pas de
// porter de l'information — il ne doit pas concurrencer le nom de l'établissement.
class _LiveCounter extends StatelessWidget {
  final String label;
  final Color accent;

  const _LiveCounter({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
