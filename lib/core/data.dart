import 'dart:async';

import 'api.dart';
import 'util.dart';

/// Services de données de la v3 : boîte unifiée, modération, journal
/// d'activité, règles du bot, brouillons du composer, étiquettes de la
/// bibliothèque et top publications. Tout est stocké dans le dépôt de
/// données GitHub (JSON versionnés), comme le reste de l'application :
/// rien ne reste enfermé dans le téléphone.

/* ---------- boîte unifiée (avis + Messenger) ---------- */

/// Un élément de la boîte : soit un avis (commentaire sur un post),
/// soit une conversation Messenger.
class UnifiedItem {
  final String kind; // 'avis' | 'msg'
  final String id;
  final int ts; // millisecondes depuis l'époque
  final String name;
  final String text; // texte du commentaire ou aperçu du dernier message
  final String postTxt; // publication concernée (avis seulement)
  final bool todo; // attend une réponse de la Page
  final Cmt? cmt;
  final Map<String, dynamic>? conv;
  const UnifiedItem({
    required this.kind,
    required this.id,
    required this.ts,
    required this.name,
    required this.text,
    this.postTxt = '',
    required this.todo,
    this.cmt,
    this.conv,
  });
}

/// Fusion des deux inbox du bot, du plus récent au plus ancien.
class Boite {
  static Future<(List<UnifiedItem>, String)> charge() async {
    Map<String, dynamic>? cm, inbox;
    await Future.wait<dynamic>([
      Api.readObj('inbox/commentaires.json')
          .then((v) => cm = v)
          .catchError((Object e) {}),
      Api.readObj('inbox/messages.json')
          .then((v) => inbox = v)
          .catchError((Object e) {}),
    ]);
    final out = <UnifiedItem>[];
    var upd = '';
    if (cm != null) {
      final fcm = cm!;
      final pid = asObj(fcm['page']).os('id');
      final all = Api.flatComments(fcm);
      final un = Api.unanswered(all, pid).toSet();
      for (final x in all) {
        final from = asObj(x.c['from']);
        var postTxt = x.post.os('message');
        if (postTxt.isEmpty) postTxt = x.post.os('story');
        out.add(UnifiedItem(
          kind: 'avis',
          id: x.c.os('id'),
          ts: iso(x.c.os('created_time')),
          name: from.os('name').isEmpty ? 'Abonné' : from.os('name'),
          text: x.c.os('message'),
          postTxt: postTxt,
          todo: un.contains(x),
          cmt: x,
        ));
      }
      final u = fcm.os('updated');
      if (u.isNotEmpty) upd = u;
    }
    final finbox = inbox;
    if (finbox != null) {
      for (final conv in Api.conversations(finbox)) {
        final who = asObj(conv['with']);
        final ms = conv['messages'] is List
            ? conv['messages'] as List<dynamic>
            : const <dynamic>[];
        var preview = 'Conversation ouverte';
        var prefix = '';
        if (ms.isNotEmpty) {
          final last = asObj(ms.last);
          final t = last.os('message');
          preview = t.isEmpty ? '(pièce jointe)' : t;
          prefix = last.ob('from_page', false) ? 'Toi : ' : '';
        }
        out.add(UnifiedItem(
          kind: 'msg',
          id: conv.os('id'),
          ts: iso(conv.os('updated_time')),
          name: who.os('name').isEmpty ? 'Contact' : who.os('name'),
          text: prefix + preview,
          todo: Api.needsReply(conv),
          conv: conv,
        ));
      }
      final u = finbox.os('updated');
      if (u.compareTo(upd) > 0) upd = u;
    }
    out.removeWhere((x) => x.ts <= 0);
    out.sort((a, b) => b.ts.compareTo(a.ts));
    return (out, upd);
  }
}

/* ---------- modération (mémoire stable de l'application) ---------- */

/// État de modération : le bot réécrit inbox/commentaires.json à chaque
/// cycle, ces listes d'identifiants gardent donc les décisions de
/// l'utilisateur entre les cycles, les réinstallations et les écrans.
class Moderation {
  final Set<String> traite; // approuvés : répondus ou validés à la main
  final Set<String> cache; // cachés : ne s'affichent plus dans l'application
  final Set<String> urgents; // marqués urgents (prix, litige, presse...)
  const Moderation({this.traite = const {}, this.cache = const {}, this.urgents = const {}});

  static const _fichier = 'moderation/moderation.json';

  static Future<Moderation> charge() async {
    final o = await Api.readObj(_fichier);
    Set<String> l(String k) =>
        (o == null ? const <dynamic>[] : asArr(o[k])).map((e) => e.toString()).toSet();
    return Moderation(traite: l('traite'), cache: l('cache'), urgents: l('urgents'));
  }

  static Future<void> _maj(
      void Function(Map<String, dynamic> o) job, String msg) async {
    await Api.updateJson(_fichier, false, (cur) {
      final o = asObj(cur);
      job(o);
      return o;
    }, msg);
  }

  static void _add(Map<String, dynamic> o, String k, String id) {
    final a = (o[k] is List ? o[k] as List<dynamic> : <dynamic>[]).toList();
    if (!a.contains(id)) a.add(id);
    o[k] = a;
  }

  static void _rm(Map<String, dynamic> o, String k, String id) {
    final a = (o[k] is List ? o[k] as List<dynamic> : <dynamic>[]).toList();
    a.remove(id);
    o[k] = a;
  }

  static Future<void> approuve(String id) => _maj((o) {
        _add(o, 'traite', id);
        _rm(o, 'cache', id);
        _rm(o, 'urgents', id);
      }, 'Modération : commentaire approuvé');

  static Future<void> masque(String id) => _maj((o) {
        _add(o, 'cache', id);
        _rm(o, 'traite', id);
        _rm(o, 'urgents', id);
      }, 'Modération : commentaire caché');

  /// Retire de « traité » : le commentaire revient comme à traiter.
  static Future<void> reouvre(String id) => _maj((o) {
        _rm(o, 'traite', id);
      }, 'Modération : commentaire réouvert');

  static Future<void> urgent(String id, bool v) => _maj((o) {
        if (v) {
          _add(o, 'urgents', id);
        } else {
          _rm(o, 'urgents', id);
        }
      }, v ? 'Modération : marqué urgent' : 'Modération : plus urgent');
}

/* ---------- journal d'activité ---------- */

/// Une action tracée : faite par l'application (source « app ») ou par le
/// bot / GitHub Actions (source « bot »). Les entrées du bot sont
/// reconstruites depuis les exécutions des workflows.
class JournalEvent {
  final int at;
  final String type; // post | reponse | moderation | media | regle | bot
  final String label;
  final String detail;
  final String source; // app | bot
  const JournalEvent(this.at, this.type, this.label,
      {this.detail = '', this.source = 'app'});

  factory JournalEvent.fromMap(Map<String, dynamic> o) => JournalEvent(
        iso(o.os('at')),
        o.os('type', 'app'),
        o.os('label'),
        detail: o.os('detail'),
        source: o.os('source', 'app'),
      );

  Map<String, dynamic> toMap() => {
        'at': isoOf(at),
        'type': type,
        'label': label,
        if (detail.isNotEmpty) 'detail': detail,
        'source': source,
      };
}

class Journal {
  static const _fichier = 'journal/evenements.json';
  static const _max = 400;

  /// Journal de l'application, du plus récent au plus ancien.
  static Future<List<JournalEvent>> charge({int max = 200}) async {
    final a = await Api.readArr(_fichier);
    final out = <JournalEvent>[];
    for (final e in a) {
      final ev = JournalEvent.fromMap(asObj(e));
      if (ev.at > 0 && ev.label.isNotEmpty) out.add(ev);
    }
    out.sort((x, y) => y.at.compareTo(x.at));
    return out.length > max ? out.sublist(0, max) : out;
  }

  /// Trace une action de l'application (silencieux : ne bloque jamais
  /// l'action principale si le journal échoue).
  static Future<void> ajoute(String type, String label, {String detail = ''}) async {
    try {
      await Api.updateJson(_fichier, true, (cur) {
        final a = (cur is List ? cur : <dynamic>[]).toList();
        a.add(JournalEvent(
                DateTime.now().millisecondsSinceEpoch, type, label, detail: detail)
            .toMap());
        return a.length > _max ? a.sublist(a.length - _max) : a;
      }, 'Journal : $label');
    } catch (_) {/* le journal ne doit jamais casser l'action */}
  }
}

/* ---------- règles du bot (« si ... alors ... ») ---------- */

/// Une règle : si le commentaire contient [contient] (vide = tous), faire
/// [action] avec [texte]. Stockée dans glm/regles.json.
class Regle {
  String id;
  bool actif;
  String contient;
  String action; // reponse | urgent | rien
  String texte;
  Regle({required this.id, this.actif = true, this.contient = '',
      this.action = 'reponse', this.texte = ''});

  Map<String, dynamic> toMap() => {
        'id': id,
        'actif': actif,
        'si': contient,
        'alors': action,
        if (texte.isNotEmpty) 'texte': texte,
      };

  factory Regle.fromMap(Map<String, dynamic> o) => Regle(
        id: o.os('id').isEmpty ? o.os('si') : o.os('id'),
        actif: o.ob('actif', true),
        contient: o.os('si'),
        action: o.os('alors', 'reponse'),
        texte: o.os('texte'),
      );

  String get libelle => switch (action) {
        'urgent' => 'Marquer urgent',
        'rien' => 'Ne rien faire',
        _ => 'Répondre automatiquement',
      };
}

class Regles {
  static const _fichier = 'glm/regles.json';

  static Future<List<Regle>> charge() async {
    final a = await Api.readArr(_fichier);
    final out = <Regle>[];
    for (final e in a) {
      final r = Regle.fromMap(asObj(e));
      if (r.id.isNotEmpty) out.add(r);
    }
    return out;
  }

  /// Réécrit la liste entière (simple et sans conflit grâce à updateJson).
  static Future<void> ecrire(List<Regle> rs) async {
    await Api.updateJson(_fichier, false, (_) => [for (final r in rs) r.toMap()],
        'Règles du bot mises à jour');
  }

  /// Testeur : première règle active qui colle au texte donné, ou null.
  static Regle? simule(List<Regle> rs, String texte) {
    final t = texte.toLowerCase();
    for (final r in rs) {
      if (!r.actif) continue;
      final k = r.contient.trim().toLowerCase();
      if (k.isEmpty || t.contains(k)) return r;
    }
    return null;
  }
}

/* ---------- brouillons du composer ---------- */

class Brouillon {
  final String id; // millisecondes de création, sert d'identifiant
  final String texte;
  final String media;
  final int whenMs;
  const Brouillon(this.id, this.texte, this.media, this.whenMs);

  factory Brouillon.fromMap(Map<String, dynamic> o) => Brouillon(
        o.os('id'),
        o.os('texte'),
        o.os('media'),
        iso(o.os('publish_at')),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'texte': texte,
        if (media.isNotEmpty) 'media': media,
        if (whenMs > 0) 'publish_at': isoOf(whenMs),
      };
}

class Brouillons {
  static const _fichier = 'posts/brouillons.json';

  static Future<List<Brouillon>> charge() async {
    final a = await Api.readArr(_fichier);
    final out = <Brouillon>[];
    for (final e in a) {
      final b = Brouillon.fromMap(asObj(e));
      if (b.id.isNotEmpty) out.add(b);
    }
    return out;
  }

  static Future<void> ajoute(String texte, String media, int whenMs) async {
    await Api.updateJson(_fichier, true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      a.add(Brouillon('${DateTime.now().millisecondsSinceEpoch}', texte, media,
              whenMs)
          .toMap());
      return a;
    }, 'Brouillon enregistré');
  }

  static Future<void> supprime(String id) async {
    await Api.updateJson(_fichier, true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      a.removeWhere((e) => e is Map<String, dynamic> && asObj(e).os('id') == id);
      return a;
    }, 'Brouillon supprimé');
  }
}

/* ---------- étiquettes de la bibliothèque ---------- */

class MediaTags {
  static const _fichier = 'media/tags.json';

  /// path → liste d'étiquettes.
  static Future<Map<String, List<String>>> charge() async {
    final o = await Api.readObj(_fichier);
    final out = <String, List<String>>{};
    o?.forEach((k, v) {
      if (v is List) out[k] = [for (final t in v) t.toString()];
    });
    return out;
  }

  static Future<void> definit(String path, List<String> tags) async {
    await Api.updateJson(_fichier, false, (cur) {
      final o = asObj(cur);
      if (tags.isEmpty) {
        o.remove(path);
      } else {
        o[path] = tags;
      }
      return o;
    }, 'Étiquettes de médias mises à jour');
  }
}

/* ---------- top publications (écran Stats) ---------- */

class TopPost {
  final String id;
  final String texte;
  final int commentaires;
  final int ts;
  const TopPost(this.id, this.texte, this.commentaires, this.ts);
}

/// Posts classés par nombre de commentaires reçus (dans commentaires.json).
List<TopPost> topPosts(Map<String, dynamic>? cm, {int max = 5}) {
  if (cm == null) return const [];
  final out = <TopPost>[];
  for (final p in asArr(cm['posts'])) {
    final po = asObj(p);
    final cc = po['comments'];
    final da = cc is Map<String, dynamic>
        ? asArr(cc['data'])
        : (cc is List ? cc : const <dynamic>[]);
    var txt = po.os('message');
    if (txt.isEmpty) txt = po.os('story');
    if (txt.isEmpty) txt = 'Publication sans texte';
    out.add(TopPost(
        po.os('id'), txt, da.length, iso(po.os('created_time'))));
  }
  out.sort((a, b) => b.commentaires.compareTo(a.commentaires));
  return out.length > max ? out.sublist(0, max) : out;
}

/// Somme des n dernières valeurs d'une métrique (comparaison semaine).
double sommeRecente(List<double> vals, int n) {
  final s = n.clamp(0, vals.length);
  var t = 0.0;
  for (var i = vals.length - s; i < vals.length; i++) {
    t += vals[i];
  }
  return t;
}

/// Somme des n valeurs précédentes (semaine d'avant).
double sommePrecedente(List<double> vals, int n) {
  final fin = vals.length - n.clamp(0, vals.length);
  final deb = fin - n;
  var t = 0.0;
  for (var i = deb < 0 ? 0 : deb; i < fin; i++) {
    t += vals[i];
  }
  return t;
}
