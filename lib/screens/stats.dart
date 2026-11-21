import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/bot_notification_sync.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/charts.dart';
import '../ui/common.dart';
import '../ui/shell.dart' show Bus;

/// Statistiques selon la maquette 06 : héros abonnés avec pilule de
/// variation, courbe de croissance, barres d'interactions de la semaine,
/// anneau de répartition et top publications par J'aime.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Dash? _d;
  bool _busy = true;
  String? _err;
  Map<String, dynamic>? _health;
  dynamic _likes;
  String? _healthError;
  String? _likesError;
  int _periode = 30; // fenêtre des courbes : 7 ou 30 jours

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await Api.dash();
      Map<String, dynamic>? health;
      dynamic likes;
      String? healthError;
      String? likesError;
      try {
        final raw = await Api.readBotJson('bot/sante.json');
        if (raw is Map<String, dynamic>) {
          health = raw;
        } else {
          healthError = 'Rapport de santé indisponible.';
        }
      } catch (error) {
        healthError = Api.hint(error);
      }
      try {
        likes = await Api.readBotJson('glm/aimes-commentaires.json');
      } catch (error) {
        likesError = Api.hint(error);
      }
      if (!mounted) return;
      setState(() {
        _d = d;
        _health = health;
        _likes = likes;
        _healthError = healthError;
        _likesError = likesError;
        _busy = false;
      });
      final cm = d.cm;
      if (cm != null) {
        final all = Api.flatComments(cm);
        final un = Api.unanswered(all, Api.pageId(d.st, d.cm));
        Bus.setAvis(un.length);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = Api.hint(e);
        _busy = false;
      });
    }
  }

  /* ---------- accès données ---------- */

  Metric? _metrique(String key) {
    for (final m in Api.metrics(_d?.st)) {
      if (m.key == key) return m;
    }
    return null;
  }

  List<double> _fen(List<double> v) =>
      v.length > _periode ? v.sublist(v.length - _periode) : v;

  List<String?>? _fenLabs(List<String?>? l) =>
      l == null || l.length <= _periode ? l : l.sublist(l.length - _periode);

  double _somme(List<double> v) {
    var t = 0.0;
    for (final x in v) {
      t += x;
    }
    return t;
  }

  double _lik(Map<String, dynamic> p) =>
      p['likes_total'] is num ? (p['likes_total'] as num).toDouble() : 0.0;

  /* libellés de la maquette : « 15/11 » devient « 15 nov » */
  String? jolieDate(String? lab) {
    if (lab == null) return null;
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})$').firstMatch(lab);
    if (m == null) return lab;
    const mois = [
      'janv',
      'févr',
      'mars',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sept',
      'oct',
      'nov',
      'déc',
    ];
    final j = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    if (mm < 1 || mm > 12) return lab;
    return '$j ${mois[mm - 1]}';
  }

  /* « 15/11 » devient la lettre du jour : L M M J V S D */
  String? jourSemaine(String? lab) {
    if (lab == null) return null;
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})$').firstMatch(lab);
    if (m == null) return null;
    final j = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    final auj = DateTime.now();
    var d = DateTime(auj.year, mm, j);
    if (d.isAfter(auj.add(const Duration(days: 2)))) {
      d = DateTime(auj.year - 1, mm, j);
    }
    const jours = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return jours[d.weekday - 1];
  }

  /* ---------- construction de l'écran ---------- */

  @override
  Widget build(BuildContext context) {
    if (_busy && _d == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          KSkeleton(120),
          SizedBox(height: 12),
          KSkeleton(160),
          SizedBox(height: 12),
          KSkeleton(140),
        ],
      );
    }
    if (_err != null && _d == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connexion impossible', style: T.strong(context.p)),
                const SizedBox(height: 6),
                Text(_err!, style: T.caption(context.p)),
                const SizedBox(height: 12),
                KBtn('Réessayer', onTap: _load),
              ],
            ),
          ),
        ],
      );
    }
    final c = context.p;
    final d = _d!;
    final suiv = _metrique('page_follows');
    final eng = _metrique('page_post_engagements');
    final vues = _metrique('page_views_total');
    final cont = _metrique('page_media_view');
    final pg = <String, dynamic>{};
    final p1 = d.st?['page'];
    if (p1 is Map<String, dynamic>) pg.addAll(p1);
    if (pg.isEmpty) {
      final p2 = d.cm?['page'];
      if (p2 is Map<String, dynamic>) pg.addAll(p2);
    }

    final kids = <Widget>[_pageHead(c)];
    var nCartes = 0;

    kids.add(_heros(c, pg, suiv));
    kids.add(const SizedBox(height: 12));
    kids.add(_carteRapport(c));
    if (suiv != null && suiv.vals.length >= 2) {
      nCartes++;
      kids.add(const SizedBox(height: 12));
      kids.add(_carteCroissance(c, suiv));
    }
    if (eng != null && eng.vals.isNotEmpty) {
      nCartes++;
      kids.add(const SizedBox(height: 12));
      kids.add(_carteInteractions(c, eng));
    }
    if (eng != null || vues != null || cont != null) {
      nCartes++;
      kids.add(const SizedBox(height: 12));
      kids.add(_carteAudience(c, eng, vues, cont));
    }
    final cm = d.cm;
    if (cm != null && asArr(cm['posts']).isNotEmpty) {
      nCartes++;
      kids.add(const SizedBox(height: 12));
      kids.add(_carteTop(c, cm));
    }
    if (nCartes == 0) {
      kids.add(const SizedBox(height: 12));
      kids.add(
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KEmpty(
                Icons.insert_chart_outlined,
                "Aucune statistique pour l'instant. Lance « Statistiques » depuis l'accueil.",
              ),
              const SizedBox(height: 8),
              ActionBtn(
                'Lancer les statistiques',
                icon: Icons.play_arrow_rounded,
                job: () => Api.dispatch('statistiques.yml', null),
                ok: 'Statistiques lancées.',
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: kids,
    );
  }

  /* en-tête : titre + segmenté 7 j / 30 j (maquette) */
  Widget _pageHead(Palette c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        children: [
          Text(
            'Stats',
            style: TextStyle(
              fontFamily: kDisp,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
              color: c.ink,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              children: [
                for (final (v, label) in const [(7, '7 j'), (30, '30 j')])
                  Press(
                    onTap: () {
                      Fx.tick();
                      setState(() => _periode = v);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _periode == v ? c.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _periode == v ? c.onAccent : c.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* héros : abonnés + pilule de variation (maquette stat-hero) */
  Widget _heros(Palette c, Map<String, dynamic> pg, Metric? suiv) {
    final f = pg['followers_count'] ?? pg['fan_count'];
    final n = f is num ? f.toDouble() : 0.0;
    String? delta;
    String? note;
    if (suiv != null && suiv.vals.length >= 2) {
      final v = _fen(suiv.vals);
      final gain = v.last - v.first;
      if (gain != 0) {
        delta = '${gain > 0 ? '+' : ''}${nf(gain.round())}';
        final tout = suiv.vals;
        if (tout.length >= _periode * 2 + 1) {
          final g2 =
              tout[tout.length - 1 - _periode] -
              tout[tout.length - 1 - 2 * _periode];
          if (g2 > 0) {
            final p = pct(gain, g2);
            if (p.isNotEmpty) note = '· $p vs période précédente';
          }
        }
      }
    }
    return KCard(
      pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ABONNÉS', style: T.micro(c)),
          const SizedBox(height: 4),
          CountUpText(
            n,
            style: TextStyle(
              fontFamily: kDisp,
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
              color: c.ink,
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: c.accent),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    delta,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.accent,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /* carte croissance : courbe des abonnés (maquette chart-card 1) */
  Widget _carteCroissance(Palette c, Metric suiv) {
    final v = _fen(suiv.vals);
    final labs = [
      for (final l in _fenLabs(suiv.labs) ?? const <String?>[]) jolieDate(l),
    ];
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CROISSANCE · $_periode JOURS', style: T.micro(c)),
          const SizedBox(height: 10),
          LineChart(v, labs: labs, color: c.accent),
        ],
      ),
    );
  }

  /* carte interactions : barres des 7 derniers jours (chart-card 2) */
  Widget _carteInteractions(Palette c, Metric eng) {
    final n = eng.vals.length < 7 ? eng.vals.length : 7;
    final v = eng.vals.sublist(eng.vals.length - n);
    List<String?> labs = const [];
    if (eng.labs != null && eng.labs!.length >= n) {
      final l = eng.labs!.sublist(eng.labs!.length - n);
      labs = [for (final s in l) jourSemaine(s)];
    }
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INTERACTIONS · 7 JOURS', style: T.micro(c)),
          const SizedBox(height: 10),
          BarChart(v, labs: labs, color: c.accent),
        ],
      ),
    );
  }

  /* carte audience : anneau de répartition + légende (chart-card 3) */
  Widget _carteAudience(Palette c, Metric? eng, Metric? vues, Metric? cont) {
    final parts = <(Metric, Color)>[];
    if (eng != null) parts.add((eng, c.accent));
    if (vues != null) parts.add((vues, c.muted));
    if (cont != null) parts.add((cont, c.line));
    if (parts.isEmpty) return const SizedBox();
    final tot = parts.fold<double>(0, (a, b) => a + _somme(_fen(b.$1.vals)));
    if (tot <= 0) return const SizedBox();
    final segs = [
      for (final (m, col) in parts) KDonutSeg(_somme(_fen(m.vals)) / tot, col),
    ];
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AUDIENCE', style: T.micro(c)),
          const SizedBox(height: 12),
          Row(
            children: [
              KDonut(
                segs,
                center: '${(segs.first.v * 100).round()} %',
                centerLabel: parts.first.$1.name,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (final (m, col) in parts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: col,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.caption(c),
                              ),
                            ),
                            Text(
                              '${(_somme(_fen(m.vals)) / tot * 100).round()} %',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Rapport opérationnel fondé sur le cache Facebook relu et les registres du bot.
  Widget _carteRapport(Palette c) {
    final comments = Api.flatComments(_d?.cm).length;
    final replies = BotNotificationSync.collectConfirmedReplyIds(
      _d?.cm ?? <String, dynamic>{},
    ).length;
    final faitsRaw = _likes is Map ? (_likes as Map)['faits'] : null;
    final faits = faitsRaw is Map ? faitsRaw : const <dynamic, dynamic>{};
    final likesConfirmed = faits.values.where(
      (value) => value is Map &&
          value['like'] == 'ok' &&
          value['verifie'] == true,
    ).length;
    final likesPending = faits.values.where(
      (value) => value is Map && value['like'] == 'pending',
    ).length;
    final errorsRaw = _health?['erreurs'];
    final errors = errorsRaw is List ? errorsRaw.length : 0;
    final fileRaw = _health?['file'];
    final queuedRaw = fileRaw is Map ? fileRaw['en_attente'] : 0;
    final queued = queuedRaw is num ? queuedRaw.toInt() : 0;
    final updated = DateTime.tryParse(_health?['mis_a_jour']?.toString() ?? '');
    final updatedLabel = updated == null
        ? (_healthError ?? 'Date de collecte indisponible')
        : 'Rapport bot du ${updated.toLocal().day.toString().padLeft(2, '0')}/'
          '${updated.toLocal().month.toString().padLeft(2, '0')} à '
          '${updated.toLocal().hour.toString().padLeft(2, '0')}:'
          '${updated.toLocal().minute.toString().padLeft(2, '0')}';
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RAPPORT DU BOT', style: T.micro(c)),
          const SizedBox(height: 5),
          Text(updatedLabel, style: T.caption(c)),
          if (_likesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Registre des J’aime : $_likesError', style: T.caption(c)),
            ),
          const SizedBox(height: 10),
          _ligneRapport(c, 'Commentaires collectés', nf(comments)),
          _ligneRapport(c, 'Réponses visibles sur Facebook', nf(replies)),
          _ligneRapport(c, 'J’aime confirmés', nf(likesConfirmed)),
          _ligneRapport(c, 'J’aime en attente', nf(likesPending)),
          _ligneRapport(c, 'Erreurs récentes', nf(errors)),
          _ligneRapport(c, 'Actions en attente', nf(queued)),
        ],
      ),
    );
  }

  Widget _ligneRapport(Palette c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: T.caption(c))),
          const SizedBox(width: 12),
          Text(
            value,
            style: T.body(c).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /* carte top publications par J'aime (chart-card 4) */
  Widget _carteTop(Palette c, Map<String, dynamic> cm) {
    final posts = [for (final e in asArr(cm['posts'])) asObj(e)];
    posts.sort((a, b) => _lik(b).compareTo(_lik(a)));
    final top = posts.take(3).toList();
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOP PUBLICATIONS · 7 JOURS', style: T.micro(c)),
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) Container(height: 1, color: c.line),
            _lignePost(c, top[i]),
          ],
        ],
      ),
    );
  }

  Widget _lignePost(Palette c, Map<String, dynamic> p) {
    var txt = p.os('message');
    if (txt.isEmpty) txt = p.os('story');
    if (txt.isEmpty) txt = 'Publication sans texte';
    final pic = p.os('full_picture');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          _vignette(c, pic),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              txt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(c).copyWith(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Text('${nf(_lik(p).round())} J\'aime', style: T.caption(c)),
        ],
      ),
    );
  }

  /* vignette 52 × 40 : image du post, ou pictogramme document */
  Widget _vignette(Palette c, String pic) {
    final vide = Container(
      width: 52,
      height: 40,
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.description_outlined, size: 16, color: c.muted),
    );
    if (pic.isEmpty) return vide;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        pic,
        width: 52,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => vide,
      ),
    );
  }
}
