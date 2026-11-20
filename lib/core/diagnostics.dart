import 'dart:convert';

import 'api.dart';

enum DiagnosticLevel { success, warning, error }

class DiagnosticCheck {
  final String id;
  final String title;
  final DiagnosticLevel level;
  final String detail;

  const DiagnosticCheck({
    required this.id,
    required this.title,
    required this.level,
    required this.detail,
  });
}

class DiagnosticReport {
  final DateTime checkedAt;
  final List<DiagnosticCheck> checks;

  const DiagnosticReport({required this.checkedAt, required this.checks});

  bool get hasErrors =>
      checks.any((check) => check.level == DiagnosticLevel.error);

  bool get isHealthy => checks.every(
        (check) => check.level == DiagnosticLevel.success,
      );
}

/// Contrôles en lecture seule : aucun workflow n'est lancé ni arrêté ici.
class Diagnostics {
  static Future<DiagnosticReport> run() async {
    final checks = <DiagnosticCheck>[];
    final checkedAt = DateTime.now();

    if (Api.tok.trim().isEmpty) {
      checks.add(const DiagnosticCheck(
        id: 'token',
        title: 'Jeton GitHub',
        level: DiagnosticLevel.error,
        detail: 'Aucun jeton configuré. Ouvre les réglages.',
      ));
      return DiagnosticReport(checkedAt: checkedAt, checks: checks);
    }

    try {
      final raw = await Api.req('GET', '/repos/${Api.mgr}');
      final repo = jsonDecode(raw);
      final fullName = repo is Map ? (repo['full_name'] ?? '').toString() : '';
      checks.add(DiagnosticCheck(
        id: 'repository',
        title: 'Authentification et dépôt du bot',
        level: fullName.isNotEmpty
            ? DiagnosticLevel.success
            : DiagnosticLevel.warning,
        detail: fullName.isNotEmpty
            ? 'Accès GitHub confirmé : $fullName'
            : 'Réponse du dépôt inattendue.',
      ));
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'repository',
        title: 'Authentification et dépôt du bot',
        level: DiagnosticLevel.error,
        detail: Api.hint(error),
      ));
      return DiagnosticReport(checkedAt: checkedAt, checks: checks);
    }

    try {
      final raw = await Api.req('GET', '/repos/${Api.data}');
      final repo = jsonDecode(raw);
      final fullName = repo is Map ? (repo['full_name'] ?? '').toString() : '';
      checks.add(DiagnosticCheck(
        id: 'data',
        title: 'Dépôt de données',
        level: fullName.isNotEmpty
            ? DiagnosticLevel.success
            : DiagnosticLevel.warning,
        detail: fullName.isNotEmpty
            ? 'Accès confirmé : $fullName'
            : 'Réponse du dépôt inattendue.',
      ));
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'data',
        title: 'Dépôt de données',
        level: DiagnosticLevel.error,
        detail: Api.hint(error),
      ));
    }

    try {
      final raw = await Api.req(
        'GET',
        '/repos/${Api.mgr}/actions/runs?per_page=1',
      );
      final payload = jsonDecode(raw);
      final runs = payload is Map ? payload['workflow_runs'] : null;
      if (runs is List && runs.isNotEmpty && runs.first is Map) {
        final run = runs.first as Map;
        final status = (run['status'] ?? 'unknown').toString();
        final conclusion = (run['conclusion'] ?? '').toString();
        final name = (run['name'] ?? 'Workflow').toString();
        final detail = status == 'completed'
            ? '$name : ${conclusion.isEmpty ? 'résultat inconnu' : conclusion}.'
            : '$name : $status.';
        checks.add(DiagnosticCheck(
          id: 'workflow',
          title: 'Dernière exécution du bot',
          level: status == 'completed' && conclusion == 'success'
              ? DiagnosticLevel.success
              : DiagnosticLevel.warning,
          detail: detail,
        ));
      } else {
        checks.add(const DiagnosticCheck(
          id: 'workflow',
          title: 'Dernière exécution du bot',
          level: DiagnosticLevel.warning,
          detail: 'Aucune exécution récente trouvée.',
        ));
      }
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'workflow',
        title: 'Dernière exécution du bot',
        level: DiagnosticLevel.error,
        detail: Api.hint(error),
      ));
    }

    return DiagnosticReport(checkedAt: checkedAt, checks: checks);
  }
}
