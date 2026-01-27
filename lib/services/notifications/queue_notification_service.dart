import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_models.dart';

class QueueNotificationService {
  static final QueueNotificationService _instance =
      QueueNotificationService._internal();
  factory QueueNotificationService() => _instance;
  QueueNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, QueueState> _activeQueues = {};
  final Map<String, StreamSubscription> _slotSubscriptions = {};
  final Map<String, Timer> _subSlotTimers = {};

  String? _companyId;
  bool _initialized = false;

  // Configuration
  static const int _subSlotDurationMinutes = 15; // Paramétrable par entreprise
  static const int _maxActiveQueues = 2; // MVP limit

  /// Initialiser le service
  Future<void> initialize() async {
    if (_initialized) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _companyId = user.uid;

    // Configuration Android
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // Configuration iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    await _loadActiveQueues();
  }

  /// Charger les queues actives depuis Firestore
  Future<void> _loadActiveQueues() async {
    if (_companyId == null) return;

    try {
      final now = DateTime.now().toUtc();

      // Récupérer toutes les queues
      final queuesSnap = await _firestore
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .get();

      for (final queueDoc in queuesSnap.docs) {
        if (_activeQueues.length >= _maxActiveQueues) break;

        final queueData = queueDoc.data();
        final queueId = queueDoc.id;
        final queueName = queueData['name'] ?? 'File';

        // Trouver le slot actif (en cours)
        final slotsSnap = await _firestore
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .doc(queueId)
            .collection('slots')
            .where('start', isLessThanOrEqualTo: now)
            .where('end', isGreaterThan: now)
            .where('status', isEqualTo: 'open')
            .limit(1)
            .get();

        if (slotsSnap.docs.isNotEmpty) {
          final slotDoc = slotsSnap.docs.first;
          await _startQueueMonitoring(queueId, queueName, slotDoc);
        }
      }
    } catch (e) {
      print('Erreur chargement queues actives: $e');
    }
  }

  /// Démarrer le monitoring d'une queue
  Future<void> _startQueueMonitoring(
    String queueId,
    String queueName,
    QueryDocumentSnapshot slotDoc,
  ) async {
    if (_companyId == null) return;

    final slotData = slotDoc.data() as Map<String, dynamic>;
    final slotId = slotDoc.id;
    final slotStart = (slotData['start'] as Timestamp).toDate();
    final slotEnd = (slotData['end'] as Timestamp).toDate();

    // Créer l'état de la queue
    final notifId = queueId.hashCode % 1000 + 1000; // ID stable par queue

    final queueState = QueueState(
      queueId: queueId,
      queueName: queueName,
      slotId: slotId,
      slotStart: slotStart,
      slotEnd: slotEnd,
      totalReservations: slotData['reserved'] ?? 0,
      totalCancellations: 0, // À récupérer depuis un compteur si disponible
      notificationId: notifId,
    );

    _activeQueues[queueId] = queueState;

    // Écouter les changements du slot
    _listenToSlot(queueId, slotId);

    // Démarrer le timer des SubSlots
    _startSubSlotTimer(queueId);

    // Envoyer la première notification
    await _updateNotification(queueState);
  }

  /// Écouter les changements d'un slot (réservations/annulations)
  void _listenToSlot(String queueId, String slotId) {
    if (_companyId == null) return;

    final subscription = _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(queueId)
        .collection('slots')
        .doc(slotId)
        .snapshots()
        .listen((snapshot) async {
          if (!snapshot.exists) return;

          final data = snapshot.data()!;
          final queueState = _activeQueues[queueId];
          if (queueState == null) return;

          // Mettre à jour les compteurs
          queueState.totalReservations = data['reserved'] ?? 0;
          // totalCancellations devrait venir d'un champ dans le slot
          queueState.totalCancellations = data['cancelled'] ?? 0;

          // Vérifier si on doit mettre à jour la notification
          if (queueState.shouldUpdateForReservations() ||
              queueState.shouldUpdateForCancellations()) {
            await _updateNotification(queueState);
            queueState.markNotified();
          }
        });

    _slotSubscriptions[queueId] = subscription;
  }

  /// Démarrer le timer pour les SubSlots
  void _startSubSlotTimer(String queueId) {
    final queueState = _activeQueues[queueId];
    if (queueState == null) return;

    // Calculer le prochain SubSlot
    _updateCurrentSubSlot(queueState);

    // Timer périodique
    final timer = Timer.periodic(Duration(minutes: _subSlotDurationMinutes), (
      _,
    ) async {
      _updateCurrentSubSlot(queueState);
      await _updateNotification(queueState);
      queueState.markNotified();

      // Vérifier si la plage est terminée
      if (DateTime.now().isAfter(queueState.slotEnd)) {
        await _endQueue(queueId);
      }
    });

    _subSlotTimers[queueId] = timer;
  }

  /// Mettre à jour le SubSlot actuel
  void _updateCurrentSubSlot(QueueState queueState) {
    final now = DateTime.now();
    final start = queueState.slotStart;
    final end = queueState.slotEnd;

    // Calculer tous les SubSlots
    final subSlots = _generateSubSlots(start, end);

    // Trouver le SubSlot actuel
    for (final subSlot in subSlots) {
      if (now.isAfter(subSlot.startTime) && now.isBefore(subSlot.endTime)) {
        queueState.currentSubSlot = subSlot;
        return;
      }
    }

    // Si aucun trouvé, prendre le dernier
    if (subSlots.isNotEmpty) {
      queueState.currentSubSlot = subSlots.last;
    }
  }

  /// Générer les SubSlots à partir d'une plage horaire
  List<SubSlot> _generateSubSlots(DateTime start, DateTime end) {
    final subSlots = <SubSlot>[];
    var current = start;

    while (current.isBefore(end)) {
      final subSlotEnd = current.add(
        Duration(minutes: _subSlotDurationMinutes),
      );

      if (subSlotEnd.isAfter(end)) break;

      subSlots.add(SubSlot(startTime: current, endTime: subSlotEnd));

      current = subSlotEnd;
    }

    return subSlots;
  }

  /// Mettre à jour ou créer la notification "en cours"
  Future<void> _updateNotification(QueueState queueState) async {
    final subSlot = queueState.currentSubSlot;
    if (subSlot == null) return;

    final title =
        '${queueState.queueName} (${_formatTime(queueState.slotStart)}–${_formatTime(queueState.slotEnd)})';
    final body =
        '${queueState.remainingPeople} personnes restantes\n'
        'En cours : ${subSlot.timeRange} (${queueState.totalReservations})';

    const androidDetails = AndroidNotificationDetails(
      'queue_active',
      'Files actives',
      channelDescription: 'Notifications des files d\'attente en cours',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: false, // Pas persistante
      autoCancel: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: 'queue_active',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(queueState.notificationId, title, body, details);
  }

  /// Terminer une queue et envoyer la notification de synthèse
  Future<void> _endQueue(String queueId) async {
    final queueState = _activeQueues[queueId];
    if (queueState == null) return;

    // Annuler la notification "en cours"
    await _notifications.cancel(queueState.notificationId);

    // Créer la notification de synthèse
    await _sendSummaryNotification(queueState);

    // Sauvegarder dans l'historique
    await _saveToHistory(queueState);

    // Nettoyer
    await _slotSubscriptions[queueId]?.cancel();
    _slotSubscriptions.remove(queueId);
    _subSlotTimers[queueId]?.cancel();
    _subSlotTimers.remove(queueId);
    _activeQueues.remove(queueId);
  }

  /// Envoyer la notification de synthèse
  Future<void> _sendSummaryNotification(QueueState queueState) async {
    final servedEstimate =
        queueState.totalReservations - queueState.totalCancellations;

    final title =
        '${queueState.queueName} (${_formatTime(queueState.slotStart)}–${_formatTime(queueState.slotEnd)}) — Terminé';
    final body =
        'Total réservations : ${queueState.totalReservations}\n'
        'Annulations : ${queueState.totalCancellations}\n'
        'Servis estimés : $servedEstimate';

    const androidDetails = AndroidNotificationDetails(
      'queue_summary',
      'Résumés de files',
      channelDescription: 'Notifications de synthèse des files terminées',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Utiliser un nouvel ID unique
    final summaryId = DateTime.now().millisecondsSinceEpoch % 100000;

    await _notifications.show(summaryId, title, body, details);
  }

  /// Sauvegarder dans l'historique Firestore
  Future<void> _saveToHistory(QueueState queueState) async {
    if (_companyId == null) return;

    final servedEstimate =
        queueState.totalReservations - queueState.totalCancellations;

    final history = NotificationHistory(
      id: '', // Firestore générera l'ID
      queueId: queueState.queueId,
      queueName: queueState.queueName,
      slotId: queueState.slotId,
      slotStart: queueState.slotStart,
      slotEnd: queueState.slotEnd,
      totalReservations: queueState.totalReservations,
      totalCancellations: queueState.totalCancellations,
      servedEstimate: servedEstimate,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('notificationsHistory')
        .add(history.toFirestore());
  }

  /// Gestion du clic sur notification
  void _onNotificationTapped(NotificationResponse response) {
    // Navigation vers la queue concernée
    // À implémenter selon votre système de navigation
    print('Notification cliquée: ${response.payload}');
  }

  /// Nettoyer toutes les ressources
  Future<void> dispose() async {
    for (final sub in _slotSubscriptions.values) {
      await sub.cancel();
    }
    for (final timer in _subSlotTimers.values) {
      timer.cancel();
    }
    _slotSubscriptions.clear();
    _subSlotTimers.clear();
    _activeQueues.clear();
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
