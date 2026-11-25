import 'package:flutter/services.dart' show PlatformException;

import 'native.dart';

/// Stockage hybride :
/// - préférences ordinaires dans SharedPreferences Android,
/// - secrets dans un coffre AES-GCM natif dont la clé reste dans Android Keystore.
///
/// Le coffre utilise une clé AES symétrique. Si le Keystore rend cette clé
/// inutilisable (mise à jour du système, restauration…), le coffre natif se
/// réinitialise tout seul : le secret est perdu (il faut ressaisir le jeton
/// GitHub) mais l'application ne reste jamais bloquée sur une erreur.
class Store {
  static const Set<String> _secureKeys = {'gh_token'};

  static bool _degraded = false;
  static bool _vaultReset = false;
  static String? _lastError;
  static final Map<String, String> _session = {};

  static bool get isDegraded => _degraded;
  static String? get lastError => _lastError;

  /// Vrai quand le coffre a dû être réinitialisé (clé Keystore inutilisable) :
  /// le jeton GitHub doit être ressaisi dans Réglages.
  static bool get vaultReset => _vaultReset;

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
      return _session[key] ?? '';
    }

    try {
      final value = await Native.secureGet(key);
      _session[key] = value;
      _degraded = false;
      _lastError = null;
      return value;
    } on PlatformException catch (error) {
      if (error.code == 'secure_reset') {
        // Coffre réinitialisé côté natif : le secret est perdu,
        // l'application continue de fonctionner normalement.
        _vaultReset = true;
        _session.remove(key);
        return '';
      }
      _markDegraded(error);
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
      await Native.secureSet(key, value);
      final verified = await Native.secureGet(key);
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
      await Native.secureDel(key);
      _session.remove(key);
      _degraded = false;
      _lastError = null;
    } catch (error) {
      _markDegraded(error);
      rethrow;
    }
  }

  static Future<Map<String, String>> all() async {
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
