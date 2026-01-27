import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle pour un créneau interne (SubSlot) calculé en mémoire
class SubSlot {
  final DateTime startTime;
  final DateTime endTime;
  final int reservationsCount;

  SubSlot({
    required this.startTime,
    required this.endTime,
    this.reservationsCount = 0,
  });

  String get timeRange => '${_formatTime(startTime)}–${_formatTime(endTime)}';

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// État d'une queue active avec ses compteurs
class QueueState {
  final String queueId;
  final String queueName;
  final String slotId;
  final DateTime slotStart;
  final DateTime slotEnd;

  int totalReservations;
  int totalCancellations;
  int lastNotifiedReservations;
  int lastNotifiedCancellations;

  SubSlot? currentSubSlot;
  int notificationId;

  QueueState({
    required this.queueId,
    required this.queueName,
    required this.slotId,
    required this.slotStart,
    required this.slotEnd,
    this.totalReservations = 0,
    this.totalCancellations = 0,
    this.lastNotifiedReservations = 0,
    this.lastNotifiedCancellations = 0,
    this.currentSubSlot,
    required this.notificationId,
  });

  int get remainingPeople => totalReservations - totalCancellations;

  bool shouldUpdateForReservations() {
    return (totalReservations - lastNotifiedReservations) >= 5;
  }

  bool shouldUpdateForCancellations() {
    return (totalCancellations - lastNotifiedCancellations) >= 3;
  }

  void markNotified() {
    lastNotifiedReservations = totalReservations;
    lastNotifiedCancellations = totalCancellations;
  }
}

/// Modèle pour l'historique des notifications de synthèse
class NotificationHistory {
  final String id;
  final String queueId;
  final String queueName;
  final String slotId;
  final DateTime slotStart;
  final DateTime slotEnd;
  final int totalReservations;
  final int totalCancellations;
  final int servedEstimate;
  final DateTime createdAt;

  NotificationHistory({
    required this.id,
    required this.queueId,
    required this.queueName,
    required this.slotId,
    required this.slotStart,
    required this.slotEnd,
    required this.totalReservations,
    required this.totalCancellations,
    required this.servedEstimate,
    required this.createdAt,
  });

  factory NotificationHistory.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return NotificationHistory(
      id: id,
      queueId: data['queueId'] ?? '',
      queueName: data['queueName'] ?? '',
      slotId: data['slotId'] ?? '',
      slotStart: (data['slotStart'] as Timestamp).toDate(),
      slotEnd: (data['slotEnd'] as Timestamp).toDate(),
      totalReservations: data['totalReservations'] ?? 0,
      totalCancellations: data['totalCancellations'] ?? 0,
      servedEstimate: data['servedEstimate'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'queueId': queueId,
      'queueName': queueName,
      'slotId': slotId,
      'slotStart': Timestamp.fromDate(slotStart),
      'slotEnd': Timestamp.fromDate(slotEnd),
      'totalReservations': totalReservations,
      'totalCancellations': totalCancellations,
      'servedEstimate': servedEstimate,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
