import 'dart:convert';

import 'api.dart';
import 'notifs.dart';
import 'store.dart';

/// Synchronise les événements confirmés du rapport bot/sante.json.
/// Le bot reste seul responsable des actions Facebook : cette classe ne fait
/// que lire son rapport et dédupliquer les notifications sur l'appareil.
class BotNotificationSync {
  static const _errorsKey = 'bot_notifs_errors_v1';
  static const _sessionKey = 'bot_notifs_session_v1';
  static const _responsesKey = 'bot_notifs_responses_v1';
  static const _repliesKey = 'bot_notifs_reply_ids_v1';
  static bool _running = false;

  /// Identifiants des réponses réellement visibles dans le cache Facebook.
  /// Le cache est produit après relecture Graph API, pas à partir d'une intention d'envoi.
  static Set<String> collectConfirmedReplyIds(Map<String, dynamic> cache) {
    final page = cache['page'];
    final pageId = page is Map ? page['id']?.toString() ?? '' : '';
    if (pageId.isEmpty) return <String>{};
    final posts = cache['posts'];
    if (posts is! List) return <String>{};
    final ids = <String>{};
    for (final post in posts.whereType<Map>()) {
      final comments = post['comments'];
      final roots = comments is Map ? comments['data'] : null;
      if (roots is! List) continue;
      for (final root in roots.whereType<Map>()) {
        final children = root['comments'];
        final replies = children is Map ? children['data'] : null;
        if (replies is! List) continue;
        for (final reply in replies.whereType<Map>()) {
          final author = reply['from'];
          final authorId = author is Map ? author['id']?.toString() ?? '' : '';
          final id = reply['id']?.toString() ?? '';
          if (authorId == pageId && id.isNotEmpty) ids.add(id);
        }
      }
    }
    return ids;
  }

  static Future<void> _syncConfirmedReplies() async {
    final cache = await Api.readObj('inbox/commentaires.json');
    if (cache == null) return;
    final current = collectConfirmedReplyIds(cache);
    final knownRaw = await Store.get(_repliesKey);
    final known = knownRaw.isEmpty
        ? <String>{}
        : (jsonDecode(knownRaw) as List).whereType<String>().toSet();
    // Premier passage : créer une référence sans notifier tout l'historique.
    if (knownRaw.isEmpty) {
      await Store.set(_repliesKey, jsonEncode(current.toList()));
      return;
    }
    final fresh = current.difference(known);
    if (fresh.isNotEmpty) {
      await Notifs.montre(
        'Réponse du bot publiée',
        '${fresh.length} nouvelle${fresh.length > 1 ? 's' : ''} réponse${fresh.length > 1 ? 's' : ''} confirmée${fresh.length > 1 ? 's' : ''} sur Facebook.',
        category: 'bot',
      );
    }
    known.addAll(current);
    final saved = known.toList();
    if (saved.length > 500) saved.removeRange(0, saved.length - 500);
    await Store.set(_repliesKey, jsonEncode(saved));
  }

  static Future<void> sync() async {
    if (_running || Api.tok.isEmpty) return;
    _running = true;
    try {
      try {
        await _syncConfirmedReplies();
      } catch (_) {
        // Le cache des commentaires peut être temporairement indisponible.
      }
      final raw = await Api.readBotJson('bot/sante.json');
      if (raw is! Map<String, dynamic>) return;
      final session = raw['session'] is Map
          ? Map<String, dynamic>.from(raw['session'] as Map)
          : <String, dynamic>{};
      final sessionId = session['debut']?.toString() ?? '';
      final responses = session['reponses'] is num
          ? (session['reponses'] as num).toInt()
          : 0;
      final oldSession = await Store.get(_sessionKey);
      final oldResponses = int.tryParse(await Store.get(_responsesKey)) ?? 0;
      if (sessionId.isNotEmpty) {
        if (oldSession == sessionId && responses > oldResponses) {
          final delta = responses - oldResponses;
          await Notifs.montre(
            'Réponses confirmées',
            '$delta réponse${delta > 1 ? 's' : ''} publiée${delta > 1 ? 's' : ''} par le bot.',
            category: 'bot',
          );
        }
        await Store.set(_sessionKey, sessionId);
        await Store.set(_responsesKey, responses.toString());
      }
      final errors = raw['erreurs'] is List
          ? (raw['erreurs'] as List).whereType<Map>().toList()
          : <Map>[];
      final knownRaw = await Store.get(_errorsKey);
      final known = knownRaw.isEmpty
          ? <String>{}
          : (jsonDecode(knownRaw) as List).whereType<String>().toSet();
      final fresh = <Map>[];
      for (final error in errors) {
        final at = error['at']?.toString() ?? '';
        final origin = error['origine']?.toString() ?? 'bot';
        final detail = error['detail']?.toString() ?? 'Erreur non détaillée';
        final fingerprint = '$at|$origin|$detail';
        if (at.isNotEmpty && !known.contains(fingerprint)) {
          fresh.add(error);
          known.add(fingerprint);
        }
      }
      if (fresh.isNotEmpty) {
        final latest = fresh.last;
        final detail = latest['detail']?.toString() ?? 'Erreur du bot';
        await Notifs.montre(
          fresh.length == 1 ? 'Erreur du bot' : 'Erreurs du bot',
          fresh.length == 1
              ? detail
              : '${fresh.length} nouvelles erreurs. Dernière : $detail',
          category: 'bot',
        );
      }
      final saved = known.toList();
      if (saved.length > 100) saved.removeRange(0, saved.length - 100);
      await Store.set(_errorsKey, jsonEncode(saved));
    } catch (_) {
      // Une indisponibilité du dépôt ne doit pas bloquer l'application.
    } finally {
      _running = false;
    }
  }
}