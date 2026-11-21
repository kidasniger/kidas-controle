import 'dart:convert';

import 'api.dart';

enum CheckLevel { success, warning, error }

class DiagnosticCheck {
  final String id;
  final String title;
  final CheckLevel level;
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
      checks.any((check) => check.level == CheckLevel.error);

  bool get isHealthy => checks.every(
        (check) => check.level == CheckLevel.success,
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
        level: CheckLevel.error,
        detail: 'Aucun jeton configuré. Ouvre les réglages.',
      ));
  
    // Santé réelle du moteur Facebook (dépôt privé en lecture seule).
    try {
      final health = await Api.readBotJson('bot/sante.json');
      if (health is Map<String, dynamic>) {
        final updated = DateTime.tryParse(health['mis_a_jour']?.toString() ?? '');
        final age = updated == null ? null : DateTime.now().toUtc().difference(updated.toUtc());
        final fresh = age != null && age.inMinutes <= 30 && age.inMinutes >= -2;
        checks.add(DiagnosticCheck(
          id: 'facebook_bot',
          title: 'Synchronisation Facebook',
          level: fresh ? CheckLevel.success : CheckLevel.warning,
          detail: updated == null
              ? 'Rapport de santé sans date exploitable.'
              : fresh
                  ? 'Bot actif · dernière synchronisation il y a ${age.inMinutes} min.'
                  : 'Dernier rapport reçu le ${updated.toLocal()}. Synchronisation possiblement interrompue.',
        ));
        final errors = health['erreurs'] is List ? (health['erreurs'] as List).length : 0;
        final pending = health['file'] is Map ? ((health['file'] as Map)['en_attente'] ?? 0) : 0;
        checks.add(DiagnosticCheck(
          id: 'bot_activity',
          title: 'Erreurs et file d’attente',
          level: errors > 0 ? CheckLevel.warning : CheckLevel.success,
          detail: '$errors erreur(s) récente(s) · $pending élément(s) en attente.',
        ));
      } else {
        checks.add(const DiagnosticCheck(
          id: 'facebook_bot',
          title: 'Synchronisation Facebook',
          level: CheckLevel.warning,
          detail: 'Rapport bot/sante.json indisponible.',
        ));
      }
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'facebook_bot',
        title: 'Synchronisation Facebook',
        level: CheckLevel.error,
        detail: Api.hint(error),
      ));
    }

    try {
      final likes = await Api.readBotJson('glm/aimes-commentaires.json');
      final faits = likes is Map && likes['faits'] is Map ? likes['faits'] as Map : const {};
      final confirmed = faits.values.where((v) =>
          v is Map && v['like'] == 'ok' && v['verifie'] == true).length;
      final pendingLikes = faits.values.where((v) => v is Map && v['like'] == 'pending').length;
      checks.add(DiagnosticCheck(
        id: 'comment_likes',
        title: 'J’aime des commentaires',
        level: pendingLikes > 0 ? CheckLevel.warning : CheckLevel.success,
        detail: '$confirmed J’aime confirmés · $pendingLikes en attente de confirmation.',
      ));
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'comment_likes',
        title: 'J’aime des commentaires',
        level: CheckLevel.warning,
        detail: 'Registre des J’aime non accessible : ${Api.hint(error)}',
      ));
    }

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
            ? CheckLevel.success
            : CheckLevel.warning,
        detail: fullName.isNotEmpty
            ? 'Accès GitHub confirmé : $fullName'
            : 'Réponse du dépôt inattendue.',
      ));
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'repository',
        title: 'Authentification et dépôt du bot',
        level: CheckLevel.error,
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
            ? CheckLevel.success
            : CheckLevel.warning,
        detail: fullName.isNotEmpty
            ? 'Accès confirmé : $fullName'
            : 'Réponse du dépôt inattendue.',
      ));
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'data',
        title: 'Dépôt de données',
        level: CheckLevel.error,
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
              ? CheckLevel.success
              : CheckLevel.warning,
          detail: detail,
        ));
      } else {
        checks.add(const DiagnosticCheck(
          id: 'workflow',
          title: 'Dernière exécution du bot',
          level: CheckLevel.warning,
          detail: 'Aucune exécution récente trouvée.',
        ));
      }
    } catch (error) {
      checks.add(DiagnosticCheck(
        id: 'workflow',
        title: 'Dernière exécution du bot',
        level: CheckLevel.error,
        detail: Api.hint(error),
      ));
    }

    return DiagnosticReport(checkedAt: checkedAt, checks: checks);
  }
}
