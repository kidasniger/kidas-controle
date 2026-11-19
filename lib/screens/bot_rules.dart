import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';

// Bot & Règles selon la maquette 07 : interrupteur global dans l'en-tête,
// héros « Bot actif », rulecards « si ... alors ... » avec interrupteur par
// règle, testeur intégré et bouton « Nouvelle règle ». Le pilotage fin
// (interrupteurs GLM, verrous, catalogue, exécutions) suit dessous.

/// Pilotage du bot : héros de contrôle, règles visuelles, testeur,
/// verrous GitHub, catalogue des workflows et exécutions récentes.
class BotRulesScreen extends StatefulWidget {
  const BotRulesScreen({super.key});
  @override
  State<BotRulesScreen> createState() => _BotRulesScreenState();
}

class _BotRulesScreenState extends State<BotRulesScreen> {
  Bot? _bot;
  List<dynamic> _runs = const [], _wl = const [];
  List<Regle> _regles = [];
  bool _reglesBusy = true;
  final List<String> _errs = [];
  bool _busy = true;

  /* santé du bot : rapport écrit par glm_boucle dans son dépôt (bot/sante.json) */
  Map<String, dynamic>? _sante;
  bool _santeAbsente = false;

  final TextEditingController _testCtl = TextEditingController();
  final TextEditingController _mpCtl = TextEditingController();
  Regle? _testRes;
  bool _testDone = false;

  /* catalogue : [groupe], puis [fichier, libellé, description] */
  static const _catalog = [
    {
      'groupe': 'Lecture',
      'items': [
        {
          'f': 'surveiller.yml',
          'n': 'Surveiller la Page',
          'd': 'Récupère commentaires et publications',
        },
        {
          'f': 'statistiques.yml',
          'n': 'Statistiques',
          'd': 'Abonnés, vues, interactions',
        },
        {'f': 'archiver.yml', 'n': 'Archiver la Page', 'd': 'Résumé des posts'},
        {
          'f': 'audit.yml',
          'n': 'Audit complet',
          'd': 'Enchaîne les 4 lectures',
        },
      ],
    },
    {
      'groupe': 'Publication',
      'items': [
        {
          'f': 'dispatcher.yml',
          'n': 'Traiter les files',
          'd': 'Lance ce qui est en attente',
        },
        {'f': 'publier.yml', 'n': 'Publier (texte)', 'd': ''},
        {
          'f': 'publier-avance.yml',
          'n': 'Publier (média / programmé)',
          'd': '',
        },
        {'f': 'repondre.yml', 'n': 'Envoyer les réponses', 'd': ''},
        {
          'f': 'actions-posts.yml',
          'n': 'Modifier / supprimer des posts',
          'd': '',
        },
      ],
    },
    {
      'groupe': 'Maintenance',
      'items': [
        {
          'f': 'apprendre.yml',
          'n': 'Apprendre',
          'd': 'Met à jour projets et performances',
        },
        {'f': 'archive-mensuelle.yml', 'n': 'Archive mensuelle', 'd': ''},
        {'f': 'keepalive.yml', 'n': 'Réactiver les tâches planifiées', 'd': ''},
        {
          'f': 'test-facebook.yml',
          'n': 'Test Facebook',
          'd': 'Vérifie le jeton de Page',
        },
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _loadRegles();
  }

  @override
  void dispose() {
    _testCtl.dispose();
    _mpCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final errs = <String>[];
    Bot? bot;
    List<dynamic> runs = const [], wl = const [];
    await Future.wait<dynamic>([
      Api.botState()
          .then((v) {
            bot = v;
            return null;
          })
          .catchError((Object e) {
            errs.add(Api.hint(e));
            return null;
          }),
      Api.runs(20)
          .then((v) {
            runs = v;
            return null;
          })
          .catchError((Object e) {
            errs.add(Api.hint(e));
            return null;
          }),
      Api.workflows(true)
          .then((v) {
            wl = v;
            return null;
          })
          .catchError((Object e) {
            errs.add(Api.hint(e));
            return null;
          }),
      /* santé : une erreur ici reste discrète (panneau, pas bandeau rouge) */
      Api.readBotJson('bot/sante.json')
          .then((v) {
            _sante = v is Map<String, dynamic> ? v : null;
            _santeAbsente = _sante == null;
            return null;
          })
          .catchError((Object e) {
            _sante = null;
            _santeAbsente = false;
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
    _mpCtl.text = asObj(bot?.cfg['aimes']).os('message');
  }

  Future<void> _loadRegles() async {
    setState(() => _reglesBusy = true);
    try {
      final rs = await Regles.charge();
      if (!mounted) return;
      setState(() {
        _regles = rs;
        _reglesBusy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _reglesBusy = false);
    }
  }

  bool _nested(String key) {
    final o = _bot?.cfg[key];
    return o is! Map<String, dynamic> || o.ob('actif', true);
  }

  Future<void> _setNested(String key, bool v, {String libelle = 'GLM'}) async {
    await Api.updateJson('glm/config.json', false, (cur) {
      final c = asObj(cur);
      final o = asObj(c[key]);
      o['actif'] = v;
      c[key] = o;
      return c;
    }, '$libelle ${v ? 'activé' : 'désactivé'}');
  }

  /* ---------- message privé facultatif envoyé après le like auto ---------- */

  Future<void> _enregistrerMp() async {
    final t = _mpCtl.text.trim();
    try {
      await Api.updateJson('glm/config.json', false, (cur) {
        final o = asObj(cur);
        final a = asObj(o['aimes']);
        if (t.isEmpty) {
          a.remove('message');
        } else {
          a['message'] = t;
        }
        o['aimes'] = a;
        return o;
      }, 'Message privé auto-like ${t.isEmpty ? 'retiré' : 'enregistré'}');
      await Journal.ajoute(
        'bot',
        t.isEmpty
            ? 'Message privé auto-like retiré'
            : 'Message privé auto-like enregistré',
      );
      if (mounted) {
        kToast(
          context,
          t.isEmpty ? 'Like sans message privé.' : 'Message privé enregistré.',
        );
      }
    } catch (e) {
      if (mounted) kToast(context, Api.hint(e), bad: true);
    }
  }

  /* ---------- interrupteur global (en-tête, maquette) ---------- */

  Future<void> _setBot(bool v) async {
    final bs = _bot;
    if (bs == null) return;
    if (!v) {
      if (!await kConfirm(
        context,
        'Arrêter le bot et annuler les sessions en cours ?',
      )) {
        throw Cancelled();
      }
      await Api.setVar('GLM_LIVE', 'off');
      await Api.setVar('AUTO_REPONSES', 'off');
      for (final s in const ['in_progress', 'queued']) {
        final raw = await Api.req(
          'GET',
          '/repos/${Api.mgr}/actions/workflows/glm-live.yml/runs?status=$s',
        );
        final j = asObj(Api.jsonDecodeSafe(raw));
        for (final run in asArr(j['workflow_runs'])) {
          try {
            await Api.cancelRun(asObj(run).oi('id'));
          } catch (_) {
            /* déjà terminé */
          }
        }
      }
      await Journal.ajoute('bot', "Arrêt d'urgence du bot");
      if (mounted) kToast(context, 'Bot arrêté.');
    } else {
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
        await Api.dispatch('glm-live.yml', {
          'dry_run': 'false',
          'minutes': '330',
        });
      }
      await Journal.ajoute('bot', 'Bot démarré');
      if (mounted) {
        kToast(context, 'Bot démarré (session dans quelques secondes).');
      }
    }
    await Future.delayed(const Duration(milliseconds: 1200));
    _load();
  }

  /* ---------- règles ---------- */

  Future<void> _ecrireRegles(List<Regle> rs) async {
    await Regles.ecrire(rs);
    await Journal.ajoute(
      'regle',
      'Règles du bot mises à jour',
      detail: '${rs.length} règle(s)',
    );
    _loadRegles();
  }

  Future<void> _ajouterRegle() async {
    final contient = TextEditingController();
    final texte = TextEditingController();
    var action = 'reponse';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) {
          final cc = ctx2.p;
          return AlertDialog(
            backgroundColor: cc.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: cc.line),
            ),
            title: Text('Nouvelle règle', style: T.title(cc)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SI le commentaire contient', style: T.micro(cc)),
                const SizedBox(height: 6),
                KEdit(
                  controller: contient,
                  hint: 'prix, livraison... (vide = tous)',
                ),
                const SizedBox(height: 12),
                Text('ALORS', style: T.micro(cc)),
                const SizedBox(height: 6),
                for (final (k, label) in const [
                  ('reponse', 'Répondre automatiquement'),
                  ('urgent', 'Marquer urgent'),
                  ('rien', 'Ne rien faire (ignorer)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Press(
                      onTap: () => setD(() => action = k),
                      child: Row(
                        children: [
                          Icon(
                            action == k
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 17,
                            color: action == k ? cc.accent : cc.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(label, style: T.body(cc))),
                        ],
                      ),
                    ),
                  ),
                if (action == 'reponse') ...[
                  const SizedBox(height: 4),
                  KEdit(
                    controller: texte,
                    hint: 'Texte de la réponse...',
                    minLines: 3,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: Text('Annuler', style: TextStyle(color: cc.muted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx2, true),
                child: Text(
                  'Ajouter',
                  style: TextStyle(
                    color: cc.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final rs = [..._regles];
    rs.add(
      Regle(
        id: 'r${DateTime.now().millisecondsSinceEpoch}',
        contient: contient.text.trim(),
        action: action,
        texte: texte.text.trim(),
      ),
    );
    await _ecrireRegles(rs);
    if (mounted) kToast(context, 'Règle ajoutée.');
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    if (_busy && _bot == null && _runs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const KSkeleton(120),
          const SizedBox(height: 12),
          const KSkeleton(90),
          const SizedBox(height: 12),
          const KSkeleton(90),
        ],
      );
    }
    final c = context.p;
    final bs = _bot;
    final pause = _regles.where((r) => !r.actif).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (final e in _errs.take(2))
          Padding(padding: const EdgeInsets.only(bottom: 8), child: ErrBox(e)),
        _pageHead(c, bs),
        if (bs != null) ...[_heros(c, bs, pause), const SizedBox(height: 14)],
        if (!_busy) ..._santePanel(c),
        KSection('Règles'),
        if (_reglesBusy)
          const KCard(child: KSkeleton(60))
        else if (_regles.isEmpty)
          KCard(
            child: Text(
              'Aucune règle : le bot répond à tout avec l\'IA. '
              'Ajoute des règles pour les cas évidents (prix, livraison...) '
              'et laisse l\'IA gérer le reste.',
              style: T.body(c).copyWith(color: c.muted),
            ),
          )
        else
          for (final r in _regles) ...[
            _ruleCard(c, r),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 14),
        _testeur(c),
        const SizedBox(height: 12),
        ActionBtn(
          'Nouvelle règle',
          icon: Icons.add,
          variant: KBtnVariant.ghost,
          job: _ajouterRegle,
        ),
        if (bs != null) ...[
          const SizedBox(height: 16),
          KSection('Interrupteurs'),
          KCard(
            child: Column(
              children: [
                KSwitchRow(
                  'GLM (tout)',
                  desc: 'Interrupteur général dans glm/config.json',
                  value:
                      !bs.cfg.containsKey('actif') || bs.cfg.ob('actif', true),
                  job: (v) => Api.updateJson('glm/config.json', false, (cur) {
                    final o = asObj(cur);
                    o['actif'] = v;
                    return o;
                  }, 'GLM ${v ? 'activé' : 'désactivé'}'),
                ),
                const KDivider(),
                KSwitchRow(
                  'Publications automatiques',
                  desc: 'Posts planifiés par GLM',
                  value: _nested('posts'),
                  job: (v) => _setNested('posts', v),
                ),
                const KDivider(),
                KSwitchRow(
                  'Réponses automatiques',
                  desc: 'Le bot like et répond aux commentaires',
                  value: _nested('reponses'),
                  job: (v) => _setNested('reponses', v),
                ),
                const KDivider(),
                KSwitchRow(
                  'Auto-like des publications',
                  desc: 'Le bot like les nouvelles publications',
                  value:
                      ((bs.cfg['aimes'] as Map<String, dynamic>?) ?? const {})
                          .ob('actif', false),
                  job: (v) => _setNested('aimes', v, libelle: 'Auto-like'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Message privé après le like', style: T.micro(c)),
                const SizedBox(height: 6),
                KEdit(
                  controller: _mpCtl,
                  hint: 'Laisser vide = like sans message',
                  minLines: 3,
                ),
                const SizedBox(height: 6),
                Text(
                  "Envoyé par Messenger à l'auteur d'une publication "
                  '(jamais à ta Page). Messenger ne passe que si la personne '
                  'a déjà écrit à la Page — sinon le like part seul.',
                  style: T.caption(c),
                ),
                const SizedBox(height: 10),
                ActionBtn(
                  'Enregistrer le message',
                  variant: KBtnVariant.ghost,
                  job: _enregistrerMp,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _hardLocks(c, bs),
          const SizedBox(height: 16),
          _manual(c),
        ],
        for (final g in _catalog) ...[
          KSection(g['groupe'] as String),
          KCard(
            child: Column(
              children: [
                for (var i = 0; i < (g['items'] as List).length; i++) ...[
                  if (i > 0) const KDivider(),
                  _wfRow(c, (g['items'] as List)[i] as Map<String, dynamic>),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_runs.isNotEmpty) ...[
          KSection('Exécutions récentes'),
          KCard(
            child: Column(
              children: [
                for (var i = 0; i < _runs.length && i < 8; i++) ...[
                  if (i > 0) const KDivider(),
                  RunRow(asObj(_runs[i]), withCancel: true, after: _load),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /* en-tête de page : titre + interrupteur global (maquette) */

  Widget _pageHead(Palette c, Bot? bs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        children: [
          Text(
            'Bot',
            style: TextStyle(
              fontFamily: kDisp,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
              color: c.ink,
            ),
          ),
          const Spacer(),
          if (bs != null) _MiniSwitch(value: bs.state != 'off', job: _setBot),
        ],
      ),
    );
  }

  /* héros : dot live + titre + ligne de libellés (maquette stat-hero) */

  Widget _heros(Palette c, Bot bs, int pause) {
    final String t = bs.state == 'off' ? 'Bot arrêté' : 'Bot actif';
    final String lab =
        (bs.running > 0
            ? '${bs.running} session${bs.running > 1 ? 's' : ''} en cours'
            : 'aucune session en cours') +
        (pause > 0 ? ' · $pause règle${pause > 1 ? 's' : ''} en pause' : '');
    return KCard(
      pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          PulseDot(bs.state == 'off' ? c.heroMut : c.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t,
                  style: TextStyle(
                    fontFamily: kDisp,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(lab.toUpperCase(), style: T.micro(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* ---------- panneau santé du bot ---------- */

  String _hh(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Ligne « libellé à gauche, valeur à droite » (éventuellement chip d'état).
  Widget _santeLigne(Palette c, String k, String v, {int chip = 0}) {
    return Row(
      children: [
        Expanded(
          child: Text(k, style: T.body(c).copyWith(color: c.muted)),
        ),
        Text(v, style: T.strong(c)),
        if (chip > 0) ...[
          const SizedBox(width: 8),
          StatusChip(chip == 3 ? 'Lourd' : 'Chargé', kind: chip),
        ],
      ],
    );
  }

  /// Panneau santé : dernier passage du bot, quota Facebook annoncé par son
  /// API, session en cours, file d'attente et erreurs récentes (rapport
  /// écrit par glm_boucle). Toute la lecture est non bloquante.
  List<Widget> _santePanel(Palette c) {
    final s = _sante;
    final out = <Widget>[KSection('Santé du bot')];
    if (s == null) {
      out.add(
        KCard(
          child: Text(
            _santeAbsente
                ? 'Pas encore de rapport — le bot écrira son premier '
                      'à son prochain cycle.'
                : 'Rapport indisponible (droits ou réseau).',
            style: T.body(c).copyWith(color: c.muted),
          ),
        ),
      );
      out.add(const SizedBox(height: 14));
      return out;
    }
    final maj = DateTime.tryParse(s.os('mis_a_jour'))?.toLocal();
    final frais =
        maj != null &&
        DateTime.now().difference(maj) < const Duration(minutes: 30);
    final quota = asObj(s['quota']);
    final qp = quota.oi('pct');
    final attente = quota.oi('attente_min');
    final sess = asObj(s['session']);
    final file = asObj(s['file']);
    final erreurs = s['erreurs'] is List
        ? (s['erreurs'] as List).whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    final rep = sess.oi('reponses');
    final cyc = sess.oi('cycles');
    out.add(
      KCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PulseDot(frais ? c.accent : c.heroMut),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    maj == null
                        ? 'Dernier passage · ?'
                        : 'Dernier passage · ${_hh(maj)}',
                    style: TextStyle(
                      fontFamily: kDisp,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                ),
                StatusChip(frais ? 'Actif' : 'Silencieux', kind: frais ? 4 : 5),
              ],
            ),
            if (!frais) ...[
              const SizedBox(height: 6),
              Text(
                'Le bot n\'a rien écrit depuis plus de 30 min — session '
                'terminée, quota saturé ou Actions à l\'arrêt.',
                style: T.caption(c).copyWith(color: c.muted),
              ),
            ],
            const KDivider(),
            _santeLigne(
              c,
              'Quota Facebook',
              '$qp %${attente > 0 ? ' · pause $attente min' : ''}',
              chip: qp >= 75 ? 3 : (qp >= 50 ? 5 : 0),
            ),
            const KDivider(),
            _santeLigne(
              c,
              'Cette session',
              '$rep réponse${rep > 1 ? 's' : ''} · $cyc cycle${cyc > 1 ? 's' : ''}',
            ),
            const KDivider(),
            _santeLigne(
              c,
              "File d'attente",
              '${file.oi('en_attente')} en attente',
            ),
            const KDivider(),
            if (erreurs.isEmpty)
              Text(
                'Aucune erreur récente.',
                style: T.caption(c).copyWith(color: c.muted),
              )
            else ...[
              Text('ERREURS RÉCENTES', style: T.micro(c)),
              const SizedBox(height: 6),
              for (final e in erreurs.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Builder(
                    builder: (_) {
                      final d = DateTime.tryParse(e.os('at'))?.toLocal();
                      final origine = e.os('origine');
                      final detail = e.os('detail');
                      return Text(
                        '${d == null ? '' : '${_hh(d)} · '}'
                        '${origine.isEmpty ? '' : '$origine · '}'
                        '$detail',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: T.caption(c),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    out.add(const SizedBox(height: 14));
    return out;
  }

  /* badge SI / ALORS (maquette kw) */

  Widget _kw(Palette c, String s, {bool acc = false}) {
    return Container(
      width: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      decoration: BoxDecoration(
        color: acc ? c.accent : c.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        s,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: acc ? c.onAccent : c.muted,
        ),
      ),
    );
  }

  String _si(Regle r) => r.contient.isEmpty
      ? 'tout commentaire'
      : 'le commentaire contient « ${r.contient} »';

  String _alors(Regle r) => switch (r.action) {
    'urgent' => 'marquer le commentaire urgent',
    'rien' => 'ignorer le commentaire',
    _ => 'envoyer la réponse',
  };

  /* rulecard « si ... alors ... » (maquette) */

  Widget _ruleCard(Palette c, Regle r) {
    return KCard(
      radius: 14,
      pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _kw(c, 'SI'),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _si(r),
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: c.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _kw(c, 'ALORS', acc: true),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _alors(r),
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: c.ink),
                ),
              ),
            ],
          ),
          if (r.action == 'reponse' && r.texte.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 53),
              child: Text(
                '« ${r.texte} »',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.caption(c),
              ),
            ),
          ],
          Container(
            margin: const EdgeInsets.only(top: 9),
            padding: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Text(
                  r.actif ? 'Active' : 'En pause',
                  style: TextStyle(fontSize: 10.5, color: c.muted),
                ),
                const Spacer(),
                Press(
                  onTap: () async {
                    if (!await kConfirm(context, 'Supprimer cette règle ?'))
                      return;
                    await _ecrireRegles(
                      _regles.where((x) => x.id != r.id).toList(),
                    );
                  },
                  child: Icon(Icons.delete_outline, size: 18, color: c.muted),
                ),
                const SizedBox(width: 8),
                Transform.scale(
                  scale: .85,
                  child: Switch.adaptive(
                    value: r.actif,
                    activeThumbColor: c.accent,
                    inactiveTrackColor: c.line,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) async {
                      final rs = [..._regles];
                      final i = rs.indexWhere((x) => x.id == r.id);
                      if (i >= 0) rs[i].actif = v;
                      await _ecrireRegles(rs);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* testeur intégré (maquette chart-card) */

  String _verbe(Regle r) => r.action == 'reponse' ? 'répondrait :' : 'ferait :';

  String _reponseTest(Regle r) {
    if (r.action == 'urgent') return 'Le commentaire serait marqué urgent.';
    if (r.action == 'rien') return 'Le commentaire serait ignoré.';
    return r.texte.isEmpty
        ? 'Le bot enverrait la réponse IA standard (aucun texte défini).'
        : '« ${r.texte} »';
  }

  Widget _tagReg(Palette c, String s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        border: Border.all(color: c.accent),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        s,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: c.accent,
        ),
      ),
    );
  }

  Widget _testeur(Palette c) {
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Testeur', style: T.micro(c)),
          const SizedBox(height: 8),
          KEdit(
            controller: _testCtl,
            hint: 'Simuler un commentaire…',
            minLines: 2,
          ),
          const SizedBox(height: 10),
          ActionBtn(
            'Tester',
            height: 38,
            job: () async {
              setState(() {
                _testRes = Regles.simule(_regles, _testCtl.text);
                _testDone = true;
              });
            },
          ),
          if (_testDone) ...[
            const SizedBox(height: 12),
            if (_testRes == null)
              Text(
                'Aucune règle ne colle : le bot répond avec l\'IA normale '
                '(si « Répondre aux commentaires » est activé).',
                style: T.body(c),
              )
            else ...[
              Row(
                children: [
                  _tagReg(c, 'Règle ${_regles.indexOf(_testRes!) + 1}'),
                  const SizedBox(width: 8),
                  Text(_verbe(_testRes!), style: T.body(c)),
                ],
              ),
              const SizedBox(height: 5),
              Text(_reponseTest(_testRes!), style: T.caption(c)),
            ],
          ],
        ],
      ),
    );
  }

  /* ---------- verrous GitHub ---------- */

  Widget _hardLocks(Palette c, Bot bs) {
    final vw = Api.wfByFile(_wl, 'glm-veille.yml');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KSection('Verrous GitHub'),
        KCard(
          child: Column(
            children: [
              KSwitchRow(
                'Variable GLM_LIVE',
                desc: 'Désactive GLM Live et la veille quand elle vaut off',
                value: bs.live != 'off',
                job: (v) => Api.setVar('GLM_LIVE', v ? 'on' : 'off'),
              ),
              const KDivider(),
              KSwitchRow(
                'Variable AUTO_REPONSES',
                desc: 'Désactive le workflow de réponses automatiques',
                value: bs.auto != 'off',
                job: (v) => Api.setVar('AUTO_REPONSES', v ? 'on' : 'off'),
              ),
              if (vw != null) ...[
                const KDivider(),
                KSwitchRow(
                  'Veille GLM',
                  desc: "Relance une session toutes les 10 minutes si aucune n'est active",
                  value: vw.os('state') == 'active',
                  job: (v) => Api.req(
                    'PUT',
                    '/repos/${Api.mgr}/actions/workflows/${vw.oi('id')}/'
                        '${v ? 'enable' : 'disable'}',
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /* ---------- GLM Live manuel ---------- */

  Widget _manual(Palette c) {
    bool dry = true;
    final min = TextEditingController(text: '2');
    return StatefulBuilder(
      builder: (ctx, setM) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KSection('GLM Live manuel'),
            KCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Mode test (rien n\'est publié)',
                          style: T.strong(c).copyWith(fontSize: 15),
                        ),
                      ),
                      Transform.scale(
                        scale: .9,
                        child: Switch.adaptive(
                          value: dry,
                          activeColor: c.accent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) => setM(() => dry = v),
                        ),
                      ),
                    ],
                  ),
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
                      await Api.dispatch('glm-live.yml', {
                        'dry_run': dry ? 'true' : 'false',
                        'minutes': '$minutes',
                      });
                      await Journal.ajoute(
                        'bot',
                        'GLM Live lancé',
                        detail: '${minutes} min${dry ? ' · mode test' : ''}',
                      );
                      await Future.delayed(const Duration(milliseconds: 1500));
                    },
                    ok: 'GLM Live lancé.',
                    after: _load,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pour un test, GLM_LIVE doit être sur on.',
                    style: T.caption(c),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
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
    final sub =
        (info != null && info.os('state') != 'active' ? 'désactivé · ' : '') +
        (last != null ? rel(last.os('created_at')) : (w['d'] as String));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w['n'] as String,
                  style: T.strong(c).copyWith(fontSize: 14.5),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption(c),
                ),
              ],
            ),
          ),
          if (last != null) ...[
            const SizedBox(width: 8),
            runChip(context, last),
          ],
          const SizedBox(width: 8),
          _LaunchBtn(
            file: w['f'] as String,
            name: w['n'] as String,
            after: _load,
          ),
        ],
      ),
    );
  }
}

/* ---------- interrupteur sans libellé (en-tête de page) ---------- */

class _MiniSwitch extends StatefulWidget {
  final bool value;
  final Future<void> Function(bool v) job;
  const _MiniSwitch({required this.value, required this.job});
  @override
  State<_MiniSwitch> createState() => _MiniSwitchState();
}

class _MiniSwitchState extends State<_MiniSwitch> {
  late bool _v = widget.value;
  bool _busy = false;

  @override
  void didUpdateWidget(_MiniSwitch old) {
    super.didUpdateWidget(old);
    if (!_busy && widget.value != _v) _v = widget.value;
  }

  Future<void> _flip(bool nv) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _v = nv;
    });
    Fx.tick();
    try {
      await widget.job(nv);
      if (mounted) setState(() => _busy = false);
    } on Cancelled {
      if (mounted) {
        setState(() {
          _busy = false;
          _v = !nv;
        });
      }
    } catch (e) {
      if (mounted) {
        kToast(context, Api.hint(e), bad: true);
        setState(() {
          _busy = false;
          _v = !nv;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Opacity(
      opacity: _busy ? .5 : 1,
      child: Transform.scale(
        scale: .9,
        child: Switch.adaptive(
          value: _v,
          activeThumbColor: c.accent,
          activeTrackColor: c.accent.withValues(alpha: .35),
          inactiveTrackColor: c.line,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: _busy ? null : _flip,
        ),
      ),
    );
  }
}

class _LaunchBtn extends StatefulWidget {
  final String file, name;
  final VoidCallback after;
  const _LaunchBtn({
    required this.file,
    required this.name,
    required this.after,
  });
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
            color: c.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(c.onAccent),
                  ),
                )
              : Text(
                  'Lancer',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c.onAccent,
                  ),
                ),
        ),
      ),
    );
  }
}
