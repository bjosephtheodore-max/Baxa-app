import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

// ════════════════════════════════════════════════════════════════════
// Section « Mon QR Code » — partagée entre la page Paramètres de
// l'entreprise et celle du staff. Affichage et comportement identiques.
//
// Le QR pointe vers https://baxa.app/company/{companyId} : le client le
// scanne et arrive sur la file (ou directement sur les créneaux si la
// structure n'a qu'une seule file).
// ════════════════════════════════════════════════════════════════════
class QrCodeSection extends StatefulWidget {
  final String companyId;
  final String companyName;

  const QrCodeSection({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<QrCodeSection> createState() => _QrCodeSectionState();
}

class _QrCodeSectionState extends State<QrCodeSection> {
  static const Color _green = Color(0xFF4B8B5E);

  bool _isGeneratingPoster = false;
  final GlobalKey _posterKey = GlobalKey();

  String get _qrUrl => 'https://baxa.app/company/${widget.companyId}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: _green,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Affichez ce QR code dans votre établissement pour que vos clients réservent instantanément.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          RepaintBoundary(key: _posterKey, child: _buildPoster()),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, color: _green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _qrUrl,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGeneratingPoster ? null : _sharePoster,
              icon: _isGeneratingPoster
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share_rounded, color: Colors.white),
              label: Text(
                _isGeneratingPoster ? 'Préparation...' : 'Partager l\'affiche',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Affiche prête à imprimer ──────────────────────────────────────
  Widget _buildPoster() {
    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4B8B5E), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF4B8B5E),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.companyName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E2D23),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Ne perdez plus votre temps dans la file.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4B8B5E),
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFB2D3C2), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4B8B5E).withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: _qrUrl,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF1E2D23),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF1E2D23),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepBadge(number: '1', label: 'Scannez'),
              _StepArrow(),
              _StepBadge(number: '2', label: 'Réservez'),
              _StepArrow(),
              _StepBadge(number: '3', label: 'Revenez'),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4B8B5E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Baxa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Réservez votre place en 30 secondes',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sharePoster() async {
    setState(() => _isGeneratingPoster = true);
    try {
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Widget non trouvé');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Conversion échouée');

      final imageBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final safeName = widget.companyName.replaceAll(' ', '_').toLowerCase();
      final file = File('${tempDir.path}/affiche_$safeName.png');
      await file.writeAsBytes(imageBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '📍 Réservez votre place chez ${widget.companyName} sans attendre ! Scannez le QR code.',
        subject: 'Affiche QR Code - ${widget.companyName}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du partage: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPoster = false);
    }
  }
}

class _StepBadge extends StatelessWidget {
  final String number;
  final String label;
  const _StepBadge({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF4B8B5E),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E2D23),
          ),
        ),
      ],
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14, left: 6, right: 6),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 14,
        color: Color(0xFFB2D3C2),
      ),
    );
  }
}
