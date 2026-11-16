import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';

/// Journal d'activité : tout ce que l'application fait (réponses mises en
/// file, posts, modération, règles, médias) et tout ce que le bot fait
/// (exécutions GitHub Actions reconstruites depuis l'API). Filtres par
/// type, du plus récent au plus ancien.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<JournalEvent> _events = const [];
  bool _busy = true;
  String _filtre = 'tout'; // tout | app | bot | post | reponse | moderation

  static const _filtres = [
    ('tout', 'Tout'),
    ('app', 'Application'),
    ('bot', 'Bot'),
    ('post', 'Posts'),
    ('reponse', 'Réponses'),
    ('moderation', 'Modération'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = _events.isEmpty);
    try {
      final events = await Journal.charge(max: 120);
      final runs = await Api.runs(30);
      for (final r in runs) {
        final ro = asObj(r);
        final at = iso(ro.os('run_started_at').isEmpty
            ? ro.os('created_at')
            : ro.os('run_started_at'));
        if (at <= 0) continue;
        final st = ro.os('status');
        final cl = ro.os('conclusion');
        final detail = st != 'completed'
            ? (st == 'queued' ? 'en file' : 'en cours')
            : switch (cl) {
                'success' => 'réussi',
                'failure' => 'échoué',
                'timed_out' => 'hors délai',
                'cancelled' => 'annulé',
                'skipped' => 'ignoré',
                _ => cl,
              };
        events.add(JournalEvent(
              at,
              'bot',
              ro.os('name').isEmpty ? 'Workflow' : ro.os('name'),
              detail: detail,
              source: 'bot',
            ));
      }
      events.sort((a, b) => b.at.compareTo(a.at));
      if (!mounted) return;
      setState(() {
        _events = events.take(160).toList();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      kToast(context, Api.hint(e), bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_busy && _events.isEmpty) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(70),
        SizedBox(height: 10),
        KSkeleton(70),
        SizedBox(height: 10),
        KSkeleton(70),
      ]);
    }
    final list = _events
        .where((e) => switch (_filtre) {
              'app' => e.source == 'app',
              'bot' => e.source == 'bot',
              'post' => e.type == 'post' || e.type == 'media',
              'reponse' => e.type == 'reponse',
              'moderation' => e.type == 'moderation' || e.type == 'regle',
              _ => true,
            })
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            children: [
              for (final (k, label) in _filtres)
                Padding(
                  padding: EdgeInsets.only(right: k == _filtres.last.$1 ? 0 : 8),
                  child: Press(
                    onTap: () {
                      Fx.tick();
                      setState(() => _filtre = k);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: _filtre == k ? c.accent : c.soft,
                          borderRadius: BorderRadius.circular(99)),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _filtre == k ? c.onAccent : c.muted)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          KEmpty(Icons.receipt_long_outlined,
              'Rien dans ce filtre pour le moment.',
              sub: 'Les actions de l\'application et les cycles du bot apparaissent ici.')
        else
          for (var i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _row(c, list[i], i == 0 ? null : list[i - 1]),
            ),
      ],
    );
  }

  /* ---------- ligne de journal + entête de jour ---------- */

  bool _memeJour(int a, int b) =>
      DateTime.fromMillisecondsSinceEpoch(a).day ==
          DateTime.fromMillisecondsSinceEpoch(b).day &&
      DateTime.fromMillisecondsSinceEpoch(a).month ==
          DateTime.fromMillisecondsSinceEpoch(b).month &&
      DateTime.fromMillisecondsSinceEpoch(a).year ==
          DateTime.fromMillisecondsSinceEpoch(b).year;

  Widget _jourEntete(Palette c, int at) {
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    final auj = _memeJour(at, DateTime.now().millisecondsSinceEpoch);
    final hier = _memeJour(
        at, DateTime.now().millisecondsSinceEpoch - 86400000);
    final label = auj
        ? "Aujourd'hui"
        : hier
            ? 'Hier'
            : '${d.day.toString().padLeft(2, '0')} ${const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'][d.month - 1]}';
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(children: [
        Text(label.toUpperCase(), style: T.micro(c)),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: c.line),
        ),
      ]),
    );
  }

  Widget _row(Palette c, JournalEvent e, JournalEvent? prev) {
    final debutSection = prev == null || !_memeJour(e.at, prev.at);
    final (ic, isBot) = switch (e.type) {
      'post' => (Icons.edit_outlined, e.source == 'bot'),
      'media' => (Icons.image_outlined, false),
      'reponse' => (Icons.chat_bubble_outline, e.source == 'bot'),
      'moderation' => (Icons.shield_outlined, false),
      'regle' => (Icons.rule_outlined, false),
      'bot' => (Icons.smart_toy_outlined, true),
      _ => (Icons.bolt_outlined, false),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (debutSection) _jourEntete(c, e.at),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: e.source == 'bot' ? c.soft : c.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: c.line)),
          child: Icon(ic, size: 16, color: c.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.strong(c).copyWith(fontSize: 13.5)),
            if (e.detail.isNotEmpty)
              Text(e.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption(c)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fdate(e.at), style: T.caption(c).copyWith(fontSize: 11)),
          const SizedBox(height: 3),
          KBadge(e.source == 'bot' ? 'BOT' : 'APP',
              bg: e.source == 'bot' ? c.soft : c.ink,
              fg: e.source == 'bot' ? c.ink : c.bg),
        ]),
      ]),
    ]);
  }
}
