import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ============================================================
// ENUMS & MODELS
// ============================================================

enum ModificationType { ponctuelle, permanente }

/// Résultat retourné après chaque opération
class ModificationResult {
  final bool success;
  final String message;
  final int slotsAffected;
  final int reservationsAnnulees;

  const ModificationResult({
    required this.success,
    required this.message,
    this.slotsAffected = 0,
    this.reservationsAnnulees = 0,
  });
}

/// Statistiques dérivées des créneaux d'une file pour une date donnée.
/// Calculées une seule fois par rafraîchissement — pas de requête supplémentaire.
class QueueStats {
  /// Places encore disponibles (capacity - reserved) sur les créneaux ouverts
  final int placesRestantes;

  /// Places déjà réservées sur les créneaux ouverts
  final int placesReservees;

  /// Personnes en attente (backlog) = réservations annulées ce jour
  final int personnesEnAttente;

  /// Nombre total de créneaux ouverts (non bloqués)
  final int totalCreneaux;

  /// true si tous les créneaux sont bloqués
  final bool estBloquee;

  const QueueStats({
    this.placesRestantes = 0,
    this.placesReservees = 0,
    this.personnesEnAttente = 0,
    this.totalCreneaux = 0,
    this.estBloquee = false,
  });
}

/// Modèle de données d'un créneau tel que lu depuis Firestore
class AgendaSlot {
  final String id;
  final String queueId;
  final DateTime start;
  final DateTime end;
  final int capacity;
  final int reserved;
  final int cancelled;
  final String status; // "open" | "blocked"
  final int duration; // en minutes
  final bool isLegacy;
  final String timeSlotId;
  final String? blockReason;
  List<String> customerNames;

  AgendaSlot({
    required this.id,
    required this.queueId,
    required this.start,
    required this.end,
    required this.capacity,
    required this.reserved,
    required this.cancelled,
    required this.status,
    required this.duration,
    this.isLegacy = false,
    this.timeSlotId = '',
    this.blockReason,
    this.customerNames = const [],
  });

  bool get isFull => reserved >= capacity;
  bool get isBlocked => status == 'blocked';
  bool get hasReservations => reserved > 0;
  int get availablePlaces => capacity - reserved;
}

// ============================================================
// AGENDA SERVICE — SINGLETON
// ============================================================

class AgendaService {
  // Singleton
  static final AgendaService _instance = AgendaService._internal();
  factory AgendaService() => _instance;
  AgendaService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _companyId = '';

  /// Doit être appelé une fois après login
  void initialize() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) _companyId = user.uid;
  }

  // ----------------------------------------------------------
  // REFERENCES CENTRALISÉES
  // ----------------------------------------------------------
  DocumentReference _queueRef(String queueId) => _firestore
      .collection('companies')
      .doc(_companyId)
      .collection('queues')
      .doc(queueId);

  CollectionReference _slotsRef(String queueId) =>
      _queueRef(queueId).collection('slots');

  CollectionReference _timeSlotsRef(String queueId) =>
      _queueRef(queueId).collection('timeSlots');

  CollectionReference _reservationsRef() => _firestore
      .collection('companies')
      .doc(_companyId)
      .collection('reservations');

  // ==============================================================
  // 1. CHARGER LES CRÉNEAUX POUR UNE DATE + UNE FILE
  // ==============================================================

  Future<List<AgendaSlot>> loadSlotsForDate(
    String queueId,
    DateTime date, {
    int? limit, // ← pagination : nombre max de slots à charger
  }) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Construction de la query de base
    Query query = _slotsRef(queueId)
        .where('start', isGreaterThanOrEqualTo: startOfDay)
        .where('start', isLessThan: endOfDay)
        .orderBy('start');

    // Appliquer la limite si fournie
    if (limit != null) {
      query = query.limit(limit);
    }

    final snap = await query.get();
    return snap.docs.map((doc) => slotFromDoc(doc, queueId: queueId)).toList();
  }

  // ==============================================================
  // CONSTRUCTION D'UN AgendaSlot DEPUIS UN DocumentSnapshot
  // Méthode publique — utilisée par HousePage pour la pagination
  // (pages 2+ chargées directement depuis Firestore sans passer
  //  par loadSlotsForDate qui ne supporte pas startAfterDocument)
  // ==============================================================

  AgendaSlot slotFromDoc(
    DocumentSnapshot doc, {
    String? queueId, // optionnel : si non fourni, laissé vide
  }) {
    final d = doc.data() as Map<String, dynamic>;
    final slotStart = (d['start'] as Timestamp).toDate();
    final slotEnd = (d['end'] as Timestamp).toDate();
    return AgendaSlot(
      id: doc.id,
      queueId: queueId ?? '',
      start: slotStart,
      end: slotEnd,
      capacity: (d['capacity'] as num).toInt(),
      reserved: (d['reserved'] as num).toInt(),
      cancelled: ((d['cancelled'] as num?)?.toInt()) ?? 0,
      status: d['status'] as String? ?? 'open',
      duration: d.containsKey('duration')
          ? (d['duration'] as num).toInt()
          : slotEnd.difference(slotStart).inMinutes,
      isLegacy: d['isLegacy'] as bool? ?? false,
      timeSlotId: d['timeSlotId'] as String? ?? '',
      blockReason: d['blockReason'] as String?,
    );
  }

  // ==============================================================
  // 2. CHARGER LES NOMS DE CLIENTS D'UN CRÉNEAU
  // ==============================================================

  Future<List<String>> loadCustomerNames(String slotId) async {
    try {
      final snap = await _reservationsRef()
          .where('slotId', isEqualTo: slotId)
          .where('status', isEqualTo: 'confirmed')
          .get();
      return snap.docs
          .map(
            (d) =>
                (d.data() as Map<String, dynamic>)['customerName'] as String? ??
                'Client',
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ==============================================================
  // 3. CHARGER LA CONFIG DES PLAGES HORAIRES (timeSlots) D'UNE FILE
  // ==============================================================

  Future<List<Map<String, dynamic>>> loadTimeRanges(String queueId) async {
    final snap = await _timeSlotsRef(queueId).get();
    return snap.docs.map((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'startTime': d['startTime'] as String? ?? '09:00',
        'endTime': d['endTime'] as String? ?? '17:00',
        'serviceDurationMinutes': (d['serviceDurationMinutes'] as num).toInt(),
        'capacityPerSlot': (d['capacityPerSlot'] as num).toInt(),
      };
    }).toList();
  }

  // ==============================================================
  // 4. VÉRIFIER SI LA PLAGE EST BLOQUÉE + RÉCUPÉRER LA RAISON
  //    Une seule requête Firestore au lieu de deux
  // ==============================================================

  Future<({bool blocked, String? reason})> getBlockInfo(
    String queueId,
    DateTime date,
  ) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snap = await _slotsRef(queueId)
        .where('start', isGreaterThanOrEqualTo: startOfDay)
        .where('start', isLessThan: endOfDay)
        .limit(20)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'blocked') {
        return (blocked: true, reason: data['blockReason'] as String?);
      }
    }
    return (blocked: false, reason: null);
  }

  // ==============================================================
  // 5. COMPTER LES RÉSERVATIONS POUR UNE DATE (preview avant blocage)
  // ==============================================================

  Future<int> countReservationsForDate(String queueId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snap = await _slotsRef(queueId)
        .where('start', isGreaterThanOrEqualTo: startOfDay)
        .where('start', isLessThan: endOfDay)
        .get();

    int total = 0;
    for (final doc in snap.docs) {
      total += ((doc.data() as Map<String, dynamic>)['reserved'] as num)
          .toInt();
    }
    return total;
  }

  // ==============================================================
  // 6. MODIFIER LA DURÉE DES CRÉNEAUX
  //    Règle : Option B — Migration progressive
  //    • Créneaux réservés → gardent leur durée originale, marqués isLegacy
  //    • Créneaux libres  → supprimés puis régénérés avec la nouvelle durée
  // ==============================================================

  Future<ModificationResult> modifySlotDuration({
    required String queueId,
    required DateTime date,
    required int newDuration,
    required ModificationType type,
    bool applyToFuture = false,
  }) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Charger tous les créneaux du jour
      final slotsSnap = await _slotsRef(queueId)
          .where('start', isGreaterThanOrEqualTo: startOfDay)
          .where('start', isLessThan: endOfDay)
          .orderBy('start')
          .get();

      final batch = _firestore.batch();

      // Séparer réservés vs libres
      final reservedDocs = <DocumentSnapshot>[];
      final freeDocs = <DocumentSnapshot>[];

      for (final doc in slotsSnap.docs) {
        final reserved =
            ((doc.data() as Map<String, dynamic>)['reserved'] as num).toInt();
        if (reserved > 0) {
          reservedDocs.add(doc);
        } else {
          freeDocs.add(doc);
        }
      }

      // Supprimer les créneaux libres
      for (final doc in freeDocs) {
        batch.delete(doc.reference);
      }

      // Marquer les réservés comme legacy
      for (final doc in reservedDocs) {
        batch.update(doc.reference, {'isLegacy': true});
      }

      await batch.commit();

      // Régénérer les créneaux libres avec la nouvelle durée
      final created = await _regenerateFreeSlots(
        queueId: queueId,
        date: date,
        newDuration: newDuration,
        reservedDocs: reservedDocs,
      );

      // Si PERMANENTE → sync config globale
      if (type == ModificationType.permanente) {
        await _syncGlobalConfig(queueId, {
          'serviceDurationMinutes': newDuration,
        });

        if (applyToFuture) {
          await _applyDurationToFutureDays(queueId, newDuration, date);
        }
      }

      return ModificationResult(
        success: true,
        message:
            'Durée mise à jour à $newDuration min. $created créneaux régénérés.',
        slotsAffected: created,
      );
    } catch (e) {
      debugPrint('❌ modifySlotDuration: $e');
      return ModificationResult(success: false, message: 'Erreur : $e');
    }
  }

  // ==============================================================
  // 7. MODIFIER LA CAPACITÉ PAR CRÉNEAU
  //    Règle : on ne peut jamais diminuer en dessous du nombre déjà réservé
  // ==============================================================

  Future<ModificationResult> modifySlotCapacity({
    required String queueId,
    required DateTime date,
    required int newCapacity,
    required ModificationType type,
    bool applyToFuture = false,
    String? timeSlotId,
  }) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final slotsSnap = await _slotsRef(queueId)
          .where('start', isGreaterThanOrEqualTo: startOfDay)
          .where('start', isLessThan: endOfDay)
          .where('status', isEqualTo: 'open')
          .get();

      final docs = timeSlotId != null
          ? slotsSnap.docs
              .where((d) =>
                  (d.data() as Map<String, dynamic>)['timeSlotId'] ==
                  timeSlotId)
              .toList()
          : slotsSnap.docs;

      final batch = _firestore.batch();
      int affected = 0;

      for (final doc in docs) {
        final reserved =
            ((doc.data() as Map<String, dynamic>)['reserved'] as num).toInt();
        final effectiveCapacity =
            newCapacity < reserved ? reserved : newCapacity;
        batch.update(doc.reference, {'capacity': effectiveCapacity});
        affected++;
      }

      await batch.commit();

      if (type == ModificationType.permanente) {
        if (timeSlotId != null) {
          await _timeSlotsRef(queueId).doc(timeSlotId).update({
            'capacityPerSlot': newCapacity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await _syncGlobalConfig(queueId, {'capacityPerSlot': newCapacity});
        }
        if (applyToFuture) {
          await _applyCapacityToFutureDays(
              queueId, newCapacity, date, timeSlotId: timeSlotId);
        }
      }

      return ModificationResult(
        success: true,
        message:
            'Capacité mise à jour à $newCapacity pers. ($affected créneaux)',
        slotsAffected: affected,
      );
    } catch (e) {
      debugPrint('❌ modifySlotCapacity: $e');
      return ModificationResult(success: false, message: 'Erreur : $e');
    }
  }

  // ==============================================================
  // 8. BLOQUER UNE PLAGE
  //    • Annulation automatique de toutes les réservations
  //    • Notification aux clients avec la raison
  // ==============================================================

  Future<ModificationResult> blockPlage({
    required String queueId,
    required DateTime date,
    required String reason,
  }) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final slotsSnap = await _slotsRef(queueId)
          .where('start', isGreaterThanOrEqualTo: startOfDay)
          .where('start', isLessThan: endOfDay)
          .get();

      final batch = _firestore.batch();
      int totalAnnulees = 0;
      final clientsToNotify = <Map<String, dynamic>>[];

      // Récupérer le nom de la file une seule fois
      final queueDoc = await _queueRef(queueId).get();
      final queueName = queueDoc.exists
          ? (queueDoc.data() as Map<String, dynamic>)['name'] as String? ??
                'File'
          : 'File';

      for (final slotDoc in slotsSnap.docs) {
        final slotData = slotDoc.data() as Map<String, dynamic>;
        final slotReserved = (slotData['reserved'] as num).toInt();

        // Bloquer le créneau
        batch.update(slotDoc.reference, {
          'status': 'blocked',
          'blockReason': reason,
          'blockedAt': FieldValue.serverTimestamp(),
        });

        // Si des réservations existent sur ce créneau
        if (slotReserved > 0) {
          final resSnap = await _reservationsRef()
              .where('slotId', isEqualTo: slotDoc.id)
              .where('status', isEqualTo: 'confirmed')
              .get();

          for (final resDoc in resSnap.docs) {
            final resData = resDoc.data() as Map<String, dynamic>;

            // Annuler la réservation
            batch.update(resDoc.reference, {
              'status': 'cancelled',
              'cancelledAt': FieldValue.serverTimestamp(),
              'cancellationSource': 'company_block',
              'cancellationReason': reason,
            });

            totalAnnulees++;

            // Collecter pour notification
            clientsToNotify.add({
              'customerId': resData['customerId'],
              'queueName': queueName,
              'slotStart': (slotData['start'] as Timestamp).toDate(),
              'slotEnd': (slotData['end'] as Timestamp).toDate(),
              'reason': reason,
            });
          }

          // Réinitialiser compteurs sur le slot
          batch.update(slotDoc.reference, {
            'cancelled': (slotData['cancelled'] as num).toInt() + slotReserved,
            'reserved': 0,
          });
        }
      }

      await batch.commit();

      // Envoyer notifications (best-effort, ne bloque pas si échoue)
      _sendBlockNotifications(clientsToNotify);

      return ModificationResult(
        success: true,
        message: 'Plage bloquée. $totalAnnulees réservation(s) annulée(s).',
        reservationsAnnulees: totalAnnulees,
      );
    } catch (e) {
      debugPrint('❌ blockPlage: $e');
      return ModificationResult(success: false, message: 'Erreur : $e');
    }
  }

  // ==============================================================
  // 9. DÉBLOQUER UNE PLAGE
  // ==============================================================

  Future<ModificationResult> unblockPlage({
    required String queueId,
    required DateTime date,
  }) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final slotsSnap = await _slotsRef(queueId)
          .where('start', isGreaterThanOrEqualTo: startOfDay)
          .where('start', isLessThan: endOfDay)
          .where('status', isEqualTo: 'blocked')
          .get();

      final batch = _firestore.batch();
      int affected = 0;

      for (final doc in slotsSnap.docs) {
        batch.update(doc.reference, {
          'status': 'open',
          'blockReason': null,
          'unblockedAt': FieldValue.serverTimestamp(),
        });
        affected++;
      }

      await batch.commit();

      return ModificationResult(
        success: true,
        message: '$affected créneau(x) débloqué(s).',
        slotsAffected: affected,
      );
    } catch (e) {
      debugPrint('❌ unblockPlage: $e');
      return ModificationResult(success: false, message: 'Erreur : $e');
    }
  }

  // ==============================================================
  // INTERNES — RÉGÉNÉRATION DE CRÉNEAUX
  // ==============================================================

  /// Régénère les créneaux libres autour des créneaux réservés (legacy).
  /// Remplit les "trous" entre les créneaux réservés avec la nouvelle durée.
  Future<int> _regenerateFreeSlots({
    required String queueId,
    required DateTime date,
    required int newDuration,
    required List<DocumentSnapshot> reservedDocs,
  }) async {
    // Charger les plages horaires configurées
    final timeRanges = await loadTimeRanges(queueId);
    if (timeRanges.isEmpty) return 0;

    final batch = _firestore.batch();
    int created = 0;

    // Collecter les intervalles occupés par les créneaux réservés, triés
    final occupied = <_Interval>[];
    for (final doc in reservedDocs) {
      final s = ((doc.data() as Map<String, dynamic>)['start'] as Timestamp)
          .toDate();
      final e = ((doc.data() as Map<String, dynamic>)['end'] as Timestamp)
          .toDate();
      occupied.add(_Interval(start: s, end: e));
    }
    occupied.sort((a, b) => a.start.compareTo(b.start));

    for (final range in timeRanges) {
      final plageStart = _parseTime(date, range['startTime'] as String);
      final plageEnd = _parseTime(date, range['endTime'] as String);
      final capacityPerSlot = (range['capacityPerSlot'] as num).toInt();

      // Filtrer les créneaux réservés qui appartiennent à cette plage
      final rangeOccupied = occupied
          .where(
            (i) =>
                i.start.compareTo(plageStart) >= 0 &&
                i.end.compareTo(plageEnd) <= 0,
          )
          .toList();

      DateTime cursor = plageStart;

      for (final occ in rangeOccupied) {
        // Remplir le trou AVANT cet intervalle réservé
        while (cursor
                .add(Duration(minutes: newDuration))
                .compareTo(occ.start) <=
            0) {
          final slotEnd = cursor.add(Duration(minutes: newDuration));
          batch.set(_slotsRef(queueId).doc(), {
            'start': cursor,
            'end': slotEnd,
            'capacity': capacityPerSlot,
            'reserved': 0,
            'cancelled': 0,
            'status': 'open',
            'duration': newDuration,
            'isLegacy': false,
          });
          created++;
          cursor = slotEnd;
        }
        // Sauter l'intervalle réservé
        cursor = occ.end;
      }

      // Remplir APRÈS le dernier intervalle réservé
      while (cursor.add(Duration(minutes: newDuration)).compareTo(plageEnd) <=
          0) {
        final slotEnd = cursor.add(Duration(minutes: newDuration));
        batch.set(_slotsRef(queueId).doc(), {
          'start': cursor,
          'end': slotEnd,
          'capacity': capacityPerSlot,
          'reserved': 0,
          'cancelled': 0,
          'status': 'open',
          'duration': newDuration,
          'isLegacy': false,
        });
        created++;
        cursor = slotEnd;
      }
    }

    await batch.commit();
    return created;
  }

  // ==============================================================
  // INTERNES — SYNC CONFIG GLOBALE (timeSlots dans Settings)
  // ==============================================================

  /// Met à jour les paramètres dans la collection timeSlots (Settings)
  Future<void> _syncGlobalConfig(
    String queueId,
    Map<String, dynamic> updates,
  ) async {
    final snap = await _timeSlotsRef(queueId).get();
    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // ==============================================================
  // INTERNES — APPLIQUER AUX JOURS FUTURS (bouton séparé)
  // ==============================================================

  /// Applique une nouvelle durée aux 30 prochains jours en parallèle
  Future<void> _applyDurationToFutureDays(
    String queueId,
    int newDuration,
    DateTime fromDate,
  ) async {
    final tomorrow = DateTime(
      fromDate.year,
      fromDate.month,
      fromDate.day,
    ).add(const Duration(days: 1));

    await Future.wait([
      for (int i = 0; i < 30; i++)
        modifySlotDuration(
          queueId: queueId,
          date: tomorrow.add(Duration(days: i)),
          newDuration: newDuration,
          type: ModificationType.ponctuelle,
        ),
    ]);
  }

  /// Applique une nouvelle capacité aux 30 prochains jours en parallèle
  Future<void> _applyCapacityToFutureDays(
    String queueId,
    int newCapacity,
    DateTime fromDate, {
    String? timeSlotId,
  }) async {
    final tomorrow = DateTime(
      fromDate.year,
      fromDate.month,
      fromDate.day,
    ).add(const Duration(days: 1));

    await Future.wait([
      for (int i = 0; i < 30; i++)
        modifySlotCapacity(
          queueId: queueId,
          date: tomorrow.add(Duration(days: i)),
          newCapacity: newCapacity,
          type: ModificationType.ponctuelle,
          timeSlotId: timeSlotId,
        ),
    ]);
  }

  // ==============================================================
  // NOTIFICATIONS AUX CLIENTS (best-effort)
  // ==============================================================

  /// Écrit une notification dans l'historique du client dans Firestore.
  /// Le client la verra la prochaine fois qu'il ouvre l'appli.
  Future<void> _sendBlockNotifications(
    List<Map<String, dynamic>> clients,
  ) async {
    await Future.wait(
      clients.map((client) async {
        final customerId = client['customerId'] as String?;
        if (customerId == null) return;

        try {
          final slotStart = client['slotStart'] as DateTime;
          final slotEnd = client['slotEnd'] as DateTime;
          final queueName = client['queueName'] as String;
          final reason = client['reason'] as String;

          final startStr =
              '${slotStart.day.toString().padLeft(2, '0')}/'
              '${slotStart.month.toString().padLeft(2, '0')} '
              '${slotStart.hour.toString().padLeft(2, '0')}:'
              '${slotStart.minute.toString().padLeft(2, '0')}';
          final endStr =
              '${slotEnd.hour.toString().padLeft(2, '0')}:'
              '${slotEnd.minute.toString().padLeft(2, '0')}';

          await _firestore
              .collection('customers')
              .doc(customerId)
              .collection('notifications')
              .add({
                'title': '❌ Réservation annulée',
                'body':
                    'File : $queueName\n'
                    'Créneau : $startStr – $endStr\n\n'
                    'Raison : $reason\n\n'
                    'Nous nous excusons pour ce désagrément.',
                'type': 'reservation_cancelled_by_company',
                'read': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
        } catch (e) {
          debugPrint('⚠️ Notification échouée pour $customerId : $e');
        }
      }),
    );
  }

  // ==============================================================
  // CALCUL DES STATISTIQUES D'UNE FILE (à partir des slots déjà chargés)
  // ==============================================================

  /// Calcule les 3 indicateurs clés à partir d'une liste de slots.
  /// Appelé après loadSlotsForDate() — aucune requête Firestore supplémentaire.
  QueueStats computeStats(List<AgendaSlot> slots) {
    if (slots.isEmpty) {
      return const QueueStats();
    }

    // Séparer ouverts vs bloqués
    final openSlots = slots.where((s) => !s.isBlocked).toList();
    final allBlocked = openSlots.isEmpty;

    int placesRestantes = 0;
    int placesReservees = 0;
    int personnesEnAttente = 0;

    for (final slot in slots) {
      // Backlog = cancelled sur TOUS les créneaux (même bloqués)
      personnesEnAttente += slot.cancelled;

      // Places restantes et réservées = uniquement sur les créneaux OUVERTS
      if (!slot.isBlocked) {
        placesReservees += slot.reserved;
        placesRestantes += (slot.capacity - slot.reserved);
      }
    }

    // Si la plage est bloquée, les places restantes tombent à 0
    if (allBlocked) {
      placesRestantes = 0;
      placesReservees = 0;
    }

    return QueueStats(
      placesRestantes: placesRestantes,
      placesReservees: placesReservees,
      personnesEnAttente: personnesEnAttente,
      totalCreneaux: openSlots.length,
      estBloquee: allBlocked,
    );
  }

  // ==============================================================
  // PROCHAIN CRÉNEAU DISPONIBLE (pour le dialog vigil)
  // ==============================================================

  /// Retourne le prochain créneau ouvert avec des places disponibles
  /// à partir de maintenant pour la date donnée.
  Future<AgendaSlot?> getNextAvailableSlot(
    String queueId,
    DateTime date,
  ) async {
    final slots = await loadSlotsForDate(queueId, date);
    final now = DateTime.now();
    final available = slots
        .where(
          (s) =>
              !s.isBlocked &&
              s.reserved < s.capacity &&
              s.start.isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return available.isEmpty ? null : available.first;
  }

  // ==============================================================
  // 10. GÉNÉRATION IMMÉDIATE DE CRÉNEAUX
  // ==============================================================
  Future<int> generateSlotsImmediately({
    required String queueId,
    required String timeSlotId,
    required String startTimeStr,
    required String endTimeStr,
    required int duration,
    required int capacity,
    required List<int> workingDays,
    required int maxAdvanceDays,
    required int maxReservationsPerPerson,
    required int reservationDeadlineMinutes,
    String? companyId,
  }) async {
    final cid = companyId ?? _companyId;
    final today = DateTime.now();
    final queuePath = _firestore
        .collection('companies')
        .doc(cid)
        .collection('queues')
        .doc(queueId);
    final slotsRef = queuePath.collection('slots');
    final dailyStatsRef = queuePath.collection('dailyStats');

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    int created = 0;
    final processedDays = <DateTime>[];

    final startParts = startTimeStr.split(':');
    final endParts = endTimeStr.split(':');

    for (int i = 0; i <= 7; i++) {
      final date =
          DateTime(today.year, today.month, today.day).add(Duration(days: i));
      if (!workingDays.contains(date.weekday)) continue;
      processedDays.add(date);

      final startOfDay = date;
      final endOfDay = date.add(const Duration(days: 1));
      Set<DateTime> existingStarts = {};
      try {
        final existingSnap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: startOfDay)
            .where('start', isLessThan: endOfDay)
            .get(const GetOptions(source: Source.cache));
        existingStarts = existingSnap.docs
            .map((d) => d.data()['start'] as Timestamp)
            .map((ts) => ts.toDate())
            .toSet();
      } catch (_) {}

      final plageStart = DateTime(
        date.year, date.month, date.day,
        int.parse(startParts[0]), int.parse(startParts[1]),
      );
      final plageEnd = endTimeStr == '24:00'
          ? DateTime(date.year, date.month, date.day)
              .add(const Duration(days: 1))
          : DateTime(date.year, date.month, date.day,
              int.parse(endParts[0]), int.parse(endParts[1]));

      DateTime cursor = plageStart;
      if (i == 0) {
        final now = DateTime.now();
        while (cursor.isBefore(now) &&
            cursor.add(Duration(minutes: duration)).compareTo(plageEnd) <= 0) {
          cursor = cursor.add(Duration(minutes: duration));
        }
      }

      while (cursor.add(Duration(minutes: duration)).compareTo(plageEnd) <= 0) {
        final slotEnd = cursor.add(Duration(minutes: duration));
        if (!existingStarts.contains(cursor)) {
          batch.set(slotsRef.doc(), {
            'start': cursor,
            'end': slotEnd,
            'capacity': capacity,
            'reserved': 0,
            'cancelled': 0,
            'status': 'open',
            'duration': duration,
            'isLegacy': false,
            'timeSlotId': timeSlotId,
            'maxReservationsPerPerson': maxReservationsPerPerson,
            'reservationDeadlineMinutes': reservationDeadlineMinutes,
          });
          batchCount++;
          created++;
          if (batchCount >= 400) {
            await batch.commit();
            batch = _firestore.batch();
            batchCount = 0;
          }
        }
        cursor = slotEnd;
      }
    }

    if (batchCount > 0) await batch.commit();
    await queuePath.update({'slotsLastGenerated': FieldValue.serverTimestamp()});

    try {
      for (final date in processedDays) {
        final startOfDay = date;
        final endOfDay = date.add(const Duration(days: 1));
        final snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: startOfDay)
            .where('start', isLessThan: endOfDay)
            .get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) continue;
        int totalSlots = 0, totalCapacity = 0, reserved = 0, cancelled = 0;
        for (final doc in snap.docs) {
          final d = doc.data();
          totalSlots++;
          totalCapacity += (d['capacity'] as int? ?? 0);
          reserved += (d['reserved'] as int? ?? 0);
          cancelled += (d['cancelled'] as int? ?? 0);
        }
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        await dailyStatsRef.doc(dateStr).set({
          'date': dateStr,
          'totalSlots': totalSlots,
          'totalCapacity': totalCapacity,
          'available': totalCapacity - reserved,
          'reserved': reserved,
          'cancelled': cancelled,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}

    return created;
  }

  // ==============================================================
  // 11. SUPPRIMER LES CRÉNEAUX VIDES FUTURS D'UNE PLAGE
  // ==============================================================
  Future<void> deleteEmptyFutureSlotsForTimeSlot(
    String timeSlotId,
    String queueId, {
    String? companyId,
  }) async {
    final cid = companyId ?? _companyId;
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final slotsRef = _firestore
        .collection('companies')
        .doc(cid)
        .collection('queues')
        .doc(queueId)
        .collection('slots');

    QuerySnapshot snap;
    try {
      snap =
          await slotsRef.where('start', isGreaterThanOrEqualTo: today).get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: today)
            .get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['timeSlotId'] != timeSlotId) continue;
      if ((data['reserved'] as int? ?? 0) > 0) continue;
      batch.delete(doc.reference);
      batchCount++;
      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();
  }

  // ==============================================================
  // 12. SUPPRIMER LES CRÉNEAUX VIDES AU-DELÀ D'UN HORIZON
  // ==============================================================
  Future<void> deleteEmptyFutureSlotsForTimeSlotBeyondHorizon(
    String timeSlotId,
    String queueId,
    int maxAdvanceDays, {
    String? companyId,
  }) async {
    final cid = companyId ?? _companyId;
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final horizon = today.add(const Duration(days: 8));
    final slotsRef = _firestore
        .collection('companies')
        .doc(cid)
        .collection('queues')
        .doc(queueId)
        .collection('slots');

    QuerySnapshot snap;
    try {
      snap =
          await slotsRef.where('start', isGreaterThanOrEqualTo: horizon).get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: horizon)
            .get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['timeSlotId'] != timeSlotId) continue;
      if ((data['reserved'] as int? ?? 0) > 0) continue;
      batch.delete(doc.reference);
      batchCount++;
      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();
  }

  // ==============================================================
  // 13. MISE À JOUR DES PARAMÈTRES SUR LES CRÉNEAUX EXISTANTS
  // ==============================================================
  Future<int> updateSlotParameters({
    required String timeSlotId,
    required String queueId,
    required int capacity,
    required int duration,
    required int maxReservationsPerPerson,
    required int reservationDeadlineMinutes,
    required int maxAdvanceDays,
    String? companyId,
  }) async {
    final cid = companyId ?? _companyId;
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final maxDate = today.add(const Duration(days: 8));
    final slotsRef = _firestore
        .collection('companies')
        .doc(cid)
        .collection('queues')
        .doc(queueId)
        .collection('slots');

    QuerySnapshot snap;
    try {
      snap = await slotsRef
          .where('start', isGreaterThanOrEqualTo: today)
          .where('start', isLessThan: maxDate)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: today)
            .where('start', isLessThan: maxDate)
            .get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    int updated = 0;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['timeSlotId'] != timeSlotId) continue;
      if (data['status'] != 'open') continue;
      final reserved = data['reserved'] as int? ?? 0;
      final safeCapacity = capacity < reserved ? reserved : capacity;
      batch.update(doc.reference, {
        'capacity': safeCapacity,
        'duration': duration,
        'maxReservationsPerPerson': maxReservationsPerPerson,
        'reservationDeadlineMinutes': reservationDeadlineMinutes,
      });
      batchCount++;
      updated++;
      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();
    return updated;
  }

  // ==============================================================
  // UTILITAIRES
  // ==============================================================

  DateTime _parseTime(DateTime date, String time) {
    final parts = time.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }
}

/// Petit modèle interne pour représenter un intervalle occupé
class _Interval {
  final DateTime start;
  final DateTime end;
  _Interval({required this.start, required this.end});
}
