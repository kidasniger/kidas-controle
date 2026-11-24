import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'native.dart';

/// Stockage hybride :
/// - préférences ordinaires dans SharedPreferences Android (sans Keystore),
/// - secrets uniquement dans flutter_secure_storage.
class Store {
  static const _s = FlutterSecureStorage(
    // Le verrouillage biométrique de l'application est géré séparément
    // par local_auth. Le coffre du token utilise donc le chiffrement Android
    // standard RSA-OAEP + AES-GCM, sans clé liée à une authentification
    // biométrique par opération.
    aOptions: AndroidOptions(
      resetOnError: true,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
  );

  /// Seul le jeton d'accès GitHub est un secret dans les clés Store actuelles.
  static const Set<String> _secureKeys = {'gh_token'};

  /// Clés historiques à récupérer individuellement si readAll() du coffre
  /// échoue sur un appareil dont le Keystore est partiellement dégradé.
  static const Set<String> _legacyPreferenceKeys = {
    'onb',
    'theme_mode',
    'cfg_data',
    'cfg_mgr',
    'cfg_exp',
    'sons',
    'notifs_on',
    'notifs_jeton',
    'notifs_urgents',
    'upd_auto',
    'regles_saved_at',
  };

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
    // Depuis v229, toutes les préférences ordinaires sont dans le stockage
    // local Android. Ne pas appeler readAll() ici : cela forcerait la
    // migration du coffre secret au démarrage et pourrait bloquer toute l'UI.
    try {
      final local = await Native.localAll();
      _session.addAll(local);
      return {...local, ..._session};
    } catch (error) {
      _lastError = error.toString();
      return Map<String, String>.from(_session);
    }
  }
}
