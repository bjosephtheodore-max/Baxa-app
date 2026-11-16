import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'geo_address_service.dart';

/// Pourquoi une position précise n'a pas pu être obtenue.
enum LocationFailure {
  /// Autorisation refusée (Android peut encore la redemander).
  denied,

  /// Autorisation refusée définitivement : seuls les réglages du
  /// téléphone permettent de l'accorder.
  deniedForever,

  /// Localisation du téléphone désactivée.
  serviceOff,

  /// Aucune mesure obtenue dans le temps imparti.
  unavailable,
}

/// Résultat de [LocationService.getPrecisePosition] : une position, ou la
/// raison de l'échec.
class PreciseLocationResult {
  final Position? position;
  final LocationFailure? failure;
  const PreciseLocationResult.ok(Position this.position) : failure = null;
  const PreciseLocationResult.failed(LocationFailure this.failure)
    : position = null;
}

/// ============================================================
/// SERVICE PARTAGÉ — GÉOLOCALISATION
/// Utilisé côté client (tri des résultats par proximité) et côté
/// entreprise (capture de la position dans les réglages).
/// ============================================================
class LocationService {
  /// Statut actuel de la permission, sans en déclencher la demande.
  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  /// Déclenche la demande système de permission de localisation.
  Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }

  /// Le GPS/service de localisation est-il activé au niveau du téléphone
  /// (indépendant de la permission accordée à l'app) ?
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Position actuelle, ou `null` si la permission ou le service ne le
  /// permettent pas (jamais d'exception levée). La permission est toujours
  /// demandée en premier, pour que la boîte de dialogue système apparaisse
  /// même si le GPS est éteint au moment de l'appel.
  Future<Position?> getCurrentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      if (!await Geolocator.isLocationServiceEnabled()) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Position PRÉCISE, pour enregistrer l'emplacement d'une structure (une
  /// fois pour toutes, tous ses clients s'y fient). Contrairement à
  /// [getCurrentPosition] (précision « moyenne » : wifi / antennes, ~100 m,
  /// souvent une position déjà en mémoire), on écoute le GPS en haute
  /// précision et on garde la meilleure mesure fraîche : arrêt dès qu'elle
  /// atteint [targetAccuracyMeters], ou au bout de [maxWait].
  Future<PreciseLocationResult> getPrecisePosition({
    double targetAccuracyMeters = 20,
    Duration maxWait = const Duration(seconds: 10),
  }) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const PreciseLocationResult.failed(
          LocationFailure.deniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const PreciseLocationResult.failed(LocationFailure.denied);
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const PreciseLocationResult.failed(LocationFailure.serviceOff);
      }

      // Mesures plus anciennes que le début de la recherche (position
      // gardée en mémoire par le téléphone) : ignorées.
      final startedAt = DateTime.now().subtract(const Duration(seconds: 2));
      Position? best;
      final done = Completer<void>();
      final sub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 0,
            ),
          ).listen(
            (p) {
              if (p.timestamp.isBefore(startedAt)) return;
              if (best == null || p.accuracy < best!.accuracy) best = p;
              if (p.accuracy <= targetAccuracyMeters && !done.isCompleted) {
                done.complete();
              }
            },
            onError: (_) {
              if (!done.isCompleted) done.complete();
            },
          );
      await Future.any([done.future, Future<void>.delayed(maxWait)]);
      await sub.cancel();

      // Rien reçu du flux : une dernière mesure directe en haute précision.
      if (best == null) {
        try {
          best = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 8),
            ),
          );
        } catch (_) {}
      }

      final found = best;
      return found == null
          ? const PreciseLocationResult.failed(LocationFailure.unavailable)
          : PreciseLocationResult.ok(found);
    } catch (_) {
      return const PreciseLocationResult.failed(LocationFailure.unavailable);
    }
  }

  /// Ouvre la page de Baxa dans les réglages du téléphone (autorisations).
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Ouvre les réglages de localisation du téléphone.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Demande la permission de localisation (si besoin) puis renvoie le
  /// code pays ISO 3166-1 alpha-2 (MAJUSCULES) du lieu où se trouve
  /// l'utilisateur. Renvoie `null` si la permission est refusée, le GPS
  /// éteint ou le géocodage impossible. Ne lève jamais d'exception.
  ///
  /// Sert à fiabiliser le pays du client (filtrage de la recherche) au
  /// moment de l'inscription, quand la locale du téléphone ne suffit pas.
  Future<String?> currentCountryCode() async {
    final pos = await getCurrentPosition();
    if (pos == null) return null;
    final geo = await GeoAddressService().fromCoordinates(
      pos.latitude,
      pos.longitude,
    );
    final code = geo?.countryCode;
    return (code != null && code.isNotEmpty) ? code : null;
  }

  /// Distance affichée au client (« à … »). Un GPS de téléphone n'est
  /// précis qu'à 5–20 m : sous 50 m on dit « moins de 50 m » plutôt qu'un
  /// faux « 9 m » ; jusqu'à 1 km, arrondi à la dizaine ; au-delà, en km.
  static String formatDistance(double km) {
    final meters = km * 1000;
    if (meters < 50) return 'moins de 50 m';
    if (meters < 1000) {
      final rounded = (meters / 10).round() * 10;
      return rounded >= 1000 ? '1.0 km' : '$rounded m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  /// Distance en kilomètres entre deux coordonnées.
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }
}
