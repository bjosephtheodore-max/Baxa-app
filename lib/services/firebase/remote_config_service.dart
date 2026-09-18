import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Accès centralisé à Firebase Remote Config (flags et réglages pilotables
/// à distance, sans passer par une mise à jour de l'app).
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  final _remoteConfig = FirebaseRemoteConfig.instance;

  Future<void> init() async {
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 1),
      ),
    );
    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      // Pas de réseau ou erreur de fetch : on continue avec les valeurs
      // par défaut (ou celles du dernier fetch réussi, mises en cache).
      debugPrint('Remote Config fetch: $e');
    }
  }

  bool getBool(String key) => _remoteConfig.getBool(key);
  String getString(String key) => _remoteConfig.getString(key);
  int getInt(String key) => _remoteConfig.getInt(key);
  double getDouble(String key) => _remoteConfig.getDouble(key);
}
