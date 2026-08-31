import 'package:geolocator/geolocator.dart';

import 'geo_address_service.dart';

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
