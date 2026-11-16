import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show Bus;

/// Boîte unifiée : tous les avis (commentaires) et toutes les conversations
/// Messenger dans un seul flux filtrable, non lus d'abord, urgents marqués.
/// Répondre ici met en file exactement comme dans les anciens écrans Avis
/// et Messages (fusionnés dans celui-ci).
class BoiteScreen extends StatefulWidget {
  final String ouvreConvo; // ouvre directement une conversation précise
  const BoiteScreen({super.key, this.ouvreConvo = ''});
  @override
  State<BoiteScreen> createState() => _BoiteScreenState();
}

class _BoiteScreenState extends State<BoiteScreen> {
  List<UnifiedItem> _items = const [];
  Moderation _mod = const Moderation();
  List<dynamic> _msgQueue = const [];
  String _upd = '';
  int _filtre = 0; // 0 tout, 1 avis, 2 messages
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = _items.isEmpty);
    try {
      final (items, upd) = await Boite.charge();
      final mod = await Moderation.charge();
      final queue = await Api.readArr('posts/messages.json');
      if (!mounted) return;
      setState(() {
        _items = items;
        _mod = mod;
        _msgQueue = queue;
        _upd = upd;
        _busy = false;
      });
      Bus.setAvis(items.where((x) => x.kind == 'avis' && x.todo && !mod.traite.contains(x.id)).length);
      Bus.setMsg(items.where((x) => x.kind == 'msg' && x.todo).length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      kToast(context, Api.hint(e), bad: true);
    }
  }

  void _afterAction() => _load();

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_busy && _items.isEmpty) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(90),
        SizedBox(height: 12),
        KSkeleton(120),
        SizedBox(height: 12),
        KSkeleton(120),
      ]);
    }
    final visibles =
        _items.where((x) => !_mod.cache.contains(x.id)).toList();
    final avis = visibles.where((x) => x.kind == 'avis').toList();
    final msgs = visibles.where((x) => x.kind == 'msg').toList();
    final list = switch (_filtre) {
      1 => avis,
      2 => msgs,
      _ => visibles,
    };
    // non lus d'abord, puis du plus récent au plus ancien
    list.sort((a, b) {
      if (a.todo != b.todo) return a.todo ? -1 : 1;
      return b.ts.compareTo(a.ts);
    });
    const maxTuiles = 40;

    return RefreshIndicator(
      color: c.accent,
      backgroundColor: c.card,
      onRefresh: () async => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          KSegmented(
            ['Tout (${visibles.length})', 'Avis (${avis.length})',
             'Messages (${msgs.length})'],
            sel: _filtre,
            onSelect: (i) {
              Fx.tick();
              setState(() => _filtre = i);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _upd.isEmpty
                ? 'Rien encore lu par le bot : lance « Surveiller ».'
                : 'Lu par le bot : ${rel(_upd)}',
            style: T.caption(c),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            KEmpty(Icons.inbox_outlined, 'Boîte vide pour ce filtre.',
                sub: 'Le bot la remplit à chaque cycle de lecture.')
          else ...[
            for (var i = 0; i < list.length && i < maxTuiles; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: list[i].kind == 'avis'
                    ? _AvisTile(
                        item: list[i],
                        mod: _mod,
                        onChanged: _afterAction,
                      )
                    : _ConvoTile(
                        item: list[i],
                        queued: Api.lastQueued(_msgQueue, list[i].id),
                        openNow: widget.ouvreConvo == list[i].id,
                        onSent: _afterAction,
                      ),
              ),
            if (list.length > maxTuiles)
              KEmpty(Icons.filter_alt_outlined,
                  '$maxTuiles plus récents affichés sur ${list.length}.'),
          ],
        ],
      ),
    );
  }
}

/* ---------- tuile avis (commentaire) ---------- */

class _AvisTile extends StatefulWidget {
  final UnifiedItem item;
  final Moderation mod;
  final VoidCallback onChanged;
  const _AvisTile({required this.item, required this.mod, required this.onChanged});
  @override
  State<_AvisTile> createState() => _AvisTileState();
}

class _AvisTileState extends State<_AvisTile> {
  bool _open = false;
  bool _sent = false;
  final _ta = TextEditingController();

  @override
  void dispose() {
    _ta.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final t = _ta.text.trim();
    if (t.isEmpty) throw Exception('Écris une réponse.');
    final cid = widget.item.cmt!.c.os('id');
    await Api.updateJson('posts/replies.json', true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      a.add({'comment_id': cid, 'message': t, 'status': 'pending'});
      return a;
    }, 'Réponse (appli de contrôle)');
    var launched = false;
    try {
      await Api.dispatch('repondre.yml', null);
      launched = true;
    } catch (_) {/* traité sous 5 à 10 min */}
    await Journal.ajoute('reponse', 'Réponse à ${widget.item.name}',
        detail: t.length > 120 ? '${t.substring(0, 120)}…' : t);
    setState(() {
      _open = false;
      _sent = true;
    });
    if (mounted) {
      kToast(context,
          launched ? 'Réponse mise en file et lancée.' : 'Réponse mise en file : traitée sous 5 à 10 min.');
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final it = widget.item;
    final answered = it.cmt!.c.ob('page_a_repondu', false);
    final urgent = widget.mod.urgents.contains(it.id);
    final traite = widget.mod.traite.contains(it.id) || answered || _sent;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar(c, it.name),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: T.strong(c)),
              Text(relMs(it.ts), style: T.caption(c)),
            ]),
          ),
          if (urgent)
            const KBadge('URGENT')
          else if (traite)
            const StatusChip('Répondu', kind: 1)
          else
            const StatusChip('Sans réponse', kind: 2),
        ]),
        if (it.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(it.text, style: T.body(c).copyWith(fontSize: 14.5)),
        ],
        if (it.postTxt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Sur : ${it.postTxt.length > 70 ? '${it.postTxt.substring(0, 70)}…' : it.postTxt}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.caption(c),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (_sent) const StatusChip('En file', kind: 4),
            ]),
          ),
          ActionBtn(_open ? 'Fermer' : 'Répondre',
              height: 38,
              variant: KBtnVariant.ghost,
              job: () async {
                Fx.tick();
                setState(() => _open = !_open);
              }),
        ]),
        if (_open && !traite) ...[
          const SizedBox(height: 10),
          KEdit(controller: _ta, hint: 'Ta réponse...', minLines: 3),
          const SizedBox(height: 8),
          ActionBtn('Mettre en file', job: _envoyer),
        ],
        const SizedBox(height: 8),
        Row(children: [
          _mini(c, traite ? Icons.replay : Icons.check,
              traite ? 'Réouvrir' : 'Traité', () async {
            if (traite) {
              await Moderation.reouvre(it.id);
            } else {
              await Moderation.approuve(it.id);
              await Journal.ajoute('moderation', 'Commentaire approuvé',
                  detail: 'de ${it.name}');
            }
            widget.onChanged();
          }),
          const SizedBox(width: 6),
          _mini(c, Icons.flag_outlined, urgent ? 'Plus urgent' : 'Urgent',
              () async {
            await Moderation.urgent(it.id, !urgent);
            widget.onChanged();
          }),
          const SizedBox(width: 6),
          _mini(c, Icons.visibility_off_outlined, 'Cacher', () async {
            await Moderation.masque(it.id);
            await Journal.ajoute('moderation', 'Commentaire caché',
                detail: 'de ${it.name}');
            widget.onChanged();
          }),
        ]),
      ]),
    );
  }

  Widget _mini(Palette c, IconData ic, String label, VoidCallback f) {
    return Press(
      onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: c.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 13, color: c.ink),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800,
                  color: c.ink)),
        ]),
      ),
    );
  }
}

/* ---------- tuile conversation Messenger ---------- */

class _ConvoTile extends StatefulWidget {
  final UnifiedItem item;
  final Map<String, dynamic>? queued;
  final bool openNow;
  final VoidCallback onSent;
  const _ConvoTile({required this.item, required this.queued,
      this.openNow = false, required this.onSent});
  @override
  State<_ConvoTile> createState() => _ConvoTileState();
}

class _ConvoTileState extends State<_ConvoTile> {
  late bool _open = widget.openNow;
  bool _sent = false;
  final _ta = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ta.addListener(() => setState(() {}));
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

  Future<void> _envoyer() async {
    final t = _ta.text.trim();
    if (t.isEmpty) throw Exception('Écris une réponse.');
    final conv = widget.item.conv!;
    final cid = conv.os('id');
    final rid = asObj(conv['with']).os('id');
    if (rid.isEmpty) throw Exception('Contact introuvable : réponse impossible.');
    await Api.queueMessage(cid, rid, t);
    await Journal.ajoute('reponse', 'Message à ${widget.item.name}',
        detail: t.length > 120 ? '${t.substring(0, 120)}…' : t);
    setState(() => _sent = true);
    if (mounted) kToast(context, 'Réponse mise en file : le bot l\'envoie à son prochain cycle.');
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final it = widget.item;
    final conv = it.conv!;
    final ms = conv['messages'] is List
        ? conv['messages'] as List<dynamic>
        : const <dynamic>[];
    final needs = Api.needsReply(conv);
    final winOpen = Api.windowOpen(conv);
    final qs = widget.queued == null ? '' : widget.queued!.os('status');
    final waiting = qs == 'pending' || _sent;
    final rid = asObj(conv['with']).os('id');

    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar(c, it.name),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: T.strong(c)),
              Text(relMs(it.ts), style: T.caption(c)),
            ]),
          ),
          if (waiting)
            const StatusChip('En file', kind: 4)
          else if (qs == 'error')
            const StatusChip("Échec d'envoi", kind: 3)
          else if (needs)
            const StatusChip('À répondre', kind: 2)
          else
            const StatusChip('Répondu', kind: 1),
        ]),
        const SizedBox(height: 8),
        Text(it.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.body(c).copyWith(fontSize: 14.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (needs && !winOpen) const StatusChip('24 h dépassées', kind: 3),
            ]),
          ),
          ActionBtn(_open ? 'Fermer' : 'Ouvrir',
              height: 38,
              variant: KBtnVariant.ghost,
              job: () async {
                Fx.tick();
                setState(() => _open = !_open);
              }),
        ]),
        if (_open) ...[
          const SizedBox(height: 4),
          for (final m in ms) _bubble(c, asObj(m)),
          if (waiting)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ta réponse est en file : le bot l\'envoie à son prochain cycle (environ 1 minute).',
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
                'Messenger n\'autorise plus la réponse 24 h après le dernier message '
                'de la personne. Elle doit réécrire pour rouvrir la conversation.',
                style: T.caption(c),
              ),
            )
          else ...[
            if (qs == 'error')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Dernier envoi refusé${widget.queued!.os('erreur').isEmpty ? '.' : ' : ${widget.queued!.os('erreur')}.'}',
                  style: T.caption(c).copyWith(color: c.ink),
                ),
              ),
            const SizedBox(height: 10),
            KEdit(controller: _ta, hint: 'Ta réponse...', minLines: 3,
                maxLength: Api.messageMax),
            const SizedBox(height: 8),
            ActionBtn('Mettre en file', job: _envoyer),
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
        Text(rel(m.os('created_time')),
            style: T.caption(c).copyWith(fontSize: 11)),
      ]),
    );
  }
}

/* ---------- avatar lettre ---------- */

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
