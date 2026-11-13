import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show Bus;

/// Messenger de la Page : conversations, fil de discussion, réponse mise
/// en file (envoyée par le bot). Port fidèle de MessagesScreen.java.
bool kShowAllConvos = false;
String kOpenConvo = '';
const int _maxCards = 30;

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  Map<String, dynamic>? _inbox;
  List<dynamic> _queue = const [];
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
      Map<String, dynamic>? inbox;
      List<dynamic> queue = const [];
      String? err;
      await Future.wait<dynamic>([
        Api.readObj('inbox/messages.json').then((v) => inbox = v),
        Api.readArr('posts/messages.json').then((v) => queue = v),
      ]).catchError((Object e) {
        err = Api.hint(e);
        return <dynamic>[];
      });
      if (!mounted) return;
      if (err != null && inbox == null) {
        setState(() {
          _err = err;
          _busy = false;
        });
        return;
      }
      setState(() {
        _inbox = inbox;
        _queue = queue;
        _busy = false;
      });
      if (inbox != null) {
        var todo = 0;
        for (final conv in Api.conversations(inbox)) {
          if (Api.needsReply(conv)) todo++;
        }
        Bus.setMsg(todo);
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
    if (_busy && _inbox == null) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(90),
        SizedBox(height: 12),
        KSkeleton(120),
        SizedBox(height: 12),
        KSkeleton(120),
      ]);
    }
    if (_err != null && _inbox == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [ErrBox(_err!)]);
    }
    final c = context.p;
    final inbox = _inbox;
    if (inbox == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        KEmpty(Icons.messenger_outline,
            "Aucune conversation pour l'instant. Le bot les écrit après son prochain cycle de lecture."),
      ]);
    }
    final all = Api.conversations(inbox);
    final todo = <Map<String, dynamic>>[];
    for (final conv in all) {
      if (Api.needsReply(conv)) todo.add(conv);
    }
    final upd = inbox.os('updated');
    final list = kShowAllConvos ? all : todo;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        KSegmented(
          ['À répondre (${todo.length})', 'Toutes (${all.length})'],
          sel: kShowAllConvos ? 1 : 0,
          onSelect: (i) {
            Fx.tick();
            setState(() => kShowAllConvos = i == 1);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Lu par le bot : ${upd.isEmpty ? 'date inconnue' : rel(upd)}',
          style: T.caption(c),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          KEmpty(Icons.messenger_outline,
              kShowAllConvos ? 'Aucune conversation.' : 'Aucun message en attente de réponse.')
        else ...[
          for (var i = 0; i < list.length && i < _maxCards; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ConvoCard(
                conv: list[i],
                queued: Api.lastQueued(_queue, list[i].os('id')),
                onSent: _load,
              ),
            ),
          if (list.length > _maxCards)
            KEmpty(Icons.filter_alt_outlined,
                '$_maxCards plus récentes affichées.'),
        ],
      ],
    );
  }
}

class _ConvoCard extends StatefulWidget {
  final Map<String, dynamic> conv;
  final Map<String, dynamic>? queued;
  final VoidCallback onSent;
  const _ConvoCard(
      {required this.conv, required this.queued, required this.onSent});
  @override
  State<_ConvoCard> createState() => _ConvoCardState();
}

class _ConvoCardState extends State<_ConvoCard> {
  Map<String, dynamic>? _queued;
  bool _open = false;
  bool _sent = false;
  final _ta = TextEditingController();

  @override
  void initState() {
    super.initState();
    _queued = widget.queued;
    _open = kOpenConvo == widget.conv.os('id');
  }

  @override
  void dispose() {
    _ta.dispose();
    super.dispose();
  }

  static String _textOf(Map<String, dynamic> m) {
    final t = m.os('message');
    return t.isEmpty ? '(pièce jointe ou sticker)' : t;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final conv = widget.conv;
    final cid = conv.os('id');
    final who = asObj(conv['with']);
    final name = who.os('name').isEmpty ? 'Contact' : who.os('name');
    final rid = who.os('id');
    final ms = conv['messages'] is List ? conv['messages'] as List<dynamic> : const <dynamic>[];
    final needs = Api.needsReply(conv);
    final winOpen = Api.windowOpen(conv);
    final qs = _queued == null ? '' : _queued!.os('status');
    final waiting = qs == 'pending' || _sent;

    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: T.strong(c).copyWith(fontSize: 15))),
          Text(rel(conv.os('updated_time')), style: T.caption(c)),
        ]),
        if (ms.isNotEmpty) ...[
          const SizedBox(height: 6),
          Builder(builder: (_) {
            final last = asObj(ms.last);
            final pre = last.ob('from_page', false) ? 'Toi : ' : '';
            return Text(pre + _textOf(last),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.body(c).copyWith(fontSize: 14.5));
          }),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (waiting)
                const StatusChip('En file', kind: 4)
              else if (qs == 'error')
                const StatusChip("Échec d'envoi", kind: 3)
              else if (needs)
                const StatusChip('Sans réponse', kind: 2)
              else
                const StatusChip('Répondu', kind: 1),
              if (needs && !winOpen) const StatusChip('24 h dépassées', kind: 3),
            ]),
          ),
          ActionBtn(_open ? 'Fermer' : 'Ouvrir',
              height: 38,
              variant: KBtnVariant.ghost,
              job: () async {
                Fx.tick();
                setState(() {
                  _open = !_open;
                  kOpenConvo = _open ? cid : '';
                });
              }),
        ]),
        if (_open) ...[
          const SizedBox(height: 4),
          for (final m in ms)
            _bubble(c, asObj(m)),
          if (waiting)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "Ta réponse est en file : le bot l'envoie à son prochain cycle (environ 1 minute).",
                style: T.caption(c),
              ),
            )
          else if (rid.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Contact introuvable : réponse impossible.',
                  style: T.caption(c)),
            )
          else if (!winOpen)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "Messenger n'autorise plus la réponse 24 h après le dernier message de la personne. "
                'Elle doit réécrire pour rouvrir la conversation.',
                style: T.caption(c),
              ),
            )
          else ...[
            if (qs == 'error')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Dernier envoi refusé${_queued!.os('erreur').isEmpty ? '.' : ' : ${_queued!.os('erreur')}.'}',
                  style: T.caption(c).copyWith(color: c.ink),
                ),
              ),
            const SizedBox(height: 10),
            KEdit(controller: _ta, hint: 'Ta réponse...', minLines: 3, maxLength: Api.messageMax),
            const SizedBox(height: 8),
            ActionBtn('Mettre en file',
                job: () async {
                  final t = _ta.text.trim();
                  if (t.isEmpty) throw Exception('Écris une réponse.');
                  await Api.queueMessage(cid, rid, t);
                  setState(() => _sent = true);
                  widget.onSent();
                }),
          ],
        ],
      ]),
    );
  }

  Widget _bubble(Palette c, Map<String, dynamic> m) {
    final mine = m.ob('from_page', false);
    return Container(
      margin: EdgeInsets.only(
          top: 8, left: mine ? 40 : 0, right: mine ? 0 : 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: mine ? c.soft : c.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: mine ? Colors.transparent : c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_textOf(m), style: T.body(c).copyWith(fontSize: 14.5)),
        const SizedBox(height: 2),
        Text(rel(m.os('created_time')), style: T.caption(c).copyWith(fontSize: 11)),
      ]),
    );
  }
}
