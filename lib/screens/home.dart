import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show Bus, SubPage;
import 'ai_chat.dart';
import 'comments.dart';
import 'messages.dart';
import 'publish.dart';

/// Accueil « façon page Facebook » : la barre de rédaction, les chiffres de
/// la Page, ce qui attend une réponse et le fil de tout ce qui s'est passé
/// (avis + messages). Aucune exécution technique ici — c'est dans l'onglet Bot.
class HomeScreen extends StatefulWidget {
  final int gen;
  const HomeScreen({super.key, this.gen = 0});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Un élément du fil : un avis (commentaire) ou une conversation Messenger.
class _FeedItem {
  final String kind; // 'avis' ou 'msg'
  final int ts;
  final Cmt? cmt;
  final Map<String, dynamic>? conv;
  const _FeedItem(this.kind, this.ts, {this.cmt, this.conv});
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _st, _cm, _inbox;
  int _avisTodo = 0, _msgTodo = 0;
  String _upd = '';
  final List<String> _errs = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.gen != widget.gen) _load();
  }

  Future<void> _load() async {
    setState(() => _busy = _st == null && _cm == null);
    final errs = <String>[];
    Map<String, dynamic>? st, cm, inbox;
    await Future.wait<dynamic>([
      Api.readObj('inbox/statistiques.json')
          .then((v) { st = v; })
          .catchError((Object e) { errs.add(Api.hint(e)); }),
      Api.readObj('inbox/commentaires.json')
          .then((v) { cm = v; })
          .catchError((Object e) { errs.add(Api.hint(e)); }),
      Api.readObj('inbox/messages.json')
          .then((v) { inbox = v; })
          .catchError((Object e) {}),
    ]);
    if (!mounted) return;
    final fcm = cm, finbox = inbox;
    var avisTodo = 0, msgTodo = 0;
    var upd = '';
    if (fcm != null) {
      final pid = asObj(fcm['page']).os('id');
      avisTodo = Api.unanswered(Api.flatComments(fcm), pid).length;
      final u = fcm.os('updated');
      if (u.isNotEmpty) upd = u;
    }
    if (finbox != null) {
      for (final conv in Api.conversations(finbox)) {
        if (Api.needsReply(conv)) msgTodo++;
      }
      final u = finbox.os('updated');
      if (u.compareTo(upd) > 0) upd = u;
    }
    setState(() {
      _st = st;
      _cm = cm;
      _inbox = inbox;
      _avisTodo = avisTodo;
      _msgTodo = msgTodo;
      _upd = upd;
      _errs
        ..clear()
        ..addAll(errs);
      _busy = false;
    });
    Bus.setAvis(avisTodo);
    Bus.setMsg(msgTodo);
  }

  void _go(String title, Widget screen) {
    Fx.tick();
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SubPage(title, child: screen)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_busy && _st == null && _cm == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          KSkeleton(64),
          SizedBox(height: 12),
          KSkeleton(90),
          SizedBox(height: 12),
          KSkeleton(110),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        _composer(c),
        const SizedBox(height: 12),
        _kpiStrip(c),
        if (_avisTodo > 0 || _msgTodo > 0) ...[
          const SizedBox(height: 12),
          _todoCard(c),
        ],
        for (final e in _errs.take(2))
          Padding(padding: const EdgeInsets.only(top: 8), child: ErrBox(e)),
        const SizedBox(height: 8),
        KSection('Fil de la Page'),
        if (_upd.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Données du dernier cycle du bot : ${rel(_upd)}',
                style: T.caption(c)),
          ),
        ..._feed(c),
        const SizedBox(height: 4),
        Text("Les exécutions du bot sont dans l'onglet Bot.",
            style: T.caption(c)),
      ],
    );
  }

  /* ---------- barre de rédaction, comme sur Facebook ---------- */

  Widget _composer(Palette c) {
    return Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: c.ink, borderRadius: BorderRadius.circular(13)),
        child: Center(
            child: Text('K',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: c.bg))),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Press(
          onTap: () => _go('Publier', const PublishScreen()),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: c.line)),
            child: Text('Quoi de neuf, Aboubacar ?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: c.muted)),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Press(
        onTap: () => _go('Assistant IA', const AiChatScreen()),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: c.accent, shape: BoxShape.circle),
          child: Icon(Icons.auto_awesome_outlined,
              size: 20, color: c.onAccent),
        ),
      ),
    ]);
  }

  /* ---------- chiffres de la Page ---------- */

  Widget _kpiStrip(Palette c) {
    final ms = Api.metrics(_st);
    Metric? find(String key) {
      for (final m in ms) {
        if (m.key == key) return m;
      }
      return null;
    }

    return KCard(
      child: Row(children: [
        _kpi(c, 'ABONNÉS', find('page_follows')),
        _vdiv(c),
        _kpi(c, 'VISITES', find('page_views_total')),
        _vdiv(c),
        _kpi(c, 'INTERACTIONS', find('page_post_engagements')),
      ]),
    );
  }

  Widget _kpi(Palette c, String label, Metric? m) {
    final v = m == null || m.vals.isEmpty ? null : m.vals.last;
    var delta = '';
    if (m != null && m.vals.length >= 2) {
      delta = pct(m.vals.last, m.vals[m.vals.length - 2]);
    }
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: T.micro(c)),
        const SizedBox(height: 3),
        Text(v == null ? '—' : nf(v), style: T.kpi(c)),
        SizedBox(
          height: 15,
          child: delta.isEmpty
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(delta,
                      style: T.caption(c)
                          .copyWith(fontWeight: FontWeight.w800))),
        ),
      ]),
    );
  }

  Widget _vdiv(Palette c) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: c.line,
    );
  }

  /* ---------- ce qui attend une réponse ---------- */

  Widget _todoCard(Palette c) {
    return KCard(
      pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(children: [
        if (_avisTodo > 0)
          _todoRow(c, Icons.chat_bubble_outline, '${nf(_avisTodo)} avis sans réponse',
              'Répondre', () => _go('Avis (commentaires)', const CommentsScreen())),
        if (_avisTodo > 0 && _msgTodo > 0) const KDivider(),
        if (_msgTodo > 0)
          _todoRow(c, Icons.messenger_outline, '${nf(_msgTodo)} messages à traiter',
              'Ouvrir', () => _go('Messages', const MessagesScreen())),
      ]),
    );
  }

  Widget _todoRow(Palette c, IconData ic, String label, String action,
      VoidCallback onTap) {
    return Press(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          IconBox(ic),
          const SizedBox(width: 11),
          Expanded(
              child: Text(label,
                  style: T.strong(c).copyWith(fontSize: 14.5))),
          KBadge(action),
        ]),
      ),
    );
  }

  /* ---------- fil unifié : avis + messages ---------- */

  List<Widget> _feed(Palette c) {
    final cm = _cm, inbox = _inbox;
    final unIds = Set<Cmt>.identity();
    final items = <_FeedItem>[];
    if (cm != null) {
      final all = Api.flatComments(cm);
      final pid = asObj(cm['page']).os('id');
      unIds.addAll(Api.unanswered(all, pid));
      for (final x in all.take(30)) {
        items.add(_FeedItem('avis', iso(x.c.os('created_time')), cmt: x));
      }
    }
    if (inbox != null) {
      for (final conv in Api.conversations(inbox).take(12)) {
        items.add(_FeedItem('msg', iso(conv.os('updated_time')), conv: conv));
      }
    }
    items.removeWhere((x) => x.ts <= 0);
    items.sort((a, b) => b.ts.compareTo(a.ts));
    if (items.isEmpty) {
      return [
        KEmpty(Icons.feed_outlined, 'Rien encore sur la Page.',
            sub: "Lance « Surveiller » dans l'onglet Bot pour remplir le fil."),
      ];
    }
    const maxItems = 18;
    final out = <Widget>[];
    for (final it in items.take(maxItems)) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: it.kind == 'avis'
            ? _avisCard(c, it.cmt!, unIds.contains(it.cmt))
            : _msgCard(c, it.conv!),
      ));
    }
    if (items.length > maxItems) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
            '${items.length - maxItems} éléments plus anciens dans Avis et Messages.',
            style: T.caption(c)),
      ));
    }
    return out;
  }

  Widget _avisCard(Palette c, Cmt x, bool unanswered) {
    final from = asObj(x.c['from']);
    final name = from.os('name').isEmpty ? 'Abonné' : from.os('name');
    final msg = x.c.os('message');
    var postTxt = x.post.os('message');
    if (postTxt.isEmpty) postTxt = x.post.os('story');
    final snippet = postTxt.isEmpty
        ? 'une publication'
        : (postTxt.length > 70 ? '${postTxt.substring(0, 70)}…' : postTxt);
    return Press(
      onTap: () => _go('Avis (commentaires)', const CommentsScreen()),
      child: KCard(
        pad: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _avatar(c, name),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.strong(c)),
                    Text(rel(x.c.os('created_time')), style: T.caption(c)),
                  ]),
            ),
            if (unanswered) const KBadge('Sans réponse'),
          ]),
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(msg, style: T.body(c).copyWith(fontSize: 14)),
          ],
          const SizedBox(height: 6),
          Text('Sur : $snippet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.caption(c)),
        ]),
      ),
    );
  }

  Widget _msgCard(Palette c, Map<String, dynamic> conv) {
    final who = asObj(conv['with']);
    final name = who.os('name').isEmpty ? 'Contact' : who.os('name');
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
    return Press(
      onTap: () => _go('Messages', const MessagesScreen()),
      child: KCard(
        pad: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _avatar(c, name),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.strong(c)),
                    Text(rel(conv.os('updated_time')), style: T.caption(c)),
                  ]),
            ),
            if (Api.needsReply(conv)) const KBadge('À répondre'),
          ]),
          const SizedBox(height: 8),
          Text(prefix + preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.body(c).copyWith(fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _avatar(Palette c, String name) {
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: c.soft, shape: BoxShape.circle, border: Border.all(color: c.line)),
      child: Text(letter,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: c.ink)),
    );
  }
}
