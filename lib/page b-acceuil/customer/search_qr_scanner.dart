part of 'search_page.dart';

// ── Page scanner QR ───────────────────────────────────────────────────────
class _QrScannerPage extends StatefulWidget {
  final void Function(
    String companyId,
    String companyNom,
    String? type,
    String? ville,
  ) onScanned;

  const _QrScannerPage({required this.onScanned});

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _extractCompanyId(String rawValue) {
    try {
      final uri = Uri.parse(rawValue);
      final segments = uri.pathSegments;
      final idx = segments.indexOf('company');
      if (idx != -1 && idx + 1 < segments.length) return segments[idx + 1];
    } catch (_) {}
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    final companyId = _extractCompanyId(raw);

    if (companyId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('QR code non reconnu par Baxa'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    await _controller.stop();

    try {
      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Entreprise introuvable'),
              backgroundColor: Colors.red.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          setState(() => _isProcessing = false);
          await _controller.start();
        }
        return;
      }

      final data = doc.data()!;
      final nom = (data['nom'] as String?) ?? 'Entreprise';
      final type = data['type'] as String?;
      final ville = data['ville'] as String?;

      widget.onScanned(companyId, nom, type, ville);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isProcessing = false);
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _buildScanOverlay(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Scanner un QR code',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          await _controller.toggleTorch();
                          setState(() => _torchOn = !_torchOn);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _torchOn
                                ? _green.withValues(alpha: 0.8)
                                : Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _torchOn
                                ? Icons.flashlight_on_rounded
                                : Icons.flashlight_off_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                children: [
                  if (_isProcessing)
                    Column(
                      children: [
                        const CircularProgressIndicator(color: _green),
                        const SizedBox(height: 12),
                        Text(
                          'Chargement de l\'entreprise...',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _green.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.qr_code_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Pointez vers le QR code Baxa',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Le scan est automatique',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
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

  Widget _buildScanOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth * 0.65;
        final top = (constraints.maxHeight - size) / 2 - 40;
        final left = (constraints.maxWidth - size) / 2;

        return Stack(
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.55),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: left,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: top - 2,
              left: left - 2,
              child: _buildCorners(size + 4),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCorners(double size) {
    const double cornerLen = 24;
    const double cornerWidth = 3.5;
    const color = _green;
    const radius = Radius.circular(4);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: _corner(cornerLen, cornerWidth, color, radius, topLeft: true),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _corner(
              cornerLen,
              cornerWidth,
              color,
              radius,
              topRight: true,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: _corner(
              cornerLen,
              cornerWidth,
              color,
              radius,
              bottomLeft: true,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _corner(
              cornerLen,
              cornerWidth,
              color,
              radius,
              bottomRight: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner(
    double len,
    double w,
    Color color,
    Radius r, {
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return CustomPaint(
      size: Size(len, len),
      painter: _CornerPainter(
        color: color,
        strokeWidth: w,
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
      ),
    );
  }
}

// ── Peintre des coins du cadre ─────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool topLeft, topRight, bottomLeft, bottomRight;

  _CornerPainter({
    required this.color,
    required this.strokeWidth,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    if (topLeft) {
      canvas.drawLine(Offset(0, h), Offset(0, 0), paint);
      canvas.drawLine(Offset(0, 0), Offset(w, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(0, 0), Offset(w, 0), paint);
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(Offset(0, 0), Offset(0, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    }
    if (bottomRight) {
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
