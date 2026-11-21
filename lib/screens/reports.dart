import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/reports.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/pictos.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<JournalEvent> _events = const [];
  List<dynamic> _runs = const [];
  Map<String, dynamic>? _health;
  bool _busy = true;
  String? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        Journal.charge(max: 400),
        Api.runs(100),
        Api.readBotJson('bot/sante.json').catchError((Object _) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _events = values[0] as List<JournalEvent>;
        _runs = values[1] as List<dynamic>;
        _health = values[2] is Map<String, dynamic>
            ? values[2] as Map<String, dynamic>
            : null;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = Api.hint(error);
        _busy = false;
      });
    }
  }

  ReportSummary get _summary => ReportSummary.build(
        events: _events,
        runs: _runs,
        health: _health,
        days: _days,
      );

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _summary.toSafeText()));
    if (mounted) kToast(context, 'Rapport copié. Tu peux le partager.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_busy && _events.isEmpty && _runs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [KSkeleton(110), SizedBox(height: 12), KSkeleton(170)],
      );
    }
    if (_error != null && _events.isEmpty && _runs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rapport indisponible', style: T.strong(c)),
                const SizedBox(height: 6),
                Text(_error!, style: T.caption(c)),
                const SizedBox(height: 12),
                KBtn('Réessayer', onTap: _load),
              ],
            ),
          ),
        ],
      );
    }

    final s = _summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        Row(
          children: [
            Expanded(child: Text('Rapports d’activité', style: T.hero(c))),
            Press(
              onTap: _load,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.line),
                ),
                child: Picto('refresh', size: 17),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (days, label) in const [
              (1, '24 h'),
              (7, '7 jours'),
              (30, '30 jours'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Press(
                    onTap: () {
                      Fx.tick();
                      setState(() => _days = days);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _days == days ? c.accent : c.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _days == days ? c.accent : c.line,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: _days == days ? c.onAccent : c.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SYNTHÈSE', style: T.micro(c)),
              const SizedBox(height: 4),
              Text(
                '${s.eventCount}',
                style: T.hero(c).copyWith(fontSize: 32),
              ),
              Text('événements journalisés sur la période', style: T.caption(c)),
              const SizedBox(height: 12),
              _metric(c, 'Application', s.appEvents),
              _metric(c, 'Bot', s.botEvents),
              _metric(c, 'Publications', s.publications),
              _metric(c, 'Réponses journalisées', s.replies),
              _metric(c, 'Modération', s.moderation),
              _metric(c, 'Médias', s.media),
              _metric(c, 'Règles', s.rules),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WORKFLOWS GITHUB ACTIONS', style: T.micro(c)),
              const SizedBox(height: 8),
              _metric(c, 'Exécutions observées', s.workflowCount),
              _metric(c, 'Réussies', s.workflowSuccess),
              _metric(c, 'Échouées', s.workflowFailure),
              _metric(c, 'En cours', s.workflowActive),
              _metric(c, 'En attente', s.workflowQueued),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ÉTAT ACTUEL DU BOT', style: T.micro(c)),
              const SizedBox(height: 8),
              _metric(c, 'Erreurs dans le rapport santé', s.recentErrors),
              _metric(c, 'Actions en attente', s.pendingActions),
              const SizedBox(height: 8),
              Text(
                'Les compteurs de santé correspondent au dernier état fourni par le bot, pas uniquement à la période sélectionnée.',
                style: T.caption(c),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EXPORT', style: T.micro(c)),
              const SizedBox(height: 5),
              Text(
                'Copie un résumé texte sans noms, identifiants, messages privés ni secrets.',
                style: T.caption(c),
              ),
              const SizedBox(height: 12),
              KBtn('Copier le rapport', onTap: _copyReport),
            ],
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: T.caption(c)),
          ),
      ],
    );
  }

  Widget _metric(Palette c, String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: T.caption(c))),
          Text(
            nf(value),
            style: T.body(c).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
