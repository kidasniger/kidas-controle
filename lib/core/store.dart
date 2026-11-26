import 'package:flutter/services.dart' show PlatformException;

import 'native.dart';

/// Stockage hybride :
/// - préférences ordinaires dans SharedPreferences Android,
/// - secrets dans un coffre AES-GCM natif dont la clé reste dans Android Keystore.
///
/// Le coffre utilise une clé AES symétrique. Une erreur du Keystore ne
/// déclenche jamais de réinitialisation automatique : les données chiffrées
/// restent conservées et l'application peut continuer en mode dégradé.
class Store {
  static const Set<String> _secureKeys = {'gh_token'};

  static bool _degraded = false;
  static bool _vaultReset = false;
  static String? _lastError;
  static final Map<String, String> _session = {};

  static bool get isDegraded => _degraded;
  static String? get lastError => _lastError;

  /// Conservé pour compatibilité avec l'interface de démarrage.
  /// Le coffre n'effectue plus aucune réinitialisation automatique.
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
      String? value;
      Object? failure;
      // Trois lectures bornées pour absorber une indisponibilité transitoire
      // du canal natif/Keystore, sans jamais réinitialiser le coffre.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          value = await Native.secureGet(key);
          failure = null;
          break;
        } catch (error) {
          failure = error;
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
          }
        }
      }
      if (failure != null) throw failure;
      var saved = value ?? '';

      // Migration non destructive de l'ancien coffre v1 : l'ancienne entrée
      // n'est jamais supprimée, même après copie réussie dans le coffre AES-GCM.
      if (key == 'gh_token' && saved.isEmpty) {
        try {
          final legacyKeys = await Native.legacyKeys();
          if (legacyKeys.contains(key)) {
            final legacy = await Native.legacyGet(key);
            if (legacy != null && legacy.isNotEmpty) {
              try {
                await Native.secureSet(key, legacy);
                final verified = await Native.secureGet(key);
                if (verified != legacy) {
                  throw StateError('Migration du jeton non confirmée.');
                }
                saved = legacy;
              } catch (error) {
                // Le jeton historique reste utilisable en mémoire pour cette
                // session, sans prétendre que sa migration est persistée.
                _session[key] = legacy;
                _markDegraded(error);
                return legacy;
              }
            }
          }
        } catch (error) {
          _lastError = error.toString();
        }
      }

      _session[key] = saved;
      _degraded = false;
      _lastError = null;
      return saved;
    } on PlatformException catch (error) {
      // Une indisponibilité du Keystore n'est pas une absence de token.
      // Garder la dernière valeur de session et surtout ne jamais l'effacer.
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
