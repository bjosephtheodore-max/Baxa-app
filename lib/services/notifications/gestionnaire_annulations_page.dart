import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baxa/services/notifications/notification_service.dart';
import 'package:baxa/services/reservation_rules_service.dart';

/// Gestionnaire des annulations de réservations depuis les notifications
class CancellationHandler {
  static final CancellationHandler _instance = CancellationHandler._internal();
  factory CancellationHandler() => _instance;
  CancellationHandler._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialiser le gestionnaire d'annulation
  void initialize() {
    // Définir le callback pour les actions de notification
    NotificationService.onNotificationAction = _handleNotificationAction;
  }

  /// Gérer les actions de notification
  void _handleNotificationAction(String action, String? payload) {
    if (action == 'cancel_reservation' && payload != null) {
      // Extraire les données du payload
      final parts = payload.split('|');
      if (parts.length == 4) {
        final reservationId = parts[0];
        final companyId = parts[1];
        final queueId = parts[2];
        final slotId = parts[3];

        // Déclencher le flux d'annulation
        _initiateCancellation(
          reservationId: reservationId,
          companyId: companyId,
          queueId: queueId,
          slotId: slotId,
        );
      }
    } else if (action == 'keep_reservation') {
      // L'utilisateur garde sa réservation, ne rien faire
      debugPrint('Réservation conservée');
    }
  }

  /// Initier le processus d'annulation
  void _initiateCancellation({
    required String reservationId,
    required String companyId,
    required String queueId,
    required String slotId,
  }) {
    // Cette méthode sera appelée depuis la page de confirmation
    // On stocke les données pour qu'elles soient accessibles
    _pendingCancellation = PendingCancellation(
      reservationId: reservationId,
      companyId: companyId,
      queueId: queueId,
      slotId: slotId,
    );
  }

  PendingCancellation? _pendingCancellation;

  /// Récupérer l'annulation en attente
  PendingCancellation? getPendingCancellation() {
    final pending = _pendingCancellation;
    _pendingCancellation = null; // Nettoyer après récupération
    return pending;
  }

  /// Exécuter l'annulation de la réservation
  Future<CancellationResult> cancelReservation({
    required String companyId,
    required String queueId,
    required String slotId,
    required String reservationPath,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return CancellationResult(
        success: false,
        message: 'Utilisateur non connecté',
      );
    }

    try {
      // Annulation par le serveur (point unique, voir ReservationRulesService) :
      // il vérifie que la réservation appartient au client et est encore
      // active, puis libère la place.
      await ReservationRulesService().cancelReservation(
        companyId: companyId,
        reservationId: _firestore.doc(reservationPath).id,
        fromNotification: true,
      );

      // 5. Annuler toutes les notifications programmées pour cette réservation
      await NotificationService().cancelReservationNotifications();

      // 6. Envoyer la notification de remerciement
      await NotificationService().sendThankYouNotification();

      // 7. Sauvegarder dans l'historique des notifications
      await _saveThankYouToHistory(user.uid);

      return CancellationResult(
        success: true,
        message: 'Réservation annulée avec succès',
      );
    } catch (e) {
      return CancellationResult(
        success: false,
        message: e is BookingException
            ? e.message
            : 'Erreur lors de l\'annulation: $e',
      );
    }
  }

  /// Sauvegarder la notification de remerciement dans Firestore
  Future<void> _saveThankYouToHistory(String userId) async {
    try {
      await _firestore
          .collection('customers')
          .doc(userId)
          .collection('notifications')
          .add({
            'title': 'Merci d\'avoir prévenu 🙏',
            'body':
                'Tu aides à réduire le gaspillage et à mieux servir les autres.',
            'createdAt': FieldValue.serverTimestamp(),
            'type': 'thank_you',
            'payload': null,
          });
    } catch (e) {
      debugPrint('Erreur sauvegarde notification: $e');
    }
  }

  /// Rechercher une réservation active pour l'utilisateur
  Future<ReservationData?> findActiveReservation(String userId) async {
    try {
      final now = DateTime.now();

      final snapshot = await _firestore
          .collectionGroup('reservations')
          .where('customerId', isEqualTo: userId)
          .where('status', isEqualTo: 'confirmed')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final slotStart = (data['slotStart'] as Timestamp).toDate();

        // Vérifier si la réservation est dans le futur
        if (slotStart.isAfter(now)) {
          return ReservationData(
            reservationPath: doc.reference.path,
            companyId: data['companyId'] ?? '',
            queueId: data['queueId'] ?? '',
            slotId: data['slotId'] ?? '',
            queueName: data['queueName'] ?? 'File',
            slotStart: slotStart,
            slotEnd: (data['slotEnd'] as Timestamp).toDate(),
          );
        }
      }

      return null;
    } catch (e) {
      debugPrint('Erreur recherche réservation: $e');
      return null;
    }
  }
}

/// Données d'une annulation en attente
class PendingCancellation {
  final String reservationId;
  final String companyId;
  final String queueId;
  final String slotId;

  PendingCancellation({
    required this.reservationId,
    required this.companyId,
    required this.queueId,
    required this.slotId,
  });
}

/// Résultat d'une tentative d'annulation
class CancellationResult {
  final bool success;
  final String message;

  CancellationResult({required this.success, required this.message});
}

/// Données d'une réservation
class ReservationData {
  final String reservationPath;
  final String companyId;
  final String queueId;
  final String slotId;
  final String queueName;
  final DateTime slotStart;
  final DateTime slotEnd;

  ReservationData({
    required this.reservationPath,
    required this.companyId,
    required this.queueId,
    required this.slotId,
    required this.queueName,
    required this.slotStart,
    required this.slotEnd,
  });
}
