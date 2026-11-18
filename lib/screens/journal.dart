import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';

/// Journal d'activité selon la maquette 09 : chips de filtre
/// (Tout / Réponses / Publications / Modération), groupes par jour avec
/// étiquette « Aujourd'hui », « Hier » ou date, cartes de liste aux coins
/// arrondis et lignes rondes d'icône — la plus récente teintée accent —,
/// heure en chiffres tabulaires à droite. Contient tout ce que l'application
/// fait (journal du dépôt de données) et tout ce que le bot fait
/// (exécutions GitHub Actions reconstruites depuis l'API).
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  JournalScreenState createState() => JournalScreenState();
}

/// State public : le bouton filtre de l'en-tête (SubPage) appelle
/// [toggleFiltres] pour afficher ou masquer la rangée de chips.
class JournalScreenState extends State<JournalScreen> {
  List<JournalEvent> _events = const [];
  bool _busy = true;
  bool _chips = true;
  String _filtre = 'tout'; // tout | reponse | post | moderation

  /* chips de la maquette */
  static const _filtres = [
    ('tout', 'Tout'),
    ('reponse', 'Réponses'),
    ('post', 'Publications'),
    ('moderation', 'Modération'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Affiche ou masque les chips de filtre (bouton filtre de l'en-tête).
  void toggleFiltres() {
    Fx.tick();
    setState(() => _chips = !_chips);
  }

  Future<void> _load() async {
    setState(() => _busy = _events.isEmpty);
    try {
      final events = await Journal.charge(max: 120);
      final runs = await Api.runs(30);
      for (final r in runs) {
        final ro = asObj(r);
        final at = iso(
          ro.os('run_started_at').isEmpty
              ? ro.os('created_at')
              : ro.os('run_started_at'),
        );
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
        events.add(
          JournalEvent(
            at,
            'bot',
            ro.os('name').isEmpty ? 'Workflow' : ro.os('name'),
            detail: detail,
            source: 'bot',
          ),
        );
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
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          KSkeleton(70),
          SizedBox(height: 10),
          KSkeleton(70),
          SizedBox(height: 10),
          KSkeleton(70),
        ],
      );
    }
    final list = _events
        .where(
          (e) => switch (_filtre) {
            'reponse' => e.type == 'reponse',
            'post' => e.type == 'post' || e.type == 'media',
            'moderation' => e.type == 'moderation' || e.type == 'regle',
            _ => true,
          },
        )
        .toList();

    /* sections par jour : une carte de liste par jour, étiquette au-dessus */
    final sections = <List<JournalEvent>>[];
    for (final e in list) {
      if (sections.isEmpty || !_memeJour(e.at, sections.last.first.at)) {
        sections.add([e]);
      } else {
        sections.last.add(e);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 40),
      children: [
        if (_chips) ...[
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              children: [
                for (final (k, label) in _filtres)
                  Padding(
                    padding: EdgeInsets.only(
                      right: k == _filtres.last.$1 ? 0 : 8,
                    ),
                    child: Press(
                      onTap: () {
                        Fx.tick();
                        setState(() => _filtre = k);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _filtre == k ? c.accent : c.card,
                          borderRadius: BorderRadius.circular(99),
                          border: _filtre == k
                              ? null
                              : Border.all(color: c.line),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _filtre == k ? c.onAccent : c.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (sections.isEmpty)
          KEmpty(
            Icons.receipt_long_outlined,
            'Rien dans ce filtre pour le moment.',
            sub:
                'Les actions de l\'application et les cycles du bot '
                'apparaissent ici.',
          )
        else
          for (var s = 0; s < sections.length; s++) ...[
            _jourEntete(c, sections[s].first.at),
            _carteJour(c, sections[s], premiere: s == 0),
          ],
      ],
    );
  }

  /* ---------- carte d'un jour : lignes séparées par un filet ---------- */

  Widget _carteJour(
    Palette c,
    List<JournalEvent> evs, {
    bool premiere = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          for (var j = 0; j < evs.length; j++) ...[
            if (j > 0) Container(height: 1, color: c.line),
            _row(c, evs[j], acc: premiere && j == 0),
          ],
        ],
      ),
    );
  }

  /* ---------- étiquette de jour (sec-label maquette) ---------- */

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
      at,
      DateTime.now().millisecondsSinceEpoch - 86400000,
    );
    final label = auj
        ? "Aujourd'hui"
        : hier
        ? 'Hier'
        : '${d.day.toString().padLeft(2, '0')} ${const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'][d.month - 1]}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(label.toUpperCase(), style: T.micro(c)),
    );
  }

  /* ---------- ligne d'activité (rowitem maquette) ---------- */

  String _heure(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _row(Palette c, JournalEvent e, {bool acc = false}) {
    final ic = switch (e.type) {
      'reponse' => Icons.send_outlined,
      'post' => Icons.image_outlined,
      'media' => Icons.image_outlined,
      'moderation' => Icons.visibility_off_outlined,
      'regle' => Icons.edit_outlined,
      'bot' => Icons.smart_toy_outlined,
      _ => Icons.bolt_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          /* pastille ronde : teinte accent pour la plus récente (tl-ic acc) */
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: acc ? c.accent.withValues(alpha: .14) : c.chip,
              shape: BoxShape.circle,
            ),
            child: Icon(ic, size: 15, color: acc ? c.accent : c.ink),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: c.ink),
                ),
                if (e.detail.isNotEmpty)
                  Text(
                    e.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption(c).copyWith(fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _heure(e.at),
            style: TextStyle(
              fontSize: 10.5,
              color: c.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
