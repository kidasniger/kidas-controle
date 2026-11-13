import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'native.dart';

/// Mise à jour de l'application depuis les Releases GitHub.
/// Port de Updater.java : vérification, téléchargement (reprise possible),
/// contrôle SHA-256, puis installation 100% native (MethodChannel).
class UpdInfo {
  int code = 0, current = 0;
  String name = '', curName = '', notes = '';
  bool mandatory = false, available = false;
  String apkWeb = '', apkApi = '', shaWeb = '', shaApi = '';
  int size = 0;
}

class _Cancelled implements Exception {
  @override
  String toString() => 'Téléchargement annulé.';
}

class Updater {
  static const _repo = 'kidasniger/kidas-controle';
  static const _apkName = 'kidas-controle.apk';
  static const _shaName = 'kidas-controle.apk.sha256';

  static bool busy = false;
  static bool _cancel = false;
  static HttpClient? _live;

  static void cancelDownload() {
    _cancel = true;
    try {
      _live?.close(force: true);
    } catch (_) {/* déjà fermé */}
  }

  /* ---------- version installée ---------- */

  static Future<int> versionCode() => Native.versionCode();
  static Future<String> versionName() => Native.versionName();

  /* ---------- vérification ---------- */

  static Future<UpdInfo> check() async {
    final j = asObj(Api.jsonDecodeSafe(await _latest()));
    final tag = j.os('tag_name');
    final m = RegExp(r'(\d+)\s*$').firstMatch(tag);
    if (m == null || m.group(1)!.length > 9) {
      throw Exception('Numéro de version illisible ($tag).');
    }
    final i = UpdInfo();
    i.code = int.parse(m.group(1)!);
    i.current = await Native.versionCode();
    i.name = '1.0.${i.code}';
    i.curName = await Native.versionName();
    final body = j.os('body');
    i.mandatory =
        body.toLowerCase().contains('[obligatoire]');
    i.notes = body
        .replaceAll(RegExp(r'\[obligatoire\]', caseSensitive: false), '')
        .trim();
    for (final a in asArr(j['assets'])) {
      final am = asObj(a);
      final n = am.os('name');
      if (n == _apkName) {
        i.apkWeb = am.os('browser_download_url');
        i.apkApi = am.os('url');
        i.size = am.oi('size');
      } else if (n == _shaName) {
        i.shaWeb = am.os('browser_download_url');
        i.shaApi = am.os('url');
      }
    }
    if (i.apkWeb.isEmpty) {
      throw Exception("Cette version ne contient pas d'APK.");
    }
    i.available = i.code > i.current;
    return i;
  }

  static Future<String> _latest() async {
    const url = 'https://api.github.com/repos/$_repo/releases/latest';
    var auth = Api.tok.isNotEmpty;
    for (var pass = 0; pass < 2; pass++) {
      final c = http.Client();
      try {
        final r = http.Request('GET', Uri.parse(url))
          ..headers['Accept'] = 'application/vnd.github+json'
          ..headers['X-GitHub-Api-Version'] = '2022-11-28'
          ..headers['User-Agent'] = 'kidas-controle';
        if (auth && Api.tok.isNotEmpty) {
          r.headers['Authorization'] = 'Bearer ${Api.tok}';
        }
        final resp = await c.send(r).timeout(const Duration(seconds: 15));
        final txt =
            await resp.stream.bytesToString().timeout(const Duration(seconds: 40));
        if (resp.statusCode == 200) return txt;
        if (auth &&
            (resp.statusCode == 401 ||
                resp.statusCode == 403 ||
                resp.statusCode == 404)) {
          auth = false;
          continue;
        }
        if (resp.statusCode == 404) {
          throw Exception('Aucune version publiée trouvée.');
        }
        if (resp.statusCode == 403) {
          throw Exception('Limite GitHub atteinte, réessaie plus tard.');
        }
        throw Exception('GitHub a répondu HTTP ${resp.statusCode}.');
      } on TimeoutException {
        throw Exception('Délai dépassé, réessaie.');
      } finally {
        c.close();
      }
    }
    throw Exception('Impossible de lire la dernière version.');
  }

  /* ---------- HTTP bas niveau (https seulement, redirections à la main) ---------- */

  static Future<HttpClientResponse> _connect(
      String url, String accept, bool auth, int from) async {
    var cur = url;
    for (var i = 0; i < 6; i++) {
      if (!cur.startsWith('https://')) {
        throw Exception('Lien non sécurisé refusé.');
      }
      final u = Uri.parse(cur);
      final c = HttpClient();
      c.connectionTimeout = const Duration(seconds: 15);
      c.idleTimeout = const Duration(seconds: 5);
      _live = c;
      try {
        final rq = await c.openUrl('GET', u);
        rq.followRedirects = false;
        rq.maxRedirects = 0;
        rq.headers.set('Accept', accept);
        rq.headers.set('User-Agent', 'kidas-controle');
        if (u.host == 'api.github.com') {
          rq.headers.set('X-GitHub-Api-Version', '2022-11-28');
          if (auth && Api.tok.isNotEmpty) {
            rq.headers.set('Authorization', 'Bearer ${Api.tok}');
          }
        }
        if (from > 0) {
          rq.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
        }
        final resp = await rq.close().timeout(const Duration(seconds: 15));
        final code = resp.statusCode;
        if (code >= 300 && code < 400 && code != 304) {
          final loc = resp.headers.value(HttpHeaders.locationHeader);
          try {
            await resp.drain<void>();
          } catch (_) {}
          c.close();
          if (loc == null || loc.isEmpty) {
            throw Exception('Redirection invalide.');
          }
          cur = u.resolve(loc).toString();
          continue;
        }
        return resp; // le client reste ouvert : le corps va être lu
      } catch (_) {
        c.close(force: true);
        rethrow;
      }
    }
    throw Exception('Trop de redirections.');
  }

  /// Lien public d'abord ; si le dépôt est privé, lien d'API avec le jeton.
  static Future<HttpClientResponse> _openAsset(String web, String api, int from) async {
    var resp = await _connect(web, 'application/octet-stream', false, from);
    final code = resp.statusCode;
    if ((code == 401 || code == 403 || code == 404) &&
        Api.tok.isNotEmpty &&
        api.isNotEmpty) {
      try {
        await resp.drain<void>();
      } catch (_) {}
      resp = await _connect(api, 'application/octet-stream', true, from);
    }
    return resp;
  }

  static void _done() {
    try {
      _live?.close(force: true);
    } catch (_) {}
    _live = null;
  }

  /* ---------- téléchargement ---------- */

  static Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/updates');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<File> download(
      UpdInfo i, void Function(int done, int total)? onProgress) async {
    if (busy) throw Exception('Un téléchargement est déjà en cours.');
    busy = true;
    _cancel = false;
    try {
      final d = await _dir();
      final fin = File('${d.path}/kidas-controle-${i.code}.apk');
      final part = File('${fin.path}.part');
      if (await fin.exists() && (i.size <= 0 || (await fin.length()) == i.size)) {
        try {
          await _verify(fin.path, i.code);
          onProgress?.call(i.size, i.size);
          return fin;
        } catch (_) {
          await fin.delete();
        }
      } else if (await fin.exists()) {
        await fin.delete();
      }
      await _fetch(i, part, onProgress);
      if (i.size > 0 && (await part.length()) != i.size) {
        await part.delete();
        throw Exception('Fichier incomplet, réessaie.');
      }
      final want = await _fetchSha(i);
      if (want.isNotEmpty && want != await _sha256(part)) {
        await part.delete();
        throw Exception('Somme de contrôle invalide : fichier corrompu, réessaie.');
      }
      await part.rename(fin.path);
      await _verify(fin.path, i.code);
      return fin;
    } finally {
      busy = false;
    }
  }

  static Future<void> _fetch(
      UpdInfo i, File part, void Function(int, int)? p) async {
    var have = await part.exists() ? await part.length() : 0;
    if (i.size > 0 && have > i.size) {
      await part.delete();
      have = 0;
    }
    if (i.size > 0 && have == i.size) {
      p?.call(have, i.size);
      return;
    }
    try {
      var resp = await _openAsset(i.apkWeb, i.apkApi, have);
      var code = resp.statusCode;
      if (code == 416) {
        try {
          await resp.drain<void>();
        } catch (_) {}
        await part.delete();
        have = 0;
        resp = await _openAsset(i.apkWeb, i.apkApi, 0);
        code = resp.statusCode;
      }
      if (code != 200 && code != 206) {
        throw Exception('Téléchargement impossible (HTTP $code).');
      }
      final append = code == 206 && have > 0;
      if (!append) have = 0;
      final len = resp.contentLength;
      final total = i.size > 0 ? i.size : (len > 0 ? len + have : 0);
      final out = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var done = have;
      var last = 0;
      try {
        await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
          if (_cancel) throw _Cancelled();
          out.add(chunk);
          done += chunk.length;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (p != null && now - last > 120) {
            last = now;
            p(done, total);
          }
        }
        await out.flush();
      } finally {
        await out.close();
      }
      p?.call(done, total);
    } on _Cancelled {
      rethrow;
    } on TimeoutException {
      if (_cancel) throw _Cancelled();
      throw Exception('Connexion trop lente. Réessaie pour reprendre.');
    } catch (e) {
      if (_cancel) throw _Cancelled();
      if (e is Exception) rethrow;
      throw Exception('Connexion interrompue. Réessaie pour reprendre.');
    } finally {
      _done();
    }
  }

  /* ---------- intégrité ---------- */
  static Future<String> _fetchSha(UpdInfo i) async {
    if (i.shaWeb.isEmpty) return '';
    try {
      final resp = await _openAsset(i.shaWeb, i.shaApi, 0);
      final code = resp.statusCode;
      if (code != 200) {
        throw Exception('Somme de contrôle introuvable (HTTP $code).');
      }
      final t = utf8.decode(await resp.fold<List<int>>(
          <int>[], (a, b) => a..addAll(b)));
      final h = t.trim().split(RegExp(r'\s+')).first.toLowerCase();
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) {
        throw Exception('Somme de contrôle illisible.');
      }
      return h;
    } on TimeoutException {
      throw Exception('Connexion trop lente. Réessaie.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Connexion interrompue. Réessaie.');
    } finally {
      _done();
    }
  }

  static Future<String> _sha256(File f) async {
    final d = await sha256.bind(f.openRead()).first;
    return d.toString();
  }

  /// Paquet, version et signature : le contrôle final est natif (Keystore).
  static Future<void> _verify(String path, int code) async {
    try {
      await Native.verify(path, code);
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'APK refusé.');
    }
  }

  /* ---------- installation ---------- */

  static Future<bool> canInstall() => Native.canInstall();
  static Future<void> openUnknownSources() => Native.openUnknownSources();
  static Future<void> install(File apk) => Native.install(apk.path);

  /* ---------- ménage ---------- */

  static Future<void> cleanup() async {
    try {
      final cur = await Native.versionCode();
      final d = await _dir();
      final re = RegExp(r'kidas-controle-(\d+)\.apk(\.part)?');
      await for (final f in d.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        final m = re.firstMatch(name);
        if (m == null) {
          await f.delete();
          continue;
        }
        final n = int.tryParse(m.group(1)!);
        if (n == null || n <= cur) await f.delete();
      }
    } catch (_) {
      // ménage facultatif
    }
  }
}
