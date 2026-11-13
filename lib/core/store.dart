import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'native.dart';

/// Stockage clé/valeur chiffré (Keystore via flutter_secure_storage).
/// À la première ouverture, récupère les valeurs de la v1 Java
/// (AES-GCM maison dans SharedPreferences) pour une mise à jour sans perte.
class Store {
  static const _s = FlutterSecureStorage();

  static bool _migrated = false;

  static Future<void> _ensure() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final keys = await Native.legacyKeys();
      for (final k in keys) {
        final old = await Native.legacyGet(k);
        if (old == null || old.isEmpty) continue;
        if (await _s.read(key: k) == null) {
          await _s.write(key: k, value: old);
        }
      }
    } catch (_) {
      // migration facultative : rien à faire en cas d'échec
    }
  }

  static Future<String> get(String k) async {
    await _ensure();
    return await _s.read(key: k) ?? '';
  }

  static Future<void> set(String k, String v) async {
    await _ensure();
    await _s.write(key: k, value: v);
  }

  static Future<void> del(String k) async {
    await _ensure();
    await _s.delete(key: k);
  }

  static Future<Map<String, String>> all() async {
    await _ensure();
    return (await _s.readAll()) ?? <String, String>{};
  }
}
