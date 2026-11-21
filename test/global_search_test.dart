import 'package:flutter_test/flutter_test.dart';
import 'package:kidas_controle/core/api.dart';
import 'package:kidas_controle/core/data.dart';
import 'package:kidas_controle/core/search.dart';

void main() {
  group('GlobalSearch', () {
    test('indexe conversations, commentaires, publications, brouillons et activite', () {
      final post = <String, dynamic>{
        'id': 'post-1',
        'message': 'Annonce du nouveau produit',
        'created_time': '2026-11-20T10:00:00+0000',
      };
      final comment = <String, dynamic>{
        'id': 'comment-1',
        'message': 'Quel est le prix ?',
        'created_time': '2026-11-20T11:00:00+0000',
        'from': {'name': 'Amina'},
      };
      final conversation = <String, dynamic>{
        'id': 'conversation-1',
        'with': {'id': 'user-1', 'name': 'Moussa'},
        'messages': [
          {
            'message': 'Bonjour, je veux des informations',
            'from_page': false,
            'created_time': '2026-11-20T12:00:00+0000',
          },
        ],
      };
      final items = [
        UnifiedItem(
          kind: 'avis',
          id: 'comment-1',
          ts: Api.iso('2026-11-20T11:00:00+0000'),
          name: 'Amina',
          text: 'Quel est le prix ?',
          postTxt: 'Annonce du nouveau produit',
          todo: true,
          cmt: Cmt(comment, post),
        ),
        UnifiedItem(
          kind: 'msg',
          id: 'conversation-1',
          ts: Api.iso('2026-11-20T12:00:00+0000'),
          name: 'Moussa',
          text: 'Bonjour, je veux des informations',
          todo: true,
          conv: conversation,
        ),
      ];
      final index = GlobalSearch.build(
        inbox: items,
        drafts: const [Brouillon('draft-1', 'Texte de lancement', '', 100)],
        events: const [JournalEvent(200, 'reponse', 'Réponse envoyée', detail: 'Message test')],
      );

      expect(index.any((hit) => hit.category == 'publication' && hit.body.contains('nouveau produit')), isTrue);
      expect(index.any((hit) => hit.category == 'conversation' && hit.conversationId == 'conversation-1'), isTrue);
      expect(index.any((hit) => hit.category == 'commentaire' && hit.title == 'Amina'), isTrue);
      expect(index.any((hit) => hit.category == 'brouillon'), isTrue);
      expect(index.any((hit) => hit.category == 'activite'), isTrue);
    });

    test('recherche sans distinction de casse et avec filtres', () {
      const hits = [
        SearchHit(id: '1', category: 'conversation', title: 'Moussa',
          subtitle: 'Messenger', body: 'Bonjour KIDAS', timestamp: 3),
        SearchHit(id: '2', category: 'commentaire', title: 'Amina',
          subtitle: 'Commentaire', body: 'Bonjour la page', timestamp: 2),
      ];
      expect(GlobalSearch.query(hits, 'BONJOUR').length, 2);
      expect(GlobalSearch.query(hits, 'bonjour', category: 'conversation').single.id, '1');
      expect(GlobalSearch.query(hits, 'absent'), isEmpty);
    });
  });
}
