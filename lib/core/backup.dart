import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// Sauvegarde versionnée des préférences non sensibles.
/// Les jetons et secrets sont volontairement exclus.
class AppBackup {
  static const formatVersion = 1;
  static const _allowedKeys = <String>{
    'theme_mode',
    'cfg_data',
    'cfg_mgr',
    'cfg_exp',
    'notifs_on',
    'upd_auto',
    'sounds',
  };

  static Map<String, dynamic> buildPayload(Map<String, String> values) => {
        'format': 'kidas-controle-settings',
        'version': formatVersion,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'settings': {
          for (final entry in values.entries)
            if (_allowedKeys.contains(entry.key)) entry.key: entry.value,
        },
      };

  static Map<String, String> validatePayload(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'kidas-controle-settings' ||
        decoded['version'] != formatVersion ||
        decoded['settings'] is! Map) {
      throw const FormatException('Fichier de sauvegarde non reconnu.');
    }

    final settings = decoded['settings'] as Map;
    final restored = <String, String>{};
    for (final entry in settings.entries) {
      if (_allowedKeys.contains(entry.key) && entry.value is String) {
        restored[entry.key.toString()] = entry.value as String;
      }
    }
    return restored;
  }

  static Future<File> create() async {
    final values = await Store.all();
    final payload = buildPayload(values);
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/kidas-settings-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  /// Restaure uniquement les préférences autorisées. Le jeton GitHub,
  /// les secrets et les identifiants biométriques ne sont jamais importés.
  static Future<int> restore(File file) async {
    final settings = validatePayload(await file.readAsString());
    for (final entry in settings.entries) {
      await Store.set(entry.key, entry.value);
    }
    return settings.length;
  }
}
