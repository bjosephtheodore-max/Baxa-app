part of 'settings_page.dart';

// Toutes les ÉCRITURES (plage, créneaux, annulations, places du jour) se
// font côté serveur : Cloud Function `companySchedule` (voir
// lib/services/company_schedule_service.dart). Ce fichier ne garde que les
// petits outils d'affichage et les dialogues de choix.
extension _QueueTimeSlotsLogic on _QueueTimeSlotsPageState {
  // ── Petits helpers ──────────────────────────────────────────────
  TimeOfDay _parseTimeOfDay(String time) {
    if (time == '24:00') return const TimeOfDay(hour: 0, minute: 0);
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // ── Texte du choix "Programmer / Appliquer maintenant" ───────────
  String _buildScheduleOrForceMessage({
    required bool hasBaxaClients,
    required bool hasManualClients,
    required String formattedDate,
  }) {
    final String consequence;
    if (hasManualClients && !hasBaxaClients) {
      consequence =
          'Ces réservations seront annulées, et ces clients — '
          'n\'ayant pas de compte Baxa — ne seront pas prévenus : pensez à '
          'les contacter.';
    } else if (hasManualClients && hasBaxaClients) {
      consequence =
          'Ces réservations seront annulées, et certains de ces '
          'clients — n\'ayant pas de compte Baxa — ne seront pas prévenus : '
          'pensez à les contacter.';
    } else {
      consequence = 'Ces réservations seront annulées et vos clients notifiés.';
    }
    return '$consequence Programmez-la plutôt pour éviter tout désagrément : '
        'elle prendra effet le $formattedDate, sans impact sur les '
        'réservations en cours.';
  }

  // ── Texte du choix "Programmer / Supprimer maintenant" ───────────
  // Variante suppression de plage : programmer n'impacte personne (les
  // réservations en cours sont honorées jusqu'au bout), supprimer maintenant
  // annule et notifie.
  String _buildScheduleOrDeleteMessage({
    required bool hasBaxaClients,
    required bool hasManualClients,
    required String formattedDate,
  }) {
    final String nowConsequence;
    if (hasManualClients && !hasBaxaClients) {
      nowConsequence =
          'Supprimer maintenant annule ces réservations ; ces clients n\'ont '
          'pas de compte Baxa et ne seront pas prévenus — pensez à les contacter.';
    } else if (hasManualClients && hasBaxaClients) {
      nowConsequence =
          'Supprimer maintenant annule ces réservations ; certains de ces '
          'clients n\'ont pas de compte Baxa et ne seront pas prévenus — pensez '
          'à les contacter.';
    } else {
      nowConsequence =
          'Supprimer maintenant annule ces réservations et notifie les clients.';
    }
    return 'Programmer la suppression n\'impacte personne : vos clients gardent '
        'leur créneau, la plage sera supprimée le $formattedDate une fois toutes '
        'les réservations en cours honorées. $nowConsequence';
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e is CompanyActionException ? e.message : 'Erreur : $e'),
      ),
    );
  }

  // ── Suppression d'une plage horaire ─────────────────────────────
  // - Aucune réservation à venir → confirmation simple, suppression immédiate.
  // - Des réservations à venir → choix : programmer la suppression (aucun
  //   impact) ou supprimer maintenant (annulation + notification des
  //   clients). L'aperçu (réservations, date) vient du serveur.
  Future<void> _deleteSlot(String slotId, Map<String, dynamic> slotData) async {
    TimeSlotImpact impact;
    try {
      impact = await CompanyScheduleService.previewDeleteTimeSlot(
        companyId: widget.companyId,
        queueId: widget.queueId,
        timeSlotId: slotId,
      );
    } catch (e) {
      _showError(e);
      return;
    }
    if (!mounted) return;

    if (impact.reservations == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Supprimer cette plage ?'),
          content: const Text(
            'Les créneaux futurs associés seront supprimés définitivement.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Supprimer',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (confirm == true) await _performTimeSlotDeletion(slotId);
      return;
    }

    final formattedDate = DateFormat(
      'EEE d MMM',
      'fr_FR',
    ).format(impact.effectiveDate ?? DateTime.now());
    final choice = await _showScheduleOrForceSheet(
      reservationCount: impact.reservations,
      hasBaxaClients: impact.hasBaxaClients,
      hasManualClients: impact.hasManualClients,
      formattedDate: formattedDate,
      isDeletion: true,
    );
    if (choice == _ConflictChoice.cancel) return;
    await _performTimeSlotDeletion(
      slotId,
      schedule: choice == _ConflictChoice.scheduleLater,
    );
  }

  // Suppression maintenant (réservations à venir annulées et notifiées par
  // la Cloud Function) ou programmée (plus aucune nouvelle réservation ; la
  // maintenance de nuit supprimera la plage après la dernière).
  Future<void> _performTimeSlotDeletion(
    String slotId, {
    bool schedule = false,
  }) async {
    try {
      final scheduledFor = await CompanyScheduleService.deleteTimeSlot(
        companyId: widget.companyId,
        queueId: widget.queueId,
        timeSlotId: slotId,
        schedule: schedule,
      );
      if (!mounted) return;
      if (scheduledFor != null) {
        final f = DateFormat('EEE d MMM', 'fr_FR').format(scheduledFor);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Suppression programmée pour le $f ✅ — vos clients gardent leur '
              'créneau, personne n\'est prévenu.',
            ),
            backgroundColor: _kGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plage et créneaux associés supprimés')),
        );
      }
    } catch (e) {
      _showError(e);
    }
  }

  // ── Annule une suppression programmée pas encore appliquée ──────
  // Le serveur efface le marqueur et régénère les créneaux des 7 jours à
  // venir sous la config actuelle de la plage.
  Future<void> _restorePendingDeletion(
    String timeSlotId,
    Map<String, dynamic> slotData,
  ) async {
    try {
      await CompanyScheduleService.restoreTimeSlot(
        companyId: widget.companyId,
        queueId: widget.queueId,
        timeSlotId: timeSlotId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Suppression annulée — la plage est de nouveau active.',
          ),
          backgroundColor: _kGreen,
        ),
      );
    } catch (e) {
      _showError(e);
    }
  }
}
