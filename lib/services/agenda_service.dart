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

/// Entrée cliente avec source (entreprise ou app customer)
class CustomerEntry {
  final String id;
  final String name;
  final bool isCompanyManual;
  const CustomerEntry({
    required this.id,
    required this.name,
    required this.isCompanyManual,
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

  /// Charge les clients d'un créneau avec leur source (entreprise ou app).
  /// Lit `companies/{companyId}/reservations`, la collection où sont
  /// réellement écrites toutes les réservations (client comme manuelles).
  Future<List<CustomerEntry>> loadCustomers(
    String slotId, {
    required String companyId,
  }) async {
    try {
      final snap = await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('reservations')
          .where('slotId', isEqualTo: slotId)
          .where('status', isEqualTo: 'confirmed')
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        return CustomerEntry(
          id: d.id,
          name: data['customerName'] as String? ?? 'Client',
          isCompanyManual: data['source'] == 'company_manual',
        );
      }).toList();
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
                .where(
                  (d) =>
                      (d.data() as Map<String, dynamic>)['timeSlotId'] ==
                      timeSlotId,
                )
                .toList()
          : slotsSnap.docs;

      final batch = _firestore.batch();
      int affected = 0;

      for (final doc in docs) {
        final reserved =
            ((doc.data() as Map<String, dynamic>)['reserved'] as num).toInt();
        final effectiveCapacity = newCapacity < reserved
            ? reserved
            : newCapacity;
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
        // « Permanente » = permanent partout : on répercute aussi la nouvelle
        // capacité sur les créneaux libres déjà générés des jours suivants
        // (sinon ils gardent l'ancienne valeur — la CF de nuit ne réécrit
        // jamais un créneau existant). Pas de case à cocher : le libellé
        // « Permanente » suffit, comme pour la durée.
        await _applyCapacityToFutureDays(
          queueId,
          newCapacity,
          date,
          timeSlotId: timeSlotId,
        );
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
  // 8. DÉBLOQUER UNE PLAGE
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

  /// Répercute une nouvelle capacité sur les créneaux LIBRES déjà générés, de
  /// demain jusqu'au bout de l'horizon — en une seule requête + des batchs,
  /// au lieu d'une boucle jour par jour. Un créneau réservé n'est jamais
  /// réduit sous son nombre de réservations (même clamp que la journée en
  /// cours).
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
    // Fenêtre large : couvre toute anticipation raisonnable en une requête.
    final horizonEnd = tomorrow.add(const Duration(days: 60));

    final snap = await _slotsRef(queueId)
        .where('start', isGreaterThanOrEqualTo: tomorrow)
        .where('start', isLessThan: horizonEnd)
        .where('status', isEqualTo: 'open')
        .get();

    WriteBatch batch = _firestore.batch();
    int pending = 0;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (timeSlotId != null && data['timeSlotId'] != timeSlotId) continue;
      final reserved = (data['reserved'] as num?)?.toInt() ?? 0;
      final effectiveCapacity = newCapacity < reserved ? reserved : newCapacity;
      batch.update(doc.reference, {'capacity': effectiveCapacity});
      pending++;
      if (pending == 400) {
        await batch.commit();
        batch = _firestore.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
  }

  // ==============================================================
  // CALCUL DES STATISTIQUES D'UNE FILE (à partir des slots déjà chargés)
  // ==============================================================

  /// Calcule les 3 indicateurs clés à partir d'une liste de slots.
  /// Appelé après loadSlotsForDate() — aucune requête Firestore supplémentaire.
  ///
  /// [now] sert de référence pour déterminer si un créneau est déjà passé.
  /// Par défaut : l'heure actuelle.
  QueueStats computeStats(List<AgendaSlot> slots, {DateTime? now}) {
    if (slots.isEmpty) {
      return const QueueStats();
    }

    final effectiveNow = now ?? DateTime.now();

    // Séparer ouverts vs bloqués
    final openSlots = slots.where((s) => !s.isBlocked).toList();
    final allBlocked = openSlots.isEmpty;

    int placesRestantes = 0;
    int placesReservees = 0;
    int personnesEnAttente = 0;

    for (final slot in slots) {
      // Backlog = clients réservés dont le créneau n'est pas encore passé
      // (même bloqué : un client déjà réservé reste "en attente" tant que
      // son heure n'est pas dépassée). Une annulation n'y contribue pas :
      // elle a déjà fait baisser `reserved` au moment où elle a eu lieu.
      if (!slot.end.isBefore(effectiveNow)) {
        personnesEnAttente += slot.reserved;
      }

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
    final available =
        slots
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
  // ESPACES LIBRES — calcul partagé entre modes ponctuel et permanent
  // ==============================================================
  /// Retourne les intervalles de [rangeStart, rangeEnd] qui ne sont PAS
  /// occupés par un créneau déjà réservé (reserved > 0). Les créneaux vides
  /// existants sont ignorés ici — ils sont destinés à être recréés dans
  /// ces mêmes espaces avec la nouvelle configuration (durée/capacité).
  List<({DateTime start, DateTime end})> freeSpans(
    List<AgendaSlot> existingSlots,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final reservedSlots = existingSlots.where((s) => s.reserved > 0).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final spans = <({DateTime start, DateTime end})>[];
    DateTime cursor = rangeStart;
    for (final rs in reservedSlots) {
      if (cursor.isBefore(rs.start)) {
        spans.add((start: cursor, end: rs.start));
      }
      if (rs.end.isAfter(cursor)) cursor = rs.end;
    }
    if (cursor.isBefore(rangeEnd)) {
      spans.add((start: cursor, end: rangeEnd));
    }
    return spans;
  }

  // ==============================================================
  // ARRONDI AU PROCHAIN MULTIPLE DE 5 MINUTES
  // ==============================================================
  /// Arrondit [t] vers l'avant (jamais vers l'arrière) au prochain multiple
  /// de 5 minutes. Si [t] est déjà exactement sur un multiple de 5, il est
  /// renvoyé inchangé. Gère nativement les débordements d'heure/jour
  /// (ex: 12:58 → 13:00) via l'arithmétique normalisée de [DateTime.add].
  DateTime roundUpToNext5Minutes(DateTime t) {
    final remainder = t.minute % 5;
    final hasSubMinutePart =
        t.second != 0 || t.millisecond != 0 || t.microsecond != 0;
    if (remainder == 0 && !hasSubMinutePart) return t;
    final minutesToAdd = 5 - remainder;
    final truncated = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    return truncated.add(Duration(minutes: minutesToAdd));
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
    required int reservationDeadlineMinutes,
    String? companyId,
    // Ancre horaire optionnelle : figée par l'appelant (ex: revert d'une
    // édition en direct) pour un résultat stable au lieu de recalculer
    // "maintenant" à chaque appel. Par défaut, l'instant présent.
    DateTime? anchorNow,
  }) async {
    final cid = companyId ?? _companyId;
    final today = anchorNow ?? DateTime.now();
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
      final date = DateTime(
        today.year,
        today.month,
        today.day,
      ).add(Duration(days: i));
      if (!workingDays.contains(date.weekday)) continue;
      processedDays.add(date);

      final startOfDay = date;
      final endOfDay = date.add(const Duration(days: 1));
      List<AgendaSlot> existingSlots = [];
      try {
        final existingSnap = await slotsRef
            .where('start', isGreaterThanOrEqualTo: startOfDay)
            .where('start', isLessThan: endOfDay)
            .get(const GetOptions(source: Source.cache));
        existingSlots = existingSnap.docs
            .where((d) => d.data()['timeSlotId'] == timeSlotId)
            .map((d) => slotFromDoc(d, queueId: queueId))
            .toList();
      } catch (_) {}

      final plageStart = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
      );
      final plageEnd = endTimeStr == '24:00'
          ? DateTime(
              date.year,
              date.month,
              date.day,
            ).add(const Duration(days: 1))
          : DateTime(
              date.year,
              date.month,
              date.day,
              int.parse(endParts[0]),
              int.parse(endParts[1]),
            );

      // Créneaux vides existants dans cette plage : recréés ci-dessous avec
      // la nouvelle configuration, dans les mêmes espaces libres. Les
      // créneaux réservés, eux, ne sont jamais touchés.
      for (final s in existingSlots) {
        if (s.reserved == 0) {
          batch.delete(slotsRef.doc(s.id));
          batchCount++;
          if (batchCount >= 400) {
            await batch.commit();
            batch = _firestore.batch();
            batchCount = 0;
          }
        }
      }

      final now = today;
      final roundedNow = roundUpToNext5Minutes(now);
      for (final span in freeSpans(existingSlots, plageStart, plageEnd)) {
        var cursor = span.start.isBefore(now) ? roundedNow : span.start;
        while (true) {
          final slotEnd = cursor.add(Duration(minutes: duration));
          if (!slotEnd.isAfter(span.end) &&
              slotEnd.difference(cursor).inMinutes >= 5) {
            batch.set(slotsRef.doc(), {
              'start': Timestamp.fromDate(cursor),
              'end': Timestamp.fromDate(slotEnd),
              'capacity': capacity,
              'reserved': 0,
              'cancelled': 0,
              'status': 'open',
              'duration': duration,
              'isLegacy': false,
              'timeSlotId': timeSlotId,
              'reservationDeadlineMinutes': reservationDeadlineMinutes,
            });
            batchCount++;
            created++;
            if (batchCount >= 400) {
              await batch.commit();
              batch = _firestore.batch();
              batchCount = 0;
            }
            cursor = slotEnd;
          } else {
            break;
          }
        }
      }
    }

    if (batchCount > 0) await batch.commit();
    await queuePath.update({
      'slotsLastGenerated': FieldValue.serverTimestamp(),
    });

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
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final slotsRef = _firestore
        .collection('companies')
        .doc(cid)
        .collection('queues')
        .doc(queueId)
        .collection('slots');

    QuerySnapshot snap;
    try {
      snap = await slotsRef.where('start', isGreaterThanOrEqualTo: today).get();
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
  // 12. MISE À JOUR DES PARAMÈTRES SUR LES CRÉNEAUX EXISTANTS
  // ==============================================================
  Future<int> updateSlotParameters({
    required String timeSlotId,
    required String queueId,
    required int capacity,
    required int duration,
    required int reservationDeadlineMinutes,
    required int maxAdvanceDays,
    String? companyId,
  }) async {
    final cid = companyId ?? _companyId;
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
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
