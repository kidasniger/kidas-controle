import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  JournalScreenState createState() => JournalScreenState();
}

class JournalScreenState extends State<JournalScreen> {
  List<JournalEvent> _events = const [];
  bool _busy = true;
  bool _chips = true;
  String _category = 'tout';
  String _source = 'tout';
  String _period = 'tout';
  String _query = '';
  String? _runsError;
  String? _loadError;
  final TextEditingController _search = TextEditingController();

  static const _categories = [
    ('tout', 'Tout'),
    ('reponse', 'Réponses'),
    ('post', 'Publications'),
    ('moderation', 'Modération'),
    ('bot', 'Workflows'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void toggleFiltres() {
    Fx.tick();
    setState(() => _chips = !_chips);
  }

  Future<void> _load() async {
    if (_busy && _events.isNotEmpty) return;
    setState(() {
      _busy = true;
      _loadError = null;
      _runsError = null;
    });

    List<JournalEvent> events = [];
    try {
      events = await Journal.charge(max: 400).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('Le chargement du journal a dépassé 20 secondes.'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = Api.hint(e);
        _busy = false;
      });
      return;
    }

    // Les workflows sont une source complémentaire : leur indisponibilité
    // ne doit jamais effacer les événements déjà lus dans le journal.
    try {
      final runs = await Api.runs(30).timeout(
        const Duration(seconds: 18),
        onTimeout: () => throw Exception('GitHub met trop de temps à répondre.'),
      );
      for (final r in runs) {
        final ro = asObj(r);
        final at = iso(
          ro.os('run_started_at').isEmpty
              ? ro.os('created_at')
              : ro.os('run_started_at'),
        );
        if (at <= 0) continue;
        final status = ro.os('status');
        final conclusion = ro.os('conclusion');
        final detail = status != 'completed'
            ? (status == 'queued' ? 'En file d’attente' : 'En cours')
            : switch (conclusion) {
                'success' => 'Terminé avec succès',
                'failure' => 'Échec',
                'timed_out' => 'Délai dépassé',
                'cancelled' => 'Annulé',
                'skipped' => 'Ignoré',
                _ => conclusion.isEmpty ? 'Terminé' : conclusion,
              };
        events.add(JournalEvent(
          at,
          'bot',
          ro.os('name').isEmpty ? 'Workflow GitHub' : ro.os('name'),
          detail: detail,
          source: 'bot',
        ));
      }
    } catch (e) {
      _runsError = Api.hint(e);
    }

    events.sort((a, b) => b.at.compareTo(a.at));
    if (!mounted) return;
    setState(() {
      _events = events.take(430).toList();
      _busy = false;
    });
  }

  bool _matches(JournalEvent event) {
    final categoryOk = switch (_category) {
      'reponse' => event.type == 'reponse',
      'post' => event.type == 'post' || event.type == 'media',
      'moderation' => event.type == 'moderation' || event.type == 'regle',
      'bot' => event.type == 'bot',
      _ => true,
    };
    final sourceOk = _source == 'tout' ||
        (_source == 'app' && event.source != 'bot') ||
        (_source == 'bot' && event.source == 'bot');
    final now = DateTime.now().millisecondsSinceEpoch;
    final periodOk = switch (_period) {
      '24h' => event.at >= now - const Duration(hours: 24).inMilliseconds,
      '7j' => event.at >= now - const Duration(days: 7).inMilliseconds,
      '30j' => event.at >= now - const Duration(days: 30).inMilliseconds,
      _ => true,
    };
    final q = _query.trim().toLowerCase();
    final searchOk = q.isEmpty ||
        event.label.toLowerCase().contains(q) ||
        event.detail.toLowerCase().contains(q) ||
        event.type.toLowerCase().contains(q);
    return categoryOk && sourceOk && periodOk && searchOk;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final filtered = _events.where(_matches).toList();
    final appCount = _events.where((e) => e.source != 'bot').length;
    final botCount = _events.where((e) => e.source == 'bot').length;
    final sections = <List<JournalEvent>>[];
    for (final event in filtered) {
      if (sections.isEmpty || !_sameDay(event.at, sections.last.first.at)) {
        sections.add([event]);
      } else {
        sections.last.add(event);
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: c.accent,
      backgroundColor: c.card,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
        children: [
          _overview(c, appCount, botCount, filtered.length),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('Historique des activités', style: T.title(c).copyWith(fontSize: 18))),
              Text('${filtered.length} résultat(s)', style: T.caption(c)),
            ],
          ),
          const SizedBox(height: 11),
          _searchField(c),
          const SizedBox(height: 13),
          if (_chips) ...[
            _sectionLabel(c, 'CATÉGORIE'),
            const SizedBox(height: 8),
            _chipsRow(c, _categories, _category, (v) => setState(() => _category = v)),
            const SizedBox(height: 14),
            _sectionLabel(c, 'ORIGINE'),
            const SizedBox(height: 8),
            _chipsRow(c, const [('tout', 'Toutes'), ('app', 'Application'), ('bot', 'Bot / GitHub')], _source, (v) => setState(() => _source = v)),
            const SizedBox(height: 14),
            _sectionLabel(c, 'PÉRIODE'),
            const SizedBox(height: 8),
            _chipsRow(c, const [('tout', 'Tout'), ('24h', '24 heures'), ('7j', '7 jours'), ('30j', '30 jours')], _period, (v) => setState(() => _period = v)),
            const SizedBox(height: 14),
          ],
          if (_runsError != null)
            _notice(c, Icons.cloud_off_outlined, 'GitHub indisponible', 'Les événements de l’application restent visibles. Les exécutions GitHub n’ont pas pu être actualisées.', warning: true),
          if (_loadError != null)
            _notice(c, Icons.error_outline_rounded, 'Chargement impossible', _loadError!, warning: true),
          if (_busy && _events.isEmpty) ...[
            const KSkeleton(76),
            const SizedBox(height: 10),
            const KSkeleton(76),
            const SizedBox(height: 10),
            const KSkeleton(76),
          ] else if (_loadError != null && _events.isEmpty) ...[
            const SizedBox(height: 14),
            Center(child: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Réessayer'))),
          ] else if (filtered.isEmpty) ...[
            const SizedBox(height: 26),
            KEmpty(Icons.manage_search_rounded, 'Aucune activité trouvée', sub: _events.isEmpty ? 'Les actions enregistrées apparaîtront ici.' : 'Modifie les filtres ou la recherche pour afficher d’autres événements.'),
            if (_query.isNotEmpty || _category != 'tout' || _source != 'tout' || _period != 'tout')
              Center(child: TextButton.icon(onPressed: _resetFilters, icon: const Icon(Icons.filter_alt_off_rounded), label: const Text('Réinitialiser les filtres'))),
          ] else ...[
            for (var i = 0; i < sections.length; i++) ...[
              _dayHeader(c, sections[i].first.at),
              _dayCard(c, sections[i]),
            ],
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.swipe_down_rounded, color: c.muted, size: 16),
              const SizedBox(width: 7),
              Expanded(child: Text('Tire vers le bas pour actualiser le journal.', style: T.caption(c))),
              TextButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 17), label: const Text('Actualiser')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overview(Palette c, int appCount, int botCount, int visibleCount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 47,
                height: 47,
                decoration: BoxDecoration(color: c.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)),
                child: Icon(Icons.history_rounded, color: c.accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Journal d’activité', style: T.title(c).copyWith(fontSize: 17)),
                  const SizedBox(height: 3),
                  Text('Suivi des actions et des automatisations', style: T.caption(c)),
                ],
              )),
              if (_busy) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
            ],
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _stat(c, 'TOTAL', _events.length, Icons.receipt_long_outlined, c.accent)),
            const SizedBox(width: 9),
            Expanded(child: _stat(c, 'APPLICATION', appCount, Icons.phone_android_rounded, Colors.teal)),
            const SizedBox(width: 9),
            Expanded(child: _stat(c, 'BOT / CI', botCount, Icons.smart_toy_outlined, Colors.deepPurple)),
          ]),
          if (visibleCount != _events.length) ...[
            const SizedBox(height: 12),
            Text('$visibleCount événement(s) correspondent aux filtres.', style: T.caption(c)),
          ],
        ],
      ),
    );
  }

  Widget _stat(Palette c, String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(height: 8),
        Text('$value', style: T.kpi(c).copyWith(fontSize: 22)),
        const SizedBox(height: 3),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.micro(c).copyWith(fontSize: 8, letterSpacing: .8)),
      ]),
    );
  }

  Widget _searchField(Palette c) {
    return TextField(
      controller: _search,
      onChanged: (value) => setState(() => _query = value),
      style: T.body(c),
      decoration: InputDecoration(
        hintText: 'Rechercher une action, un workflow…',
        hintStyle: T.caption(c),
        prefixIcon: Icon(Icons.search_rounded, color: c.muted, size: 21),
        suffixIcon: _query.isEmpty ? null : IconButton(
          tooltip: 'Effacer la recherche',
          onPressed: () {
            _search.clear();
            setState(() => _query = '');
          },
          icon: Icon(Icons.close_rounded, color: c.muted, size: 19),
        ),
        filled: true,
        fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: c.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: c.accent, width: 1.4)),
      ),
    );
  }

  Widget _sectionLabel(Palette c, String text) => Text(text, style: T.micro(c));

  Widget _chipsRow(Palette c, List<(String, String)> options, String selected, ValueChanged<String> onSelected) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final option in options) ...[
          ChoiceChip(
            label: Text(option.$2),
            selected: selected == option.$1,
            onSelected: (_) {
              Fx.tick();
              onSelected(option.$1);
            },
            showCheckmark: false,
            labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected == option.$1 ? c.onAccent : c.ink),
            selectedColor: c.accent,
            backgroundColor: c.card,
            side: BorderSide(color: selected == option.$1 ? c.accent : c.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          ),
          const SizedBox(width: 7),
        ],
      ]),
    );
  }

  Widget _notice(Palette c, IconData icon, String title, String detail, {bool warning = false}) {
    final color = warning ? Colors.orange : c.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .22))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: T.strong(c).copyWith(color: color)),
          const SizedBox(height: 3),
          Text(detail, style: T.caption(c)),
        ])),
      ]),
    );
  }

  Widget _dayHeader(Palette c, int at) {
    final date = DateTime.fromMillisecondsSinceEpoch(at);
    final now = DateTime.now();
    final today = _sameDay(at, now.millisecondsSinceEpoch);
    final yesterday = _sameDay(at, now.subtract(const Duration(days: 1)).millisecondsSinceEpoch);
    final label = today ? 'AUJOURD’HUI' : yesterday ? 'HIER' : '${date.day.toString().padLeft(2, '0')} ${const ['JANV.', 'FÉVR.', 'MARS', 'AVR.', 'MAI', 'JUIN', 'JUIL.', 'AOÛT', 'SEPT.', 'OCT.', 'NOV.', 'DÉC.'][date.month - 1]} ${date.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 13, 3, 8),
      child: Row(children: [
        Text(label, style: T.micro(c)),
        const SizedBox(width: 9),
        Expanded(child: Container(height: 1, color: c.line)),
      ]),
    );
  }

  bool _sameDay(int a, int b) {
    final x = DateTime.fromMillisecondsSinceEpoch(a);
    final y = DateTime.fromMillisecondsSinceEpoch(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  Widget _dayCard(Palette c, List<JournalEvent> events) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
      child: Column(children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) Padding(padding: const EdgeInsets.only(left: 60), child: Container(height: 1, color: c.line)),
          _eventRow(c, events[i], newest: i == 0 && events.first == _events.first),
        ],
      ]),
    );
  }

  Widget _eventRow(Palette c, JournalEvent event, {bool newest = false}) {
    final color = _eventColor(event);
    final icon = _eventIcon(event);
    final date = DateTime.fromMillisecondsSinceEpoch(event.at);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(event),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(color: color.withValues(alpha: newest ? .16 : .10), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.strong(c).copyWith(fontSize: 13)),
              const SizedBox(height: 3),
              Text(event.detail.isEmpty ? _typeLabel(event) : event.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(c).copyWith(fontSize: 11)),
              const SizedBox(height: 5),
              Text(event.source == 'bot' ? 'BOT · GITHUB ACTIONS' : 'APPLICATION', style: T.micro(c).copyWith(fontSize: 8, letterSpacing: .9)),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.ink, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 5),
              Icon(Icons.chevron_right_rounded, color: c.muted, size: 17),
            ]),
          ]),
        ),
      ),
    );
  }

  Color _eventColor(JournalEvent e) {
    if (e.type == 'bot') {
      final d = e.detail.toLowerCase();
      if (d.contains('échec') || d.contains('erreur') || d.contains('délai')) return Colors.red;
      if (d.contains('cours') || d.contains('file')) return Colors.orange;
      return Colors.deepPurple;
    }
    return switch (e.type) {
      'reponse' => Colors.blue,
      'post' || 'media' => Colors.teal,
      'moderation' => Colors.orange,
      'regle' => Colors.deepPurple,
      _ => Colors.blueGrey,
    };
  }

  IconData _eventIcon(JournalEvent e) => switch (e.type) {
    'reponse' => Icons.reply_rounded,
    'post' => Icons.campaign_outlined,
    'media' => Icons.perm_media_outlined,
    'moderation' => Icons.shield_outlined,
    'regle' => Icons.rule_rounded,
    'bot' => Icons.smart_toy_outlined,
    _ => Icons.bolt_rounded,
  };

  String _typeLabel(JournalEvent e) => switch (e.type) {
    'reponse' => 'Réponse envoyée',
    'post' => 'Publication',
    'media' => 'Média',
    'moderation' => 'Modération',
    'regle' => 'Règle du bot',
    'bot' => 'Exécution du workflow',
    _ => 'Action de l’application',
  };

  void _showDetails(JournalEvent event) {
    final c = context.p;
    final date = DateTime.fromMillisecondsSinceEpoch(event.at);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: _eventColor(event).withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(_eventIcon(event), color: _eventColor(event))),
            const SizedBox(width: 12),
            Expanded(child: Text('Détail de l’activité', style: T.title(c).copyWith(fontSize: 18))),
          ]),
          const SizedBox(height: 18),
          Text(event.label, style: T.strong(c).copyWith(fontSize: 16)),
          if (event.detail.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(event.detail, style: T.body(c)),
          ],
          const SizedBox(height: 17),
          _detailLine(c, Icons.category_outlined, 'Catégorie', _typeLabel(event)),
          _detailLine(c, Icons.source_outlined, 'Origine', event.source == 'bot' ? 'Bot / GitHub Actions' : 'Application'),
          _detailLine(c, Icons.calendar_today_outlined, 'Date', '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'),
          _detailLine(c, Icons.schedule_rounded, 'Heure', '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'),
        ]),
      )),
    );
  }

  Widget _detailLine(Palette c, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Icon(icon, size: 17, color: c.muted),
        const SizedBox(width: 10),
        SizedBox(width: 76, child: Text(label, style: T.caption(c))),
        Expanded(child: Text(value, style: T.strong(c))),
      ]),
    );
  }

  void _resetFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _category = 'tout';
      _source = 'tout';
      _period = 'tout';
    });
  }
}
