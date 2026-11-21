import 'data.dart';
import 'api.dart';

/// Agrégats non sensibles d'un rapport d'activité.
class ReportSummary {
  final int days;
  final int eventCount;
  final int appEvents;
  final int botEvents;
  final int publications;
  final int replies;
  final int moderation;
  final int media;
  final int rules;
  final int workflowCount;
  final int workflowSuccess;
  final int workflowFailure;
  final int workflowActive;
  final int workflowQueued;
  final int recentErrors;
  final int pendingActions;
  final DateTime generatedAt;

  const ReportSummary({
    required this.days,
    required this.eventCount,
    required this.appEvents,
    required this.botEvents,
    required this.publications,
    required this.replies,
    required this.moderation,
    required this.media,
    required this.rules,
    required this.workflowCount,
    required this.workflowSuccess,
    required this.workflowFailure,
    required this.workflowActive,
    required this.workflowQueued,
    required this.recentErrors,
    required this.pendingActions,
    required this.generatedAt,
  });

  factory ReportSummary.build({
    required List<JournalEvent> events,
    required List<dynamic> runs,
    Map<String, dynamic>? health,
    required int days,
    DateTime? now,
  }) {
    final generated = now ?? DateTime.now();
    final start = generated.subtract(Duration(days: days));
    final selected = events.where((event) {
      final at = DateTime.fromMillisecondsSinceEpoch(event.at);
      return !at.isBefore(start) && !at.isAfter(generated);
    }).toList();

    int countType(String type) =>
        selected.where((event) => event.type == type).length;

    final selectedRuns = runs.where((raw) {
      final run = asObj(raw);
      final rawDate = run.os('run_started_at').isNotEmpty
          ? run.os('run_started_at')
          : run.os('created_at');
      final date = DateTime.tryParse(rawDate)?.toLocal();
      return date != null && !date.isBefore(start) && !date.isAfter(generated);
    }).map(asObj).toList();

    int statusCount(String status) =>
        selectedRuns.where((run) => run.os('status') == status).length;

    final failures = selectedRuns.where((run) =>
        run.os('status') == 'completed' &&
        run.os('conclusion') != 'success' &&
        run.os('conclusion').isNotEmpty &&
        run.os('conclusion') != 'skipped').length;
    final errorsRaw = health?['erreurs'];
    final queueRaw = health?['file'];
    final pendingRaw = queueRaw is Map ? queueRaw['en_attente'] : 0;

    return ReportSummary(
      days: days,
      eventCount: selected.length,
      appEvents: selected.where((event) => event.source == 'app').length,
      botEvents: selected.where((event) => event.source == 'bot').length,
      publications: countType('post'),
      replies: countType('reponse'),
      moderation: countType('moderation'),
      media: countType('media'),
      rules: countType('regle'),
      workflowCount: selectedRuns.length,
      workflowSuccess: selectedRuns.where((run) =>
          run.os('status') == 'completed' &&
          run.os('conclusion') == 'success').length,
      workflowFailure: failures,
      workflowActive: statusCount('in_progress'),
      workflowQueued: statusCount('queued'),
      recentErrors: errorsRaw is List ? errorsRaw.length : 0,
      pendingActions: pendingRaw is num ? pendingRaw.toInt() : 0,
      generatedAt: generated,
    );
  }

  String toSafeText() {
    final date = generatedAt.toLocal();
    final stamp = '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final period = days == 1 ? '24 dernières heures' : '$_daysLabel';
    return [
      'KI DAS CONTRÔLE — RAPPORT D’ACTIVITÉ',
      'Période : $period',
      'Généré le : $stamp',
      '',
      'ACTIVITÉ JOURNALISÉE',
      'Événements : $eventCount',
      'Application : $appEvents',
      'Bot : $botEvents',
      'Publications journalisées : $publications',
      'Réponses journalisées : $replies',
      'Modération : $moderation',
      'Médias : $media',
      'Règles : $rules',
      '',
      'EXÉCUTIONS GITHUB ACTIONS',
      'Workflows observés : $workflowCount',
      'Réussis : $workflowSuccess',
      'Échoués : $workflowFailure',
      'En cours : $workflowActive',
      'En attente : $workflowQueued',
      '',
      'ÉTAT ACTUEL DU BOT',
      'Erreurs présentes dans le dernier rapport santé : $recentErrors',
      'Actions actuellement en attente : $pendingActions',
      '',
      'Note : une exécution GitHub réussie ne prouve pas, à elle seule, '
          'qu’une action Facebook a été publiée. Les données détaillées, '
          'identifiants et secrets sont exclus de cet export.',
    ].join('\n');
  }

  String get _daysLabel => '$days derniers jours';
}
