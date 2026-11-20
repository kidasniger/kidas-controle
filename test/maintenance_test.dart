import 'package:flutter_test/flutter_test.dart';
import 'package:kidas_controle/core/backup.dart';
import 'package:kidas_controle/core/diagnostics.dart';

void main() {
  group('AppBackup', () {
    test('exclut les jetons et secrets de la sauvegarde', () {
      final payload = AppBackup.buildPayload({
        'gh_token': 'ghp-secret',
        'theme_mode': 'dark',
        'cfg_mgr': 'kidasniger/facebook-manager',
        'KEYSTORE_PASSWORD': 'secret',
      });
      final settings = payload['settings'] as Map<String, String>;
      expect(settings, containsPair('theme_mode', 'dark'));
      expect(settings, containsPair('cfg_mgr', 'kidasniger/facebook-manager'));
      expect(settings, isNot(contains('gh_token')));
      expect(settings, isNot(contains('KEYSTORE_PASSWORD')));
    });

    test('refuse un format ou une version inconnus', () {
      expect(
        () => AppBackup.validatePayload('{"format":"other","version":1,"settings":{}}'),
        throwsFormatException,
      );
      expect(
        () => AppBackup.validatePayload('{"format":"kidas-controle-settings","version":99,"settings":{}}'),
        throwsFormatException,
      );
    });

    test('restaure uniquement les clés autorisées et les chaînes', () {
      final restored = AppBackup.validatePayload(
        '{"format":"kidas-controle-settings","version":1,"settings":'
        '{"theme_mode":"light","gh_token":"must-not-restore","notifs_on":true}}',
      );
      expect(restored, {'theme_mode': 'light'});
    });
  });

  group('DiagnosticReport', () {
    test('signale une santé complète uniquement si tous les contrôles réussissent', () {
      final report = DiagnosticReport(
        checkedAt: DateTime(2026, 11, 20),
        checks: const [
          DiagnosticCheck(
            id: 'token',
            title: 'GitHub',
            level: CheckLevel.success,
            detail: 'OK',
          ),
          DiagnosticCheck(
            id: 'workflow',
            title: 'Bot',
            level: CheckLevel.warning,
            detail: 'En attente',
          ),
        ],
      );
      expect(report.hasErrors, isFalse);
      expect(report.isHealthy, isFalse);
    });

    test('distingue un échec bloquant', () {
      final report = DiagnosticReport(
        checkedAt: DateTime(2026, 11, 20),
        checks: const [
          DiagnosticCheck(
            id: 'token',
            title: 'GitHub',
            level: CheckLevel.error,
            detail: 'Jeton invalide',
          ),
        ],
      );
      expect(report.hasErrors, isTrue);
      expect(report.isHealthy, isFalse);
    });
  });
}
