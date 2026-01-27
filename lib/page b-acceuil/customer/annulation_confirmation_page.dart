import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/gestionnaire_annulations_page.dart';

/// Page de confirmation d'annulation de réservation
class CancellationConfirmationPage extends StatefulWidget {
  final ReservationData reservation;

  const CancellationConfirmationPage({super.key, required this.reservation});

  @override
  State<CancellationConfirmationPage> createState() =>
      _CancellationConfirmationPageState();
}

class _CancellationConfirmationPageState
    extends State<CancellationConfirmationPage>
    with SingleTickerProviderStateMixin {
  final Color _primaryGreen = const Color.fromARGB(255, 75, 139, 94);
  final Color _lightGreen = const Color.fromARGB(255, 178, 211, 194);
  final DateFormat _dateFmt = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  bool _isProcessing = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: _primaryGreen),
        title: Text(
          'Confirmer l\'annulation',
          style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icône principale avec animation
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.event_busy_rounded,
                        size: 80,
                        color: Colors.orange.shade600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Titre principal
                  const Text(
                    'Tu ne pourras pas venir ?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Pas de souci ! Ton annulation libérera ta place pour quelqu\'un d\'autre.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Carte des détails de la réservation
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _lightGreen.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.event_available,
                                color: _primaryGreen,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Réservation à annuler',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.reservation.queueName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        _buildDetailRow(
                          icon: Icons.calendar_today,
                          label: 'Date',
                          value: _dateFmt.format(widget.reservation.slotStart),
                        ),

                        const SizedBox(height: 12),

                        _buildDetailRow(
                          icon: Icons.access_time,
                          label: 'Horaire',
                          value:
                              '${_timeFmt.format(widget.reservation.slotStart)} - ${_timeFmt.format(widget.reservation.slotEnd)}',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Message d'impact positif
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _lightGreen.withOpacity(0.3),
                          _lightGreen.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _primaryGreen.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.eco_rounded, color: _primaryGreen, size: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'En prévenant, tu permets à quelqu\'un d\'autre de prendre ta place',
                            style: TextStyle(
                              color: _primaryGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Bouton "Oui, je ne viendrai pas"
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _confirmCancellation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Oui, je ne viendrai pas',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Bouton "Je garde ma réservation"
                  OutlinedButton(
                    onPressed: _isProcessing ? null : _keepReservation,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryGreen,
                      side: BorderSide(color: _primaryGreen, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Je garde ma réservation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmCancellation() async {
    setState(() => _isProcessing = true);

    try {
      final handler = CancellationHandler();
      final result = await handler.cancelReservation(
        companyId: widget.reservation.companyId,
        queueId: widget.reservation.queueId,
        slotId: widget.reservation.slotId,
        reservationPath: widget.reservation.reservationPath,
      );

      if (!mounted) return;

      if (result.success) {
        // Animation de succès
        await _showSuccessAnimation();

        // Fermer la page après un délai
        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) {
          Navigator.of(context).pop(true); // Retour avec succès
        }
      } else {
        _showErrorDialog(result.message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Une erreur est survenue: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _showSuccessAnimation() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 60,
                  color: _primaryGreen,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Annulation confirmée',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Merci d\'avoir prévenu ! 🙏',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Erreur'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _keepReservation() {
    Navigator.of(context).pop(false); // Retour sans annulation
  }
}
