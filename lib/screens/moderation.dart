import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/notifs.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../widgets/post_card.dart' show avatarInitiales, etiquette;
import 'boite.dart' show ReplyBoxAvis;

/// Modération, comme sur la maquette : file des commentaires à traiter,
/// tri par urgence (détection locale : prix, colère, spam, doublons),
/// contexte de publication visible au-dessus de chaque bulle, réponse
/// en un tap, balayage droite = approuver / gauche = cacher avec
/// « Annuler », et traitement par lot.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  List<UnifiedItem> _avis = const [];
  Moderation _mod = const Moderation();
  bool _busy = true;
  final Set<String> _reponseOuverte = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = _avis.isEmpty);
    try {
      final (items, _) = await Boite.charge();
      final mod = await Moderation.charge();
      if (!mounted) return;
      setState(() {
        _avis = items.where((x) => x.kind == 'avis').toList();
        _mod = mod;
        _busy = false;
      });
      /* notifications locales : nouveaux urgents, une fois chacun */
      unawaited(
        Notifs.urgents(
          _aTraiter
              .where((x) => _mod.estUrgent(x.id, x.text))
              .map((x) => x.id)
              .toList(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      kToast(context, Api.hint(e), bad: true);
    }
  }

  /* ---------- actions ---------- */

  Future<void> _approuve(UnifiedItem it) async {
    await Moderation.approuve(it.id);
    await Journal.ajoute(
      'moderation',
      'Commentaire approuvé',
      detail: 'de ${it.name}',
    );
    if (!mounted) return;
    setState(
      () => _mod = Moderation(
        traite: {..._mod.traite, it.id},
        cache: _mod.cache.where((x) => x != it.id).toSet(),
        urgents: _mod.urgents.where((x) => x != it.id).toSet(),
      ),
    );
    _bandeau('Approuvé : ${it.name}', () async {
      await Moderation.reouvre(it.id);
      await Journal.ajoute(
        'moderation',
        'Approbation annulée',
        detail: 'de ${it.name}',
      );
      await _load();
    });
  }

  Future<void> _cache(UnifiedItem it) async {
    await Moderation.masque(it.id);
    await Journal.ajoute(
      'moderation',
      'Commentaire caché',
      detail: 'de ${it.name}',
    );
    if (!mounted) return;
    setState(
      () => _mod = Moderation(
        cache: {..._mod.cache, it.id},
        traite: _mod.traite.where((x) => x != it.id).toSet(),
        urgents: _mod.urgents.where((x) => x != it.id).toSet(),
      ),
    );
    _bandeau('Caché : ${it.name}', () async {
      await Moderation.reouvre(it.id);
      await Journal.ajoute(
        'moderation',
        'Masquage annulé',
        detail: 'de ${it.name}',
      );
      await _load();
    });
  }

  /// Suppression réelle : confirmation, puis mise en file pour le bot.
  /// Le commentaire est retiré de Facebook au prochain cycle du bot
  /// (action « delete_comment » dans posts/actions.json).
  Future<void> _supprime(UnifiedItem it) async {
    if (!await kConfirm(
      context,
      'Supprimer définitivement ce commentaire sur Facebook ? '
      'Action irréversible : le bot l\'exécutera au prochain cycle.',
    )) {
      return;
    }
    final pid = asObj(it.cmt?.post).os('id');
    try {
      await Api.updateJson('posts/actions.json', true, (cur) {
        final a = (cur is List ? cur : <dynamic>[]).toList();
        a.add({
          if (pid.isNotEmpty) 'post_id': pid,
          'comment_id': it.id,
          'action': 'delete_comment',
          'status': 'pending',
        });
        return a;
      }, 'Suppression de commentaire (appli de contrôle)');
    } catch (e) {
      if (mounted) kToast(context, Api.hint(e), bad: true);
      return;
    }
    await Moderation.approuve(it.id); // retiré de la file à afficher
    await Journal.ajoute(
      'moderation',
      'Suppression envoyée au bot',
      detail: 'de ${it.name}',
    );
    if (!mounted) return;
    setState(
      () => _mod = Moderation(
        traite: {..._mod.traite, it.id},
        cache: _mod.cache.where((x) => x != it.id).toSet(),
        urgents: _mod.urgents.where((x) => x != it.id).toSet(),
      ),
    );
    kToast(
      context,
      'Suppression mise en file : appliquée au prochain cycle du bot.',
    );
  }

  void _bandeau(String msg, Future<void> Function() annuler) {
    Fx.medium();
    final c = context.p;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: c.bg,
            ),
          ),
          backgroundColor: c.ink,
          behavior: SnackBarBehavior.floating,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 78),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Annuler',
            textColor: c.accent,
            onPressed: () => Future.microtask(annuler),
          ),
        ),
      );
  }

  Future<void> _toutApprouver() async {
    final liste = _aTraiter;
    if (liste.isEmpty) return;
    if (!await kConfirm(
      context,
      'Approuver les ${liste.length} commentaires en attente ?',
    )) {
      return;
    }
    for (final it in liste) {
      await Moderation.approuve(it.id);
    }
    await Journal.ajoute(
      'moderation',
      'Lot approuvé (${liste.length} commentaires)',
    );
    await _load();
    if (mounted) kToast(context, '${liste.length} commentaires approuvés.');
  }

  /* ---------- sélections ---------- */

  List<UnifiedItem> get _aTraiter {
    final liste =
        _avis
            .where(
              (x) => !_mod.traite.contains(x.id) && !_mod.cache.contains(x.id),
            )
            .toList()
          ..sort((a, b) {
            final ua = _mod.estUrgent(a.id, a.text) ? 0 : 1;
            final ub = _mod.estUrgent(b.id, b.text) ? 0 : 1;
            if (ua != ub) return ua - ub;
            return b.ts.compareTo(a.ts);
          });
    return liste;
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_busy && _avis.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          KSkeleton(110),
          SizedBox(height: 12),
          KSkeleton(110),
          SizedBox(height: 12),
          KSkeleton(90),
        ],
      );
    }
    final liste = _aTraiter;
    final urgents = liste.where((x) => _mod.estUrgent(x.id, x.text)).length;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    "Tri par urgence — détection locale : prix, colère, spam, doublons. "
                    'Balaye à droite pour approuver, à gauche pour cacher.',
                    style: T.caption(c),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: liste.isEmpty ? c.soft : c.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${liste.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: liste.isEmpty ? c.muted : c.onAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (urgents > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text('MODÉRATION — ', style: T.microInk(c)),
                    Text(
                      '$urgents URGENT(S) D\u2019ABORD',
                      style: T.micro(c).copyWith(color: c.ink),
                    ),
                  ],
                ),
              ),
            if (liste.isEmpty)
              KEmpty(
                Icons.verified_outlined,
                'Rien à modérer : tout est traité.',
                sub:
                    'Les nouveaux commentaires arrivent à chaque cycle du bot.',
              )
            else
              for (final it in liste.take(60))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _carte(c, it),
                ),
          ],
        ),
        /* barre de traitement par lot */
        if (liste.length > 1)
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: ActionBtn(
              'Tout approuver (${liste.length})',
              icon: Icons.done_all_outlined,
              height: 50,
              job: _toutApprouver,
            ),
          ),
      ],
    );
  }

  /* ---------- carte de modération : contexte + bulle + actions ---------- */

  Widget _carte(Palette c, UnifiedItem it) {
    final urgent = _mod.estUrgent(it.id, it.text);
    final tag = Moderation.detecteTag(it.text);
    final ouverte = _reponseOuverte.contains(it.id);
    final postTxt = it.postTxt;

    Widget coeur = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /* contexte : la publication concernée */
          if (postTxt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c.soft,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: c.line),
                    ),
                    child: Icon(Icons.image_outlined, size: 13, color: c.muted),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '« ${postTxt.length > 70 ? '${postTxt.substring(0, 70)}…' : postTxt} »',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.caption(c).copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          /* la bulle du commentaire */
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatarInitiales(c, it.name, 30),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              it.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.strong(c).copyWith(fontSize: 12.5),
                            ),
                          ),
                          if (tag != null) etiquette(c, tag, urgent),
                        ],
                      ),
                      if (it.text.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(it.text, style: T.body(c).copyWith(fontSize: 13)),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        relMs(it.ts),
                        style: T.caption(c).copyWith(fontSize: 11),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: _cAct(
                              c,
                              Icons.reply_outlined,
                              'Répondre',
                              true,
                              () {
                                Fx.tick();
                                setState(
                                  () => ouverte
                                      ? _reponseOuverte.remove(it.id)
                                      : _reponseOuverte.add(it.id),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _cAct(
                              c,
                              Icons.check_outlined,
                              'Approuver',
                              false,
                              () => _approuve(it),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _cAct(
                              c,
                              Icons.visibility_off_outlined,
                              'Masquer',
                              false,
                              () => _cache(it),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _cAct(
                              c,
                              Icons.delete_outline,
                              'Supprimer',
                              false,
                              () => _supprime(it),
                            ),
                          ),
                        ],
                      ),
                      if (ouverte) ...[
                        const SizedBox(height: 8),
                        ReplyBoxAvis(cid: it.id, nom: it.name, onSent: _load),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Cacher retire le commentaire des écrans de l\'application ; '
            'le commentaire reste visible sur Facebook. Supprimer le retire '
            'définitivement de Facebook (confirmation demandée).',
            style: T.caption(c).copyWith(fontSize: 10.5),
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('mod-${it.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 22, color: c.ink),
            const SizedBox(width: 8),
            Text(
              'APPROUVER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: c.ink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CACHER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
                color: c.bg,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.visibility_off_outlined, size: 20, color: c.bg),
          ],
        ),
      ),
      onDismissed: (_) {},
      confirmDismiss: (d) async {
        if (d == DismissDirection.startToEnd) {
          await _approuve(it);
        } else {
          await _cache(it);
        }
        return true;
      },
      child: coeur,
    );
  }

  Widget _cAct(Palette c, IconData ic, String label, bool pri, VoidCallback f) {
    return Press(
      onTap: f,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pri ? c.accent.withValues(alpha: .1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: pri ? c.accent.withValues(alpha: .4) : c.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ic, size: 12, color: pri ? c.accent : c.muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: pri ? c.accent : c.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
