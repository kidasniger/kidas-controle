import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';

/// Modération : file de commentaires à traiter. Balayer vers la droite
/// approuve, vers la gauche cache (avec « Annuler » dans le bandeau).
/// Le bouton « Tout approuver » traite le lot d'un coup. Chaque décision
/// est tracée dans le journal et gardée dans moderation/moderation.json,
/// donc elle survit aux cycles du bot.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  List<UnifiedItem> _avis = const [];
  Moderation _mod = const Moderation();
  int _vue = 0; // 0 à traiter, 1 approuvés, 2 cachés
  bool _busy = true;

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      kToast(context, Api.hint(e), bad: true);
    }
  }

  /* ---------- actions ---------- */

  Future<void> _approuve(UnifiedItem it, {bool annulable = true}) async {
    await Moderation.approuve(it.id);
    await Journal.ajoute('moderation', 'Commentaire approuvé',
        detail: 'de ${it.name}');
    if (!mounted) return;
    setState(() => _mod = Moderation(
        traite: {..._mod.traite, it.id},
        cache: _mod.cache.where((x) => x != it.id).toSet(),
        urgents: _mod.urgents.where((x) => x != it.id).toSet()));
    if (annulable) _bandeau('Approuvé : ${it.name}', () async {
      await Moderation.reouvre(it.id);
      await Journal.ajoute('moderation', 'Approbation annulée',
          detail: 'de ${it.name}');
      await _load();
    });
  }

  Future<void> _cache(UnifiedItem it) async {
    await Moderation.masque(it.id);
    await Journal.ajoute('moderation', 'Commentaire caché',
        detail: 'de ${it.name}');
    if (!mounted) return;
    setState(() => _mod = Moderation(
        cache: {..._mod.cache, it.id},
        traite: _mod.traite.where((x) => x != it.id).toSet(),
        urgents: _mod.urgents.where((x) => x != it.id).toSet()));
    _bandeau('Caché : ${it.name}', () async {
      await Moderation.reouvre(it.id);
      await Journal.ajoute('moderation', 'Masquage annulé',
          detail: 'de ${it.name}');
      await _load();
    });
  }

  void _bandeau(String msg, Future<void> Function() annuler) {
    Fx.medium();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                color: context.p.bg)),
        backgroundColor: context.p.ink,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 78),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          textColor: context.p.accent,
          onPressed: () => Future.microtask(annuler),
        ),
      ));
  }

  Future<void> _toutApprouver() async {
    final liste = _avis.where((x) =>
        !_mod.traite.contains(x.id) && !_mod.cache.contains(x.id)).toList();
    if (liste.isEmpty) return;
    if (!await kConfirm(context,
        'Approuver les ${liste.length} commentaires en attente ?')) {
      return;
    }
    for (final it in liste) {
      await Moderation.approuve(it.id);
    }
    await Journal.ajoute('moderation',
        'Lot approuvé (${liste.length} commentaires)');
    await _load();
    if (mounted) kToast(context, '${liste.length} commentaires approuvés.');
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_busy && _avis.isEmpty) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(110),
        SizedBox(height: 12),
        KSkeleton(110),
        SizedBox(height: 12),
        KSkeleton(90),
      ]);
    }
    final aTraiter = _avis
        .where((x) => !_mod.traite.contains(x.id) && !_mod.cache.contains(x.id))
        .toList()
      ..sort((a, b) {
        final ua = _mod.urgents.contains(a.id) ? 0 : 1;
        final ub = _mod.urgents.contains(b.id) ? 0 : 1;
        if (ua != ub) return ua - ub;
        return b.ts.compareTo(a.ts);
      });
    final approuves = _avis.where((x) => _mod.traite.contains(x.id)).toList();
    final caches = _avis.where((x) => _mod.cache.contains(x.id)).toList();
    final urgents = aTraiter.where((x) => _mod.urgents.contains(x.id)).length;
    final list = switch (_vue) {
      1 => approuves,
      2 => caches,
      _ => aTraiter,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Row(children: [
          Expanded(child: _counter(c, '${aTraiter.length}', 'à traiter')),
          Expanded(child: _counter(c, '${urgents}', 'urgents')),
          Expanded(child: _counter(c, '${caches.length}', 'cachés')),
        ]),
        const SizedBox(height: 12),
        KSegmented(
          ['À traiter', 'Approuvés', 'Cachés'],
          sel: _vue,
          onSelect: (i) {
            Fx.tick();
            setState(() => _vue = i);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Balaye une carte vers la droite pour approuver, vers la gauche pour cacher.',
          style: T.caption(c),
        ),
        const SizedBox(height: 12),
        if (_vue == 0 && aTraiter.length > 1) ...[
          SizedBox(
            width: double.infinity,
            child: ActionBtn('Tout approuver (${aTraiter.length})',
                icon: Icons.done_all_outlined, job: _toutApprouver),
          ),
          const SizedBox(height: 12),
        ],
        if (list.isEmpty)
          KEmpty(Icons.verified_outlined,
              _vue == 0 ? 'Rien à modérer : tout est traité.' : 'Aucun commentaire ici.')
        else
          for (final it in list.take(60))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _vue == 0
                  ? _SwipeCarte(
                      item: it,
                      urgent: _mod.urgents.contains(it.id),
                      onApprouve: () => _approuve(it),
                      onCache: () => _cache(it),
                    )
                  : _CarteFixe(item: it, estCache: _vue == 2),
            ),
      ],
    );
  }

  Widget _counter(Palette c, String v, String label) {
    return KCard(
      pad: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: T.kpi(c).copyWith(fontSize: 19)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: T.micro(c)),
      ]),
    );
  }
}

/* ---------- carte balayable (à traiter) ---------- */

class _SwipeCarte extends StatelessWidget {
  final UnifiedItem item;
  final bool urgent;
  final Future<void> Function() onApprouve;
  final Future<void> Function() onCache;
  const _SwipeCarte({required this.item, required this.urgent,
      required this.onApprouve, required this.onCache});

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Dismissible(
      key: ValueKey('mod-${item.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(KDim.rCard),
            border: Border.all(color: c.line)),
        child: Row(children: [
          Icon(Icons.check_circle_outline, size: 22, color: c.ink),
          const SizedBox(width: 8),
          Text('APPROUVER',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  letterSpacing: .8, color: c.ink)),
        ]),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
            color: c.ink,
            borderRadius: BorderRadius.circular(KDim.rCard)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('CACHER',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  letterSpacing: .8, color: c.bg)),
          const SizedBox(width: 8),
          Icon(Icons.visibility_off_outlined, size: 20, color: c.bg),
        ]),
      ),
      onDismissed: (_) {},
      confirmDismiss: (d) async {
        if (d == DismissDirection.startToEnd) {
          await onApprouve();
        } else {
          await onCache();
        }
        return true;
      },
      child: _CarteFixe(item: item, urgent: urgent, actions: true),
    );
  }
}

/* ---------- carte fixe (contenu d'un commentaire) ---------- */

class _CarteFixe extends StatelessWidget {
  final UnifiedItem item;
  final bool urgent;
  final bool estCache;
  final bool actions;
  const _CarteFixe({required this.item, this.urgent = false,
      this.estCache = false, this.actions = false});

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final it = item;
    var postTxt = it.postTxt;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: c.soft, shape: BoxShape.circle,
                border: Border.all(color: c.line)),
            child: Text(it.name.isEmpty ? '?' : it.name[0].toUpperCase(),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                    color: c.ink)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: T.strong(c)),
              Text(relMs(it.ts), style: T.caption(c)),
            ]),
          ),
          if (urgent)
            const KBadge('URGENT')
          else if (estCache)
            const StatusChip('Caché', kind: 3)
          else if (!actions)
            const StatusChip('Approuvé', kind: 1),
        ]),
        if (it.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(it.text, style: T.body(c).copyWith(fontSize: 14.5)),
        ],
        if (postTxt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Sur : ${postTxt.length > 70 ? '${postTxt.substring(0, 70)}…' : postTxt}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.caption(c),
          ),
        ],
        if (actions) ...[
          const SizedBox(height: 8),
          Text(
            'Caché = retiré des écrans de l\'application. Le commentaire reste sur Facebook : '
            'utilise la Page pour un masquage côté Facebook.',
            style: T.caption(c).copyWith(fontSize: 11),
          ),
        ],
      ]),
    );
  }
}
