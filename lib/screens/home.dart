import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show Bus, SubPage;
import '../widgets/post_card.dart';
import 'boite.dart';
import 'composer.dart';
import 'moderation.dart';

/// Accueil « façon page Facebook », comme sur la maquette : l'identité de
/// la Page est dans la barre du haut, les chiffres en une carte, la barre
/// de rédaction, les filtres, puis le fil des publications avec leurs
/// commentaires, la modération intégrée et les réponses suggérées par l'IA.
class HomeScreen extends StatefulWidget {
  final int gen;
  const HomeScreen({super.key, this.gen = 0});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _st, _cm;
  Moderation _mod = const Moderation();
  int _avisTodo = 0, _msgTodo = 0;
  int _vue = 0; // 0 Tout, 1 Avis, 2 Messages, 3 Chiffres
  String _upd = '';
  final List<String> _errs = [];
  bool _busy = true;

  /* fil paginé, programmations visibles et nouveautés depuis la dernière visite */
  int _limite = 15;
  List<Map<String, dynamic>> _avance = const [];
  String _vu = '';
  bool _aDefile = false;
  final GlobalKey _cleNouveau = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_preparerVisite());
  }

  /* La dernière ouverture sert de repère aux points « nouveau ». Elle est
     enregistrée tout de suite : la prochaine ouverture repartira de cette date. */
  Future<void> _preparerVisite() async {
    final v = await Store.get('accueil.vu');
    if (!mounted) return;
    setState(() => _vu = v ?? '');
    await Store.set('accueil.vu', DateTime.now().toUtc().toIso8601String());
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
    List<dynamic> avance = const [];
    await Future.wait<dynamic>([
      Api.readObj('inbox/statistiques.json')
          .then((v) {
            st = v;
          })
          .catchError((Object e) {
            errs.add(Api.hint(e));
          }),
      Api.readObj('inbox/commentaires.json')
          .then((v) {
            cm = v;
          })
          .catchError((Object e) {
            errs.add(Api.hint(e));
          }),
      Api.readObj('inbox/messages.json')
          .then((v) {
            inbox = v;
          })
          .catchError((Object e) {}),
      Api.readObj('posts/avance.json')
          .then((v) {
            avance = v is List ? v : const [];
          })
          .catchError((Object e) {}),
      Moderation.charge()
          .then((v) {
            _mod = v;
          })
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
      _avance = [
        for (final e in avance)
          if (e is Map<String, dynamic> && asObj(e).os('status') == 'pending') asObj(e),
      ];
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SubPage(title, child: screen)),
    );
  }

  /* ---------- données dérivées ---------- */

  String get _pageName {
    final p1 = _st?['page'];
    if (p1 is Map<String, dynamic> && p1.os('name').isNotEmpty) {
      return p1.os('name');
    }
    final p2 = _cm?['page'];
    if (p2 is Map<String, dynamic> && p2.os('name').isNotEmpty) {
      return p2.os('name');
    }
    return 'Ma Page';
  }

  String get _pageId {
    final p1 = _st?['page'];
    if (p1 is Map<String, dynamic> && p1.os('id').isNotEmpty)
      return p1.os('id');
    final p2 = _cm?['page'];
    if (p2 is Map<String, dynamic>) return p2.os('id');
    return '';
  }

  /* activité d'une publication : date de création ou du dernier commentaire */
  int _activite(Map<String, dynamic> po) {
    var t = Api.iso(po.os('created_time'));
    final cc = po['comments'];
    final da = cc is Map<String, dynamic> ? asArr(cc['data']) : const <dynamic>[];
    for (final c in da) {
      final ct = Api.iso(asObj(c).os('created_time'));
      if (ct > t) t = ct;
    }
    return t;
  }

  bool _estNouveau(Map<String, dynamic> p) {
    final vu = Api.iso(_vu);
    return vu > 0 && _activite(p) > vu;
  }

  List<Map<String, dynamic>> get _posts {
    final cm = _cm;
    if (cm == null) return const [];
    final out = <Map<String, dynamic>>[];
    for (final p in asArr(cm['posts'])) {
      final po = asObj(p);
      if (po.isNotEmpty) out.add(po);
    }
    out.sort((a, b) => _activite(b).compareTo(_activite(a)));
    return out;
  }

  /* ---------- rendu ---------- */

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
    return RefreshIndicator(
      color: c.accent,
      backgroundColor: c.card,
      onRefresh: () async => _load(),
      child: ListenableBuilder(
        listenable: Listenable.merge([Bus.chercher, Bus.requete]),
        builder: (_, __) {
          final cherche = Bus.chercher.value;
          final q = Bus.requete.value.trim().toLowerCase();
          final posts = _posts.where((p) {
            if (q.isEmpty) return true;
            if (_postTxt(p).toLowerCase().contains(q)) return true;
            for (final x in Api.flatComments({
              'posts': [p],
            })) {
              if (x.c.os('message').toLowerCase().contains(q)) return true;
            }
            return false;
          }).toList();
          if (_vue == 0 && posts.any(_estNouveau) && !_aDefile) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = _cleNouveau.currentContext;
              if (ctx == null) return;
              _aDefile = true;
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 450),
                alignment: 0.02,
              );
            });
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 96),
            children: [
              _kpis(c),
              const SizedBox(height: 10),
              _salutation(c),
              const SizedBox(height: 10),
              _compose(c),
              const SizedBox(height: 10),
              _chips(c),
              if (cherche) ...[const SizedBox(height: 8), _champRecherche(c)],
              if (_avisTodo > 0 && _vue == 0) ...[
                const SizedBox(height: 10),
                _bandeModeration(c),
              ],
              if (_avance.isNotEmpty && _vue == 0) ...[
                const SizedBox(height: 10),
                _prog(c),
              ],
              for (final e in _errs.take(2))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: ErrBox(e),
                ),
              const SizedBox(height: 10),
              ..._contenu(c, posts),
            ],
          );
        },
      ),
    );
  }

  String _postTxt(Map<String, dynamic> p) {
    final t = p.os('message');
    return t.isEmpty ? p.os('story') : t;
  }

  /* ---------- chiffres de la Page (carte KPI de la maquette) ---------- */

  Widget _kpis(Palette c) {
    final ms = Api.metrics(_st);
    Metric? find(String k) {
      for (final m in ms) {
        if (m.key == k) return m;
      }
      return null;
    }

    final page = _st?['page'] is Map<String, dynamic>
        ? _st!['page'] as Map<String, dynamic>
        : <String, dynamic>{};
    final abonnes =
        find('page_follows') != null && find('page_follows')!.vals.isNotEmpty
        ? find('page_follows')!.vals.last
        : (page['followers_count'] is num
              ? (page['followers_count'] as num).toDouble()
              : 0.0);
    final nouveaux = sommeRecente(
      find('page_daily_follows_unique')?.vals ?? const [],
      7,
    );
    final visites = sommeRecente(find('page_views_total')?.vals ?? const [], 7);
    final interactions = sommeRecente(
      find('page_post_engagements')?.vals ?? const [],
      7,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _kpi(
              c,
              abonnes <= 0 ? '—' : nf(abonnes),
              'Abonnés',
              nouveaux > 0 ? '+${nf(nouveaux)}' : '',
            ),
          ),
          _vdiv(c),
          Expanded(
            child: _kpi(
              c,
              visites > 0 ? nf(visites) : '—',
              'Visites · 7 j',
              '',
            ),
          ),
          _vdiv(c),
          Expanded(
            child: _kpi(
              c,
              interactions > 0 ? nf(interactions) : '—',
              'Interactions',
              '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(Palette c, String v, String label, String delta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(v, style: T.kpi(c)),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: T.micro(c).copyWith(fontSize: 9, letterSpacing: 1.26),
              ),
              if (delta.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  delta,
                  style: T
                      .micro(c)
                      .copyWith(
                        color: c.accent,
                        fontSize: 9.5,
                        letterSpacing: 0,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _vdiv(Palette c) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: c.line,
    );
  }

  /* ---------- barre de rédaction ---------- */

  Widget _compose(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          avatarPage(
            c,
            36,
            _pageName.isEmpty ? null : _pageName.substring(0, 1),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Press(
              onTap: () => _go('Composer', const ComposerScreen()),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quoi de neuf, $_pageName ?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    ),
                    Icon(Icons.image_outlined, size: 16, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ---------- filtres ---------- */

  Widget _chips(Palette c) {
    final labels = [
      ('Tout', ''),
      ('Avis', _avisTodo > 0 ? '${_avisTodo}' : ''),
      ('Messages', _msgTodo > 0 ? '$_msgTodo' : ''),
      ('Chiffres', ''),
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
                  if (i == 1) {
                    _go('Boîte unifiée', const BoiteScreen(filtreInitial: 1));
                  } else if (i == 2) {
                    _go('Boîte unifiée', const BoiteScreen(filtreInitial: 2));
                  } else {
                    setState(() => _vue = i == 3 ? 3 : 0);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _vue == i ? c.accent : c.card,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _vue == i ? c.accent : c.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labels[i].$1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _vue == i ? c.onAccent : c.ink,
                        ),
                      ),
                      if (labels[i].$2.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Text(
                          labels[i].$2,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: _vue == i ? c.onAccent : c.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _champRecherche(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: KEdit(
              text: Bus.requete.value,
              hint: 'Chercher un post ou un commentaire...',
              onChanged: (v) => Bus.requete.value = v,
            ),
          ),
          const SizedBox(width: 8),
          Press(
            onTap: () {
              Fx.tick();
              Bus.requete.value = '';
              Bus.chercher.value = false;
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line),
              ),
              child: Icon(Icons.close, size: 17, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bandeModeration(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Press(
        onTap: () => _go('Modération', const ModerationScreen()),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text('MODÉRATION — ', style: T.microInk(c)),
              Text(
                '$_avisTodo EN ATTENTE',
                style: T.micro(c).copyWith(color: c.ink),
              ),
              const Spacer(),
              Text(
                "Urgent d'abord",
                style: T.caption(c).copyWith(fontSize: 10.5),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 14, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------- salutation et date du jour ---------- */

  Widget _salutation(Palette c) {
    final n = DateTime.now();
    final bon = n.hour >= 5 && n.hour < 18 ? 'Bonjour' : 'Bonsoir';
    const jours = [
      'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
    ];
    const mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$bon, $_pageName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.strong(c).copyWith(fontSize: 15),
            ),
          ),
          Text(
            '${jours[n.weekday - 1]} ${n.day} ${mois[n.month - 1]}',
            style: T.caption(c),
          ),
        ],
      ),
    );
  }

  /* ---------- publications programmées ---------- */

  Widget _prog(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Press(
        onTap: _feuilleProg,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text('PROGRAMMÉES — ', style: T.microInk(c)),
              Text(
                '${_avance.length} EN FILE',
                style: T.micro(c).copyWith(color: c.ink),
              ),
              const Spacer(),
              Text(
                'Voir et annuler',
                style: T.caption(c).copyWith(fontSize: 10.5),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 14, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }

  String _progTexte(Map<String, dynamic> e) {
    final t = e.os('message');
    if (t.isNotEmpty) return t;
    if (e.os('image_path').isNotEmpty || e.os('video_path').isNotEmpty) {
      return 'Publication avec média';
    }
    return '(sans texte)';
  }

  Future<void> _feuilleProg() async {
    final c = context.p;
    final items = List<Map<String, dynamic>>.from(_avance);
    await kSheet<int>(
      context,
      title: 'Publications programmées',
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                IconBox(Icons.schedule_outlined),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fdate(Api.iso(items[i].os('publish_at'))),
                        style:
                            T.micro(c).copyWith(color: c.accent, fontSize: 10),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _progTexte(items[i]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      if (items[i].containsKey('claimed_at')) ...[
                        const SizedBox(height: 2),
                        Text(
                          "En cours d'envoi par le bot...",
                          style: T.caption(c).copyWith(fontSize: 10.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!items[i].containsKey('claimed_at'))
                  Press(
                    onTap: () {
                      Fx.tick();
                      Navigator.pop(context);
                      _annulerProg(items[i]);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        'Annuler',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _annulerProg(Map<String, dynamic> cible) async {
    try {
      await Api.updateJson('posts/avance.json', true, (cur) {
        final a = (cur is List ? cur : <dynamic>[]).toList();
        for (var j = 0; j < a.length; j++) {
          final e = asObj(a[j]);
          if (e.os('status') == 'pending' &&
              e.os('publish_at') == cible.os('publish_at') &&
              e.os('message') == cible.os('message') &&
              e.os('image_path') == cible.os('image_path') &&
              e.os('video_path') == cible.os('video_path')) {
            a.removeAt(j);
            break;
          }
        }
        return a;
      }, 'Programmation annulée');
      await Journal.ajoute(
        'post',
        'Programmation annulée',
        detail: _progTexte(cible),
      );
      if (mounted) kToast(context, 'Programmation annulée.');
      _load();
    } catch (e) {
      if (mounted) kToast(context, Api.hint(e), bad: true);
    }
  }

  /* ---------- contenu selon le filtre ---------- */

  List<Widget> _contenu(Palette c, List<Map<String, dynamic>> posts) {
    switch (_vue) {
      case 3:
        return [_chiffres(c), const SizedBox(height: 4)];
      case 0:
        if (posts.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: KEmpty(
                Icons.feed_outlined,
                Bus.requete.value.isEmpty
                    ? 'Rien encore sur la Page.'
                    : 'Aucun résultat pour cette recherche.',
                sub: Bus.requete.value.isEmpty
                    ? "Lance « Surveiller » dans l'onglet Bot pour remplir le fil."
                    : 'Essaie un autre mot.',
              ),
            ),
          ];
        }
        final liste = posts.take(_limite).toList();
        final premierNouveau = liste.indexWhere(_estNouveau);
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                for (var i = 0; i < liste.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PostCard(
                      key: i == premierNouveau ? _cleNouveau : null,
                      post: liste[i],
                      pageName: _pageName,
                      pageId: _pageId,
                      mod: _mod,
                      nouveau: _estNouveau(liste[i]),
                      onChanged: _load,
                    ),
                  ),
                if (posts.length > _limite)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    child: ActionBtn(
                      'Afficher plus (${posts.length - _limite} restantes)',
                      icon: Icons.expand_more_outlined,
                      variant: KBtnVariant.ghost,
                      job: () => setState(() => _limite += 15),
                    ),
                  ),
                if (_upd.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Données du dernier cycle du bot : ${rel(_upd)}',
                      style: T.caption(c),
                    ),
                  ),
              ],
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  /* ---------- vue Chiffres ---------- */

  Widget _chiffres(Palette c) {
    final ms = Api.metrics(_st);
    if (ms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: KCard(
          child: Text(
            'Aucune statistique : lance « Statistiques » depuis l\'onglet Bot.',
            style: T.body(c).copyWith(color: c.muted),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: KCard(
        child: Column(
          children: [
            for (var i = 0; i < ms.length; i++) ...[
              if (i > 0) const KDivider(),
              Row(
                children: [
                  Expanded(child: Text(ms[i].name, style: T.body(c))),
                  Text(
                    nf(ms[i].vals.last),
                    style: T.strong(c).copyWith(fontSize: 15),
                  ),
                  if (ms[i].vals.length > 1) ...[
                    const SizedBox(width: 8),
                    Text(
                      pct(ms[i].vals.last, ms[i].vals[ms[i].vals.length - 2]),
                      style: T.caption(c).copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
