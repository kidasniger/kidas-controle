import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/palette.dart';
import '../ui/common.dart';

/// Accueil réel : héros état du bot + files d'attente + dernières exécutions.
/// (Version fondation — fidélité fine à la maquette à la passe UI.)
class HomeScreen extends StatefulWidget {
  final int gen;
  const HomeScreen({super.key, this.gen = 0});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Dash? _dash;
  bool _busy = true;
  String? _err;

  static const _queueNames = {
    'queue': 'File standard',
    'avance': 'File avancée',
    'replies': 'Réponses',
    'actions': 'Actions',
    'messages': 'Messages',
  };

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
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await Api.dash();
      if (!mounted) return;
      setState(() {
        _dash = d;
        _busy = false;
      });
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
    final c = context.p;
    if (_busy && _dash == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const KSkeleton(120),
          const SizedBox(height: 12),
          const KSkeleton(80),
          const SizedBox(height: 12),
          const KSkeleton(200),
        ],
      );
    }
    if (_err != null && _dash == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          KCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Connexion impossible', style: T.strong(c)),
              const SizedBox(height: 6),
              Text(_err!, style: T.caption(c)),
              const SizedBox(height: 12),
              KBtn('Réessayer', onTap: _load),
            ]),
          ),
        ],
      );
    }
    final d = _dash!;
    final bot = d.bot;
    final pendingSum = d.pending.fold<int>(0, (a, b) => a + b);
    final state = bot?.state ?? 'wait';
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        /* héros inversé : état du bot */
        KHero(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PulseDot(state == 'on' ? c.accent : c.heroMut),
              const SizedBox(width: 8),
              Text(
                state == 'on'
                    ? 'Bot en route'
                    : state == 'off'
                        ? "À l'arrêt"
                        : 'En attente',
                style: T.hero(c),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              bot == null
                  ? 'État indisponible'
                  : '${bot.running} exécution(s) en cours'
                    '${bot.veille == null ? '' : ' · veille ${bot.veille}'}',
              style: T.body(c).copyWith(color: c.heroMut),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        /* KPI : à traiter */
        Row(children: [
          Expanded(
            child: KCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('À TRAITER', style: T.micro(c)),
                const SizedBox(height: 4),
                Text('$pendingSum', style: T.kpi(c)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('EXÉCUTIONS', style: T.micro(c)),
                const SizedBox(height: 4),
                Text('${bot?.running ?? 0}', style: T.kpi(c)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        /* files d'attente */
        KSection('Files d\'attente'),
        for (var i = 0; i < Api.queues.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Press(
              onTap: () {},
              child: KCard(
                pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  IconBox(Icons.list_alt_outlined),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_queueNames[Api.queues[i]] ?? Api.queues[i],
                          style: T.strong(c)),
                      Text('${d.total[i]} élément(s)',
                          style: T.caption(c)),
                    ]),
                  ),
                  if (d.pending[i] > 0) KBadge('${d.pending[i]} à faire'),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 8),
        /* dernières exécutions */
        KSection('Dernières exécutions'),
        if (d.runs.isEmpty)
          KEmpty(Icons.terminal_outlined, 'Aucune exécution récente'),
        for (final r in d.runs.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _runCard(context, c, asObj(r)),
          ),
        if (d.errs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(d.errs.join('\n'),
                style: T.caption(c).copyWith(color: c.muted)),
          ),
      ],
    );
  }

  Widget _runCard(BuildContext ctx, Palette c, Map<String, dynamic> r) {
    final status = r.os('status');
    final concl = r.os('conclusion');
    final running = status != 'completed';
    final label = running
        ? 'En cours'
        : concl == 'success'
            ? 'Terminé'
            : concl.isEmpty
                ? status
                : concl;
    return KCard(
      pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        IconBox(running ? Icons.bolt_outlined : Icons.check_circle_outline),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.os('name').isEmpty ? 'Workflow' : r.os('name'),
                style: T.strong(c), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_ago(r.os('created_at')), style: T.caption(c)),
          ]),
        ),
        KBadge(label,
            bg: running ? c.accent : null,
            fg: running ? c.onAccent : null),
      ]),
    );
  }

  String _ago(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return "à l'instant";
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    return 'il y a ${d.inDays} j';
  }
}
