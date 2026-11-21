import 'api.dart';
import 'data.dart';

/// Résultat normalisé de la recherche transversale.
class SearchHit {
  final String id;
  final String category; // conversation | commentaire | publication | brouillon | activite
  final String title;
  final String subtitle;
  final String body;
  final int timestamp;
  final String? conversationId;

  const SearchHit({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.timestamp,
    this.conversationId,
  });

  String get searchable =>
      '$title $subtitle $body'.toLowerCase();
}

class GlobalSearch {
  /// Construit un index en mémoire à partir des données déjà synchronisées.
  /// Aucun appel réseau ni écriture n'est effectué par cette classe.
  static List<SearchHit> build({
    required List<UnifiedItem> inbox,
    required List<Brouillon> drafts,
    required List<JournalEvent> events,
  }) {
    final hits = <SearchHit>[];
    final seenPosts = <String>{};

    for (final item in inbox) {
      if (item.kind == 'msg') {
        final messages = item.conv?['messages'];
        if (messages is List && messages.isNotEmpty) {
          for (var i = 0; i < messages.length; i++) {
            final message = asObj(messages[i]);
            final mine = message.ob('from_page', false);
            final text = message.os('message');
            hits.add(SearchHit(
              id: 'msg:${item.id}:$i',
              category: 'conversation',
              title: item.name,
              subtitle: mine ? 'Message de la Page' : 'Message reçu · Messenger',
              body: text,
              timestamp: Api.iso(message.os('created_time')),
              conversationId: item.id,
            ));
          }
        } else {
          hits.add(SearchHit(
            id: 'conv:${item.id}',
            category: 'conversation',
            title: item.name,
            subtitle: 'Conversation Messenger',
            body: item.text,
            timestamp: item.ts,
            conversationId: item.id,
          ));
        }
      } else {
        hits.add(SearchHit(
          id: 'comment:${item.id}',
          category: 'commentaire',
          title: item.name,
          subtitle: 'Commentaire · ${item.postTxt}',
          body: item.text,
          timestamp: item.ts,
        ));
        final post = item.cmt?.post;
        if (post != null) {
          final postId = post.os('id');
          if (postId.isNotEmpty && seenPosts.add(postId)) {
            var postText = post.os('message');
            if (postText.isEmpty) postText = post.os('story');
            if (postText.isNotEmpty) {
              hits.add(SearchHit(
                id: 'post:$postId',
                category: 'publication',
                title: 'Publication',
                subtitle: 'Publication Facebook',
                body: postText,
                timestamp: Api.iso(post.os('created_time')),
              ));
            }
          }
        }
      }
    }

    for (final draft in drafts) {
      hits.add(SearchHit(
        id: 'draft:${draft.id}',
        category: 'brouillon',
        title: 'Brouillon',
        subtitle: draft.media.isEmpty ? 'Texte non publié' : 'Brouillon avec média',
        body: draft.texte,
        timestamp: draft.whenMs,
      ));
    }

    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      hits.add(SearchHit(
        id: 'event:$i:${event.at}',
        category: 'activite',
        title: event.label,
        subtitle: event.type,
        body: event.detail,
        timestamp: event.at,
      ));
    }

    hits.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return hits;
  }

  /// Tous les termes saisis doivent être présents (recherche AND),
  /// sans distinction de casse ni d'accents laissés tels quels.
  static List<SearchHit> query(
    List<SearchHit> index,
    String value, {
    String category = 'tout',
    int limit = 100,
  }) {
    final terms = value.trim().toLowerCase().split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty).toList();
    final results = index.where((hit) {
      if (category != 'tout' && hit.category != category) return false;
      return terms.every(hit.searchable.contains);
    }).take(limit).toList();
    return results;
  }
}
