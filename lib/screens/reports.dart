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
        padding: const EdgeInsets.all(14),
        children: const [KSkeleton(120), SizedBox(height: 12), KSkeleton(180)],
      );
    }
    if (_error != null && _events.isEmpty && _runs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_rounded, color: c.accent, size: 28),
                const SizedBox(height: 10),
                Text('Rapports indisponibles', style: T.strong(c)),
                const SizedBox(height: 6),
                Text(_error!, style: T.caption(c)),
                const SizedBox(height: 14),
                KBtn('Réessayer', onTap: _load),
              ],
            ),
          ),
        ],
      );
    }

    final s = _summary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 36),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vue d’ensemble', style: T.hero(c)),
                    const SizedBox(height: 3),
                    Text('Rapports et activité de votre espace', style: T.caption(c)),
                  ],
                ),
              ),
              Press(
                onTap: _load,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: c.line),
                  ),
                  child: _busy
                      ? SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
                      : Picto('refresh', size: 19),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('PÉRIODE DU RAPPORT', style: T.micro(c)),
          const SizedBox(height: 9),
          Row(
            children: [
              for (final (days, label) in const [(1, '24 heures'), (7, '7 jours'), (30, '30 jours')])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Press(
                      onTap: () {
                        Fx.tick();
                        setState(() => _days = days);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _days == days ? c.accent.withValues(alpha: .14) : c.card,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: _days == days ? c.accent : c.line),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: _days == days ? c.accent : c.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.accent.withValues(alpha: .19), c.card, c.card],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.accent.withValues(alpha: .25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_rounded, color: c.accent, size: 19),
                    const SizedBox(width: 8),
                    Text('ACTIVITÉ JOURNALISÉE', style: T.micro(c).copyWith(color: c.accent)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(nf(s.eventCount), style: T.hero(c).copyWith(fontSize: 38, height: 1)),
                    const SizedBox(width: 9),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('événements', style: T.caption(c)),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: _miniStat(c, 'Application', s.appEvents, Icons.phone_android_rounded)),
                    const SizedBox(width: 9),
                    Expanded(child: _miniStat(c, 'Bot', s.botEvents, Icons.smart_toy_outlined)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            c,
            title: 'Actions enregistrées',
            subtitle: 'Détail des événements sur la période',
            icon: Icons.bolt_rounded,
            rows: [
              ('Publications', s.publications, Icons.post_add_rounded),
              ('Réponses journalisées', s.replies, Icons.reply_rounded),
              ('Modération', s.moderation, Icons.shield_outlined),
              ('Médias', s.media, Icons.perm_media_outlined),
              ('Règles', s.rules, Icons.rule_rounded),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            c,
            title: 'GitHub Actions',
            subtitle: 'Exécutions observées pendant la période',
            icon: Icons.account_tree_outlined,
            rows: [
              ('Total des exécutions', s.workflowCount, Icons.history_rounded),
              ('Réussies', s.workflowSuccess, Icons.check_circle_outline_rounded),
              ('Échouées', s.workflowFailure, Icons.error_outline_rounded),
              ('En cours', s.workflowActive, Icons.autorenew_rounded),
              ('En attente', s.workflowQueued, Icons.schedule_rounded),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.monitor_heart_outlined, color: c.accent, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('État actuel du bot', style: T.strong(c)),
                          Text('Dernier rapport de santé reçu', style: T.caption(c)),
                        ],
                      ),
                    ),
                    _statusDot(c, s.recentErrors > 0),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _healthMetric(c, 'Erreurs signalées', s.recentErrors, s.recentErrors > 0)),
                    const SizedBox(width: 10),
                    Expanded(child: _healthMetric(c, 'Actions en attente', s.pendingActions, false)),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  'Ces deux compteurs proviennent du dernier état transmis par le bot. Ils ne sont pas limités à la période sélectionnée.',
                  style: T.caption(c),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.ios_share_rounded, color: c.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Exporter le rapport', style: T.strong(c)),
                      const SizedBox(height: 3),
                      Text('Copier un résumé texte sans données sensibles.', style: T.caption(c)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copier le rapport',
                  onPressed: _copyReport,
                  icon: Icon(Icons.copy_rounded, color: c.accent),
                ),
              ],
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Actualisation incomplète : $_error', style: T.caption(c)),
            ),
        ],
      ),
    );
  }

  Widget _miniStat(Palette c, String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: c.accent, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nf(value), style: T.strong(c).copyWith(fontSize: 18)),
                Text(label, style: T.caption(c).copyWith(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    Palette c, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<(String, int, IconData)> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c.accent, size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: T.strong(c)),
                    Text(subtitle, style: T.caption(c)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 14, color: c.line),
            Row(
              children: [
                Icon(rows[i].$3, size: 16, color: c.muted),
                const SizedBox(width: 9),
                Expanded(child: Text(rows[i].$1, style: T.body(c))),
                Text(nf(rows[i].$2), style: T.strong(c).copyWith(fontSize: 14)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _healthMetric(Palette c, String label, int value, bool warning) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.caption(c)),
          const SizedBox(height: 5),
          Text(
            nf(value),
            style: T.strong(c).copyWith(
              fontSize: 22,
              color: warning ? c.accent : c.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(Palette c, bool warning) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: warning ? c.accent : Colors.green,
      ),
    );
  }
}
