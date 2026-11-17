import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show Bus, SubPage;
import '../widgets/post_card.dart' show avatarInitiales, etiquette;
import 'settings.dart';

/// Boîte unifiée, comme sur la maquette : titre, recherche, filtres
/// (Tout / Non lus / Urgents / Avis / Messages), sections « Non lus » et
/// « Plus tôt », lignes compactes qui se déplient pour répondre.
/// Répondre ici met en file exactement comme dans les anciens écrans Avis
/// et Messages (fusionnés dans celui-ci).
class BoiteScreen extends StatefulWidget {
  final int filtreInitial; // 1 = avis, 2 = messages (depuis l'accueil)
  const BoiteScreen({super.key, this.filtreInitial = 0});
  @override
  State<BoiteScreen> createState() => _BoiteScreenState();
}

class _BoiteScreenState extends State<BoiteScreen> {
  List<UnifiedItem> _items = const [];
  Moderation _mod = const Moderation();
  List<dynamic> _msgQueue = const [];
  String _upd = '';
  int _filtre = 0; // 0 tout, 1 non lus, 2 urgents, 3 avis, 4 messages
  bool _cherche = false;
  String _q = '';
  final Set<String> _ouverts = {};
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    // depuis l'accueil : chip Avis (1) ou Messages (2)
    _filtre = switch (widget.filtreInitial) {
      1 => 3,
      2 => 4,
      _ => 0,
    };
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
      Bus.setAvis(items
          .where((x) =>
              x.kind == 'avis' &&
              x.todo &&
              !mod.traite.contains(x.id) &&
              !mod.cache.contains(x.id))
          .length);
      Bus.setMsg(items.where((x) => x.kind == 'msg' && x.todo).length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      kToast(context, Api.hint(e), bad: true);
    }
  }

  /* ---------- sélections ---------- */

  List<UnifiedItem> get _visibles {
    final q = _q.trim().toLowerCase();
    return _items.where((x) {
      if (_mod.cache.contains(x.id)) return false;
      if (q.isNotEmpty &&
          !x.name.toLowerCase().contains(q) &&
          !x.text.toLowerCase().contains(q)) {
        return false;
      }
      return switch (_filtre) {
        1 => x.todo,
        2 => x.kind == 'avis' && _mod.estUrgent(x.id, x.text),
        3 => x.kind == 'avis',
        4 => x.kind == 'msg',
        _ => true,
      };
    }).toList();
  }

  int get _nbNonLus =>
      _items.where((x) => !_mod.cache.contains(x.id) && x.todo).length;
  int get _nbUrgents => _items
      .where((x) =>
          x.kind == 'avis' &&
          !_mod.cache.contains(x.id) &&
          _mod.estUrgent(x.id, x.text))
      .length;
  int get _nbAvis => _items
      .where((x) => x.kind == 'avis' && !_mod.cache.contains(x.id))
      .length;
  int get _nbMsgs => _items
      .where((x) => x.kind == 'msg' && !_mod.cache.contains(x.id))
      .length;

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_busy && _items.isEmpty) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(70),
        SizedBox(height: 10),
        KSkeleton(70),
        SizedBox(height: 10),
        KSkeleton(70),
      ]);
    }
    final tous = _visibles
      ..sort((a, b) {
        final ua = a.kind == 'avis' && _mod.estUrgent(a.id, a.text) ? 0 : 1;
        final ub = b.kind == 'avis' && _mod.estUrgent(b.id, b.text) ? 0 : 1;
        if (ua != ub) return ua - ub;
        return b.ts.compareTo(a.ts);
      });
    final nonLus = tous.where((x) => x.todo).toList();
    const maxLignes = 40;

    Widget lignes(List<UnifiedItem> liste, bool readSection) {
      if (liste.isEmpty) return const SizedBox();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Text(readSection ? 'PLUS TÔT' : 'NON LUS', style: T.micro(c)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line)),
          child: Column(children: [
            for (var i = 0; i < liste.length && i < maxLignes; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
              _ligne(c, liste[i]),
            ],
          ]),
        ),
      ]);
    }

    return RefreshIndicator(
      color: c.accent,
      backgroundColor: c.card,
      onRefresh: () async => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 96),
        children: [
          _pageHead(c),
          _chips(c),
          if (_cherche) ...[
            const SizedBox(height: 4),
            _champRecherche(c),
          ],
          const SizedBox(height: 8),
          Text(
            _upd.isEmpty
                ? 'Rien encore lu par le bot : lance « Surveiller ».'
                : 'Lu par le bot : ${rel(_upd)}',
            style: T.caption(c),
          ),
          const SizedBox(height: 6),
          if (tous.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: KEmpty(Icons.inbox_outlined,
                  _q.isEmpty ? 'Boîte vide pour ce filtre.' : 'Aucun résultat.',
                  sub: _q.isEmpty
                      ? 'Le bot la remplit à chaque cycle de lecture.'
                      : 'Essaie un autre mot.'),
            )
          else if (_filtre == 0) ...[
            lignes(nonLus, false),
            if (nonLus.isNotEmpty) const SizedBox(height: 14),
            lignes(
                tous.where((x) => !x.todo).toList(), true),
          ] else
            lignes(tous, false),
        ],
      ),
    );
  }

  /* ---------- en-tête de page : titre + recherche + réglages ---------- */

  Widget _pageHead(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Text('Boîte',
            style: TextStyle(
                fontFamily: T.kpi(c).fontFamily, fontSize: 26, fontWeight: FontWeight.w800,
                letterSpacing: -.5, color: c.ink)),
        const Spacer(),
        _ic(c, Icons.search_outlined, () {
          Fx.tick();
          setState(() => _cherche = !_cherche);
        }),
        const SizedBox(width: 8),
        _ic(c, Icons.settings_outlined, () {
          Fx.tick();
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  const SubPage('Réglages', child: SettingsScreen())));
        }),
      ]),
    );
  }

  Widget _ic(Palette c, IconData ic, VoidCallback f) {
    return Press(
      onTap: f,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: c.chip,
            borderRadius: BorderRadius.circular(18)),
        child: Icon(ic, size: 17, color: c.ink),
      ),
    );
  }

  Widget _champRecherche(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Expanded(
          child: KEdit(
            text: _q,
            hint: 'Chercher un nom ou un texte...',
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const SizedBox(width: 8),
        Press(
          onTap: () => setState(() {
            _q = '';
            _cherche = false;
          }),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line)),
            child: Icon(Icons.close, size: 17, color: c.ink),
          ),
        ),
      ]),
    );
  }

  /* ---------- chips ---------- */

  Widget _chips(Palette c) {
    final labels = [
      ('Tout', ''),
      ('Non lus', _nbNonLus > 0 ? '$_nbNonLus' : ''),
      ('Urgents', _nbUrgents > 0 ? '$_nbUrgents' : ''),
      ('Avis', _nbAvis > 0 ? '$_nbAvis' : ''),
      ('Messages', _nbMsgs > 0 ? '$_nbMsgs' : ''),
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shrinkWrap: true,
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
              child: Press(
                onTap: () {
                  Fx.tick();
                  setState(() => _filtre = i);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                      color: _filtre == i ? c.accent : c.card,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: _filtre == i ? c.accent : c.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(labels[i].$1,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _filtre == i ? c.onAccent : c.muted)),
                    if (labels[i].$2.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text(labels[i].$2,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _filtre == i ? c.onAccent : c.muted)),
                    ],
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /* ---------- une ligne (dépliable) ---------- */

  Widget _ligne(Palette c, UnifiedItem it) {
    final ouvert = _ouverts.contains(it.id);
    final urgent = it.kind == 'avis' && _mod.estUrgent(it.id, it.text);
    final tag = it.kind == 'avis' ? Moderation.detecteTag(it.text) : null;
    return Column(children: [
      Press(
        onTap: () {
          Fx.tick();
          setState(() =>
              ouvert ? _ouverts.remove(it.id) : _ouverts.add(it.id));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(children: [
            avatarInitiales(c, it.name, 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(it.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.strong(c).copyWith(fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  _typeChip(c, it.kind),
                ]),
                const SizedBox(height: 2),
                Text(
                  it.text.isEmpty ? '(sans texte)' : it.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption(c).copyWith(fontSize: 12.5, height: 1.45),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(relMs(it.ts),
                  style: T.caption(c).copyWith(fontSize: 10.5)),
              const SizedBox(height: 3),
              if (urgent)
                etiquette(c, tag ?? 'Urgent', true)
              else if (it.todo)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: c.accent, shape: BoxShape.circle),
                ),
            ]),
          ]),
        ),
      ),
      if (ouvert)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: it.kind == 'avis'
              ? _detailAvis(c, it)
              : _detailMsg(c, it),
        ),
    ]);
  }

  Widget _typeChip(Palette c, String kind) {
    final avis = kind == 'avis';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(avis ? Icons.chat_bubble_outline : Icons.bolt_outlined,
            size: 10, color: c.muted),
        const SizedBox(width: 3),
        Text(avis ? 'AVIS' : 'MESSAGE',
            style: T.caption(c).copyWith(
                fontSize: 9.5, fontWeight: FontWeight.w700,
                letterSpacing: .57)),
      ]),
    );
  }

  /* ---------- détail avis ---------- */

  Widget _detailAvis(Palette c, UnifiedItem it) {
    final cid = it.id;
    final traite = _mod.traite.contains(cid) || !it.todo;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (it.postTxt.isNotEmpty)
        Text('Sur : ${it.postTxt}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.caption(c)),
      const SizedBox(height: 6),
      Text(it.text, style: T.body(c).copyWith(fontSize: 13.5)),
      const SizedBox(height: 8),
      ReplyBoxAvis(
        cid: cid,
        nom: it.name,
        onSent: _load,
      ),
      const SizedBox(height: 8),
      Row(children: [
        _mini(c, Icons.check_outlined, 'Approuvé', traite, () async {
          await Moderation.approuve(cid);
          await Journal.ajoute('moderation', 'Commentaire approuvé',
              detail: 'de ${it.name}');
          _load();
        }),
        const SizedBox(width: 6),
        _mini(c, Icons.flag_outlined, 'Urgent', _mod.urgents.contains(cid),
            () async {
          await Moderation.urgent(cid, !_mod.urgents.contains(cid));
          _load();
        }),
        const SizedBox(width: 6),
        _mini(c, Icons.visibility_off_outlined, 'Cacher', false, () async {
          await Moderation.masque(cid);
          await Journal.ajoute('moderation', 'Commentaire caché',
              detail: 'de ${it.name}');
          _load();
        }),
      ]),
    ]);
  }

  /* ---------- détail message ---------- */

  Widget _detailMsg(Palette c, UnifiedItem it) {
    final conv = it.conv!;
    final cid = conv.os('id');
    final rid = asObj(conv['with']).os('id');
    final ms = conv['messages'] is List
        ? conv['messages'] as List<dynamic>
        : const <dynamic>[];
    final winOpen = Api.windowOpen(conv);
    final queued = Api.lastQueued(_msgQueue, cid);
    final qs = queued == null ? '' : queued.os('status');
    final waiting = qs == 'pending';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final m in ms) _bulleMsg(c, asObj(m)),
      if (waiting)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'Ta réponse est en file : le bot l\'envoie à son prochain cycle (environ 1 minute).',
              style: T.caption(c)),
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
              style: T.caption(c)),
        )
      else if (qs == 'error')
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'Dernier envoi refusé${queued!.os('erreur').isEmpty ? '.' : ' : ${queued.os('erreur')}.'}',
              style: T.caption(c).copyWith(color: c.ink)),
        )
      else
        ReplyBoxMessage(convId: cid, rid: rid, nom: it.name, onSent: _load),
    ]);
  }

  Widget _bulleMsg(Palette c, Map<String, dynamic> m) {
    final mine = m.ob('from_page', false);
    return Container(
      margin: EdgeInsets.only(
          top: 8, left: mine ? 40 : 0, right: mine ? 0 : 40),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
          color: mine ? c.soft : c.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: mine ? Colors.transparent : c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.os('message').isEmpty ? '(pièce jointe)' : m.os('message'),
            style: T.body(c).copyWith(fontSize: 13.5)),
        const SizedBox(height: 2),
        Text(rel(m.os('created_time')),
            style: T.caption(c).copyWith(fontSize: 10.5)),
      ]),
    );
  }

  Widget _mini(Palette c, IconData ic, String label, bool on, VoidCallback f) {
    return Press(
      onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: on ? c.accent.withValues(alpha: .1) : c.soft,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? c.accent : c.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 13, color: on ? c.accent : c.ink),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: on ? c.accent : c.ink)),
        ]),
      ),
    );
  }
}

/* ---------- zones de réponse réutilisables ---------- */

/// Réponse à un commentaire : mise en file + lancement + journal.
class ReplyBoxAvis extends StatefulWidget {
  final String cid;
  final String nom;
  final VoidCallback onSent;
  const ReplyBoxAvis({super.key, required this.cid, required this.nom, required this.onSent});
  @override
  State<ReplyBoxAvis> createState() => _ReplyBoxAvisState();
}

class _ReplyBoxAvisState extends State<ReplyBoxAvis> {
  final _ta = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _ta.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final t = _ta.text.trim();
    if (t.isEmpty) throw Exception('Écris une réponse.');
    await Api.updateJson('posts/replies.json', true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      a.add({'comment_id': widget.cid, 'message': t, 'status': 'pending'});
      return a;
    }, 'Réponse (appli de contrôle)');
    var lance = false;
    try {
      await Api.dispatch('repondre.yml', null);
      lance = true;
    } catch (_) {/* traité sous 5 à 10 min */}
    await Journal.ajoute('reponse', 'Réponse à ${widget.nom}',
        detail: t.length > 120 ? '${t.substring(0, 120)}…' : t);
    setState(() => _sent = true);
    if (mounted) {
      kToast(context,
          lance ? 'Réponse mise en file et lancée.' : 'Réponse mise en file : traitée sous 5 à 10 min.');
    }
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Text('En file : le bot répondra à son prochain cycle.',
          style: T.caption(context.p));
    }
    return Column(children: [
      KEdit(controller: _ta, hint: 'Ta réponse...', minLines: 2),
      const SizedBox(height: 8),
      ActionBtn('Mettre en file', height: 38, job: _envoyer),
    ]);
  }
}

/// Réponse Messenger : la fenêtre de 24 h est vérifiée avant l'envoi.
class ReplyBoxMessage extends StatefulWidget {
  final String convId;
  final String rid;
  final String nom;
  final VoidCallback onSent;
  const ReplyBoxMessage({super.key, required this.convId, required this.rid,
      required this.nom, required this.onSent});
  @override
  State<ReplyBoxMessage> createState() => _ReplyBoxMessageState();
}

class _ReplyBoxMessageState extends State<ReplyBoxMessage> {
  final _ta = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _ta.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final t = _ta.text.trim();
    if (t.isEmpty) throw Exception('Écris une réponse.');
    await Api.queueMessage(widget.convId, widget.rid, t);
    await Journal.ajoute('reponse', 'Message à ${widget.nom}',
        detail: t.length > 120 ? '${t.substring(0, 120)}…' : t);
    setState(() => _sent = true);
    if (mounted) {
      kToast(context, 'Message envoyé : il part dans la minute.');
    }
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Text('Envoyé : le message part dans la minute.',
          style: T.caption(context.p));
    }
    return Column(children: [
      KEdit(controller: _ta, hint: 'Ta réponse...', minLines: 2,
          maxLength: Api.messageMax),
      const SizedBox(height: 8),
      ActionBtn('Envoyer', height: 38, job: _envoyer),
    ]);
  }
}
