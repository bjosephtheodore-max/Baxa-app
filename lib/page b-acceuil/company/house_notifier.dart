part of 'house_page.dart';

// ════════════════════════════════════════════════════════════════════════════
// HOUSE NOTIFIER — État + opérations Firestore, sans BuildContext
// Séparation nette : données ici, UI dans house_page.dart
// ════════════════════════════════════════════════════════════════════════════
class _HouseNotifier extends ChangeNotifier {
  // ── Services ──────────────────────────────────────────────────────────────
  final _db = FirebaseFirestore.instance;
  final _agenda = AgendaService();

  // ── État ──────────────────────────────────────────────────────────────────
  String? _companyId;
  String _companyName = '';
  DateTime _selectedDate = DateTime.now();
  List<_QueueAgenda?> _queues = [];
  int _totalQueues = 0;
  bool _isLoading = true;
  bool _hasQueues = false;
  bool _loadFailed = false;
  bool _isRefreshing = false;
  bool _isStaff = false;
  bool _disposed = false;

  // ── Pagination ────────────────────────────────────────────────────────────
  static const int _pageSize = 15;
  final Map<String, DocumentSnapshot?> _lastSlotDoc = {};
  final Map<String, bool> _hasMoreSlots = {};
  final Map<String, bool> _isLoadingMore = {};

  // ── Flux temps réel ───────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _sub;
  bool _initialLoadDone = false;

  // ── Getters (lecture publique) ────────────────────────────────────────────
  String? get companyId => _companyId;
  String get companyName => _companyName;
  DateTime get selectedDate => _selectedDate;
  List<_QueueAgenda?> get queues => _queues;
  bool get isLoading => _isLoading;
  bool get hasQueues => _hasQueues;
  bool get loadFailed => _loadFailed;
  bool get isStaff => _isStaff;
  bool isLoadingMore(String qid) => _isLoadingMore[qid] == true;
  bool hasMore(String qid) => _hasMoreSlots[qid] == true;
  AgendaService get agenda => _agenda;

  // ── Initialisation ────────────────────────────────────────────────────────
  void initialize() {
    _agenda.initialize();
    _loadCompanyData();
  }

  void refreshSilent() => _refreshAgenda(silent: true);

  // ── Navigation de date ────────────────────────────────────────────────────
  void changeDate(int days) {
    _selectedDate = _selectedDate.add(Duration(days: days));
    _notify();
    _refreshAgenda();
  }

  void setDate(DateTime date) {
    _selectedDate = date;
    _notify();
    _refreshAgenda();
  }

  // ── Marquage skeleton pendant une opération ───────────────────────────────
  void setQueueLoading(String queueId) {
    final i = _queues.indexWhere((q) => q?.id == queueId);
    if (i != -1) {
      _queues[i] = null;
      _notify();
    }
  }

  // ── Scroll infini ─────────────────────────────────────────────────────────
  Future<void> loadMoreSlots(String queueId) async {
    if (_isLoadingMore[queueId] == true) return;
    if (_hasMoreSlots[queueId] != true) return;

    _isLoadingMore[queueId] = true;
    _notify();

    try {
      final page = await _loadSlotPage(queueId, startAfter: _lastSlotDoc[queueId]);
      _lastSlotDoc[queueId] = page.lastDoc;
      _hasMoreSlots[queueId] = page.hasMore;

      final idx = _queues.indexWhere((q) => q != null && q.id == queueId);
      if (idx != -1) {
        final q = _queues[idx]!;
        _queues[idx] = _QueueAgenda(
          id: q.id,
          name: q.name,
          slots: [...q.slots, ...page.slots],
          isBlocked: q.isBlocked,
          blockReason: q.blockReason,
          stats: q.stats,
          weekdays: q.weekdays,
          timeSlotCount: q.timeSlotCount,
        );
      }
    } catch (e) {
      debugPrint('Erreur page suivante: $e');
    }
    _isLoadingMore[queueId] = false;
    _notify();
  }

  // ── Trouver la prochaine date avec créneaux ───────────────────────────────
  Future<DateTime?> findNextSlotDate(String queueId) async {
    if (_companyId == null) return null;
    final dayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
        .add(const Duration(days: 1));

    final snap = await _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .orderBy('start')
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final ts = snap.docs.first.data()['start'] as Timestamp;
    final d = ts.toDate();
    return DateTime(d.year, d.month, d.day);
  }

  // ── Blocage de créneaux ───────────────────────────────────────────────────
  Future<String?> blockTimeSlot({
    required String queueId,
    String? timeSlotId, // null = bloquer toutes les plages du jour
    required String reason,
  }) async {
    if (_companyId == null) return 'Aucune entreprise trouvée';
    try {
      final dayStart = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final snap = await _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .collection('slots')
          .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('start', isLessThan: Timestamp.fromDate(dayEnd))
          .orderBy('start')
          .get();

      final docs = timeSlotId != null
          ? snap.docs
              .where((d) => d.data()['timeSlotId'] == timeSlotId)
              .toList()
          : snap.docs;

      WriteBatch batch = _db.batch();
      int count = 0;
      for (final doc in docs) {
        batch.update(doc.reference, {
          'status': 'blocked',
          'blockReason': reason,
          'blockedAt': FieldValue.serverTimestamp(),
        });
        count++;
        if (count % 400 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      }
      if (count % 400 != 0) await batch.commit();

      await _refreshAgenda(silent: true);
      return null;
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  // ── Déblocage ─────────────────────────────────────────────────────────────
  Future<ModificationResult> unblockPlage(String queueId) async {
    setQueueLoading(queueId);
    final result = await _agenda.unblockPlage(queueId: queueId, date: _selectedDate);
    await _refreshAgenda(silent: true);
    return result;
  }

  // ── RDV manuel ────────────────────────────────────────────────────────────
  Future<String?> createManualAppointment(
    String clientName,
    _QueueAgenda queue,
    AgendaSlot slot,
  ) async {
    if (_companyId == null) return 'Aucune entreprise trouvée';
    try {
      await _db.collection('reservations').add({
        'customerId': 'manual_booking',
        'customerName': clientName,
        'companyId': _companyId,
        'queueId': queue.id,
        'queueName': queue.name,
        'slotStart': slot.start,
        'slotEnd': slot.end,
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'company_manual',
      });
      final slotsRef = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id)
          .collection('slots');
      final matching = await slotsRef
          .where('start', isEqualTo: slot.start)
          .where('end', isEqualTo: slot.end)
          .limit(1)
          .get();
      if (matching.docs.isNotEmpty) {
        await matching.docs.first.reference.update({
          'reserved': FieldValue.increment(1),
        });
      }
      await _refreshAgenda(silent: true);
      return null;
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  // ── Vérification réservations existantes ──────────────────────────────────
  bool hasReservationsInSlots(List<AgendaSlot> slots) => slots.any((s) => s.reserved > 0);

  // ── Créneaux disponibles du jour (pour le carousel du FAB) ────────────────
  Future<List<AgendaSlot>> fetchAvailableSlots(String queueId) async {
    if (_companyId == null) return [];
    final now = DateTime.now();
    final dayEnd = DateTime(
            _selectedDate.year, _selectedDate.month, _selectedDate.day)
        .add(const Duration(days: 1));

    QuerySnapshot snap;
    final query = _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .where('start', isGreaterThan: Timestamp.fromDate(now))
        .where('start', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('start');
    try {
      snap = await query.get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await query.get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    return snap.docs
        .map((doc) => _agenda.slotFromDoc(doc, queueId: queueId))
        .where((s) => !s.isBlocked && s.reserved < s.capacity)
        .toList();
  }

  // ── Récupérer les plages horaires (timeSlots) d'une file ─────────────────
  Future<List<_TimeSlotInfo>> fetchTimeSlots(String queueId) async {
    if (_companyId == null) return [];
    final snap = await _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('timeSlots')
        .get();
    return snap.docs.map((doc) {
      final d = doc.data();
      return _TimeSlotInfo(
        id: doc.id,
        startTime: d['startTime'] as String? ?? '00:00',
        endTime: d['endTime'] as String? ?? '23:59',
        capacity: (d['capacityPerSlot'] as num?)?.toInt() ?? 1,
        duration: (d['serviceDurationMinutes'] as num?)?.toInt() ?? 15,
        workingDays: d['workingDays'] != null
            ? List<int>.from(d['workingDays'] as List)
            : <int>[],
        maxAdvanceDays: (d['maxAdvanceDays'] as num?)?.toInt() ?? 5,
        maxReservationsPerPerson:
            (d['maxReservationsPerPerson'] as num?)?.toInt() ?? 1,
        reservationDeadlineMinutes:
            (d['reservationDeadlineMinutes'] as num?)?.toInt() ?? 10,
      );
    }).toList();
  }

  // ── Modification de durée — algorithme timeline ───────────────────────────
  Future<ModificationResult> applyDurationChange({
    required _QueueAgenda queue,
    required _TimeSlotInfo tsInfo,
    required DateTime plageStart,
    required DateTime plageEnd,
    required int newDuration,
    required ModificationType type,
  }) async {
    try {
      // ── Mode PERMANENTE : delete-empty + regenerate + update-params ──────
      if (type == ModificationType.permanente) {
        await _db
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .doc(queue.id)
            .collection('timeSlots')
            .doc(tsInfo.id)
            .update({
          'serviceDurationMinutes': newDuration,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await _agenda.deleteEmptyFutureSlotsForTimeSlot(
          tsInfo.id, queue.id,
          companyId: _companyId,
        );
        final effectiveWorkingDays = tsInfo.workingDays.isNotEmpty
            ? tsInfo.workingDays
            : queue.weekdays.isNotEmpty
            ? queue.weekdays
            : List.generate(7, (i) => i + 1);
        final created = await _agenda.generateSlotsImmediately(
          queueId: queue.id,
          timeSlotId: tsInfo.id,
          startTimeStr: tsInfo.startTime,
          endTimeStr: tsInfo.endTime,
          duration: newDuration,
          capacity: tsInfo.capacity > 0 ? tsInfo.capacity : currentCapacity(queue),
          workingDays: effectiveWorkingDays,
          maxAdvanceDays: tsInfo.maxAdvanceDays,
          maxReservationsPerPerson: tsInfo.maxReservationsPerPerson,
          reservationDeadlineMinutes: tsInfo.reservationDeadlineMinutes,
          companyId: _companyId,
        );
        await _agenda.updateSlotParameters(
          timeSlotId: tsInfo.id,
          queueId: queue.id,
          capacity: tsInfo.capacity > 0 ? tsInfo.capacity : currentCapacity(queue),
          duration: newDuration,
          maxReservationsPerPerson: tsInfo.maxReservationsPerPerson,
          reservationDeadlineMinutes: tsInfo.reservationDeadlineMinutes,
          maxAdvanceDays: tsInfo.maxAdvanceDays,
          companyId: _companyId,
        );
        return ModificationResult(
          success: true,
          message:
              'Durée mise à jour à $newDuration min ✅  ·  $created créneaux régénérés',
          slotsAffected: created,
        );
      }

      // ── Mode PONCTUEL : free-spans approach ─────────────────────────────
      final dayStart = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final slotsQuery = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id)
          .collection('slots')
          .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('start', isLessThan: Timestamp.fromDate(dayEnd))
          .orderBy('start');

      QuerySnapshot slotsSnap;
      try {
        slotsSnap = await slotsQuery.get();
      } on FirebaseException catch (e) {
        if (e.code == 'unavailable') {
          slotsSnap =
              await slotsQuery.get(const GetOptions(source: Source.cache));
        } else {
          rethrow;
        }
      }

      final allDocs = slotsSnap.docs
          .where((doc) =>
              (doc.data() as Map<String, dynamic>)['timeSlotId'] == tsInfo.id)
          .toList();

      if (allDocs.isEmpty) {
        return ModificationResult(
            success: false, message: 'Aucun créneau trouvé pour cette plage');
      }

      final allSlots = allDocs
          .map((doc) => _agenda.slotFromDoc(doc, queueId: queue.id))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

      final reservedSlots =
          allSlots.where((s) => s.reserved > 0).toList();
      final emptySlotIds =
          allSlots.where((s) => s.reserved == 0).map((s) => s.id).toList();

      // Espaces libres = [plageStart, plageEnd] minus reserved intervals
      final List<({DateTime start, DateTime end})> freeSpans = [];
      DateTime cursor = plageStart;
      for (final rs in reservedSlots) {
        if (cursor.isBefore(rs.start)) {
          freeSpans.add((start: cursor, end: rs.start));
        }
        if (rs.end.isAfter(cursor)) cursor = rs.end;
      }
      if (cursor.isBefore(plageEnd)) {
        freeSpans.add((start: cursor, end: plageEnd));
      }

      final batch = _db.batch();
      final slotsRef = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id)
          .collection('slots');

      // Supprimer tous les créneaux vides
      for (final id in emptySlotIds) {
        batch.delete(slotsRef.doc(id));
      }

      // Remplir chaque espace libre avec la nouvelle durée
      // On ne crée jamais de créneaux dans le passé (cas création de plage le jour J)
      int createdCount = 0;
      final now = DateTime.now();
      final slotCapacity =
          tsInfo.capacity > 0 ? tsInfo.capacity : currentCapacity(queue);
      for (final span in freeSpans) {
        var t = span.start.isBefore(now) ? now : span.start;
        while (true) {
          final newEnd = t.add(Duration(minutes: newDuration));
          if (!newEnd.isAfter(span.end) &&
              newEnd.difference(t).inMinutes >= 5) {
            batch.set(slotsRef.doc(), {
              'start': Timestamp.fromDate(t),
              'end': Timestamp.fromDate(newEnd),
              'duration': newDuration,
              'capacity': slotCapacity,
              'reserved': 0,
              'cancelled': 0,
              'status': 'open',
              'isLegacy': false,
              'timeSlotId': tsInfo.id,
              'maxReservationsPerPerson': tsInfo.maxReservationsPerPerson,
              'reservationDeadlineMinutes': tsInfo.reservationDeadlineMinutes,
            });
            createdCount++;
            t = newEnd;
          } else {
            break;
          }
        }
      }

      // Recalculer dailyStats pour que "disponible" soit correct après refresh
      final int totalReservedPeople =
          reservedSlots.fold(0, (acc, s) => acc + s.reserved);
      final int reservedCapacityRemaining =
          reservedSlots.fold(0, (acc, s) => acc + (s.capacity - s.reserved));
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      batch.set(
        _db
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .doc(queue.id)
            .collection('dailyStats')
            .doc(dateStr),
        {
          'available': reservedCapacityRemaining + createdCount * slotCapacity,
          'reserved': totalReservedPeople,
          'cancelled': 0,
          'totalSlots': reservedSlots.length + createdCount,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
      return ModificationResult(
        success: true,
        message: '$createdCount créneau(x) créés ✅',
        slotsAffected: createdCount,
      );
    } catch (e) {
      return ModificationResult(success: false, message: 'Erreur : $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  int currentDuration(_QueueAgenda q) {
    final nl = q.slots.where((s) => !s.isLegacy).toList();
    return nl.isNotEmpty ? nl.first.duration : (q.slots.isNotEmpty ? q.slots.first.duration : 15);
  }

  int currentCapacity(_QueueAgenda q) {
    final nl = q.slots.where((s) => !s.isLegacy).toList();
    return nl.isNotEmpty ? nl.first.capacity : (q.slots.isNotEmpty ? q.slots.first.capacity : 1);
  }

  // ── Chargement initial ────────────────────────────────────────────────────
  Future<void> _loadCompanyData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('🔴 HouseNotifier: currentUser null à l\'init');
      _isLoading = false;
      _notify();
      return;
    }
    final uid = user.uid;
    debugPrint('🟢 HouseNotifier: init pour uid=$uid');

    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data['role'] == 'staff' && data['companyId'] != null) {
          _companyId = data['companyId'] as String;
          _isStaff = true;
        } else {
          _companyId = uid;
          _isStaff = false;
        }
      } else {
        _companyId = uid;
        _isStaff = false;
      }
    } catch (_) {
      _companyId = uid;
      _isStaff = false;
    }
    _isLoading = true;
    _notify();

    try {
      final results = await Future.wait([
        _db.collection('companies').doc(_companyId).get(),
        _db
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .limit(1)
            .get(),
      ]);

      final companyDoc = results[0] as DocumentSnapshot;
      final queuesCheck = results[1] as QuerySnapshot;

      if (companyDoc.exists) {
        _companyName = (companyDoc.data() as Map<String, dynamic>?)?['nom'] ?? 'Baxa';
      }

      if (queuesCheck.docs.isEmpty) {
        debugPrint('🟡 HouseNotifier: aucune file → état vide');
        _hasQueues = false;
        _isLoading = false;
        _notify();
      } else {
        debugPrint('🟢 HouseNotifier: ${queuesCheck.docs.length} file(s) trouvée(s)');
        _hasQueues = true;
        await _refreshAgenda();
      }

      _sub?.cancel();
      _initialLoadDone = false;
      _sub = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .snapshots()
          .listen((snap) {
            if (!_initialLoadDone) {
              _initialLoadDone = true;
              return;
            }
            _hasQueues = snap.docs.isNotEmpty;
            if (_hasQueues) {
              _refreshAgenda(silent: true);
            } else {
              _queues = [];
              _notify();
            }
          });
    } catch (e) {
      debugPrint('🔴 HouseNotifier: erreur loadCompanyData: $e');
      _isLoading = false;
      _notify();
    }
  }

  // ── Rafraîchissement agenda ───────────────────────────────────────────────
  Future<void> _refreshAgenda({bool silent = false}) async {
    if (_companyId == null) return;
    if (_isRefreshing) {
      // Un refresh concurrent tourne déjà. En mode non-silencieux,
      // s'assurer que _isLoading ne reste pas bloqué à true.
      if (!silent) {
        _isLoading = false;
        _notify();
      }
      return;
    }
    _isRefreshing = true;

    _lastSlotDoc.clear();
    _hasMoreSlots.clear();
    _isLoadingMore.clear();

    if (!silent) {
      _isLoading = true;
      _notify();
    }

    try {
      final queuesSnap = await _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .limit(10)
          .get();

      if (queuesSnap.docs.isEmpty) {
        debugPrint('🟡 HouseNotifier: _refreshAgenda — queues vides');
        _isLoading = false;
        _isRefreshing = false;
        _notify();
        return;
      }

      debugPrint('🟢 HouseNotifier: _refreshAgenda — ${queuesSnap.docs.length} file(s), silent=$silent');
      if (!silent) {
        _totalQueues = queuesSnap.docs.length;
        _queues = List.filled(_totalQueues, null);
        _isLoading = false;
        _notify();
      }

      final newQueues = List<_QueueAgenda?>.filled(queuesSnap.docs.length, null);

      await Future.wait(queuesSnap.docs.asMap().entries.map((entry) async {
        final index = entry.key;
        final qDoc = entry.value;
        final qData = qDoc.data();

        try {
          final firstPage = await _loadSlotPage(qDoc.id, startAfter: null);
          _lastSlotDoc[qDoc.id] = firstPage.lastDoc;
          _hasMoreSlots[qDoc.id] = firstPage.hasMore;
          _isLoadingMore[qDoc.id] = false;

          final isBlocked = firstPage.slots.isNotEmpty &&
              firstPage.slots.every((s) => s.isBlocked);
          final blockReason = isBlocked
              ? firstPage.slots.first.blockReason
              : null;

          final rawWeekdays = qData['weekdays'];
          final weekdays = rawWeekdays is List
              ? rawWeekdays.map((e) => (e as num).toInt()).toList()
              : <int>[];

          final tsQuery = _db
              .collection('companies')
              .doc(_companyId)
              .collection('queues')
              .doc(qDoc.id)
              .collection('timeSlots')
              .limit(2);
          QuerySnapshot tsSnap;
          try {
            tsSnap = await tsQuery.get();
          } on FirebaseException catch (e) {
            if (e.code == 'unavailable') {
              tsSnap = await tsQuery.get(const GetOptions(source: Source.cache));
            } else {
              rethrow;
            }
          }
          final timeSlotCount = tsSnap.docs.length;

          final dateStr =
              '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
          final statsRef = _db
              .collection('companies')
              .doc(_companyId)
              .collection('queues')
              .doc(qDoc.id)
              .collection('dailyStats')
              .doc(dateStr);
          DocumentSnapshot<Map<String, dynamic>> statsDoc;
          try {
            statsDoc = await statsRef.get();
          } on FirebaseException catch (e) {
            if (e.code == 'unavailable') {
              statsDoc = await statsRef.get(const GetOptions(source: Source.cache));
            } else {
              rethrow;
            }
          }

          final QueueStats stats;
          if (statsDoc.exists) {
            final sd = statsDoc.data()!;
            stats = QueueStats(
              placesRestantes: (sd['available'] as int? ?? 0).clamp(0, 99999),
              placesReservees: sd['reserved'] as int? ?? 0,
              personnesEnAttente: sd['cancelled'] as int? ?? 0,
              totalCreneaux: sd['totalSlots'] as int? ?? 0,
              estBloquee: isBlocked,
            );
          } else {
            stats = _agenda.computeStats(firstPage.slots);
          }

          final queueData = _QueueAgenda(
            id: qDoc.id,
            name: qData['name'] ?? 'File sans nom',
            slots: firstPage.slots,
            isBlocked: isBlocked,
            blockReason: blockReason,
            stats: stats,
            weekdays: weekdays,
            timeSlotCount: timeSlotCount,
          );

          if (silent) {
            newQueues[index] = queueData;
          } else {
            _queues[index] = queueData;
            _notify();
          }
        } catch (e) {
          debugPrint('🔴 HouseNotifier: erreur file ${qDoc.id}: $e');
          // En refresh silencieux : conserver les données existantes si la
          // requête serveur échoue (cache local valide, index manquant, etc.)
          if (silent) {
            final existing = _queues.firstWhere(
              (q) => q?.id == qDoc.id,
              orElse: () => null,
            );
            if (existing != null) newQueues[index] = existing;
          }
        }
      }));

      if (silent) {
        _totalQueues = newQueues.length;
        // Ne remplacer que si au moins une file a été chargée avec succès
        if (newQueues.any((q) => q != null)) {
          _queues = newQueues;
        }
      }
      _loadFailed = false;
      _isRefreshing = false;
      _notify();
    } catch (e) {
      debugPrint('Erreur rafraîchissement: $e');
      _isLoading = false;
      _loadFailed = true;
      _isRefreshing = false;
      _notify();
    }
  }

  // ── Requête paginée d'une page de slots ───────────────────────────────────
  Future<_SlotPage> _loadSlotPage(
    String queueId, {
    required DocumentSnapshot? startAfter,
  }) async {
    final dayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    Query query = _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('start', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('start')
        .limit(_pageSize);

    if (startAfter != null) query = query.startAfterDocument(startAfter);

    // Réseau indisponible → lire le cache local (inclut les pending writes du batch)
    QuerySnapshot snap;
    try {
      snap = await query.get();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        snap = await query.get(const GetOptions(source: Source.cache));
      } else {
        rethrow;
      }
    }

    final slots = snap.docs.map((doc) => _agenda.slotFromDoc(doc, queueId: queueId)).toList();
    return _SlotPage(
      slots: slots,
      lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
      hasMore: snap.docs.length >= _pageSize,
    );
  }

  // ── Utilitaire interne ────────────────────────────────────────────────────
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
