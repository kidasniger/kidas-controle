import 'package:flutter_test/flutter_test.dart';
import 'package:kidas_controle/core/notification_center.dart';
import 'package:kidas_controle/core/bot_notification_sync.dart';

void main() {
  group('NotificationEntry', () {
    test('sérialise et restaure une notification', () {
      final original = NotificationEntry(
        id: 'evt-1',
        title: 'Jeton Facebook',
        body: 'Le jeton expire bientôt.',
        category: 'security',
        createdAt: DateTime(2026, 11, 20, 10, 30),
      );

      final restored = NotificationEntry.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.category, 'security');
      expect(restored.createdAt, original.createdAt);
      expect(restored.read, isFalse);
    });

    test('permet de marquer une notification comme lue sans perdre ses données', () {
      final original = NotificationEntry(
        id: 'evt-2',
        title: 'Modération',
        body: 'Un commentaire urgent.',
        category: 'moderation',
        createdAt: DateTime(2026, 11, 20),
      );

      final read = original.copyWith(read: true);

      expect(read.read, isTrue);
      expect(read.id, original.id);
      expect(read.title, original.title);
      expect(read.body, original.body);
      expect(original.read, isFalse);
    });

    test('tolère les données partielles et les dates invalides', () {
      final item = NotificationEntry.fromMap({
        'id': 'evt-3',
        'title': 'Test',
        'createdAt': 'invalid',
      });

      expect(item.id, 'evt-3');
      expect(item.category, 'general');
      expect(item.createdAt.millisecondsSinceEpoch, 0);
      expect(item.read, isFalse);
    });
  });
}

void botNotificationSyncTests() {
  group('BotNotificationSync', () {
    test('ne retient que les réponses publiées par la Page', () {
      final ids = BotNotificationSync.collectConfirmedReplyIds({
        'page': {'id': 'page-1'},
        'posts': [
          {
            'comments': {
              'data': [
                {
                  'id': 'root-1',
                  'comments': {
                    'data': [
                      {'id': 'reply-1', 'from': {'id': 'page-1'}},
                      {'id': 'reply-2', 'from': {'id': 'person-2'}},
                    ],
                  },
                },
              ],
            },
          },
        ],
      });

      expect(ids, {'reply-1'});
    });

    test('tolère un cache incomplet', () {
      expect(BotNotificationSync.collectConfirmedReplyIds({}), isEmpty);
      expect(
        BotNotificationSync.collectConfirmedReplyIds({
          'page': {'id': 'page-1'},
          'posts': [],
        }),
        isEmpty,
      );
    });
  });
}

