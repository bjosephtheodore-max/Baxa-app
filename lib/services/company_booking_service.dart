import 'package:baxa/services/company_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ════════════════════════════════════════════════════════════════════
// Réservations gérées par la structure, arbitrées par le serveur
// (Cloud Function `companyBooking`, functions/company_booking.js) :
// inscription au guichet, retrait, blocage / déblocage, fermetures,
// départ de Baxa.
//
// L'app n'écrit plus elle-même réservations ni compteurs : le serveur
// vérifie (place encore libre, droits du membre, file ouverte…) puis
// écrit en une fois. Erreurs : CompanyActionException, message prêt à
// afficher (company_functions.dart).
// ════════════════════════════════════════════════════════════════════

class CompanyBookingService {
  CompanyBookingService._();

  static const String _function = 'companyBooking';

  /// Réveille la fonction en avance (accueil ouvert).
  static Future<void> warmup() => warmupCompanyFunction(_function);

  static Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> data,
  ) => callCompanyFunction(_function, {...data, 'action': action});

  /// Jour « AAAA-MM-JJ » tel qu'affiché à l'accueil.
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Identifiant de demande : une nouvelle tentative après une coupure
  /// retombe sur la même inscription au lieu d'en créer une seconde.
  static String newRequestId() =>
      FirebaseFirestore.instance.collection('companies').doc().id;

  /// Inscrit [clientName] sur le créneau [slotId].
  static Future<String> addManual({
    required String companyId,
    required String queueId,
    required String slotId,
    required String clientName,
    String? queueName,
    String? requestId,
  }) async {
    final res = await _call('addManual', {
      'companyId': companyId,
      'queueId': queueId,
      'slotId': slotId,
      'clientName': clientName,
      if (queueName != null) 'queueName': queueName,
      'requestId': requestId ?? newRequestId(),
    });
    return res['reservationId'] as String? ?? '';
  }

  /// Retire une inscription faite par la structure.
  static Future<void> removeManual({
    required String companyId,
    required String reservationId,
  }) => _call('removeManual', {
    'companyId': companyId,
    'reservationId': reservationId,
  });

  /// Bloque la journée [day] de la file (ou seulement la plage
  /// [timeSlotId]). Renvoie le nombre de créneaux bloqués.
  static Future<int> block({
    required String companyId,
    required String queueId,
    required DateTime day,
    String? timeSlotId,
    required String reason,
  }) async {
    final res = await _call('block', {
      'companyId': companyId,
      'queueId': queueId,
      'day': dayKey(day),
      if (timeSlotId != null) 'timeSlotId': timeSlotId,
      'reason': reason,
    });
    return (res['blocked'] as num?)?.toInt() ?? 0;
  }

  /// Débloque la journée [day] de la file. Renvoie le nombre de créneaux
  /// rouverts.
  static Future<int> unblock({
    required String companyId,
    required String queueId,
    required DateTime day,
  }) async {
    final res = await _call('unblock', {
      'companyId': companyId,
      'queueId': queueId,
      'day': dayKey(day),
    });
    return (res['unblocked'] as num?)?.toInt() ?? 0;
  }

  /// Ferme les files [queueIds] de [start] à [end] (sans fin si null).
  /// [cancelCaught] : annule les réservations prises dans la période.
  /// [replaceExisting] : « Stopper les réservations » remplace une
  /// fermeture déjà posée. Renvoie le nombre de réservations annulées.
  static Future<int> close({
    required String companyId,
    required List<String> queueIds,
    required DateTime start,
    DateTime? end,
    bool cancelCaught = false,
    bool replaceExisting = false,
  }) async {
    final res = await _call('close', {
      'companyId': companyId,
      'queueIds': queueIds,
      'start': start.millisecondsSinceEpoch,
      'end': end?.millisecondsSinceEpoch,
      'cancelCaught': cancelCaught,
      'replaceExisting': replaceExisting,
    });
    return (res['cancelled'] as num?)?.toInt() ?? 0;
  }

  /// Quitte Baxa : demande de suppression (délai de grâce), fermeture de
  /// toutes les files et annulation des réservations à venir. Renvoie la
  /// date de suppression définitive.
  static Future<DateTime> leave({
    required String companyId,
    required String reason,
  }) async {
    final res = await _call('leave', {
      'companyId': companyId,
      'reason': reason,
    });
    final ms = (res['executeAfter'] as num?)?.toInt();
    return ms != null
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.now().add(const Duration(days: 7));
  }
}
