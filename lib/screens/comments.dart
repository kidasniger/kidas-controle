import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show Bus;

/// Avis et commentaires : sélecteur sans réponse / tous, cartes, réponse
/// mise en file puis envoyée par le bot. Port fidèle de CommentsScreen.java.
bool kShowAllComments = false;

class CommentsScreen extends StatefulWidget {
  const CommentsScreen({super.key});
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  Map<String, dynamic>? _cm;
  bool _busy = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final cm = await Api.readObj('inbox/commentaires.json');
      if (!mounted) return;
      setState(() {
        _cm = cm;
        _busy = false;
      });
      if (cm != null) {
        final all = Api.flatComments(cm);
        final pid = asObj(cm['page']).os('id');
        Bus.setAvis(Api.unanswered(all, pid).length);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = Api.hint(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _cm == null) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(90),
        SizedBox(height: 12),
        KSkeleton(120),
        SizedBox(height: 12),
        KSkeleton(120),
      ]);
    }
    if (_err != null && _cm == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [ErrBox(_err!)]);
    }
    final c = context.p;
    final cm = _cm;
    if (cm == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        KEmpty(Icons.forum_outlined,
            "Aucune donnée. Lance « Surveiller » depuis l'accueil."),
      ]);
    }
    final pid = asObj(cm['page']).os('id');
    final all = Api.flatComments(cm);
    final un = Api.unanswered(all, pid);
    final upd = cm.os('updated');

    final list = kShowAllComments ? all : un;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        KSegmented(
          ['Sans réponse (${un.length})', 'Tous (${all.length})'],
          sel: kShowAllComments ? 1 : 0,
          onSelect: (i) {
            Fx.tick();
            setState(() => kShowAllComments = i == 1);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Données du dernier audit : ${upd.isEmpty ? 'date inconnue' : rel(upd)}',
          style: T.caption(c),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          KEmpty(Icons.chat_bubble_outline, 'Aucun commentaire à afficher.')
        else ...[
          for (var i = 0; i < list.length && i < 40; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CommentCard(cmt: list[i], pid: pid),
            ),
          if (list.length > 40)
            KEmpty(Icons.filter_alt_outlined, '40 plus récents affichés.'),
        ],
      ],
    );
  }
}

class _CommentCard extends StatefulWidget {
  final Cmt cmt;
  final String pid;
  const _CommentCard({required this.cmt, required this.pid});
  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _open = false;
  bool _queued = false;
  final _ta = TextEditingController();

  @override
  void dispose() {
    _ta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final x = widget.cmt;
    final from = asObj(x.c['from']);
    final name = from.os('name').isEmpty ? 'Abonné' : from.os('name');
    final mine = from.os('id') == widget.pid;
    final msg = x.c.os('message');
    final post = x.post.os('message').isEmpty
        ? (x.post.os('story').isEmpty ? 'publication' : x.post.os('story'))
        : x.post.os('message');
    final answered = x.c.ob('page_a_repondu', false);
    final body = msg.isEmpty ? '(sans texte)' : msg;

    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(mine ? 'Ta Page' : name, style: T.strong(c).copyWith(fontSize: 15))),
          Text(rel(x.c.os('created_time')), style: T.caption(c)),
        ]),
        const SizedBox(height: 6),
        Text(body, style: T.body(c).copyWith(fontSize: 14.5)),
        const SizedBox(height: 6),
        Text('Sur : ${post.length > 90 ? post.substring(0, 90) : post}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.caption(c)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              StatusChip(answered ? 'Répondu' : 'Sans réponse',
                  kind: answered ? 1 : 2),
              if (_queued) const StatusChip('En file', kind: 4),
            ]),
          ),
          if (!mine && !_queued && !answered)
            ActionBtn('Répondre',
                height: 38,
                variant: KBtnVariant.ghost,
                job: () async => setState(() => _open = !_open)),
        ]),
        if (_open && !_queued) ...[
          const SizedBox(height: 10),
          KEdit(controller: _ta, hint: 'Ta réponse...', minLines: 3),
          const SizedBox(height: 8),
          ActionBtn('Mettre en file',
              job: () async {
                final t = _ta.text.trim();
                if (t.isEmpty) throw Exception('Écris une réponse.');
                final cid = x.c.os('id');
                await Api.updateJson('posts/replies.json', true, (cur) {
                  final a = (cur is List ? cur : <dynamic>[]).toList();
                  a.add({
                    'comment_id': cid,
                    'message': t,
                    'status': 'pending',
                  });
                  return a;
                }, 'Réponse (appli de contrôle)');
                var launched = false;
                try {
                  await Api.dispatch('repondre.yml', null);
                  launched = true;
                } catch (_) {/* traité sous 5 à 10 min */}
                setState(() {
                  _open = false;
                  _queued = true;
                });
                kToast(
                    context,
                    launched
                        ? 'Réponse mise en file et lancée.'
                        : 'Réponse mise en file : traitée sous 5 à 10 min.');
              }),
        ],
      ]),
    );
  }
}
