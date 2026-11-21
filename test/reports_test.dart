import 'package:flutter_test/flutter_test.dart';
import 'package:kidas_controle/core/data.dart';
import 'package:kidas_controle/core/reports.dart';

void main() {
  group('ReportSummary', () {
    final now = DateTime(2026, 11, 21, 12);
    final recent = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
    final old = now.subtract(const Duration(days: 10)).millisecondsSinceEpoch;

    test('agrège les événements uniquement dans la période', () {
      final summary = ReportSummary.build(
        now: now,
        days: 7,
        events: [
          JournalEvent(recent, 'reponse', 'Réponse journalisée'),
          JournalEvent(recent, 'post', 'Publication', source: 'bot'),
          JournalEvent(old, 'moderation', 'Ancienne modération'),
        ],
        runs: const [],
      );

      expect(summary.eventCount, 2);
      expect(summary.appEvents, 1);
      expect(summary.botEvents, 1);
      expect(summary.replies, 1);
      expect(summary.publications, 1);
      expect(summary.moderation, 0);
    });

    test('distingue les états des workflows et les compteurs de santé', () {
      final summary = ReportSummary.build(
        now: now,
        days: 7,
        events: const [],
        runs: [
          {
            'run_started_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
            'status': 'completed',
            'conclusion': 'success',
          },
          {
            'created_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
            'status': 'completed',
            'conclusion': 'failure',
          },
          {
            'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
            'status': 'in_progress',
          },
          {
            'created_at': now.subtract(const Duration(days: 12)).toIso8601String(),
            'status': 'completed',
            'conclusion': 'success',
          },
        ],
        health: {
          'erreurs': ['e1', 'e2'],
          'file': {'en_attente': 3},
        },
      );

      expect(summary.workflowCount, 3);
      expect(summary.workflowSuccess, 1);
      expect(summary.workflowFailure, 1);
      expect(summary.workflowActive, 1);
      expect(summary.recentErrors, 2);
      expect(summary.pendingActions, 3);
    });

    test('exporte uniquement des agrégats, sans données détaillées', () {
      final summary = ReportSummary.build(
        now: now,
        days: 1,
        events: [
          JournalEvent(recent, 'reponse', 'Nom privé', detail: 'message privé'),
        ],
        runs: const [],
      );
      final text = summary.toSafeText();
      expect(text, contains('Réponses journalisées : 1'));
      expect(text, isNot(contains('Nom privé')));
      expect(text, isNot(contains('message privé')));
      expect(text, isNot(contains('token')));
    });
  });
}
