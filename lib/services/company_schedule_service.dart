import 'package:baxa/services/company_booking_service.dart';
import 'package:baxa/services/company_functions.dart';

// ════════════════════════════════════════════════════════════════════
// Plages horaires et créneaux, arbitrés par le serveur (Cloud Function
// `companySchedule`, functions/company_schedule.js) : création,
// modification (appliquer / programmer), suppression et restitution d'une
// plage, durée et capacité du jour, réouverture, retour sur Baxa.
//
// Le serveur fait TOUT d'un coup (plage, créneaux, annulations, places du
// jour) dans le fuseau de la structure : plus de plage à moitié
// enregistrée si le réseau coupe. Erreurs : CompanyActionException
// (company_functions.dart), message prêt à afficher.
// ════════════════════════════════════════════════════════════════════

/// Conséquences d'une modification ou d'une suppression de plage.
class TimeSlotImpact {
  /// Créneaux réservés touchés (modification) — 0 si aucun conflit.
  final int conflictSlots;

  /// Réservations touchées.
  final int reservations;
  final bool hasBaxaClients;
  final bool hasManualClients;

  /// Date à laquelle la modification / suppression peut être programmée
  /// sans toucher personne.
  final DateTime? effectiveDate;

  const TimeSlotImpact({
    this.conflictSlots = 0,
    this.reservations = 0,
    this.hasBaxaClients = false,
    this.hasManualClients = false,
    this.effectiveDate,
  });

  factory TimeSlotImpact.fromMap(Map<String, dynamic> m) {
    final ms = (m['effectiveDate'] as num?)?.toInt();
    return TimeSlotImpact(
      conflictSlots: (m['conflictSlots'] as num?)?.toInt() ?? 0,
      reservations: (m['reservations'] as num?)?.toInt() ?? 0,
      hasBaxaClients: m['hasBaxaClients'] == true,
      hasManualClients: m['hasManualClients'] == true,
      effectiveDate: ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : null,
    );
  }
}

/// Résultat de l'enregistrement d'une plage.
class TimeSlotSaveResult {
  final String timeSlotId;
  final bool unchanged;
  final int created;
  final int updated;
  final int cancelled;

  /// Non nul si la modification a été programmée (date d'effet).
  final DateTime? scheduledFor;

  const TimeSlotSaveResult({
    required this.timeSlotId,
    this.unchanged = false,
    this.created = 0,
    this.updated = 0,
    this.cancelled = 0,
    this.scheduledFor,
  });
}

/// Comment traiter les réservations en conflit avec une modification.
enum ConflictMode { none, now, schedule }

class CompanyScheduleService {
  CompanyScheduleService._();

  static const String _function = 'companySchedule';

  /// Réveille la fonction en avance (page des plages ouverte).
  static Future<void> warmup() => warmupCompanyFunction(_function);

  static Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> data,
  ) => callCompanyFunction(_function, {...data, 'action': action});

  static Map<String, dynamic> _form({
    required String startTime,
    required String endTime,
    required int duration,
    required int capacity,
    required List<int> workingDays,
    int? reservationDeadlineMinutes,
  }) => {
    'startTime': startTime,
    'endTime': endTime,
    'duration': duration,
    'capacity': capacity,
    'workingDays': workingDays,
    if (reservationDeadlineMinutes != null)
      'reservationDeadlineMinutes': reservationDeadlineMinutes,
  };

  /// Conflits qu'entraînerait la modification de la plage [timeSlotId].
  static Future<TimeSlotImpact> previewTimeSlot({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required String startTime,
    required String endTime,
    required int duration,
    required int capacity,
    required List<int> workingDays,
    int? reservationDeadlineMinutes,
  }) async {
    final res = await _call('previewTimeSlot', {
      'companyId': companyId,
      'queueId': queueId,
      'timeSlotId': timeSlotId,
      ..._form(
        startTime: startTime,
        endTime: endTime,
        duration: duration,
        capacity: capacity,
        workingDays: workingDays,
        reservationDeadlineMinutes: reservationDeadlineMinutes,
      ),
    });
    return TimeSlotImpact.fromMap(res);
  }

  /// Crée ([timeSlotId] nul) ou modifie une plage, créneaux compris.
  static Future<TimeSlotSaveResult> saveTimeSlot({
    required String companyId,
    required String queueId,
    String? timeSlotId,
    required String startTime,
    required String endTime,
    required int duration,
    required int capacity,
    required List<int> workingDays,
    int? reservationDeadlineMinutes,
    ConflictMode conflictMode = ConflictMode.none,
  }) async {
    final res = await _call('saveTimeSlot', {
      'companyId': companyId,
      'queueId': queueId,
      if (timeSlotId != null) 'timeSlotId': timeSlotId,
      'conflictMode': conflictMode.name,
      ..._form(
        startTime: startTime,
        endTime: endTime,
        duration: duration,
        capacity: capacity,
        workingDays: workingDays,
        reservationDeadlineMinutes: reservationDeadlineMinutes,
      ),
    });
    final scheduled = (res['scheduled'] as num?)?.toInt();
    return TimeSlotSaveResult(
      timeSlotId: res['timeSlotId'] as String? ?? timeSlotId ?? '',
      unchanged: res['unchanged'] == true,
      created: (res['created'] as num?)?.toInt() ?? 0,
      updated: (res['updated'] as num?)?.toInt() ?? 0,
      cancelled: (res['cancelled'] as num?)?.toInt() ?? 0,
      scheduledFor: scheduled != null
          ? DateTime.fromMillisecondsSinceEpoch(scheduled)
          : null,
    );
  }

  /// Réservations à venir touchées par la suppression de la plage.
  static Future<TimeSlotImpact> previewDeleteTimeSlot({
    required String companyId,
    required String queueId,
    required String timeSlotId,
  }) async {
    final res = await _call('previewDeleteTimeSlot', {
      'companyId': companyId,
      'queueId': queueId,
      'timeSlotId': timeSlotId,
    });
    return TimeSlotImpact.fromMap(res);
  }

  /// Supprime la plage maintenant ([schedule] faux : réservations à venir
  /// annulées et notifiées) ou programme sa suppression. Renvoie la date
  /// programmée, ou null.
  static Future<DateTime?> deleteTimeSlot({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required bool schedule,
  }) async {
    final res = await _call('deleteTimeSlot', {
      'companyId': companyId,
      'queueId': queueId,
      'timeSlotId': timeSlotId,
      'mode': schedule ? 'schedule' : 'now',
    });
    final ms = (res['scheduled'] as num?)?.toInt();
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Annule une suppression programmée (plage de nouveau active).
  static Future<void> restoreTimeSlot({
    required String companyId,
    required String queueId,
    required String timeSlotId,
  }) => _call('restoreTimeSlot', {
    'companyId': companyId,
    'queueId': queueId,
    'timeSlotId': timeSlotId,
  });

  /// Nouvelle durée des créneaux du jour [day] pour la plage. [anchor] :
  /// instant de la modification d'origine (annulation sous 5 min).
  /// Renvoie le nombre de créneaux créés.
  static Future<int> changeDayDuration({
    required String companyId,
    required String queueId,
    required String timeSlotId,
    required DateTime day,
    required int duration,
    required int capacity,
    DateTime? anchor,
  }) async {
    final res = await _call('changeDayDuration', {
      'companyId': companyId,
      'queueId': queueId,
      'timeSlotId': timeSlotId,
      'day': CompanyBookingService.dayKey(day),
      'duration': duration,
      'capacity': capacity,
      if (anchor != null) 'anchor': anchor.millisecondsSinceEpoch,
    });
    return (res['created'] as num?)?.toInt() ?? 0;
  }

  /// Nouvelle capacité des créneaux du jour [day] (jamais sous les
  /// réservations). Renvoie le nombre de créneaux modifiés.
  static Future<int> changeDayCapacity({
    required String companyId,
    required String queueId,
    required DateTime day,
    required int capacity,
    String? timeSlotId,
  }) async {
    final res = await _call('changeDayCapacity', {
      'companyId': companyId,
      'queueId': queueId,
      'day': CompanyBookingService.dayKey(day),
      'capacity': capacity,
      if (timeSlotId != null) 'timeSlotId': timeSlotId,
    });
    return (res['affected'] as num?)?.toInt() ?? 0;
  }

  /// Rouvre des files ; recrée leurs créneaux si la fermeture était en
  /// cours. Renvoie vrai si au moins une fermeture était en cours.
  static Future<bool> reopen({
    required String companyId,
    required List<String> queueIds,
  }) async {
    final res = await _call('reopen', {
      'companyId': companyId,
      'queueIds': queueIds,
    });
    return res['wasActive'] == true;
  }

  /// Annule un départ de Baxa : demande supprimée, files rouvertes,
  /// créneaux recréés (les réservations annulées ne reviennent pas).
  static Future<void> returnToBaxa({required String companyId}) =>
      _call('returnToBaxa', {'companyId': companyId});

  // ── Files d'attente ──────────────────────────────────────────────

  /// Crée une file (au plus 5, vérifié par le serveur). Renvoie son id.
  static Future<String> createQueue({
    required String companyId,
    required String name,
    required int maxAdvanceDays,
    required int reservationDeadlineMinutes,
    required bool allowMultiplePerPlage,
  }) async {
    final res = await _call('createQueue', {
      'companyId': companyId,
      'name': name,
      'maxAdvanceDays': maxAdvanceDays,
      'reservationDeadlineMinutes': reservationDeadlineMinutes,
      'allowMultiplePerPlage': allowMultiplePerPlage,
    });
    return res['queueId'] as String? ?? '';
  }

  /// Supprime une file sans plage ni réservation à venir (et ses restes).
  static Future<void> deleteQueue({
    required String companyId,
    required String queueId,
  }) => _call('deleteQueue', {'companyId': companyId, 'queueId': queueId});

  /// Programme la suppression de la file à la date de sa dernière plage
  /// (toutes ses plages doivent déjà partir). Renvoie cette date.
  static Future<DateTime> scheduleQueueDeletion({
    required String companyId,
    required String queueId,
  }) async {
    final res = await _call('scheduleQueueDeletion', {
      'companyId': companyId,
      'queueId': queueId,
    });
    return DateTime.fromMillisecondsSinceEpoch(
      (res['deleteAfter'] as num).toInt(),
    );
  }

  /// Annule la suppression programmée d'une file.
  static Future<void> restoreQueueDeletion({
    required String companyId,
    required String queueId,
  }) => _call('restoreQueueDeletion', {
    'companyId': companyId,
    'queueId': queueId,
  });
}
