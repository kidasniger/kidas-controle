import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Accès GitHub (API REST) + modèles partagés par les écrans.
/// Port fidèle de Api.java (v1 Java) — mêmes chemins, mêmes messages d'erreur.
class ApiError implements Exception {
  final int status;
  final String message;
  final String path;
  ApiError(this.status, this.message, this.path);
  @override
  String toString() => message;
}

/// Fichier du dépôt de données : sha (pour PUT/DELETE) + contenu texte.
class FileData {
  final String sha;
  final String text;
  FileData(this.sha, this.text);
}

/* ---------- helpers JSON (équivalents optXxx de org.json) ---------- */

Map<String, dynamic> asObj(dynamic v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

List<dynamic> asArr(dynamic v) => v is List ? v : const <dynamic>[];

extension J on Map<String, dynamic> {
  String os(String k, [String d = '']) =>
      this[k] == null ? d : this[k].toString();
  bool ob(String k, [bool d = true]) =>
      this[k] is bool ? this[k] as bool : d;
  int oi(String k, [int d = 0]) {
    final v = this[k];
    return v is num ? v.toInt() : d;
  }
}

class Api {
  static String tok = '';
  static String data = 'kidasniger/facebook-data';
  static String mgr = 'kidasniger/facebook-manager';
  static String exp = '';
  static List<dynamic>? _wf;
  static const queues = ['queue', 'avance', 'replies', 'actions', 'messages'];

  static final http.Client _c = http.Client();
  static const _base = 'https://api.github.com';

  /// Charge la configuration depuis le stockage sécurisé.
  static void loadCfg(Map<String, String> s) {
    tok = s['gh_token'] ?? '';
    final d = s['cfg_data'] ?? '';
    if (d.isNotEmpty) data = d;
    final m = s['cfg_mgr'] ?? '';
    if (m.isNotEmpty) mgr = m;
    exp = s['cfg_exp'] ?? '';
  }

  /// Invalide le cache des workflows (bouton rafraîchir).
  static void resetCache() => _wf = null;

  static String isoNow() =>
      '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

  /* ---------- messages d'erreur ---------- */

  static String need(String p) {
    var path = p;
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    final repo = path.contains('/$mgr/') ? mgr : data;
    if (path.contains('/actions/variables')) {
      return 'Variables : Read and write sur $mgr';
    }
    if (path.contains('/actions/')) return 'Actions : Read and write sur $mgr';
    return 'Contents : Read and write sur $repo';
  }

  static String hint(Object e) {
    if (e is ApiError) {
      if (e.status == 401) return 'Jeton invalide ou expiré. Va dans Réglages.';
      if (e.status == 403 || e.status == 404) {
        return 'Droit manquant sur le jeton : ${need(e.path)}.';
      }
      return e.message;
    }
    return e.toString();
  }

  /* ---------- HTTP ---------- */

  static String cp(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  static http.Request _rq(String method, String path, String? accept) {
    final r = http.Request(method, Uri.parse('$_base$path'));
    r.headers['Authorization'] = 'Bearer $tok';
    r.headers['Accept'] = accept ?? 'application/vnd.github+json';
    r.headers['X-GitHub-Api-Version'] = '2022-11-28';
    r.headers['User-Agent'] = 'kidas-controle';
    return r;
  }

  /// Requête générique. 204 → chaîne vide ; >=400 → ApiError avec message GitHub.
  static Future<String> req(String method, String path,
      {String? body, String? accept}) async {
    final r = _rq(method, path, accept);
    var b = body;
    if (b == null &&
        (method == 'POST' || method == 'PUT' || method == 'PATCH')) {
      b = '{}';
    }
    if (b != null) {
      r.headers['Content-Type'] = 'application/json';
      r.body = b;
    }
    http.StreamedResponse resp;
    try {
      resp = await _c.send(r).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiError(0, 'Délai dépassé, réessaie.', path);
    } catch (_) {
      throw ApiError(0, 'Réseau indisponible.', path);
    }
    final String txt;
    try {
      txt = await resp.stream.bytesToString().timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw ApiError(0, 'Délai dépassé, réessaie.', path);
    } catch (_) {
      throw ApiError(0, 'Réseau indisponible.', path);
    }
    if (resp.statusCode == 204) return '';
    if (resp.statusCode >= 400) {
      var msg = 'HTTP ${resp.statusCode}';
      try {
        final j = jsonDecode(txt);
        if (j is Map && j['message'] != null && j['message'].toString().isNotEmpty) {
          msg = j['message'].toString();
        }
      } catch (_) {/* corps non JSON */}
      throw ApiError(resp.statusCode, msg, path);
    }
    return txt;
  }

  static Future<Uint8List> getBytes(String path) async {
    final r = _rq('GET', path, 'application/vnd.github.raw+json');
    try {
      final resp = await _c.send(r).timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 400) {
        throw ApiError(resp.statusCode, 'HTTP ${resp.statusCode}', path);
      }
      return await resp.stream.toBytes().timeout(const Duration(seconds: 40));
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError(0, 'Délai dépassé, réessaie.', path);
    } catch (_) {
      throw ApiError(0, 'Réseau indisponible.', path);
    }
  }

  /* ---------- fichiers du dépôt de données ---------- */

  static Future<FileData?> getFile(String repo, String path) async {
    final url = '/repos/$repo/contents/${cp(path)}';
    String t;
    try {
      t = await req('GET', url);
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
    Map<String, dynamic>? o;
    try {
      final j = jsonDecode(t);
      if (j is Map<String, dynamic>) o = j;
    } catch (_) {
      return null;
    }
    if (o == null) return null;
    final c = o.os('content').replaceAll(RegExp(r'\s'), '');
    final txt = c.isNotEmpty
        ? utf8.decode(base64Decode(c))
        : await req('GET', url, accept: 'application/vnd.github.raw+json');
    return FileData(o.os('sha'), txt);
  }

  static Future<dynamic> readJson(String path) async {
    final f = await getFile(data, path);
    if (f == null || f.text.trim().isEmpty) return null;
    try {
      return jsonDecode(f.text);
    } catch (_) {
      return null;
    }
  }

  static Future<List<dynamic>> readArr(String path) async => asArr(await readJson(path));

  static Future<Map<String, dynamic>?> readObj(String path) async {
    final v = await readJson(path);
    return v is Map<String, dynamic> ? v : null;
  }

  /// Réessaie jusqu'à 5 fois sur 409/422 (conflit) avec back-off.
  static Future<T> retry<T>(Future<T> Function(int attempt) f) async {
    Object? last;
    for (var i = 0; i < 5; i++) {
      try {
        return await f(i);
      } on ApiError catch (e) {
        last = e;
        if (e.status == 409 || e.status == 422) {
          await Future.delayed(
              Duration(milliseconds: 700 * (i + 1) + Random().nextInt(500)));
          continue;
        }
        rethrow;
      }
    }
    throw last!;
  }

  /// Lit, modifie et réécrit un fichier JSON (reprise automatique en cas de conflit).
  static Future<void> updateJson(String path, bool isArray,
      FutureOr<Object?> Function(Object? cur) m, String msg) async {
    await retry((_) async {
      final f = await getFile(data, path);
      Object? cur;
      if (f != null && f.text.trim().isNotEmpty) {
        try {
          cur = jsonDecode(f.text);
        } catch (_) {
          cur = null;
        }
      }
      cur ??= isArray ? <dynamic>[] : <String, dynamic>{};
      Object? out = await m(cur);
      out ??= cur;
      const enc = JsonEncoder.withIndent('  ');
      final s = enc.convert(out);
      final body = <String, dynamic>{
        'message': msg,
        'content': base64Encode(utf8.encode('$s\n')),
      };
      if (f != null) body['sha'] = f.sha;
      await req('PUT', '/repos/$data/contents/${cp(path)}',
          body: jsonEncode(body));
    });
  }

  static Future<List<dynamic>> listDir(String path) async {
    try {
      final t = await req('GET', '/repos/$data/contents/${cp(path)}');
      return asArr(jsonDecode(t));
    } on ApiError catch (e) {
      if (e.status == 404) return const [];
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> deleteFile(String path, String name, String sha) =>
      retry((_) async {
        await req('DELETE', '/repos/$data/contents/${cp(path)}',
            body: jsonEncode({'message': 'Suppression media $name', 'sha': sha}));
      });

  /// Envoie un fichier dans media/ en flux (base64 par tranches de 96 Ko).
  static Future<String> upload(File file, String displayName,
      {void Function(String)? say}) async {
    final size = file.lengthSync();
    if (size > 50 * 1024 * 1024) {
      throw Exception('Fichier trop gros (maximum 50 Mo).');
    }
    final name =
        '${DateTime.now().millisecondsSinceEpoch}-${displayName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final path = 'media/$name';
    await retry((i) async {
      say?.call(i > 0 ? 'Nouvelle tentative ${i + 1}...' : 'Envoi...');
      await _putStream(file, size, '/repos/$data/contents/${cp(path)}',
          'Ajout media $name');
    });
    return path;
  }

  static Future<void> _putStream(
      File file, int size, String path, String msg) async {
    final pre = utf8.encode('{"message":${jsonEncode(msg)},"content":"');
    final suf = utf8.encode('"}');
    final r = http.StreamedRequest('PUT', Uri.parse('$_base$path'));
    r.headers['Authorization'] = 'Bearer $tok';
    r.headers['Accept'] = 'application/vnd.github+json';
    r.headers['X-GitHub-Api-Version'] = '2022-11-28';
    r.headers['Content-Type'] = 'application/json';
    if (size > 0) {
      r.headers['Content-Length'] =
          '${pre.length + 4 * ((size + 2) ~/ 3) + suf.length}';
    }
    // remplissage du corps en tâche de fond
    () async {
      r.sink.add(pre);
      const step = 96 * 1024; // multiple de 3 : tranches base64 indépendantes
      for (var off = 0; off < size; off += step) {
        final end = min(off + step, size);
        final b = BytesBuilder(copy: false);
        await for (final chunk in file.openRead(off, end)) {
          b.add(chunk);
        }
        r.sink.add(utf8.encode(base64Encode(b.takeBytes())));
      }
      r.sink.add(suf);
      await r.sink.close();
    }();
    http.StreamedResponse resp;
    try {
      resp = await _c.send(r).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiError(0, 'Délai dépassé, réessaie.', path);
    } catch (_) {
      throw ApiError(0, 'Réseau indisponible ou lecture impossible.', path);
    }
    final String txt;
    try {
      txt = await resp.stream.bytesToString().timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw ApiError(0, 'Délai dépassé, réessaie.', path);
    } catch (_) {
      throw ApiError(0, 'Réseau indisponible ou lecture impossible.', path);
    }
    if (resp.statusCode >= 400) {
      var m2 = 'HTTP ${resp.statusCode}';
      try {
        final j = jsonDecode(txt);
        if (j is Map && j['message'] != null) m2 = j['message'].toString();
      } catch (_) {}
      throw ApiError(resp.statusCode, m2, path);
    }
  }

  /* ---------- GitHub Actions ---------- */

  static Future<void> dispatch(String file, Map<String, dynamic>? inputs) async {
    final b = <String, dynamic>{'ref': 'main'};
    if (inputs != null) b['inputs'] = inputs;
    await req('POST', '/repos/$mgr/actions/workflows/$file/dispatches',
        body: jsonEncode(b));
  }

  static Future<List<dynamic>> workflows(bool force) async {
    if (_wf == null || force) {
      final j = asObj(jsonDecode(
          await req('GET', '/repos/$mgr/actions/workflows?per_page=50')));
      _wf = asArr(j['workflows']);
    }
    return _wf!;
  }

  static Map<String, dynamic>? wfByFile(List<dynamic> list, String file) {
    for (final w in list) {
      if (w is Map<String, dynamic> && w.os('path').endsWith('/$file')) return w;
    }
    return null;
  }

  static Future<List<dynamic>> runs(int n) async {
    final j = asObj(jsonDecode(
        await req('GET', '/repos/$mgr/actions/runs?per_page=$n')));
    return asArr(j['workflow_runs']);
  }

  static Future<String?> getVar(String n) async {
    try {
      final j = asObj(jsonDecode(
          await req('GET', '/repos/$mgr/actions/variables/$n')));
      return j.os('value');
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  static Future<void> setVar(String n, String v) async {
    final b = jsonEncode({'name': n, 'value': v});
    final base = '/repos/$mgr/actions/variables';
    try {
      await req('PATCH', '$base/$n', body: b);
    } on ApiError catch (e) {
      if (e.status == 404) {
        await req('POST', base, body: b);
      } else if (e.status == 0) {
        try {
          await req('DELETE', '$base/$n');
        } on ApiError catch (_) {/* absent */}
        await req('POST', base, body: b);
      } else {
        rethrow;
      }
    }
  }

  static Future<void> cancelRun(int id) =>
      req('POST', '/repos/$mgr/actions/runs/$id/cancel');

  static Future<void> startAudit() async {
    await updateJson('audit/demande.json', false,
        (_) => {'status': 'demande', 'date': isoNow()}, "Demande d'audit");
    await dispatch('audit.yml', null);
  }

  static dynamic jsonDecodeSafe(String t) {
    try {
      return jsonDecode(t);
    } catch (_) {
      return null;
    }
  }

  /* ---------- état du bot ---------- */

  static Future<Bot> botState() async {
    final b = Bot();
    Map<String, dynamic>? cfg;
    String? live, auto;
    List<dynamic> wl = const [];
    String runsRaw = '';
    await Future.wait<dynamic>([
      readObj('glm/config.json').then((v) { cfg = v; }).catchError((Object e) {}),
      getVar('GLM_LIVE').then((v) { live = v; }).catchError((Object e) {}),
      getVar('AUTO_REPONSES').then((v) { auto = v; }).catchError((Object e) {}),
      workflows(false).then((v) { wl = v; }).catchError((Object e) {}),
      req('GET', '/repos/$mgr/actions/workflows/glm-live.yml/runs?per_page=10')
          .then((v) { runsRaw = v; }).catchError((Object e) {}),
    ]);
    if (cfg != null) b.cfg = cfg!;
    b.live = live;
    b.auto = auto;
    final v = wfByFile(wl, 'glm-veille.yml');
    b.veille = v?.os('state');
    final rr = asObj(jsonDecodeSafe(runsRaw));
    for (final r in asArr(rr['workflow_runs'])) {
      if (asObj(r).os('status') != 'completed') b.running++;
    }
    b.hardOff = b.live == 'off';
    b.softOff = b.cfg.containsKey('actif') && !b.cfg.ob('actif', true);
    b.state = (b.hardOff || b.softOff) ? 'off' : (b.running > 0 ? 'on' : 'wait');
    return b;
  }

  /* ---------- tableau de bord (accueil + stats) ---------- */

  static Future<Dash> dash() async {
    final d = Dash();
    await Future.wait<dynamic>([
      readObj('inbox/statistiques.json').then((v) { d.st = v; }).catchError((Object e) { d.errs.add(hint(e)); }),
      readObj('inbox/commentaires.json').then((v) { d.cm = v; }).catchError((Object e) { d.errs.add(hint(e)); }),
      for (var i = 0; i < queues.length; i++)
        readArr('posts/${queues[i]}.json').then((a) {
          for (final e in a) {
            final m = asObj(e);
            d.total[i]++;
            if (m.os('status') == 'pending') d.pending[i]++;
          }
        }).catchError((Object e) {}),
      runs(20).then((v) { d.runs = v; }).catchError((Object e) { d.errs.add(hint(e)); }),
      botState().then((v) { d.bot = v; }).catchError((Object e) {}),
    ]);
    return d;
  }

  static const _names = {
    'page_post_engagements': 'Interactions',
    'page_media_view': 'Vues du contenu',
    'page_views_total': 'Visites de la Page',
    'page_follows': 'Abonnés (total)',
    'page_daily_follows_unique': 'Nouveaux abonnés par jour',
  };

  static List<Metric> metrics(Map<String, dynamic>? st) {
    final out = <Metric>[];
    if (st == null) return out;
    final ms = st['metriques'];
    if (ms is! Map<String, dynamic>) return out;
    ms.forEach((k, mv) {
      final m = asArr(mv);
      if (m.isEmpty) return;
      final first = asObj(m.first);
      final vs = asArr(first['valeurs']);
      final nums = <double>[];
      final labs = <String?>[];
      var allLab = true;
      for (final vv in vs) {
        final v = asObj(vv);
        final o = v['valeur'];
        if (o is! num) continue;
        nums.add(o.toDouble());
        final lab = dayLabel(v);
        if (lab == null) allLab = false;
        labs.add(lab);
      }
      if (nums.isEmpty) return;
      final mt = Metric()
        ..key = k
        ..name = _names[k] ?? k
        ..vals = nums;
      if (allLab) mt.labs = labs;
      out.add(mt);
    });
    return out;
  }

  static String? dayLabel(Map<String, dynamic> v) {
    for (final k in const ['date', 'fin', 'end_time', 'fin_periode', 'debut']) {
      final s = v.os(k);
      if (s.length >= 10 && s[4] == '-') {
        return '${s.substring(8, 10)}/${s.substring(5, 7)}';
      }
    }
    return null;
  }

  /* ---------- commentaires ---------- */

  static List<Cmt> flatComments(Map<String, dynamic>? cm) {
    final out = <Cmt>[];
    if (cm == null) return out;
    for (final p in asArr(cm['posts'])) {
      final po = asObj(p);
      final cc = po['comments'];
      final da = cc is Map<String, dynamic> ? asArr(cc['data']) : const <dynamic>[];
      for (final c in da) {
        if (c is Map<String, dynamic>) out.add(Cmt(c, po));
      }
    }
    out.sort((a, b) =>
        b.c.os('created_time').compareTo(a.c.os('created_time')));
    return out;
  }

  static List<Cmt> unanswered(List<Cmt> all, String? pageId) {
    final out = <Cmt>[];
    for (final x in all) {
      final from = asObj(x.c['from']);
      final fid = from.os('id');
      if (x.c.os('message').isNotEmpty &&
          x.c.containsKey('page_a_repondu') &&
          !x.c.ob('page_a_repondu', true) &&
          fid != (pageId ?? '')) {
        out.add(x);
      }
    }
    return out;
  }

  /* ---------- messages (Messenger) ---------- */

  /// Messenger n'autorise la réponse que 24 h après le dernier message de la personne.
  static const fenetreMs = Duration(hours: 24);
  static const messageMax = 1000;

  /// Conversations de inbox/messages.json, la plus récente d'abord.
  static List<Map<String, dynamic>> conversations(Map<String, dynamic>? inbox) {
    final out = <Map<String, dynamic>>[];
    for (final c in inbox == null ? const <dynamic>[] : asArr(inbox['conversations'])) {
      if (c is Map<String, dynamic>) out.add(c);
    }
    out.sort((x, y) => y.os('updated_time').compareTo(x.os('updated_time')));
    return out;
  }

  /// Vrai quand le dernier message vient de la personne (la Page n'a pas encore répondu).
  static bool needsReply(Map<String, dynamic> conv) {
    final m = conv['messages'];
    return m is List && m.isNotEmpty && !conv.ob('repondu', true);
  }

  static int iso(String s) {
    if (s.isEmpty) return 0;
    final d = DateTime.tryParse(s);
    return d?.millisecondsSinceEpoch ?? 0;
  }

  static bool windowOpen(Map<String, dynamic> conv) {
    final t = iso(conv.os('last_user_time'));
    return t > 0 &&
        DateTime.now().millisecondsSinceEpoch - t < fenetreMs.inMilliseconds;
  }

  /// Dernier élément de posts/messages.json pour cette conversation, ou null.
  static Map<String, dynamic>? lastQueued(List<dynamic> queue, String convId) {
    Map<String, dynamic>? r;
    for (final e in queue) {
      final m = asObj(e);
      if (m.os('conversation_id') == convId) r = m;
    }
    return r;
  }

  /// Met une réponse Messenger en file : le bot l'envoie à son prochain cycle (~1 min).
  static Future<void> queueMessage(String convId, String recipientId, String text) =>
      updateJson('posts/messages.json', true, (cur) {
        final a = (cur is List ? cur : <dynamic>[]).toList();
        a.add({
          'conversation_id': convId,
          'recipient_id': recipientId,
          'message': text,
          'status': 'pending',
          'created': isoNow(),
        });
        return a;
      }, 'Message (appli de contrôle)');

  static String pageId(Map<String, dynamic>? st, Map<String, dynamic>? cm) {
    final p = st == null ? null : st['page'];
    if (p is Map<String, dynamic> && p.containsKey('id')) return p.os('id');
    final p2 = cm?['page'];
    return p2 is Map<String, dynamic> ? p2.os('id') : '';
  }
}

/* ---------- modèles partagés (ex-Java : classes internes de Api) ---------- */

class Bot {
  Map<String, dynamic> cfg = {};
  String? live, auto, veille;
  int running = 0;
  bool hardOff = false, softOff = false;
  String state = 'wait';
}

class Metric {
  String key = '', name = '';
  List<double> vals = [];
  List<String?>? labs;
}

class Dash {
  Map<String, dynamic>? st, cm;
  List<dynamic> runs = const [];
  Bot? bot;
  final List<int> pending = List.filled(Api.queues.length, 0);
  final List<int> total = List.filled(Api.queues.length, 0);
  final List<String> errs = [];
}

class Cmt {
  final Map<String, dynamic> c;
  final Map<String, dynamic> post;
  Cmt(this.c, this.post);
}
