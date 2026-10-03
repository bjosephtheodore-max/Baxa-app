part of 'house_page.dart';

// ── Trace de révocation (undo 5 min, scoping par timeSlot) ─────────────────
// Utilisé uniquement pour les modifications de durée en direct depuis la
// page d'accueil (applyDurationChange). Stockage en mémoire uniquement —
// pas de persistance Firestore, cette trace est un filet de sécurité léger,
// pas un historique durable.
class _PendingRevert {
  final String queueId;
  final _TimeSlotInfo tsInfo;
  final DateTime plageStart;
  final DateTime plageEnd;
  final int previousDuration;
  final ModificationType type;
  final DateTime originalSelectedDate;
  final DateTime anchorNow;
  final DateTime expiresAt;
  Timer? expiryTimer;

  _PendingRevert({
    required this.queueId,
    required this.tsInfo,
    required this.plageStart,
    required this.plageEnd,
    required this.previousDuration,
    required this.type,
    required this.originalSelectedDate,
    required this.anchorNow,
    required this.expiresAt,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// HOUSE NOTIFIER — État + opérations Firestore, sans BuildContext
// Séparation nette : données ici, UI dans house_page.dart
// ════════════════════════════════════════════════════════════════════════════
class _HouseNotifier extends ChangeNotifier {
  // Entreprise du staff, transmise par StaffPage (qui la connaît déjà) :
  // l'accueil n'a alors plus à deviner le rôle. null = contexte admin.
  _HouseNotifier({String? staffCompanyId})
    : _staffCompanyId = staffCompanyId,
      _isStaff = staffCompanyId != null;

  final String? _staffCompanyId;

  // Personne connectée (admin : uid == companyId) et, pour un membre du
  // staff, son nom tel que l'admin l'a renseigné (lu dans le suivi de
  // statut, sans requête de plus).
  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;
  String _myStaffName = '';

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
  bool _isStaff;
  bool _disposed = false;
  bool _initialized = false;
  bool _revoked = false;

  // ── Cache local (session) ─────────────────────────────────────────────────
  static const _kCompanyId = 'hn_company_id';
  static const _kIsStaff = 'hn_is_staff';

  // ── Undo "durée" (live-edit page d'accueil uniquement) ────────────────────
  final Map<String, _PendingRevert> _pendingReverts = {}; // clé = timeSlotId

  // ── Verrou anti-chevauchement : un seul applyDurationChange à la fois par
  // plage (empêche des taps rapprochés — stepper ou bouton retour — de
  // lancer des régénérations concurrentes qui se marchent dessus).
  final Set<String> _busyTimeSlotIds = {}; // clé = timeSlotId

  // ── Pagination (dates déjà passées uniquement) ─────────────────────────────
  static const int _pageSize = 15;
  final Map<String, DocumentSnapshot?> _lastSlotDoc = {};
  final Map<String, bool> _hasMoreSlots = {};
  final Map<String, bool> _isLoadingMore = {};

  // ── Flux temps réel ───────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _sub;
  bool _initialLoadDone = false;

  // Suivi en direct du statut staff (isActive) : détecte un retrait de
  // l'équipe pendant que l'app est ouverte, et dès l'ouverture.
  StreamSubscription<DocumentSnapshot>? _staffStatusSub;

  // Créneaux à venir (aujourd'hui dès "maintenant", ou jour futur en entier) :
  // tenus à jour en direct via Firestore, un flux par file affichée.
  static const int _liveSlotsCap = 300;

  // Durée maximale d'un créneau (bornes du réglage de durée : 5 à 120 min,
  // voir _onDurationChanged dans house_page.dart). Sert à garder en direct
  // tout créneau encore en cours.
  static const Duration _maxSlotDuration = Duration(minutes: 120);

  static DateTime _latest(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  final Map<String, StreamSubscription<QuerySnapshot>> _liveSlotSubs = {};
  final Map<String, List<AgendaSlot>> _pastSlotsCache = {};
  final Map<String, List<AgendaSlot>> _liveSlotsCache = {};
  // Nombre de plages (borné à 2) par file, tenu à jour en direct : l'accueil
  // reste vivant (IndexedStack) pendant qu'on crée la 1re plage dans Réglages,
  // il doit quitter l'état « Aucune plage horaire » sans rechargement.
  final Map<String, StreamSubscription<QuerySnapshot>> _tsCountSubs = {};

  // ── Getters (lecture publique) ────────────────────────────────────────────
  String? get companyId => _companyId;
  String get companyName => _companyName;
  DateTime get selectedDate => _selectedDate;
  List<_QueueAgenda?> get queues => _queues;
  bool get isLoading => _isLoading;
  bool get hasQueues => _hasQueues;
  bool get loadFailed => _loadFailed;
  bool get isStaff => _isStaff;
  bool get revoked => _revoked;
  bool isLoadingMore(String qid) => _isLoadingMore[qid] == true;
  bool hasMore(String qid) => _hasMoreSlots[qid] == true;
  AgendaService get agenda => _agenda;

  // ── Initialisation ────────────────────────────────────────────────────────
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _agenda.initialize();
    _loadCompanyData();
  }

  void refreshSilent() => _refreshAgenda(silent: true);

  // ── Navigation de date ────────────────────────────────────────────────────
  void changeDate(int days) {
    _selectedDate = _selectedDate.add(Duration(days: days));
    if (_queues.isNotEmpty) _queues = List.filled(_queues.length, null);
    _notify();
    _refreshAgenda(skipInitialSpinner: true);
  }

  void setDate(DateTime date) {
    _selectedDate = date;
    if (_queues.isNotEmpty) _queues = List.filled(_queues.length, null);
    _notify();
    _refreshAgenda(skipInitialSpinner: true);
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
      final page = await _loadSlotPage(
        queueId,
        startAfter: _lastSlotDoc[queueId],
      );
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
          closureStart: q.closureStart,
          closureEnd: q.closureEnd,
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
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    ).add(const Duration(days: 1));

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

  // ── Blocage d'un jour (incident) ─────────────────────────────────────────
  // Marque les créneaux du jour `blocked` (plage précise ou toutes) SANS
  // annuler les réservations : celles-ci passent en `suspended: true`. Le
  // client est prévenu par la Cloud Function `onReservationBlockChange`.
  // Au déblocage (unblockPlage) : créneau encore à venir → réservation
  // rétablie ; créneau déjà passé → réservation annulée
  // (`company_block_unresolved`) et client invité à re-réserver.
  Future<String?> blockTimeSlot({
    required String queueId,
    String? timeSlotId, // null = bloquer toutes les plages du jour
    required String reason,
  }) async {
    if (_companyId == null) return 'Aucune entreprise trouvée';
    try {
      final dayStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));
      final slotsRef = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queueId)
          .collection('slots');

      final snap = await slotsRef
          .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('start', isLessThan: Timestamp.fromDate(dayEnd))
          .orderBy('start')
          .get();

      final docs = timeSlotId != null
          ? snap.docs
                .where((d) => d.data()['timeSlotId'] == timeSlotId)
                .toList()
          : snap.docs;

      // La raison part telle quelle dans une notification client.
      final trimmed = reason.trim();
      final safeReason = trimmed.length > 120
          ? '${trimmed.substring(0, 117)}…'
          : trimmed;
      final reasonValue = safeReason.isEmpty ? null : safeReason;

      WriteBatch batch = _db.batch();
      int count = 0;
      Future<void> flush() async {
        if (count >= 380) {
          await batch.commit();
          batch = _db.batch();
          count = 0;
        }
      }

      for (final doc in docs) {
        batch.update(doc.reference, {
          'status': 'blocked',
          'blockReason': reasonValue,
          'blockedAt': FieldValue.serverTimestamp(),
        });
        count++;
        await flush();

        final reserved = (doc.data()['reserved'] as num?)?.toInt() ?? 0;
        if (reserved > 0) {
          final resSnap = await _db
              .collection('companies')
              .doc(_companyId)
              .collection('reservations')
              .where('slotId', isEqualTo: doc.id)
              .where('status', isEqualTo: 'confirmed')
              .get();
          for (final resDoc in resSnap.docs) {
            batch.update(resDoc.reference, {
              'suspended': true,
              'suspendedReason': reasonValue,
              'suspendedAt': FieldValue.serverTimestamp(),
            });
            count++;
            await flush();
          }
        }
      }
      if (count > 0) await batch.commit();

      await _refreshAgenda(silent: true);
      return null;
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  // ── Déblocage ─────────────────────────────────────────────────────────────
  Future<ModificationResult> unblockPlage(String queueId) async {
    setQueueLoading(queueId);
    final result = await _agenda.unblockPlage(
      queueId: queueId,
      date: _selectedDate,
    );
    if (result.success) {
      await _reactivateSuspendedReservations(queueId);
    }
    await _refreshAgenda(silent: true);
    return result;
  }

  // Après déblocage : rétablit les réservations suspendues du jour dont le
  // créneau est encore à venir ; annule celles dont le créneau est déjà
  // passé (`company_block_unresolved`). Les notifications sont envoyées par
  // les Cloud Functions (onReservationBlockChange / onReservationCancelledByCompany).
  Future<void> _reactivateSuspendedReservations(String queueId) async {
    if (_companyId == null) return;
    try {
      final dayStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));
      final now = DateTime.now();

      final resSnap = await _db
          .collection('companies')
          .doc(_companyId)
          .collection('reservations')
          .where('queueId', isEqualTo: queueId)
          .where('status', isEqualTo: 'confirmed')
          .get();

      final suspended = resSnap.docs.where((d) {
        final data = d.data();
        if (data['suspended'] != true) return false;
        final ss = (data['slotStart'] as Timestamp?)?.toDate();
        return ss != null && !ss.isBefore(dayStart) && ss.isBefore(dayEnd);
      }).toList();
      if (suspended.isEmpty) return;

      WriteBatch batch = _db.batch();
      int count = 0;
      for (final d in suspended) {
        final se = (d.data()['slotEnd'] as Timestamp?)?.toDate();
        final passed = se != null && se.isBefore(now);
        batch.update(
          d.reference,
          passed
              ? {
                  'status': 'cancelled',
                  'cancelledAt': FieldValue.serverTimestamp(),
                  'cancellationSource': 'company_block_unresolved',
                  'suspended': FieldValue.delete(),
                  'suspendedReason': FieldValue.delete(),
                  'suspendedAt': FieldValue.delete(),
                }
              : {
                  'suspended': FieldValue.delete(),
                  'suspendedReason': FieldValue.delete(),
                  'suspendedAt': FieldValue.delete(),
                },
        );
        count++;
        if (count >= 380) {
          await batch.commit();
          batch = _db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (_) {
      // non bloquant : les créneaux sont débloqués, c'est l'essentiel
    }
  }

  // ── RDV manuel ────────────────────────────────────────────────────────────
  Future<String?> createManualAppointment(
    String clientName,
    _QueueAgenda queue,
    AgendaSlot slot,
  ) async {
    if (_companyId == null) return 'Aucune entreprise trouvée';
    try {
      final queuePath = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id);

      // Garde-fou : une file fermée ou une plage en suppression programmée
      // n'accepte plus AUCUNE nouvelle réservation, manuelle comprise.
      final queueDoc = await queuePath.get();
      final qd = queueDoc.data();
      if (isQueueClosedNow(
        (qd?['closureStart'] as Timestamp?)?.toDate(),
        (qd?['closureEnd'] as Timestamp?)?.toDate(),
      )) {
        return 'Cette file est fermée aux réservations.';
      }
      if (slot.timeSlotId.isNotEmpty) {
        final tsDoc = await queuePath
            .collection('timeSlots')
            .doc(slot.timeSlotId)
            .get();
        if (tsDoc.data()?['deleteAfter'] != null) {
          return 'Cette plage est en cours de suppression, plus de réservation possible.';
        }
      }

      final slotRef = queuePath.collection('slots').doc(slot.id);

      final d = slot.start.toLocal();
      final dateKey =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final dailyRef = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id)
          .collection('dailyStats')
          .doc(dateKey);

      await Future.wait([
        _db
            .collection('companies')
            .doc(_companyId)
            .collection('reservations')
            .add({
              'customerId': 'manual_booking',
              'customerName': clientName,
              'companyId': _companyId,
              'queueId': queue.id,
              'queueName': queue.name,
              'slotId': slot.id,
              'slotStart': slot.start,
              'slotEnd': slot.end,
              'status': 'confirmed',
              'createdAt': FieldValue.serverTimestamp(),
              'source': 'company_manual',
              // Auteur de l'inscription : décide qui peut la supprimer
              // (l'admin toujours, un membre seulement les siennes) et
              // alimente « Ajouté par … ». Contrôlé aussi par les règles.
              if (_myUid != null) 'createdBy': _myUid,
              'createdByRole': _isStaff ? 'staff' : 'admin',
              if (_isStaff && _myStaffName.isNotEmpty)
                'createdByName': _myStaffName,
            }),
        slotRef.update({'reserved': FieldValue.increment(1)}),
        dailyRef.update({'reserved': FieldValue.increment(1)}),
      ]);
      _recordManualAdd();
      return null;
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  // ── Inscriptions manuelles : droits et libellés ───────────────────────────

  /// L'admin supprime toute inscription manuelle ; un membre du staff
  /// seulement celles qu'il a faites lui-même. Même logique que
  /// firestore.rules (match /reservations, allow delete).
  bool canDeleteManual(CustomerEntry c) {
    if (!c.isCompanyManual) return false;
    if (!_isStaff) return true;
    return c.createdBy != null && c.createdBy == _myUid;
  }

  /// « Ajouté par … » sous le nom du client, ou null si l'auteur est
  /// inconnu (inscriptions antérieures à ce suivi).
  String? addedByLabel(CustomerEntry c) {
    if (!c.isCompanyManual || c.createdBy == null) return null;
    if (c.createdBy == _myUid) return 'Ajouté par vous';
    if (c.createdByRole == 'admin') return 'Ajouté par le responsable';
    final name = c.createdByName?.trim() ?? '';
    return 'Ajouté par ${name.isNotEmpty ? name : 'un membre de l\'équipe'}';
  }

  // ── Exemple « Ex : Jean Dupont » : 5 premières inscriptions seulement ─────
  // Compteur propre à chaque compte, gardé sur le téléphone (simple aide à
  // la saisie : il repart à zéro après une réinstallation, sans gravité).
  static const int _nameHintMaxUses = 5;
  int _manualAddCount = 0;

  bool get showNameHint => _manualAddCount < _nameHintMaxUses;

  String get _manualAddCountKey => 'manual_add_count_${_myUid ?? ''}';

  Future<void> _loadManualAddCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _manualAddCount = prefs.getInt(_manualAddCountKey) ?? 0;
    } catch (_) {}
  }

  void _recordManualAdd() {
    if (_manualAddCount >= _nameHintMaxUses) return;
    _manualAddCount++;
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_manualAddCountKey, _manualAddCount))
        .ignore();
  }

  // ── Suppression d'un client ajouté manuellement ───────────────────────────
  Future<String?> deleteManualReservation({
    required String reservationId,
    required _QueueAgenda queue,
    required AgendaSlot slot,
  }) async {
    if (_companyId == null) return 'Aucune entreprise trouvée';
    try {
      final slotRef = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id)
          .collection('slots')
          .doc(slot.id);

      final d = slot.start.toLocal();
      final dateKey =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final dailyRef = _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(queue.id)
          .collection('dailyStats')
          .doc(dateKey);

      await Future.wait([
        _db
            .collection('companies')
            .doc(_companyId)
            .collection('reservations')
            .doc(reservationId)
            .delete(),
        slotRef.update({'reserved': FieldValue.increment(-1)}),
        dailyRef.update({
          'reserved': FieldValue.increment(-1),
          'available': FieldValue.increment(1),
        }),
      ]);
      return null;
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  // ── Vérification réservations existantes ──────────────────────────────────
  bool hasReservationsInSlots(List<AgendaSlot> slots) =>
      slots.any((s) => s.reserved > 0);

  // ── Créneaux disponibles du jour (pour le carousel du FAB) ────────────────
  Future<List<AgendaSlot>> fetchAvailableSlots(String queueId) async {
    if (_companyId == null) return [];
    final now = DateTime.now();
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    // Borne basse : "maintenant" seulement si le jour sélectionné est
    // aujourd'hui (exclut les créneaux déjà passés) — sinon le début du
    // jour sélectionné, pour ne jamais faire déborder la recherche sur
    // les créneaux d'un autre jour (ex : aujourd'hui) que celui affiché.
    final lowerBound = dayStart.isAfter(DateTime(now.year, now.month, now.day))
        ? dayStart
        : now;

    QuerySnapshot snap;
    final query = _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .where('start', isGreaterThan: Timestamp.fromDate(lowerBound))
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
        maxAdvanceDays: (d['maxAdvanceDays'] as num?)?.toInt() ?? 2,
        reservationDeadlineMinutes:
            (d['reservationDeadlineMinutes'] as num?)?.toInt() ?? 0,
        deleteAfter: (d['deleteAfter'] as Timestamp?)?.toDate(),
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
    bool isRevertAction = false,
    DateTime? anchorNow,
  }) async {
    if (_busyTimeSlotIds.contains(tsInfo.id)) {
      return const ModificationResult(
        success: false,
        message:
            'Une modification est déjà en cours sur cette plage — patiente qu\'elle se termine.',
      );
    }
    // Plage en cours de suppression programmée : verrouillée. (Le revert
    // d'une modif faite AVANT la programmation passe par revertDurationChange,
    // qui refait sa propre vérification sur une donnée fraîche.)
    if (!isRevertAction && tsInfo.deleteAfter != null) {
      return const ModificationResult(
        success: false,
        message:
            'Cette plage est en cours de suppression — restituez-la d\'abord pour la modifier.',
      );
    }
    _busyTimeSlotIds.add(tsInfo.id);
    // Ancre horaire : figée à l'édition d'origine pour un revert (résultat
    // stable peu importe quand dans les 5 min le bouton est pressé), sinon
    // l'instant présent pour une édition normale.
    final effectiveNow = anchorNow ?? DateTime.now();
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
          tsInfo.id,
          queue.id,
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
          capacity: tsInfo.capacity > 0
              ? tsInfo.capacity
              : currentCapacity(queue),
          workingDays: effectiveWorkingDays,
          maxAdvanceDays: tsInfo.maxAdvanceDays,
          reservationDeadlineMinutes: tsInfo.reservationDeadlineMinutes,
          companyId: _companyId,
          anchorNow: effectiveNow,
        );
        await _agenda.updateSlotParameters(
          timeSlotId: tsInfo.id,
          queueId: queue.id,
          capacity: tsInfo.capacity > 0
              ? tsInfo.capacity
              : currentCapacity(queue),
          duration: newDuration,
          reservationDeadlineMinutes: tsInfo.reservationDeadlineMinutes,
          maxAdvanceDays: tsInfo.maxAdvanceDays,
          companyId: _companyId,
        );
        if (!isRevertAction) {
          _registerPendingRevert(
            timeSlotId: tsInfo.id,
            queueId: queue.id,
            tsInfo: tsInfo,
            plageStart: plageStart,
            plageEnd: plageEnd,
            previousDuration: tsInfo.duration,
            type: type,
            anchorNow: effectiveNow,
          );
        }
        return ModificationResult(
          success: true,
          message:
              'Durée mise à jour à $newDuration min ✅  ·  $created créneaux régénérés',
          slotsAffected: created,
        );
      }

      // ── Mode PONCTUEL : free-spans approach ─────────────────────────────
      final dayStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
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
          slotsSnap = await slotsQuery.get(
            const GetOptions(source: Source.cache),
          );
        } else {
          rethrow;
        }
      }

      final allDocs = slotsSnap.docs
          .where(
            (doc) =>
                (doc.data() as Map<String, dynamic>)['timeSlotId'] == tsInfo.id,
          )
          .toList();

      if (allDocs.isEmpty) {
        return ModificationResult(
          success: false,
          message: 'Aucun créneau trouvé pour cette plage',
        );
      }

      final allSlots =
          allDocs
              .map((doc) => _agenda.slotFromDoc(doc, queueId: queue.id))
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));

      final emptySlotIds = allSlots
          .where((s) => s.reserved == 0)
          .map((s) => s.id)
          .toList();

      // Espaces libres = [plageStart, plageEnd] minus les créneaux réservés
      // (même calcul que le mode permanent — une seule logique partagée).
      final freeSpans = _agenda.freeSpans(allSlots, plageStart, plageEnd);

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
      final roundedNow = _agenda.roundUpToNext5Minutes(effectiveNow);
      final slotCapacity = tsInfo.capacity > 0
          ? tsInfo.capacity
          : currentCapacity(queue);
      for (final span in freeSpans) {
        var t = span.start.isBefore(effectiveNow) ? roundedNow : span.start;
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
      final reservedSlots = allSlots.where((s) => s.reserved > 0).toList();
      final int totalReservedPeople = reservedSlots.fold(
        0,
        (acc, s) => acc + s.reserved,
      );
      final int reservedCapacityRemaining = reservedSlots.fold(
        0,
        (acc, s) => acc + (s.capacity - s.reserved),
      );
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
      if (!isRevertAction) {
        _registerPendingRevert(
          timeSlotId: tsInfo.id,
          queueId: queue.id,
          tsInfo: tsInfo,
          plageStart: plageStart,
          plageEnd: plageEnd,
          previousDuration: tsInfo.duration,
          type: type,
          anchorNow: effectiveNow,
        );
      }
      return ModificationResult(
        success: true,
        message: '$createdCount créneau(x) créés ✅',
        slotsAffected: createdCount,
      );
    } catch (e) {
      return ModificationResult(success: false, message: 'Erreur : $e');
    } finally {
      _busyTimeSlotIds.remove(tsInfo.id);
    }
  }

  // ── Enregistre/écrase la trace de révocation pour un timeSlot ────────────
  void _registerPendingRevert({
    required String timeSlotId,
    required String queueId,
    required _TimeSlotInfo tsInfo,
    required DateTime plageStart,
    required DateTime plageEnd,
    required int previousDuration,
    required ModificationType type,
    required DateTime anchorNow,
  }) {
    _pendingReverts.remove(timeSlotId)?.expiryTimer?.cancel();
    final entry = _PendingRevert(
      queueId: queueId,
      tsInfo: tsInfo,
      plageStart: plageStart,
      plageEnd: plageEnd,
      previousDuration: previousDuration,
      type: type,
      originalSelectedDate: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      anchorNow: anchorNow,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    entry.expiryTimer = Timer(const Duration(minutes: 5), () {
      _pendingReverts.remove(timeSlotId);
      _notify();
    });
    _pendingReverts[timeSlotId] = entry;
  }

  // ── Révocation (undo) d'une modification de durée en direct ──────────────
  Future<ModificationResult> revertDurationChange(String timeSlotId) async {
    final entry = _pendingReverts[timeSlotId];
    if (entry == null) {
      return const ModificationResult(
        success: false,
        message: 'Rien à annuler : le délai de 5 minutes est dépassé.',
      );
    }

    // La modif a pu être suivie d'une suppression programmée de la plage :
    // dans ce cas le revert (qui régénère des créneaux) est refusé. On lit
    // la donnée fraîche car `entry.tsInfo` date de la modif d'origine.
    if (_companyId != null) {
      try {
        final tsDoc = await _db
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .doc(entry.queueId)
            .collection('timeSlots')
            .doc(timeSlotId)
            .get();
        if (tsDoc.exists && tsDoc.data()?['deleteAfter'] != null) {
          _pendingReverts.remove(timeSlotId)?.expiryTimer?.cancel();
          _notify();
          return const ModificationResult(
            success: false,
            message:
                'Cette plage est en cours de suppression — restituez-la d\'abord pour la modifier.',
          );
        }
      } catch (_) {
        // Lecture best-effort : en cas d'échec réseau on laisse le revert
        // suivre son cours (comportement d'avant).
      }
    }

    // Une révocation "ponctuelle" dépend du jour actuellement affiché (la
    // branche ponctuelle de applyDurationChange lit _selectedDate en
    // interne, pas un paramètre) — refuser si le jour affiché a changé
    // depuis la modification d'origine, pour éviter un décalage entre la
    // plage stockée et le jour réellement interrogé.
    if (entry.type == ModificationType.ponctuelle) {
      final today = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      if (today != entry.originalSelectedDate) {
        final label = DateFormat(
          'dd/MM/yyyy',
          'fr_FR',
        ).format(entry.originalSelectedDate);
        return ModificationResult(
          success: false,
          message:
              'Retournez au $label pour annuler cette modification ponctuelle.',
        );
      }
    }

    final queue = _queues.firstWhere(
      (q) => q?.id == entry.queueId,
      orElse: () => null,
    );
    if (queue == null) {
      return const ModificationResult(
        success: false,
        message: 'File introuvable.',
      );
    }

    final result = await applyDurationChange(
      queue: queue,
      tsInfo: entry.tsInfo,
      plageStart: entry.plageStart,
      plageEnd: entry.plageEnd,
      newDuration: entry.previousDuration,
      type: entry.type,
      isRevertAction: true,
      anchorNow: entry.anchorNow,
    );

    // Trace consommée seulement en cas de succès — usage unique, pas de
    // redo, mais réessayable tant que l'opération elle-même n'a pas abouti
    // (ex: coupure réseau pendant l'écriture Firestore).
    if (result.success) {
      _pendingReverts.remove(timeSlotId);
      entry.expiryTimer?.cancel();
      _notify();
    }

    return result;
  }

  // ── Indice ponctuel "découverte du bouton retour" ─────────────────────────
  // Indépendant de OnboardingService (séquence numérotée de 1ère config) :
  // cet indice peut se déclencher bien plus tard, à la 1ère modification de
  // durée en direct réussie. Persisté sur le doc de l'entreprise, comme
  // firstSetupDone.
  Future<bool> hasSeenRevertHint() async {
    if (_companyId == null) return true;
    try {
      final doc = await _db.collection('companies').doc(_companyId).get();
      return doc.data()?['revertHintSeen'] as bool? ?? false;
    } catch (_) {
      return true; // en cas d'erreur, ne pas importuner l'utilisateur
    }
  }

  Future<void> markRevertHintSeen() async {
    if (_companyId == null) return;
    try {
      await _db.collection('companies').doc(_companyId).update({
        'revertHintSeen': true,
      });
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  int currentDuration(_QueueAgenda q) {
    final nl = q.slots.where((s) => !s.isLegacy).toList();
    return nl.isNotEmpty
        ? nl.first.duration
        : (q.slots.isNotEmpty ? q.slots.first.duration : 15);
  }

  int currentCapacity(_QueueAgenda q) {
    final nl = q.slots.where((s) => !s.isLegacy).toList();
    return nl.isNotEmpty
        ? nl.first.capacity
        : (q.slots.isNotEmpty ? q.slots.first.capacity : 1);
  }

  /// Trace de révocation active pour ce timeSlot (null si aucune ou expirée).
  _PendingRevert? pendingRevert(String timeSlotId) =>
      _pendingReverts[timeSlotId];

  /// Trace de révocation la plus récente parmi toutes les plages de cette
  /// file — peu importe laquelle a été modifiée (1ère, 2ème, 3ème...), un
  /// seul chip est affiché par file, toujours celui de la dernière action.
  /// Les traces des autres plages restent valides en mémoire et expirent
  /// normalement, simplement non affichées tant qu'une plus récente existe.
  _PendingRevert? mostRecentPendingRevert(_QueueAgenda q) {
    final timeSlotIds = q.slots.map((s) => s.timeSlotId).toSet();
    _PendingRevert? latest;
    for (final id in timeSlotIds) {
      final entry = _pendingReverts[id];
      if (entry == null) continue;
      if (latest == null || entry.expiresAt.isAfter(latest.expiresAt)) {
        latest = entry;
      }
    }
    return latest;
  }

  // ── Suivi du statut staff (retrait d'équipe) ──────────────────────────────
  Future<void> _checkStaffStatus(String uid) async {
    _staffStatusSub?.cancel();
    final completer = Completer<void>();

    _staffStatusSub = _db
        .collection('companies')
        .doc(_companyId)
        .collection('staff')
        .doc(uid)
        .snapshots()
        .listen(
          (doc) {
            _myStaffName =
                (doc.data()?['displayName'] as String?)?.trim() ?? '';
            final isActive = doc.data()?['isActive'] as bool? ?? false;
            if (!isActive) {
              _handleRevocation();
            }
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object e) {
            debugPrint('🔴 HouseNotifier: erreur suivi statut staff: $e');
            if (!completer.isCompleted) completer.complete();
          },
        );

    await completer.future;
  }

  Future<void> _handleRevocation() async {
    if (_revoked) return;
    _revoked = true;
    _staffStatusSub?.cancel();
    _sub?.cancel();
    _cancelLiveSlotSubs();
    await Auth().logout();
    _notify();
  }

  // ── Rôle : staff (transmis par StaffPage) ou admin (uid == companyId) ─────
  // Ne conclut JAMAIS « admin » sur une erreur : un staff pris pour un admin
  // verrait une entreprise vide (et l'icône d'équipe). En cas d'échec,
  // l'écran « Réessayer » s'affiche et rien n'est mémorisé.
  Future<bool> _resolveRole(String uid) async {
    final staffCompanyId = _staffCompanyId;
    if (staffCompanyId != null) {
      _companyId = staffCompanyId;
      _isStaff = true;
      return true;
    }

    // Cache local (évite 1 round-trip) : uniquement un admin déjà confirmé
    // sur CE compte — la clé est son propre uid, donc un autre compte
    // connecté sur le même téléphone ne peut jamais en hériter.
    final prefs = await SharedPreferences.getInstance();
    final cachedId = prefs.getString(_kCompanyId);
    final cachedStaff = prefs.getBool(_kIsStaff) ?? false;
    if (cachedId != null && !cachedStaff && cachedId == uid) {
      _companyId = cachedId;
      _isStaff = false;
      return true;
    }

    DocumentSnapshot<Map<String, dynamic>>? userDoc;
    for (var attempt = 0; attempt < 3 && userDoc == null; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(seconds: 1));
      try {
        userDoc = await _db.collection('users').doc(uid).get();
      } catch (e) {
        debugPrint('🔴 HouseNotifier: lecture du rôle échouée: $e');
      }
    }
    if (userDoc == null) {
      _loadFailed = true;
      _isLoading = false;
      _notify();
      return false;
    }

    final data = userDoc.data();
    if (data?['role'] == 'staff' && data?['companyId'] != null) {
      _companyId = data!['companyId'] as String;
      _isStaff = true;
    } else {
      _companyId = uid;
      _isStaff = false;
      prefs.setString(_kCompanyId, uid).ignore();
      prefs.setBool(_kIsStaff, false).ignore();
    }
    return true;
  }

  // Bouton « Réessayer » : si le rôle n'a pas pu être lu, tout est relancé.
  void retry() {
    if (_companyId == null) {
      _loadFailed = false;
      _isLoading = true;
      _notify();
      _loadCompanyData();
    } else {
      _refreshAgenda(silent: true);
    }
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

    if (!await _resolveRole(uid)) return;
    await _loadManualAddCount();

    // ── Staff : vérifier tout de suite (et en continu) qu'il n'a pas été
    //    retiré de l'équipe. Le premier événement du flux couvre le cas
    //    "déjà retiré avant l'ouverture de l'app", les suivants couvrent
    //    le cas "retiré pendant que l'app est ouverte".
    if (_isStaff) {
      await _checkStaffStatus(uid);
      if (_revoked) return;
    }

    _isLoading = true;
    _notify();

    try {
      // ── Nom entreprise en arrière-plan (ne bloque pas le chargement) ─────────
      _db.collection('companies').doc(_companyId).get().then((doc) {
        if (doc.exists) {
          _companyName = doc.data()?['nom'] as String? ?? 'Baxa';
          _notify();
        }
      }).ignore();

      // ── Files : seule requête sur le chemin critique ──────────────────────────
      final queuesSnap = await _db
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .limit(5)
          .get();

      if (queuesSnap.docs.isEmpty) {
        debugPrint('🟡 HouseNotifier: aucune file → état vide');
        _hasQueues = false;
        _isLoading = false;
        _notify();
      } else {
        debugPrint(
          '🟢 HouseNotifier: ${queuesSnap.docs.length} file(s) trouvée(s)',
        );
        _hasQueues = true;
        await _refreshAgenda(preloadedQueues: queuesSnap); // ← plus de re-fetch
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
  Future<void> _refreshAgenda({
    bool silent = false,
    bool skipInitialSpinner = false,
    QuerySnapshot<Map<String, dynamic>>? preloadedQueues,
  }) async {
    if (_companyId == null) return;
    if (_isRefreshing) {
      if (!silent && !skipInitialSpinner) {
        _isLoading = false;
        _notify();
      }
      return;
    }
    _isRefreshing = true;

    _lastSlotDoc.clear();
    _hasMoreSlots.clear();
    _isLoadingMore.clear();
    _cancelLiveSlotSubs();

    if (!silent && !skipInitialSpinner) {
      _isLoading = true;
      _notify();
    }

    try {
      // Gain 1 : réutiliser le snapshot déjà chargé dans _loadCompanyData
      final queuesSnap =
          preloadedQueues ??
          await _db
              .collection('companies')
              .doc(_companyId)
              .collection('queues')
              .limit(5)
              .get();

      if (queuesSnap.docs.isEmpty) {
        debugPrint('🟡 HouseNotifier: _refreshAgenda — queues vides');
        _isLoading = false;
        _isRefreshing = false;
        _notify();
        return;
      }

      debugPrint(
        '🟢 HouseNotifier: _refreshAgenda — ${queuesSnap.docs.length} file(s), silent=$silent',
      );
      if (!silent) {
        _totalQueues = queuesSnap.docs.length;
        _queues = List.filled(_totalQueues, null);
        _isLoading = false;
        _notify();
      }

      final newQueues = List<_QueueAgenda?>.filled(
        queuesSnap.docs.length,
        null,
      );

      await Future.wait(
        queuesSnap.docs.asMap().entries.map((entry) async {
          final index = entry.key;
          final qDoc = entry.value;
          final qData = qDoc.data();

          try {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final selectedDay = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
            );
            final isToday = selectedDay == today;
            final isPastDate = selectedDay.isBefore(today);

            final dateStr =
                '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

            final rawWeekdays = qData['weekdays'];
            final weekdays = rawWeekdays is List
                ? rawWeekdays.map((e) => (e as num).toInt()).toList()
                : <int>[];
            final queueName = qData['name'] ?? 'File sans nom';

            // TimeSlot count — flux borné à 2 docs (peu coûteux). En direct
            // plutôt qu'une lecture ponctuelle : une plage peut être créée ou
            // supprimée depuis l'onglet Settings pendant que l'accueil reste
            // vivant en parallèle via l'IndexedStack de company_page.dart.
            final Future<int> tsCountFuture = _subscribeTimeSlotCount(qDoc.id);

            final List<AgendaSlot> allSlots;
            final QueueStats stats;
            final bool isBlocked;
            final String? blockReason;

            if (isPastDate) {
              // ── Date déjà passée : ne change plus → pagination + dailyStats,
              //    comportement inchangé (pas besoin de flux temps réel ici) ──
              final pageFuture = _loadSlotPage(qDoc.id, startAfter: null);

              final statsRef = _db
                  .collection('companies')
                  .doc(_companyId)
                  .collection('queues')
                  .doc(qDoc.id)
                  .collection('dailyStats')
                  .doc(dateStr);
              final statsFuture = () async {
                try {
                  return await statsRef.get();
                } on FirebaseException catch (e) {
                  if (e.code == 'unavailable') {
                    return statsRef.get(const GetOptions(source: Source.cache));
                  }
                  rethrow;
                }
              }();

              final page = await pageFuture;
              final statsDoc = await statsFuture;

              _lastSlotDoc[qDoc.id] = page.lastDoc;
              _hasMoreSlots[qDoc.id] = page.hasMore;
              _isLoadingMore[qDoc.id] = false;
              allSlots = page.slots;

              isBlocked =
                  allSlots.isNotEmpty && allSlots.every((s) => s.isBlocked);
              blockReason = isBlocked ? allSlots.first.blockReason : null;

              if (statsDoc.exists) {
                final sd = statsDoc.data() as Map<String, dynamic>;
                stats = QueueStats(
                  placesRestantes: (sd['available'] as int? ?? 0).clamp(
                    0,
                    99999,
                  ),
                  placesReservees: sd['reserved'] as int? ?? 0,
                  // Jour déjà passé : tous les créneaux sont derrière nous,
                  // plus personne n'est "en attente" de son passage.
                  personnesEnAttente: 0,
                  totalCreneaux: sd['totalSlots'] as int? ?? 0,
                  estBloquee: isBlocked,
                );
              } else {
                stats = _agenda.computeStats(allSlots, now: now);
              }
            } else {
              // ── Aujourd'hui ou date future : portion à venir tenue à jour
              //    en direct par un flux Firestore (plus de pagination ici,
              //    donc plus de reset de scroll possible) ──────────────────
              // Aujourd'hui, la limite entre « lu une fois » et « en direct »
              // est reculée de la durée max d'un créneau : un créneau EN
              // COURS au chargement reste ainsi suivi en direct (inscription,
              // suppression, annulation client s'y affichent aussitôt). Seuls
              // des créneaux forcément terminés sont lus une seule fois.
              final liveFrom = isToday
                  ? _latest(now.subtract(_maxSlotDuration), selectedDay)
                  : selectedDay;
              final pastFuture = isToday && liveFrom.isAfter(selectedDay)
                  ? _loadSlotPage(
                      qDoc.id,
                      startAfter: null,
                      endBefore: liveFrom,
                      limit: 200,
                    )
                  : null;
              final liveFuture = _subscribeLiveSlots(
                qDoc.id,
                selectedDay: selectedDay,
                startFrom: liveFrom,
              );

              _pastSlotsCache[qDoc.id] = pastFuture != null
                  ? (await pastFuture).slots
                  : const [];
              await liveFuture;
              _isLoadingMore[qDoc.id] = false;

              allSlots = [
                ...?_pastSlotsCache[qDoc.id],
                ...?_liveSlotsCache[qDoc.id],
              ];
              isBlocked =
                  allSlots.isNotEmpty && allSlots.every((s) => s.isBlocked);
              blockReason = isBlocked ? allSlots.first.blockReason : null;
              stats = _agenda.computeStats(allSlots, now: now);
            }

            final timeSlotCount = await tsCountFuture;

            final queueData = _QueueAgenda(
              id: qDoc.id,
              name: queueName,
              slots: allSlots,
              isBlocked: isBlocked,
              blockReason: blockReason,
              stats: stats,
              weekdays: weekdays,
              timeSlotCount: timeSlotCount,
              closureStart: (qData['closureStart'] as Timestamp?)?.toDate(),
              closureEnd: (qData['closureEnd'] as Timestamp?)?.toDate(),
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
        }),
      );

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
    DateTime? startFrom,
    DateTime? endBefore,
    int? limit,
  }) async {
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    final effectiveLimit = limit ?? _pageSize;

    Query query = _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .where(
          'start',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startFrom ?? dayStart),
        )
        .where('start', isLessThan: Timestamp.fromDate(endBefore ?? dayEnd))
        .orderBy('start')
        .limit(effectiveLimit);

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

    final slots = snap.docs
        .map((doc) => _agenda.slotFromDoc(doc, queueId: queueId))
        .toList();
    return _SlotPage(
      slots: slots,
      lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
      hasMore: snap.docs.length >= effectiveLimit,
    );
  }

  // ── Flux temps réel sur les créneaux à venir ──────────────────────────────
  // S'abonne aux créneaux d'une file à partir de [startFrom] jusqu'à la fin
  // de [selectedDay]. Résout dès le premier instantané (chargement initial),
  // puis continue d'écouter en arrière-plan : chaque changement ultérieur
  // (réservation, annulation, blocage, régénération de créneaux...) met à
  // jour uniquement la file concernée, sans toucher à la pagination.
  Future<void> _subscribeLiveSlots(
    String queueId, {
    required DateTime selectedDay,
    required DateTime startFrom,
  }) async {
    _liveSlotSubs.remove(queueId)?.cancel();

    final dayEnd = selectedDay.add(const Duration(days: 1));
    final query = _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(startFrom))
        .where('start', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('start')
        .limit(_liveSlotsCap);

    final completer = Completer<void>();
    _liveSlotSubs[queueId] = query.snapshots().listen(
      (snap) {
        _liveSlotsCache[queueId] = snap.docs
            .map((d) => _agenda.slotFromDoc(d, queueId: queueId))
            .toList();
        if (!completer.isCompleted) {
          completer.complete();
        } else {
          _rebuildQueueFromCache(queueId);
        }
      },
      onError: (Object e) {
        debugPrint('🔴 HouseNotifier: erreur flux créneaux $queueId: $e');
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    await completer.future;
  }

  // Reconstruit une seule file à partir des caches (passé + direct) et
  // notifie l'UI. Utilisé uniquement pour les mises à jour reçues *après*
  // le chargement initial d'une file (déjà présente dans _queues).
  void _rebuildQueueFromCache(String queueId) {
    // Un rechargement complet est en cours : il repartira lui-même des
    // caches à jour en fin de course, inutile (et risqué) de patcher ici.
    if (_isRefreshing) return;

    final idx = _queues.indexWhere((q) => q?.id == queueId);
    if (idx == -1) return;
    final old = _queues[idx]!;

    final allSlots = [
      ...?_pastSlotsCache[queueId],
      ...?_liveSlotsCache[queueId],
    ];
    final isBlocked = allSlots.isNotEmpty && allSlots.every((s) => s.isBlocked);
    final blockReason = isBlocked ? allSlots.first.blockReason : null;

    _queues[idx] = _QueueAgenda(
      id: old.id,
      name: old.name,
      slots: allSlots,
      isBlocked: isBlocked,
      blockReason: blockReason,
      stats: _agenda.computeStats(allSlots, now: DateTime.now()),
      weekdays: old.weekdays,
      timeSlotCount: old.timeSlotCount,
      closureStart: old.closureStart,
      closureEnd: old.closureEnd,
    );
    _notify();
  }

  // ── Flux temps réel sur le nombre de plages d'une file ────────────────────
  // Résout avec le premier instantané (chargement initial), puis met à jour
  // `timeSlotCount` de la file affichée à chaque création/suppression.
  Future<int> _subscribeTimeSlotCount(String queueId) {
    _tsCountSubs.remove(queueId)?.cancel();

    final query = _db
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('timeSlots')
        .limit(2);

    final completer = Completer<int>();
    _tsCountSubs[queueId] = query.snapshots().listen(
      (snap) {
        final count = snap.docs.length;
        if (!completer.isCompleted) {
          completer.complete(count);
          return;
        }
        // Un rechargement complet relira lui-même le compteur.
        if (_isRefreshing) return;
        final idx = _queues.indexWhere((q) => q?.id == queueId);
        if (idx == -1) return;
        final old = _queues[idx]!;
        if (old.timeSlotCount == count) return;
        _queues[idx] = _QueueAgenda(
          id: old.id,
          name: old.name,
          slots: old.slots,
          isBlocked: old.isBlocked,
          blockReason: old.blockReason,
          stats: old.stats,
          weekdays: old.weekdays,
          timeSlotCount: count,
          closureStart: old.closureStart,
          closureEnd: old.closureEnd,
        );
        _notify();
      },
      onError: (Object e) {
        debugPrint('🔴 HouseNotifier: erreur flux plages $queueId: $e');
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    return completer.future;
  }

  void _cancelLiveSlotSubs() {
    for (final sub in _liveSlotSubs.values) {
      sub.cancel();
    }
    _liveSlotSubs.clear();
    for (final sub in _tsCountSubs.values) {
      sub.cancel();
    }
    _tsCountSubs.clear();
    _pastSlotsCache.clear();
    _liveSlotsCache.clear();
  }

  // ── Utilitaire interne ────────────────────────────────────────────────────
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _staffStatusSub?.cancel();
    for (final sub in _liveSlotSubs.values) {
      sub.cancel();
    }
    for (final sub in _tsCountSubs.values) {
      sub.cancel();
    }
    for (final r in _pendingReverts.values) {
      r.expiryTimer?.cancel();
    }
    _pendingReverts.clear();
    super.dispose();
  }
}
