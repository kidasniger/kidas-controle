import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ai.dart';
import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../screens/moderation.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show SubPage;

/// Carte de publication « façon Facebook », comme sur la maquette :
/// en-tête avec la Page et son badge, texte, compteur de commentaires,
/// rangée J'aime / Commenter / Partager, bulles de commentaires avec
/// réponses, bande de modération et réponse suggérée par l'IA.
/// Tout ce qui s'affiche vient des données réelles du dépôt (pas de
/// chiffres inventés : le bot ne récupère que les commentaires).
class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String pageName;
  final String pageId;
  final Moderation mod;
  final VoidCallback onChanged;
  const PostCard({
    super.key,
    required this.post,
    required this.pageName,
    required this.pageId,
    required this.mod,
    required this.onChanged,
  });
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _toutVoir = false;
  String _reponseA = ''; // id du commentaire en cours de réponse
  String _suggestionPour = ''; // id du commentaire suggéré
  String _suggestion = '';
  String _iaEnCours = '';
  final _ta = TextEditingController();

  @override
  void dispose() {
    _ta.dispose();
    super.dispose();
  }

  /* ---------- données ---------- */

  String get _postTexte {
    var t = widget.post.os('message');
    if (t.isEmpty) t = widget.post.os('story');
    return t;
  }

  /* ---------- actions ---------- */

  Future<void> _envoyerReponse(Cmt c) async {
    final t = _ta.text.trim();
    if (t.isEmpty) throw Exception('Écris une réponse.');
    final cid = c.c.os('id');
    await Api.updateJson('posts/replies.json', true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      a.add({'comment_id': cid, 'message': t, 'status': 'pending'});
      return a;
    }, 'Réponse (appli de contrôle)');
    var lance = false;
    try {
      await Api.dispatch('repondre.yml', null);
      lance = true;
    } catch (_) {/* traité sous 5 à 10 min */}
    final from = asObj(c.c['from']).os('name');
    await Journal.ajoute('reponse', 'Réponse à ${from.isEmpty ? 'Abonné' : from}',
        detail: t.length > 120 ? '${t.substring(0, 120)}…' : t);
    setState(() {
      _reponseA = '';
      _ta.clear();
    });
    if (mounted) {
      kToast(context, lance ? 'Réponse mise en file et lancée.' : 'Réponse mise en file : traitée sous 5 à 10 min.');
    }
    widget.onChanged();
  }

  Future<void> _suggere(Cmt c) async {
    if (_iaEnCours.isNotEmpty) return;
    setState(() => _iaEnCours = c.c.os('id'));
    try {
      final from = asObj(c.c['from']).os('name');
      final rep = await Ai.chat([
        {
          'role': 'system',
          'content': 'Tu réponds aux commentaires de la Page Facebook '
              '« ${widget.pageName} ». Réponds en français, ton chaleureux et '
              'professionnel, une ou deux phrases maximum, sans guillemets, '
              'prête à publier telle quelle.',
        },
        {
          'role': 'user',
          'content': 'Publication : « ${_postTexte.isEmpty ? '(sans texte)' : _postTexte} »\n'
              'Commentaire de ${from.isEmpty ? 'un abonné' : from} : '
              '« ${c.c.os('message')} »\nPropose la réponse à publier.',
        },
      ]);
      if (!mounted) return;
      setState(() {
        _suggestionPour = c.c.os('id');
        _suggestion = rep;
        _iaEnCours = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _iaEnCours = '');
      kToast(context, Api.hint(e), bad: true);
    }
  }

  Future<void> _envoyerSuggestion(Cmt c) async {
    final t = _suggestion.trim();
    if (t.isEmpty) return;
    await Api.updateJson('posts/replies.json', true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      a.add({'comment_id': c.c.os('id'), 'message': t, 'status': 'pending'});
      return a;
    }, 'Réponse suggérée (appli de contrôle)');
    try {
      await Api.dispatch('repondre.yml', null);
    } catch (_) {}
    await Journal.ajoute('reponse', 'Réponse suggérée envoyée', detail: t);
    setState(() {
      _suggestionPour = '';
      _suggestion = '';
    });
    if (mounted) kToast(context, 'Réponse mise en file.');
    widget.onChanged();
  }

  Future<void> _kebab() async {
    final action = await kSheet<String>(context, title: 'Publication', children: [
      _sheetRow(context, Icons.copy_outlined, 'Copier le texte', 'txt'),
      _sheetRow(context, Icons.link_outlined, 'Copier le lien du post', 'lnk'),
      _sheetRow(context, Icons.shield_outlined, 'Modérer les commentaires', 'mod'),
    ]);
    if (action == null || !mounted) return;
    if (action == 'txt') {
      await Clipboard.setData(ClipboardData(text: _postTexte));
      if (mounted) kToast(context, 'Texte copié.');
    } else if (action == 'lnk') {
      final url = widget.post.os('permalink_url');
      if (url.isEmpty) {
        kToast(context, 'Pas de lien pour cette publication.', bad: true);
        return;
      }
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) kToast(context, 'Lien copié : colle-le dans ton navigateur.');
    } else if (action == 'mod') {
      Fx.tick();
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SubPage('Modération', child: ModerationScreen())));
    }
  }

  Widget _sheetRow(BuildContext ctx, IconData ic, String label, String v) {
    final c = ctx.p;
    return Press(
      onTap: () {
        Fx.tick();
        Navigator.pop(ctx, v);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          IconBox(ic),
          const SizedBox(width: 13),
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14.5,
                      fontWeight: FontWeight.w700, color: c.ink))),
        ]),
      ),
    );
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    // une seule instance de la liste : les comparaisons d'identité tiennent
    final tous = Api.flatComments({'posts': [widget.post]});
    final attendants = Api.unanswered(tous, widget.pageId).toList()
      ..sort((a, b) {
        final ua = widget.mod.estUrgent(a.c.os('id'), a.c.os('message')) ? 0 : 1;
        final ub = widget.mod.estUrgent(b.c.os('id'), b.c.os('message')) ? 0 : 1;
        if (ua != ub) return ua - ub;
        return b.c.os('created_time').compareTo(a.c.os('created_time'));
      });
    final affiches = _toutVoir
        ? (List<Cmt>.from(attendants)
          ..addAll(tous.where((x) => !attendants.contains(x)).toList()
            ..sort((a, b) =>
                b.c.os('created_time').compareTo(a.c.os('created_time')))))
        : (attendants.isNotEmpty
            ? attendants.take(2).toList()
            : tous.take(2).toList());
    final reste = tous.length - affiches.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _tete(c),
        if (_postTexte.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_postTexte, style: T.body(c).copyWith(fontSize: 13.5)),
        ],
        _compteur(c, tous),
        _actions(c, tous.length),
        if (tous.isNotEmpty || attendants.isNotEmpty)
          _commentairesBloc(c, affiches, attendants, reste),
      ]),
    );
  }

  /* ----- en-tête : avatar Page + nom + badge vérifié + heure + kebab ----- */

  Widget _tete(Palette c) {
    final name = widget.pageName;
    return Row(children: [
      avatarPage(c, 40),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.strong(c).copyWith(fontSize: 13)),
            ),
            const SizedBox(width: 4),
            badgeVerifie(c, 15),
          ]),
          Row(children: [
            Text(rel(widget.post.os('created_time')),
                style: T.caption(c).copyWith(fontSize: 11.5)),
            const SizedBox(width: 5),
            Icon(Icons.public_outlined, size: 12, color: c.muted),
          ]),
        ]),
      ),
      Press(
        onTap: _kebab,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.more_horiz, size: 18, color: c.muted),
        ),
      ),
    ]);
  }

  /* ----- compteur : nombre réel de commentaires ----- */

  Widget _compteur(Palette c, List<Cmt> tous) {
    if (tous.isEmpty) return const SizedBox(height: 4);
    var n = 0;
    for (final x in tous) {
      n += 1 + (x.c.oi('comment_count'));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(children: [
        Icon(Icons.chat_bubble_outline, size: 13, color: c.muted),
        const SizedBox(width: 6),
        Text('$n commentaires',
            style: T.caption(c).copyWith(fontSize: 11.5)),
        const Spacer(),
        if (widget.post.os('permalink_url').isNotEmpty)
          Press(
            onTap: () async {
              await Clipboard.setData(ClipboardData(
                  text: widget.post.os('permalink_url')));
              if (mounted) kToast(context, 'Lien copié.');
            },
            child: Text('Voir sur Facebook',
                style: T.caption(c).copyWith(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: c.muted)),
          ),
      ]),
    );
  }

  /* ----- rangée d'actions ----- */

  Widget _actions(Palette c, int nCommentaires) {
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Row(children: [
        Expanded(
          child: _act(c, Icons.thumb_up_outlined, "J'aime", () async {
            Fx.tick();
            kToast(context,
                "Les J'aime ne se publient pas depuis l'application : clique sur « Voir sur Facebook ».");
          }),
        ),
        Expanded(
          child: _act(c, Icons.chat_bubble_outline, 'Commenter', () {
            Fx.tick();
            if (nCommentaires == 0) {
              kToast(context,
                  'Pas encore de commentaire : ils arrivent au prochain cycle du bot.');
              return;
            }
            setState(() => _toutVoir = true);
          }),
        ),
        Expanded(
          child: _act(c, Icons.share_outlined, 'Partager', () async {
            final t = _postTexte;
            await Clipboard.setData(ClipboardData(text: t.isEmpty
                ? widget.post.os('permalink_url')
                : '$t\n\n${widget.post.os('permalink_url')}'));
            if (mounted) kToast(context, 'Texte et lien copiés pour partager.');
          }),
        ),
      ]),
    );
  }

  Widget _act(Palette c, IconData ic, String label, VoidCallback f) {
    return Press(
      onTap: f,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ic, size: 15, color: c.muted),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: c.muted)),
        ]),
      ),
    );
  }

  /* ----- commentaires : bande de modération + bulles + IA ----- */

  Widget _commentairesBloc(Palette c, List<Cmt> affiches,
      List<Cmt> attendants, int reste) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.only(top: 9),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (attendants.isNotEmpty) ...[
          _bandeModeration(c, attendants.length),
          const SizedBox(height: 8),
        ],
        for (final x in affiches) ...[
          _bulle(c, x, attendants.contains(x)),
          const SizedBox(height: 8),
        ],
        if (reste > 0)
          Press(
            onTap: () {
              Fx.tick();
              setState(() => _toutVoir = !_toutVoir);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _toutVoir ? 'Replier' : 'Voir les $reste autres commentaires',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: c.muted),
              ),
            ),
          ),
        if (_reponseA == 'nouveau') _boiteReponse(c, null),
      ]),
    );
  }

  Widget _bandeModeration(Palette c, int n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
          color: c.soft, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Text('MODÉRATION — ', style: T.microInk(c)),
        Text('$n EN ATTENTE', style: T.micro(c).copyWith(color: c.ink)),
        const Spacer(),
        Text("Urgent d'abord", style: T.caption(c).copyWith(fontSize: 10.5)),
      ]),
    );
  }

  /* ----- une bulle de commentaire (+ réponses imbriquées) ----- */

  Widget _bulle(Palette c, Cmt x, bool attend) {
    final from = asObj(x.c['from']);
    final name = from.os('name').isEmpty ? 'Abonné' : from.os('name');
    final cid = x.c.os('id');
    final tag = attend ? Moderation.detecteTag(x.c.os('message')) : null;
    final urgent = attend && widget.mod.estUrgent(cid, x.c.os('message'));
    final reps = x.c['comments'] is Map<String, dynamic>
        ? asArr((x.c['comments'] as Map<String, dynamic>)['data'])
        : const <dynamic>[];
    final estMaReponse = _reponseA == cid;
    final suggereIci = _suggestionPour == cid;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      avatarInitiales(c, name, 30),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
              color: c.soft,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.strong(c).copyWith(fontSize: 12.5)),
              ),
              if (tag != null) etiquette(c, tag, urgent),
            ]),
            if (x.c.os('message').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(x.c.os('message'),
                  style: T.body(c).copyWith(fontSize: 13)),
            ],
            const SizedBox(height: 4),
            Row(children: [
              Text(rel(x.c.os('created_time')),
                  style: T.caption(c).copyWith(fontSize: 11)),
              const SizedBox(width: 12),
              Press(
                onTap: () {
                  Fx.tick();
                  setState(() => _reponseA = estMaReponse ? '' : cid);
                },
                child: Text('Répondre',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w800, color: c.muted)),
              ),
              if (x.c.oi('comment_count') > 0) ...[
                const SizedBox(width: 12),
                Text('${x.c.oi('comment_count')} réponses',
                    style: T.caption(c).copyWith(fontSize: 11)),
              ],
            ]),
            if (reps.isNotEmpty)
              for (final m in reps) _reponseImbriquee(c, asObj(m)),
            if (attend) ...[
              const SizedBox(height: 7),
              Row(children: [
                _cAct(c, Icons.reply_outlined, 'Répondre', true, () {
                  setState(() => _reponseA = cid);
                }),
                const SizedBox(width: 4),
                _cAct(c, Icons.check_outlined, 'Approuver', false, () async {
                  await Moderation.approuve(cid);
                  await Journal.ajoute('moderation',
                      'Commentaire approuvé', detail: 'de $name');
                  widget.onChanged();
                }),
                const SizedBox(width: 4),
                _cAct(c, Icons.visibility_off_outlined, 'Masquer', false,
                    () async {
                  await Moderation.masque(cid);
                  await Journal.ajoute('moderation',
                      'Commentaire caché', detail: 'de $name');
                  widget.onChanged();
                }),
              ]),
            ],
            if (estMaReponse) ...[
              const SizedBox(height: 8),
              _boiteReponse(c, x),
            ],
            if (suggereIci && _suggestion.isNotEmpty) ...[
              const SizedBox(height: 8),
              _blocIa(c, x),
            ] else if (attend && !suggereIci) ...[
              const SizedBox(height: 8),
              _lancerIa(c, x),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _reponseImbriquee(Palette c, Map<String, dynamic> m) {
    final from = asObj(m['from']);
    final name = from.os('name').isEmpty ? 'Page' : from.os('name');
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        avatarInitiales(c, name, 24),
        const SizedBox(width: 7),
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
                color: c.card,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: T.strong(c).copyWith(fontSize: 11.5)),
              if (m.os('message').isNotEmpty)
                Text(m.os('message'), style: T.body(c).copyWith(fontSize: 12)),
              Text(rel(m.os('created_time')),
                  style: T.caption(c).copyWith(fontSize: 10.5)),
            ]),
          ),
        ),
      ]),
    );
  }

  /* ----- bloc réponse suggérée par l'IA ----- */

  Widget _lancerIa(Palette c, Cmt x) {
    final busy = _iaEnCours == x.c.os('id');
    return Press(
      onTap: busy ? null : () => _suggere(x),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy)
            SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(c.accent)))
          else
            Icon(Icons.auto_awesome, size: 13, color: c.accent),
          const SizedBox(width: 6),
          Text('Réponse suggérée · IA',
              style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w800, color: c.ink)),
        ]),
      ),
    );
  }

  Widget _blocIa(Palette c, Cmt x) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: c.accent.withValues(alpha: .14),
                shape: BoxShape.circle),
            child: Icon(Icons.auto_awesome, size: 12, color: c.accent),
          ),
          const SizedBox(width: 7),
          Text('RÉPONSE SUGGÉRÉE · ASSISTANT IA', style: T.micro(c)),
        ]),
        const SizedBox(height: 6),
        SelectableText(_suggestion, style: T.body(c).copyWith(fontSize: 13)),
        const SizedBox(height: 8),
        Row(children: [
          Press(
            onTap: () => _envoyerSuggestion(x),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(9)),
              child: Text('Envoyer',
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: c.onAccent)),
            ),
          ),
          const SizedBox(width: 8),
          Press(
            onTap: () => setState(() {
              _suggestionPour = '';
              _suggestion = '';
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                  color: c.soft,
                  borderRadius: BorderRadius.circular(9)),
              child: Text('Écarter',
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: c.ink)),
            ),
          ),
        ]),
      ]),
    );
  }

  /* ----- zone de saisie de réponse ----- */

  Widget _boiteReponse(Palette c, Cmt? x) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KEdit(controller: _ta, hint: 'Ta réponse...', minLines: 2),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: ActionBtn('Mettre en file',
              height: 38,
              job: x == null
                  ? () async {
                      throw Exception('Choisis d\'abord un commentaire à répondre.');
                    }
                  : () => _envoyerReponse(x)),
        ),
        const SizedBox(width: 8),
        ActionBtn('Annuler',
            height: 38,
            variant: KBtnVariant.ghost,
            job: () async {
              setState(() {
                _reponseA = '';
                _ta.clear();
              });
            }),
      ]),
    ]);
  }

  Widget _cAct(Palette c, IconData ic, String label, bool pri, VoidCallback f) {
    return Press(
      onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: pri ? c.accent.withValues(alpha: .1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: pri ? c.accent.withValues(alpha: .4) : c.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 12, color: pri ? c.accent : c.muted),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: pri ? c.accent : c.ink)),
        ]),
      ),
    );
  }
}

/* ---------- helpers visuels partagés (page + badges) ---------- */

/// Avatar rond de la Page : initiale sur fond inversé.
Widget avatarPage(Palette c, double size) {
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
    child: Text('K',
        style: TextStyle(
            fontSize: size * .42, fontWeight: FontWeight.w900, color: c.bg)),
  );
}

/// Badge « vérifié » bleu avec coche blanche, comme la maquette.
Widget badgeVerifie(Palette c, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
    child: Icon(Icons.check, size: size * .62, color: c.onAccent),
  );
}

/// Avatar rond avec initiales (2 lettres) pour un abonné.
Widget avatarInitiales(Palette c, String name, double size) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final ini = parts.length >= 2 && parts[1].isNotEmpty
      ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
      : (name.isNotEmpty ? name[0].toUpperCase() : '?');
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
        color: c.soft, shape: BoxShape.circle, border: Border.all(color: c.line)),
    child: Text(ini,
        style: TextStyle(
            fontSize: size * .38, fontWeight: FontWeight.w800, color: c.ink)),
  );
}

/// Étiquette d'urgence locale (Prix / Colère / Spam).
Widget etiquette(Palette c, String label, bool urgent) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: urgent ? c.accent : c.line)),
    child: Text(label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: urgent ? c.accent : c.muted)),
  );
}
