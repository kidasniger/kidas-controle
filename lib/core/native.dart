import 'package:flutter/services.dart';

/// Pont natif (Kotlin) : stockage v1 (migration), version installée,
/// installation d'APK (PackageInstaller + vérification signature).
class Native {
  static const MethodChannel ch = MethodChannel('kidas/native');
  static void Function(int status, String? msg)? onInstallResult;

  static void init() {
    ch.setMethodCallHandler((call) async {
      if (call.method == 'installResult') {
        final a = (call.arguments as Map?) ?? const {};
        onInstallResult?.call(
            (a['status'] as int?) ?? 0, a['msg'] as String?);
      }
      return null;
    });
  }

  static Future<List<String>> legacyKeys() async =>
      ((await ch.invokeMethod<dynamic>('legacyKeys')) as List?)
              ?.cast<String>() ??
          const <String>[];

  static Future<String?> legacyGet(String key) async =>
      await ch.invokeMethod<String>('legacyGet', {'key': key});

  static Future<int> versionCode() async =>
      await ch.invokeMethod<int>('versionCode') ?? 0;

  static Future<String> versionName() async =>
      await ch.invokeMethod<String>('versionName') ?? '';

  static Future<bool> canInstall() async =>
      await ch.invokeMethod<bool>('canInstall') ?? false;

  static Future<void> openUnknownSources() => ch.invokeMethod('openUnknownSources');

  /// Lève une PlatformException si l'APK n'est pas un successeur valide.
  static Future<void> verify(String path, int code) =>
      ch.invokeMethod('verify', {'path': path, 'code': code});

  static Future<void> install(String path) =>
      ch.invokeMethod('install', {'path': path});

  /// Son court de 40 ms côté natif (ToneGenerator). Silencieux en cas d'échec.
  static Future<void> beep(String kind) async {
    try {
      await ch.invokeMethod('beep', {'kind': kind});
    } catch (_) {/* pas de son si le pont est indisponible */}
  }
}
