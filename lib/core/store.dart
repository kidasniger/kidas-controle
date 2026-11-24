import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'native.dart';

/// Stockage chiffré. Android utilise une clé AES directement dans Keystore
/// (sans génération de paire RSA), avec migration sauvegardée depuis l'ancien
/// chiffrement RSA/AES du plugin.
class Store {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: false,
      resetOnError: false,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
  );

  static bool _migrated = false;
  static bool _degraded = false;
  static String? _lastError;
  static final Map<String, String> _session = {};

  /// Indique que le coffre sécurisé est momentanément indisponible.
  /// Dans ce cas, les changements restent uniquement en mémoire.
  static bool get isDegraded => _degraded;
  static String? get lastError => _lastError;

  static void _markDegraded(Object error) {
    _degraded = true;
    _lastError = error.toString();
  }

  static Future<void> _ensure() async {
    if (_migrated) return;
    try {
      final keys = await Native.legacyKeys();
      for (final k in keys) {
        final old = await Native.legacyGet(k);
        if (old == null || old.isEmpty) continue;
        if (await _s.read(key: k) == null) {
          await _s.write(key: k, value: old);
        }
      }
      _migrated = true;
    } catch (error) {
      // Ne jamais effacer le stockage en cas d'erreur Keystore.
      _markDegraded(error);
      _migrated = true;
    }
  }

  static Future<String> get(String k) async {
    await _ensure();
    try {
      final value = await _s.read(key: k);
      if (value != null) {
        _session[k] = value;
        return value;
      }
      return _session[k] ?? '';
    } catch (error) {
      _markDegraded(error);
      return _session[k] ?? '';
    }
  }

  static Future<void> set(String k, String v) async {
    await _ensure();
    _session[k] = v;
    try {
      await _s.write(key: k, value: v);
    } catch (error) {
      _markDegraded(error);
    }
  }

  static Future<void> del(String k) async {
    await _ensure();
    _session.remove(k);
    try {
      await _s.delete(key: k);
    } catch (error) {
      _markDegraded(error);
    }
  }

  static Future<Map<String, String>> all() async {
    await _ensure();
    try {
      final values = await _s.readAll();
      _session.addAll(values);
      return {...values, ..._session};
    } catch (error) {
      _markDegraded(error);
      return Map<String, String>.from(_session);
    }
  }
}
