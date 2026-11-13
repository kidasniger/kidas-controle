import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/charts.dart';
import '../ui/common.dart';
import '../ui/shell.dart' show Bus;

/// Statistiques : héros abonnés, tuiles KPI, explorateur de courbes,
/// barres quotidiennes, anneaux de santé. Port fidèle de StatsScreen.java.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Dash? _d;
  bool _busy = true;
  String? _err;
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await Api.dash();
      if (!mounted) return;
      setState(() {
        _d = d;
        _busy = false;
        _sel = 0;
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

  @override
  Widget build(BuildContext context) {
    if (_busy && _d == null) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(120),
        SizedBox(height: 12),
        KSkeleton(80),
        SizedBox(height: 12),
        KSkeleton(80),
      ]);
    }
    if (_err != null && _d == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Connexion impossible', style: T.strong(context.p)),
          const SizedBox(height: 6),
          Text(_err!, style: T.caption(context.p)),
          const SizedBox(height: 12),
          KBtn('Réessayer', onTap: _load),
        ])),
      ]);
    }
    final c = context.p;
    final d = _d!;
    final ms = Api.metrics(d.st);
    Map<String, dynamic> pg = <String, dynamic>{};
    final p1 = d.st?['page'];
    if (p1 is Map<String, dynamic>) pg = p1;
    if (pg.isEmpty) {
      final p2 = d.cm?['page'];
      if (p2 is Map<String, dynamic>) pg = p2;
    }
    final pendingSum = d.pending.fold<int>(0, (a, b) => a + b);
    final all = Api.flatComments(d.cm);
    final un = Api.unanswered(all, Api.pageId(d.st, d.cm));

    var sub = pg.containsKey('fan_count')
        ? '${nf(pg['fan_count'] is num ? pg['fan_count'] : 0)} J\'aime sur la Page'
        : '';
    if (d.st != null && d.st!.os('date').isNotEmpty) {
      sub += '${sub.isEmpty ? '' : ' · '}mis à jour ${rel(d.st!.os('date'))}';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        /* héros : abonnés */
        KHero(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ABONNÉS', style: T.micro(c).copyWith(color: c.heroMut)),
            CountUpText(
              pg.containsKey('followers_count')
                  ? (pg['followers_count'] as num? ?? 0).toDouble()
                  : 0,
              style: T.hero(c).copyWith(fontSize: 42, color: c.heroInk),
            ),
            if (sub.isNotEmpty)
              Text(sub, style: T.body(c).copyWith(color: c.heroMut)),
          ]),
        ),
        const SizedBox(height: 12),
        /* tuiles KPI */
        Row(children: [
          Expanded(
              child: _kpi(c, Icons.favorite_outline, 'J\'aime la Page',
                  _num(pg['fan_count']))),
          const SizedBox(width: 12),
          Expanded(
              child: _kpi(c, Icons.chat_bubble_outline, 'Sans réponse',
                  d.cm == null ? 0 : un.length.toDouble())),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _kpi(c, Icons.schedule_outlined, 'En attente',
                  pendingSum.toDouble())),
          const SizedBox(width: 12),
          Expanded(
              child: _kpi(c, Icons.trending_up_outlined, 'Commentaires',
                  d.cm == null ? 0 : all.length.toDouble())),
        ]),
        const SizedBox(height: 16),
        /* courbes */
        if (ms.isEmpty) ...[
          KSection('Courbes'),
          KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KEmpty(Icons.insert_chart_outlined,
                "Aucune statistique pour l'instant. Lance « Statistiques » depuis l'accueil."),
            const SizedBox(height: 8),
            ActionBtn('Lancer les statistiques',
                icon: Icons.play_arrow_rounded,
                job: () => Api.dispatch('statistiques.yml', null),
                ok: 'Statistiques lancées.'),
          ])),
        ] else ...[
          _explorer(c, ms),
          const SizedBox(height: 16),
          _bars(c, ms),
        ],
        const SizedBox(height: 16),
        /* anneaux */
        _rings(c, d, all, un),
        const SizedBox(height: 16),
        /* toutes les métriques */
        if (ms.isNotEmpty) ...[
          KSection('Toutes les métriques'),
          KCard(
            child: Column(children: [
              for (var i = 0; i < ms.length; i++) ...[
                if (i > 0) const KDivider(),
                _metricRow(c, i, ms[i]),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  double _num(dynamic v) => v is num ? v.toDouble() : 0;

  Widget _kpi(Palette c, IconData ic, String label, double v) {
    return KCard(
      pad: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ic, size: 15, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption(c))),
        ]),
        const SizedBox(height: 4),
        CountUpText(v, style: T.kpi(c)),
      ]),
    );
  }

  /* ---------- explorateur ---------- */

  Widget _explorer(Palette c, List<Metric> ms) {
    final m = ms[_sel.clamp(0, ms.length - 1)];
    final last = m.vals.last;
    var mn = m.vals[0], mx = m.vals[0], sum = 0.0;
    for (final v in m.vals) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
      sum += v;
    }
    final palette = [c.accent, c.muted, c.accent, c.muted, c.muted];
    final color = palette[_sel % palette.length];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('Évolution'),
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          children: [
            for (var i = 0; i < ms.length; i++)
              Padding(
                padding: EdgeInsets.only(right: i == ms.length - 1 ? 0 : 8),
                child: Press(
                  onTap: () {
                    Fx.tick();
                    setState(() => _sel = i);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: _sel == i ? c.accent : c.soft,
                        borderRadius: BorderRadius.circular(99)),
                    child: Text(ms[i].name,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _sel == i ? c.onAccent : c.muted)),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        CountUpText(last, style: T.title(c).copyWith(fontSize: 32)),
        const SizedBox(width: 10),
        if (m.vals.length > 1) deltaChip(context, last, m.vals[m.vals.length - 2]),
      ]),
      const SizedBox(height: 6),
      LineChart(m.vals, labs: m.labs, color: color),
      const SizedBox(height: 8),
      Row(children: [
        for (final it in [
          ['Min', nf(mn)],
          ['Moyenne', nf(sum / m.vals.length)],
          ['Max', nf(mx)],
        ])
          Expanded(
            child: Column(children: [
              Text(it[1], style: T.strong(c).copyWith(fontSize: 16)),
              Text(it[0], style: T.caption(c)),
            ]),
          ),
      ]),
    ]);
  }

  /* ---------- barres quotidiennes ---------- */

  Widget _bars(Palette c, List<Metric> ms) {
    var pick = ms[0];
    for (final m in ms) {
      if (m.key == 'page_daily_follows_unique') pick = m;
    }
    if (identical(pick, ms[0]) && ms.length > 1 && pick.key != 'page_daily_follows_unique') {
      pick = ms[1];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('${pick.name} par jour'),
      KCard(
        pad: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: BarChart(pick.vals, labs: pick.labs, color: c.accent),
      ),
    ]);
  }

  /* ---------- anneaux de santé ---------- */

  Widget _rings(Palette c, Dash d, List<Cmt> all, List<Cmt> un) {
    final answered =
        all.isEmpty ? 1.0 : (all.length - un.length) / all.length;
    var done = 0, ok = 0;
    for (final r in d.runs) {
      final ro = asObj(r);
      if (ro.os('status') != 'completed') continue;
      done++;
      if (ro.os('conclusion') == 'success') ok++;
    }
    final success = done == 0 ? 0.0 : ok / done;
    final tot = d.total.fold<int>(0, (a, b) => a + b);
    final pend = d.pending.fold<int>(0, (a, b) => a + b);
    final files = tot == 0 ? 1.0 : (tot - pend) / tot;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('Santé du bot'),
      KCard(
        child: Row(children: [
          Expanded(child: _ring(c, 'Réponses données', answered, c.accent)),
          Expanded(child: _ring(c, 'Exécutions réussies', success, c.muted)),
          Expanded(child: _ring(c, 'Files traitées', files, c.accent)),
        ]),
      ),
    ]);
  }

  Widget _ring(Palette c, String label, double p, Color color) {
    return Column(children: [
      KRing(p, color: color),
      const SizedBox(height: 8),
      Text(label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: T.caption(c)),
    ]);
  }

  Widget _metricRow(Palette c, int idx, Metric m) {
    final last = m.vals.last;
    return Press(
      onTap: () {
        Fx.tick();
        setState(() => _sel = idx);
        kToast(context, '${m.name} affiché plus haut.');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(m.name, style: T.body(c))),
          const SizedBox(width: 8),
          Text(nf(last), style: T.strong(c).copyWith(fontSize: 15)),
          if (m.vals.length > 1) ...[
            const SizedBox(width: 8),
            deltaChip(context, last, m.vals[m.vals.length - 2]),
          ],
        ]),
      ),
    );
  }
}
