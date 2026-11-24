import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'native.dart';

/// Stockage hybride :
/// - préférences ordinaires dans SharedPreferences Android (sans Keystore),
/// - secrets uniquement dans flutter_secure_storage.
class Store {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: false,
      resetOnError: false,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
  );

  /// Seul le jeton d'accès GitHub est un secret dans les clés Store actuelles.
  static const Set<String> _secureKeys = {'gh_token'};

  static bool _degraded = false;
  static String? _lastError;
  static final Map<String, String> _session = {};

  /// Indique que le coffre des secrets est indisponible.
  /// Les préférences ordinaires restent persistées par Android.
  static bool get isDegraded => _degraded;
  static String? get lastError => _lastError;

  static bool _isSecure(String key) => _secureKeys.contains(key);

  static void _markDegraded(Object error) {
    _degraded = true;
    _lastError = error.toString();
  }

  static Future<String> get(String key) async {
    if (!_isSecure(key)) {
      try {
        final local = await Native.localGet(key);
        if (local != null) {
          _session[key] = local;
          return local;
        }
      } catch (error) {
        _lastError = error.toString();
      }
    }

    try {
      final value = await _s.read(key: key);
      if (value != null) {
        _session[key] = value;
        // Migration transparente des anciennes préférences qui étaient
        // auparavant stockées à tort dans le coffre sécurisé.
        if (!_isSecure(key)) {
          try {
            await Native.localSet(key, value);
          } catch (_) {}
        }
        return value;
      }
      return _session[key] ?? '';
    } catch (error) {
      _markDegraded(error);
      return _session[key] ?? '';
    }
  }

  static Future<void> set(String key, String value) async {
    if (!_isSecure(key)) {
      final saved = await Native.localSet(key, value);
      if (!saved || await Native.localGet(key) != value) {
        throw StateError('Android n’a pas confirmé la sauvegarde de "$key".');
      }
      _session[key] = value;
      return;
    }

    try {
      await _s.write(key: key, value: value);
      final verified = await _s.read(key: key);
      if (verified != value) {
        throw StateError('Le coffre sécurisé n’a pas confirmé la sauvegarde de "$key".');
      }
      _session[key] = value;
      _degraded = false;
      _lastError = null;
    } catch (error) {
      _markDegraded(error);
      rethrow;
    }
  }

  static Future<void> del(String key) async {
    if (!_isSecure(key)) {
      final saved = await Native.localDel(key);
      if (!saved) {
        throw StateError('Android n’a pas confirmé la suppression de "$key".');
      }
      _session.remove(key);
      return;
    }

    try {
      await _s.delete(key: key);
      _session.remove(key);
      _degraded = false;
      _lastError = null;
    } catch (error) {
      _markDegraded(error);
      rethrow;
    }
  }

  static Future<Map<String, String>> all() async {
    Map<String, String> local = {};
    try {
      local = await Native.localAll();
      _session.addAll(local);
    } catch (error) {
      _lastError = error.toString();
    }

    try {
      final secure = await _s.readAll();
      // Les anciennes versions plaçaient les préférences ordinaires dans
      // le coffre. Les migrer une à une vers le stockage local Android.
      for (final entry in secure.entries) {
        if (!_isSecure(entry.key) && local[entry.key] == null) {
          try {
            if (await Native.localSet(entry.key, entry.value)) {
              local[entry.key] = entry.value;
            }
          } catch (_) {}
        }
      }
      _session.addAll(secure);
      _degraded = false;
      _lastError = null;
      return {...secure, ...local, ..._session};
    } catch (error) {
      _markDegraded(error);
      return {...local, ..._session};
    }
  }
}
