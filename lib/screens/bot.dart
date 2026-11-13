import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';

// Port fidèle de BotScreen.java.

/// Pilotage du bot : interrupteurs, verrous, GLM Live manuel, catalogue des
/// workflows et exécutions récentes. Port fidèle de BotScreen.java.
class BotScreen extends StatefulWidget {
  const BotScreen({super.key});
  @override
  State<BotScreen> createState() => _BotScreenState();
}

class _BotScreenState extends State<BotScreen> {
  Bot? _bot;
  List<dynamic> _runs = const [], _wl = const [];
  final List<String> _errs = [];
  bool _busy = true;

  /* catalogue : [groupe], puis [fichier, libellé, description] */
  static const _catalog = [
    {
      'groupe': 'Lecture',
      'items': [
        {'f': 'surveiller.yml', 'n': 'Surveiller la Page', 'd': 'Récupère commentaires et publications'},
        {'f': 'statistiques.yml', 'n': 'Statistiques', 'd': 'Abonnés, vues, interactions'},
        {'f': 'archiver.yml', 'n': 'Archiver la Page', 'd': 'Résumé des posts'},
        {'f': 'audit.yml', 'n': 'Audit complet', 'd': 'Enchaîne les 4 lectures'},
      ],
    },
    {
      'groupe': 'Publication',
      'items': [
        {'f': 'dispatcher.yml', 'n': 'Traiter les files', 'd': 'Lance ce qui est en attente'},
        {'f': 'publier.yml', 'n': 'Publier (texte)', 'd': ''},
        {'f': 'publier-avance.yml', 'n': 'Publier (média / programmé)', 'd': ''},
        {'f': 'repondre.yml', 'n': 'Envoyer les réponses', 'd': ''},
        {'f': 'actions-posts.yml', 'n': 'Modifier / supprimer des posts', 'd': ''},
      ],
    },
    {
      'groupe': 'Maintenance',
      'items': [
        {'f': 'apprendre.yml', 'n': 'Apprendre', 'd': 'Met à jour projets et performances'},
        {'f': 'archive-mensuelle.yml', 'n': 'Archive mensuelle', 'd': ''},
        {'f': 'keepalive.yml', 'n': 'Réactiver les tâches planifiées', 'd': ''},
        {'f': 'test-facebook.yml', 'n': 'Test Facebook', 'd': 'Vérifie le jeton de Page'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final errs = <String>[];
    Bot? bot;
    List<dynamic> runs = const [], wl = const [];
    await Future.wait<dynamic>([
      Api.botState().then((v) { bot = v; return null; }).catchError((Object e) {
        errs.add(Api.hint(e));
        return null;
      }),
      Api.runs(20).then((v) { runs = v; return null; }).catchError((Object e) {
        errs.add(Api.hint(e));
        return null;
      }),
      Api.workflows(true).then((v) { wl = v; return null; }).catchError((Object e) {
        errs.add(Api.hint(e));
        return null;
      }),
    ]);
    if (!mounted) return;
    setState(() {
      _bot = bot;
      _runs = runs;
      _wl = wl;
      _errs
        ..clear()
        ..addAll(errs);
      _busy = false;
    });
  }

  bool _nested(String key) {
    final o = _bot?.cfg[key];
    return o is! Map<String, dynamic> || o.ob('actif', true);
  }

  Future<void> _setNested(String key, bool v) async {
    await Api.updateJson('glm/config.json', false, (cur) {
      final c = asObj(cur);
      final o = asObj(c[key]);
      o['actif'] = v;
      c[key] = o;
      return c;
    }, 'GLM $key ${v ? 'activé' : 'désactivé'}');
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _bot == null && _runs.isEmpty) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        const KSkeleton(120),
        const SizedBox(height: 12),
        const KSkeleton(90),
        const SizedBox(height: 12),
        const KSkeleton(90),
      ]);
    }
    final c = context.p;
    final bs = _bot;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (final e in _errs.take(2)) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ErrBox(e),
        ),
        if (bs != null) ...[
          _hero(c, bs),
          const SizedBox(height: 16),
          KSection('Interrupteurs'),
          KCard(
            child: Column(children: [
              KSwitchRow('GLM (tout)',
                  desc: 'Interrupteur général dans glm/config.json',
                  value: !bs.cfg.containsKey('actif') || bs.cfg.ob('actif', true),
                  job: (v) => Api.updateJson('glm/config.json', false, (cur) {
                        final o = asObj(cur);
                        o['actif'] = v;
                        return o;
                      }, 'GLM ${v ? 'activé' : 'désactivé'}')),
              const KDivider(),
              KSwitchRow('Publications automatiques',
                  desc: 'Posts planifiés par GLM',
                  value: _nested('posts'),
                  job: (v) => _setNested('posts', v)),
              const KDivider(),
              KSwitchRow('Réponses automatiques',
                  desc: 'Réponses aux commentaires',
                  value: _nested('reponses'),
                  job: (v) => _setNested('reponses', v)),
            ]),
          ),
          const SizedBox(height: 16),
          _hardLocks(c, bs),
          const SizedBox(height: 16),
          _manual(c),
        ],
        const SizedBox(height: 16),
        for (final g in _catalog) ...[
          KSection(g['groupe'] as String),
          KCard(
            child: Column(children: [
              for (var i = 0; i < (g['items'] as List).length; i++) ...[
                if (i > 0) const KDivider(),
                _wfRow(c, (g['items'] as List)[i] as Map<String, dynamic>),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ],
        if (_runs.isNotEmpty) ...[
          KSection('Exécutions récentes'),
          KCard(
            child: Column(children: [
              for (var i = 0; i < _runs.length && i < 8; i++) ...[
                if (i > 0) const KDivider(),
                RunRow(asObj(_runs[i]), withCancel: true, after: _load),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  /* ---------- héros avec démarrage / arrêt d'urgence ---------- */

  Widget _hero(Palette c, Bot bs) {
    final String t = switch (bs.state) {
      'on' => 'En marche',
      'wait' => 'Actif, en attente de session',
      _ => 'Arrêté',
    };
    return KHero(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PulseDot(bs.state == 'off' ? c.heroMut : c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: T.hero(c).copyWith(fontSize: 19)),
              Text(
                bs.running > 0
                    ? '${bs.running} session(s) GLM Live en cours'
                    : 'Aucune session en cours',
                style: T.body(c).copyWith(color: c.heroMut),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: ActionBtn(
              'Démarrer',
              icon: Icons.play_arrow_rounded,
              job: () async {
                await Api.setVar('GLM_LIVE', 'on');
                await Api.setVar('AUTO_REPONSES', 'on');
                if (bs.cfg.containsKey('actif') && !bs.cfg.ob('actif', true)) {
                  await Api.updateJson('glm/config.json', false, (cur) {
                    final o = asObj(cur);
                    o['actif'] = true;
                    return o;
                  }, 'Réactivation GLM');
                }
                final vw = Api.wfByFile(_wl, 'glm-veille.yml');
                if (vw != null && vw.os('state') == 'active') {
                  await Api.dispatch('glm-veille.yml', null);
                } else {
                  await Api.dispatch('glm-live.yml',
                      {'dry_run': 'false', 'minutes': '330'});
                }
                await Future.delayed(const Duration(milliseconds: 1500));
              },
              ok: 'Bot démarré (session dans quelques secondes).',
              after: _load,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ActionBtn(
              "Arrêt d'urgence",
              icon: Icons.close,
              variant: KBtnVariant.danger,
              job: () async {
                if (!await kConfirm(
                    context, 'Arrêter le bot et annuler les sessions en cours ?')) {
                  throw Cancelled();
                }
                await Api.setVar('GLM_LIVE', 'off');
                await Api.setVar('AUTO_REPONSES', 'off');
                for (final s in const ['in_progress', 'queued']) {
                  final raw = await Api.req('GET',
                      '/repos/${Api.mgr}/actions/workflows/glm-live.yml/runs?status=$s');
                  final j = asObj(Api.jsonDecodeSafe(raw));
                  for (final run in asArr(j['workflow_runs'])) {
                    try {
                      await Api.cancelRun(asObj(run).oi('id'));
                    } catch (_) {/* déjà terminé */}
                  }
                }
                await Future.delayed(const Duration(milliseconds: 800));
              },
              ok: 'Bot arrêté.',
              after: _load,
            ),
          ),
        ]),
      ]),
    );
  }

  /* ---------- verrous GitHub ---------- */

  Widget _hardLocks(Palette c, Bot bs) {
    final vw = Api.wfByFile(_wl, 'glm-veille.yml');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('Verrous GitHub'),
      KCard(
        child: Column(children: [
          KSwitchRow('Variable GLM_LIVE',
              desc: 'Désactive GLM Live et la veille quand elle vaut off',
              value: bs.live != 'off',
              job: (v) => Api.setVar('GLM_LIVE', v ? 'on' : 'off')),
          const KDivider(),
          KSwitchRow('Variable AUTO_REPONSES',
              desc: 'Désactive le workflow de réponses automatiques',
              value: bs.auto != 'off',
              job: (v) => Api.setVar('AUTO_REPONSES', v ? 'on' : 'off')),
          if (vw != null) ...[
            const KDivider(),
            KSwitchRow('Veille GLM',
                desc: "Relance une session toutes les 10 minutes si aucune n'est active",
                value: vw.os('state') == 'active',
                job: (v) => Api.req(
                    'PUT',
                    '/repos/${Api.mgr}/actions/workflows/${vw.oi('id')}/'
                    '${v ? 'enable' : 'disable'}')),
          ],
        ]),
      ),
    ]);
  }

  /* ---------- GLM Live manuel ---------- */

  Widget _manual(Palette c) {
    bool dry = true;
    final min = TextEditingController(text: '2');
    return StatefulBuilder(builder: (ctx, setM) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KSection('GLM Live manuel'),
        KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('Mode test (rien n\'est publié)',
                      style: T.strong(c).copyWith(fontSize: 15))),
              Transform.scale(
                scale: .9,
                child: Switch.adaptive(
                    value: dry,
                    activeColor: c.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setM(() => dry = v)),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text('Durée (minutes)', style: T.micro(c)),
            ),
            KEdit(controller: min, number: true, hint: '2'),
            const SizedBox(height: 12),
            ActionBtn(
              'Lancer GLM Live',
              icon: Icons.play_arrow_rounded,
              job: () async {
                final m = int.tryParse(min.text.trim()) ?? 2;
                final minutes = m.clamp(1, 330);
                await Api.dispatch('glm-live.yml',
                    {'dry_run': dry ? 'true' : 'false', 'minutes': '$minutes'});
                await Future.delayed(const Duration(milliseconds: 1500));
              },
              ok: 'GLM Live lancé.',
              after: _load,
            ),
            const SizedBox(height: 8),
            Text('Pour un test, GLM_LIVE doit être sur on.', style: T.caption(c)),
          ]),
        ),
      ]);
    });
  }

  /* ---------- ligne de workflow du catalogue ---------- */

  Widget _wfRow(Palette c, Map<String, dynamic> w) {
    final info = Api.wfByFile(_wl, w['f'] as String);
    Map<String, dynamic>? last;
    for (final r in _runs) {
      final ro = asObj(r);
      if (info != null && ro.oi('workflow_id') == info.oi('id')) {
        last = ro;
        break;
      }
    }
    final sub = (info != null && info.os('state') != 'active' ? 'désactivé · ' : '') +
        (last != null ? rel(last.os('created_at')) : (w['d'] as String));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w['n'] as String,
                style: T.strong(c).copyWith(fontSize: 14.5)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: T.caption(c)),
          ]),
        ),
        if (last != null) ...[
          const SizedBox(width: 8),
          runChip(context, last),
        ],
        const SizedBox(width: 8),
        _LaunchBtn(file: w['f'] as String, name: w['n'] as String, after: _load),
      ]),
    );
  }
}

class _LaunchBtn extends StatefulWidget {
  final String file, name;
  final VoidCallback after;
  const _LaunchBtn({required this.file, required this.name, required this.after});
  @override
  State<_LaunchBtn> createState() => _LaunchBtnState();
}

class _LaunchBtnState extends State<_LaunchBtn> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Press(
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              Fx.tick();
              try {
                if (widget.file == 'audit.yml') {
                  await Api.startAudit();
                } else {
                  await Api.dispatch(widget.file, null);
                }
                await Future.delayed(const Duration(milliseconds: 1500));
                if (mounted) {
                  kToast(context, '${widget.name} lancé.');
                  widget.after();
                }
              } catch (e) {
                if (mounted) kToast(context, Api.hint(e), bad: true);
              }
              if (mounted) setState(() => _busy = false);
            },
      child: Opacity(
        opacity: _busy ? .6 : 1,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: c.accent, borderRadius: BorderRadius.circular(12)),
          child: _busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(c.onAccent)))
              : Text('Lancer',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: c.onAccent)),
        ),
      ),
    );
  }
}
