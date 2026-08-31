import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baxa/page%20d-d%C3%A9but/choose_page.dart';
import 'package:baxa/services/company_lifecycle_service.dart';

// ============================================================
// GATE affiché à la connexion quand l'entreprise a demandé à quitter Baxa.
//  • status 'scheduled' : délai de grâce en cours → « Revenir sur Baxa ».
//  • status 'gone'      : compte déjà supprimé → simple déconnexion.
// ============================================================
class CompanyDeletionGatePage extends StatefulWidget {
  final String companyId;
  final String status; // 'scheduled' | 'gone'
  final Map<String, dynamic>? data;
  final VoidCallback onRevived;

  const CompanyDeletionGatePage({
    super.key,
    required this.companyId,
    required this.status,
    required this.data,
    required this.onRevived,
  });

  @override
  State<CompanyDeletionGatePage> createState() =>
      _CompanyDeletionGatePageState();
}

class _CompanyDeletionGatePageState extends State<CompanyDeletionGatePage> {
  static const Color _green = Color.fromARGB(255, 75, 139, 94);
  bool _working = false;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _signOutToChoose() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ChoosePage()),
      (route) => false,
    );
  }

  Future<void> _revive() async {
    setState(() => _working = true);
    try {
      await cancelCompanyDeletion(
        firestore: FirebaseFirestore.instance,
        companyId: widget.companyId,
      );
      if (!mounted) return;
      widget.onRevived();
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gone = widget.status == 'gone';
    final execAfter = (widget.data?['executeAfter'] as Timestamp?)?.toDate();
    final daysLeft = execAfter?.difference(DateTime.now()).inDays;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: gone ? Colors.grey.shade100 : Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    gone ? Icons.exit_to_app_rounded : Icons.timer_outlined,
                    size: 40,
                    color: gone ? Colors.grey.shade600 : Colors.red.shade500,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                gone
                    ? 'Cet établissement a été supprimé'
                    : 'Votre établissement est en cours de suppression',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1C2E),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                gone
                    ? 'Toutes ses files et ses données ont été effacées de Baxa.'
                    : execAfter != null
                    ? 'Suppression définitive le ${_fmt(execAfter)}'
                          '${daysLeft != null && daysLeft >= 0 ? ' — dans $daysLeft jour${daysLeft > 1 ? 's' : ''}' : ''}.\n'
                          'Vos réservations sont fermées. Revenez avant cette '
                          'date pour tout réactiver.'
                    : 'Vos réservations sont fermées. Revenez avant la fin du '
                          'délai pour tout réactiver.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              if (!gone)
                ElevatedButton(
                  onPressed: _working ? null : _revive,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _working
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Revenir sur Baxa',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _working ? null : _signOutToChoose,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
                child: Text(gone ? 'Se déconnecter' : 'Me déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
