import 'dart:ui' show Locale;

import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:geocoding/geocoding.dart';

/// ============================================================
/// SERVICE PARTAGÉ — GÉOCODAGE (direct & inverse)
///
/// Transforme des coordonnées OU un texte d'adresse en une adresse
/// normalisée exploitable partout dans le monde : position GPS, adresse
/// lisible, et surtout `region` + `country` / `countryCode` — les deux
/// informations qui manquaient pour un usage hors Afrique de l'Ouest
/// (adresses ambiguës) et pour filtrer la recherche par pays.
///
/// Aucune API externe : s'appuie sur le géocodeur natif Android / Apple.
/// Aucune méthode ne lève d'exception (retourne `null` en cas d'échec).
/// ============================================================
class GeoAddressService {
  GeoAddressService({this.locale = const Locale('fr', 'FR')});

  /// Langue des libellés retournés (nom du pays, de la région…).
  /// N'affecte pas `countryCode`, qui reste un code ISO stable.
  final Locale? locale;

  final Geocoding _geocoding = Geocoding();

  /// Géocodage inverse : coordonnées → adresse structurée.
  Future<GeoAddress?> fromCoordinates(double latitude, double longitude) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
        locale: locale,
      );
      if (placemarks.isEmpty) return null;
      return GeoAddress._fromPlacemark(
        placemarks.first,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      return null;
    }
  }

  /// Géocodage direct : texte libre → position + adresse structurée.
  ///
  /// Sert quand la structure ne peut pas capturer sa position sur place
  /// (inscription à distance, GPS imprécis, correction manuelle). Retourne
  /// `null` si l'adresse n'a pas pu être résolue en un point.
  Future<GeoAddress?> fromAddress(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    try {
      final locations = await _geocoding.locationFromAddress(q, locale: locale);
      if (locations.isEmpty) return null;
      final loc = locations.first;

      // Complète avec le découpage administratif (pays, région, ville…)
      // via un géocodage inverse sur le point trouvé.
      final detailed = await fromCoordinates(loc.latitude, loc.longitude);
      return detailed ??
          GeoAddress(latitude: loc.latitude, longitude: loc.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// Résultat normalisé d'un géocodage.
class GeoAddress {
  const GeoAddress({
    this.street,
    this.ville,
    this.region,
    this.country,
    this.countryCode,
    this.postalCode,
    this.latitude,
    this.longitude,
  });

  /// Rue + quartier ("Rue 10, Almadies").
  final String? street;

  /// Ville / localité.
  final String? ville;

  /// État, région ou province (`administrativeArea`).
  final String? region;

  /// Nom du pays, dans la langue de l'app ("Sénégal", "France").
  final String? country;

  /// Code pays ISO 3166-1 alpha-2, en MAJUSCULES ("SN", "FR").
  final String? countryCode;

  final String? postalCode;
  final double? latitude;
  final double? longitude;

  bool get hasPosition => latitude != null && longitude != null;

  GeoPoint? get position =>
      hasPosition ? GeoPoint(latitude!, longitude!) : null;

  /// Adresse lisible la plus complète possible, sans doublons ni segments
  /// vides ("Rue 10, Almadies, Dakar, Sénégal").
  String get formatted {
    final parts = <String>[];
    for (final segment in [street, ville, region, country]) {
      final v = segment?.trim();
      if (v != null && v.isNotEmpty && !parts.contains(v)) parts.add(v);
    }
    return parts.join(', ');
  }

  static GeoAddress? _fromPlacemark(
    Placemark p, {
    double? latitude,
    double? longitude,
  }) {
    final street = [p.street, p.subLocality]
        .map((s) => s?.trim())
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toSet()
        .join(', ');
    final iso = p.isoCountryCode?.trim().toUpperCase();

    final address = GeoAddress(
      street: street.isEmpty ? null : street,
      ville: _clean(p.locality) ?? _clean(p.subAdministrativeArea),
      region: _clean(p.administrativeArea),
      country: _clean(p.country),
      countryCode: (iso == null || iso.isEmpty) ? null : iso,
      postalCode: _clean(p.postalCode),
      latitude: latitude,
      longitude: longitude,
    );

    // Un placemark totalement vide n'apporte rien.
    if (address.formatted.isEmpty && !address.hasPosition) return null;
    return address;
  }

  static String? _clean(String? s) {
    final v = s?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}
