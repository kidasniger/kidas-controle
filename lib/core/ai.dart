import 'api.dart';

/// Discussion avec l'IA : l'application écrit le message dans glm/chat.json
/// (dépôt de données), déclenche le workflow « assistant.yml » du dépôt du bot
/// (qui possède la clé Z.ai en secret) et attend que la réponse soit ajoutée
/// au même fichier. Aucune clé d'IA n'est stockée dans l'application et la
/// mémoire du modèle est la conversation elle-même.
class Ai {
  /// Un tour de discussion : renvoie le texte de la réponse. Le message de
  /// l'utilisateur doit déjà être sauvegardé dans glm/chat.json.
  static Future<String> chat() async {
    final avant = (await _histo()).length;
    await Api.dispatch('assistant.yml', null);
    final fin = DateTime.now().add(const Duration(seconds: 150));
    while (DateTime.now().isBefore(fin)) {
      await Future.delayed(const Duration(seconds: 4));
      final a = await _histo();
      if (a.length > avant) {
        final m = asObj(a.last);
        if (m.os('r') == 'a') {
          final t = m.os('t').trim();
          if (t.isNotEmpty) return t;
        }
      }
    }
    throw ApiError(
      0,
      "Le relais de l'IA n'a pas répondu à temps. Réessaie.",
      'assistant.yml',
    );
  }

  /// Réponse à un message isolé (suggestion de réponse à un commentaire) :
  /// le relais écrit le résultat dans glm/reponse.json, sans toucher au chat.
  static Future<String> chatOneShot(String prompt) async {
    final avant = await _reponse();
    final at = avant == null ? '' : avant.os('at');
    await Api.dispatch('assistant.yml', {'message': prompt});
    final fin = DateTime.now().add(const Duration(seconds: 150));
    while (DateTime.now().isBefore(fin)) {
      await Future.delayed(const Duration(seconds: 4));
      final m = await _reponse();
      if (m != null && m.os('at') != at) {
        final t = m.os('t').trim();
        if (t.isNotEmpty) return t;
      }
    }
    throw ApiError(
      0,
      "Le relais de l'IA n'a pas répondu à temps. Réessaie.",
      'assistant.yml',
    );
  }

  /// Historique du chat (liste vide si le dépôt est indisponible).
  static Future<List<dynamic>> _histo() async {
    try {
      return await Api.readArr('glm/chat.json');
    } catch (_) {
      return const <dynamic>[];
    }
  }

  /// Dernière réponse isolée (null si absente ou indisponible).
  static Future<Map<String, dynamic>?> _reponse() async {
    try {
      return await Api.readObj('glm/reponse.json');
    } catch (_) {
      return null;
    }
  }
}
