import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'util.dart';

/// Discussion avec l'IA via GitHub Models : le jeton de l'application appelle
/// directement le modèle (aucun serveur supplémentaire). Le jeton doit avoir
/// la permission « Models : read ». La conversation est sauvegardée dans
/// glm/chat.json du dépôt de données ; le contexte de la Page
/// (personnalisation, ligne éditoriale, faits, chiffres, commentaires en
/// attente) est construit ici.
class Ai {
  static const model = 'openai/gpt-4o-mini';
  static const _url = 'https://models.github.ai/inference/chat/completions';
  static final http.Client _c = http.Client();

  static const _base =
      "Tu es l'assistant IA intégré à KI DAS Contrôle, l'application de "
      'gestion de la Page Facebook « Aboubacar Sidik | KI DAS ». Tu discutes '
      "avec Aboubacar, le gérant de la Page (pas avec les clients). Ton rôle : "
      "l'aider à comprendre ce qui se passe sur sa Page, préparer des réponses "
      'aux commentaires et aux messages, proposer des publications conformes '
      'à la ligne éditoriale et conseiller. Réponds toujours en français, de '
      'façon concise, concrète et actionnable (listes courtes, réponses '
      'prêtes à copier). Si une information manque dans le contexte, dis-le '
      "franchement au lieu d'inventer.";

  /// Un tour de discussion : renvoie le texte du modèle.
  static Future<String> chat(List<Map<String, String>> messages) async {
    final r = http.Request('POST', Uri.parse(_url));
    r.headers['Authorization'] = 'Bearer ${Api.tok}';
    r.headers['Content-Type'] = 'application/json';
    r.headers['Accept'] = 'application/vnd.github+json';
    r.headers['X-GitHub-Api-Version'] = '2022-11-28';
    r.body = jsonEncode(<String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': .6,
      'max_tokens': 900,
    });
    http.StreamedResponse resp;
    try {
      resp = await _c.send(r).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw ApiError(0, 'Délai dépassé, réessaie.', _url);
    } catch (_) {
      throw ApiError(0, 'Réseau indisponible.', _url);
    }
    final String txt;
    try {
      txt = await resp.stream
          .bytesToString()
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw ApiError(0, 'Délai dépassé, réessaie.', _url);
    } catch (_) {
      throw ApiError(0, 'Réseau indisponible.', _url);
    }
    if (resp.statusCode >= 400) {
      var msg = 'HTTP ${resp.statusCode}';
      try {
        final j = jsonDecode(txt);
        if (j is Map &&
            j['message'] != null &&
            j['message'].toString().isNotEmpty) {
          msg = j['message'].toString();
        }
      } catch (_) {/* corps non JSON */}
      if (resp.statusCode == 401) {
        msg = 'Jeton invalide ou expiré. Va dans Réglages.';
      } else if (resp.statusCode == 403 || resp.statusCode == 404) {
        msg = "Le jeton n'a pas la permission « Models : read ». "
            'GitHub → Réglages → Developer settings → Jetons fine-grained → '
            'ajoute la permission Models en lecture.';
      } else if (resp.statusCode == 429) {
        msg = 'Limite GitHub Models atteinte, réessaie dans quelques instants.';
      }
      throw ApiError(resp.statusCode, msg, _url);
    }
    try {
      final j = jsonDecode(txt);
      final choices = j is Map && j['choices'] is List
          ? j['choices'] as List<dynamic>
          : null;
      final first =
          choices != null && choices.isNotEmpty ? choices.first : null;
      final m = first is Map ? first['message'] : null;
      final content = m is Map ? m['content'] : null;
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
      throw ApiError(0, 'Réponse vide du modèle.', _url);
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(0, 'Réponse illisible du modèle.', _url);
    }
  }

  /// Contexte complet injecté en message système au début de la discussion.
  /// Chaque brique est optionnelle : si le dépôt de données est indisponible,
  /// le modèle reçoit au moins le prompt de base.
  static Future<String> context() async {
    final b = StringBuffer(_base);
    for (final f in const [
      'PERSONNALISATION_CHATGPT.md',
      'LIGNE_EDITORIALE.md',
      'faits.md',
      'connaissances/projets.md',
      'connaissances/performance.md',
    ]) {
      try {
        final d = await Api.getFile(Api.data, f);
        var t = d == null ? '' : d.text.trim();
        if (t.isEmpty) continue;
        if (t.length > 2400) t = '${t.substring(0, 2400)}…';
        b.write('\n\n### $f\n$t');
      } catch (_) {/* fichier absent : ignoré */}
    }
    try {
      final ms = Api.metrics(await Api.readObj('inbox/statistiques.json'));
      if (ms.isNotEmpty) {
        b.write('\n\n### Statistiques de la Page (dernier point mesuré)\n');
        for (final m in ms.take(6)) {
          b.write('- ${m.name} : ${nf(m.vals.last)}\n');
        }
      }
    } catch (_) {}
    try {
      final cm = await Api.readObj('inbox/commentaires.json');
      if (cm != null) {
        final pid = asObj(cm['page']).os('id');
        final un = Api.unanswered(Api.flatComments(cm), pid);
        if (un.isNotEmpty) {
          b.write('\n\n### Commentaires sans réponse (${un.length})\n');
          for (var i = 0; i < un.length && i < 6; i++) {
            final cc = un[i].c;
            final from = asObj(cc['from']).os('name');
            var ps = un[i].post.os('message');
            if (ps.isEmpty) ps = un[i].post.os('story');
            if (ps.length > 80) ps = '${ps.substring(0, 80)}…';
            b.write('- ${from.isEmpty ? 'Abonné' : from} : ${cc.os('message')}'
                '${ps.isEmpty ? '' : ' (sur : $ps)'}\n');
          }
        }
      }
    } catch (_) {}
    try {
      final inbox = await Api.readObj('inbox/messages.json');
      if (inbox != null) {
        final todo = <Map<String, dynamic>>[];
        for (final conv in Api.conversations(inbox)) {
          if (Api.needsReply(conv)) todo.add(conv);
        }
        if (todo.isNotEmpty) {
          b.write('\n\n### Messages Messenger en attente (${todo.length})\n');
          for (var i = 0; i < todo.length && i < 4; i++) {
            final conv = todo[i];
            final who = asObj(conv['with']).os('name');
            final ms2 = conv['messages'] is List
                ? conv['messages'] as List<dynamic>
                : const <dynamic>[];
            final last = ms2.isEmpty ? null : asObj(ms2.last);
            b.write('- ${who.isEmpty ? 'Contact' : who} : '
                '${last == null ? '' : last.os('message')}\n');
          }
        }
      }
    } catch (_) {}
    return b.toString();
  }
}
