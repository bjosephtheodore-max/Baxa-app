import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:baxa/services/notification_permission_service.dart';

const Color _green = Color(0xFF4B8B5E);
const Duration _repeatEvery = Duration(days: 3);

// ============================================================
// CLIENT — juste après une réservation réussie
// ============================================================

const String _customerPromptKey = 'notif_prompt_customer_last';

/// Si les notifications sont coupées, propose de les activer (au plus une
/// fois tous les 3 jours). Renvoie true si la fenêtre a été affichée — les
/// autres invitations d'après réservation attendent alors la suivante,
/// pour ne pas empiler les fenêtres.
Future<bool> maybePromptCustomerNotifications(BuildContext context) async {
  if (await NotificationPermissionService.isEnabled()) return false;
  if (!await NotificationPermissionService.isDue(
    _customerPromptKey,
    _repeatEvery,
  )) {
    return false;
  }
  if (!context.mounted) return false;
  await NotificationPermissionService.markShown(_customerPromptKey);
  if (!context.mounted) return false;

  final wantsEnable = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(ctx).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: _green,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Soyez prévenu quand c\'est votre tour',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Les notifications de Baxa sont désactivées sur ce téléphone : '
            'vous ne recevrez ni le rappel avant votre passage, ni les '
            'changements de la structure.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Activer les notifications',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Plus tard',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    ),
  );
  if (wantsEnable == true) await NotificationPermissionService.enable();
  return true;
}

// ============================================================
// STRUCTURE / STAFF — bandeau sur l'accueil
// ============================================================

const String _proBannerKey = 'notif_banner_pro_dismissed';

/// Bandeau orange tant que les notifications sont coupées : sans elles,
/// la structure ou le membre d'équipe ne sait pas qu'une réservation
/// arrive. Se revérifie au retour des réglages ; masquable 3 jours.
class NotificationsOffBanner extends StatefulWidget {
  const NotificationsOffBanner({super.key});

  @override
  State<NotificationsOffBanner> createState() =>
      _NotificationsOffBannerState();
}

class _NotificationsOffBannerState extends State<NotificationsOffBanner>
    with WidgetsBindingObserver {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour des réglages du téléphone : le bandeau suit le nouvel état.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await NotificationPermissionService.isEnabled();
    final due = enabled
        ? false
        : await NotificationPermissionService.isDue(
            _proBannerKey,
            _repeatEvery,
          );
    if (mounted && _visible != (!enabled && due)) {
      setState(() => _visible = !enabled && due);
    }
  }

  Future<void> _enable() async {
    final ok = await NotificationPermissionService.enable();
    if (ok && mounted) setState(() => _visible = false);
  }

  Future<void> _dismiss() async {
    await NotificationPermissionService.markShown(_proBannerKey);
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final color = Colors.orange.shade800;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Notifications désactivées : vous ne serez pas averti des '
              'nouvelles réservations.',
              style: TextStyle(fontSize: 12.5, color: color, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: _enable,
            style: TextButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text(
              'Activer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: _dismiss,
            tooltip: 'Masquer',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: color),
          ),
        ],
      ),
    );
  }
}
