import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import 'maintenance.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/native.dart';
import '../core/notifs.dart';
import '../core/palette.dart';
import '../core/store.dart';
import '../core/updater.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart' show KEdit, KSegmented, KSwitchRow, kConfirm;
import '../ui/pictos.dart';
import '../ui/shell.dart' show Bus, SubPage, kUpdateFlow;
import 'bot_rules.dart';
import 'journal.dart';
import 'moderation.dart';

/// Réglages selon la maquette 10 : carte profil en tête (avatar rond à
/// anneau accent, nom de la Page avec badge vérifié, bouton Modifier),
/// puis des groupes de lignes — Page, Bot, Apparence, Sécurité —, chaque
/// ligne pastille carrée d'icône + titre + sous-titre + chevron qui pousse
/// une sous-page. La connexion GitHub, la sauvegarde des règles et la mise
/// à jour vivent dans ces sous-pages.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _page;
  List<Regle> _regles = const [];
  String _savedAt = '';
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadPage();
    _loadRegles();
    _loadVersion();
  }

  Future<void> _loadPage() async {
    Map<String, dynamic>? pg;
    try {
      final st = await Api.readObj('inbox/statistiques.json');
      final cm = await Api.readObj('inbox/commentaires.json');
      for (final o in [st?['page'], cm?['page']]) {
        if (o is Map<String, dynamic> && o.isNotEmpty) {
          pg = o;
          break;
        }
      }
    } catch (_) {
      // pas de profil : la carte reste muette
    }
    if (!mounted) return;
    setState(() => _page = pg);
  }

  Future<void> _loadRegles() async {
    try {
      final rs = await Regles.charge();
      final s = await Store.get('regles_saved_at');
      if (!mounted) return;
      setState(() {
        _regles = rs;
        _savedAt = s;
      });
    } catch (_) {}
  }

  Future<void> _loadVersion() async {
    try {
      final n = await Native.versionName();
      final code = await Native.versionCode();
      if (!mounted) return;
      setState(() => _version = '$n ($code)');
    } catch (_) {}
  }

  Future<void> _push(Widget page) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _ouvrirConnexion() async {
    Fx.tick();
    await _push(const ConnexionPage());
    _loadPage();
  }

  void _ouvrirSauvegarde() async {
    Fx.tick();
    await _push(const _SauvegardePage());
    _loadRegles();
  }

  /* ---------- sous-titre « Compte connecté » : jours restants du jeton ---------- */

  String _sousCompte(String name) {
    final page = _page == null
        ? 'Connexion GitHub et Facebook'
        : 'Page « $name » via Facebook';
    final j = Api.joursAvantExp();
    if (j == null) return page;
    if (j < 0) return '$page · jeton expiré';
    if (j == 0) return '$page · jeton : dernier jour';
    return '$page · jeton : $j jour${j > 1 ? 's' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final mode = Bus.themeMode.value;
    final modeIdx = mode == ThemeMode.light
        ? 1
        : mode == ThemeMode.dark
        ? 2
        : 0;
    final name = (_page == null || _page!.os('name').trim().isEmpty)
        ? 'Ma Page'
        : _page!.os('name').trim();
    final actives = _regles.where((r) => r.actif).length;
    final pause = _regles.length - actives;
    final subRegles = _regles.isEmpty
        ? 'Aucune règle pour le moment'
        : '$actives actives · $pause en pause';
    final subSauv = _savedAt.isNotEmpty
        ? 'Dernière : ${_dateLisible(_savedAt)}'
        : _regles.isEmpty
        ? 'Aucune règle à mettre de côté'
        : '${_regles.length} règle${_regles.length > 1 ? 's' : ''} à mettre de côté';

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        _profil(c, name),
        /* groupe Page */
        _groupe(c, [
          _ligne(
            c,
            'user',
            'Compte connecté',
            _sousCompte(name),
            onTap: _ouvrirConnexion,
          ),
          _ligne(
            c,
            'doc',
            "Journal d'activité",
            "Tout ce que l'application et le bot ont fait",
            onTap: () async {
              Fx.tick();
              await _push(
                const SubPage("Journal d'activité", child: JournalScreen()),
              );
            },
          ),
        ]),
        /* groupe Bot */
        _groupe(c, [
          _ligne(
            c,
            'bot',
            'Règles du bot',
            subRegles,
            onTap: () async {
              Fx.tick();
              await _push(
                const SubPage('Bot & Règles', child: BotRulesScreen()),
              );
            },
          ),
          _ligne(
            c,
            'shield',
            'Modération automatique',
            'Filtres, masquages et réponses',
            onTap: () async {
              Fx.tick();
              await _push(
                const SubPage('Modération', child: ModerationScreen()),
              );
            },
          ),
        ]),
        /* groupe Apparence */
        _groupe(c, [_ligneTheme(c, modeIdx), _ligneSons(c), _ligneNotifs(c)]),
        /* groupe Diagnostic et maintenance */
        _groupe(c, [
          _ligne(
            c,
            'activity',
            'Diagnostic des services',
            'Connexion GitHub, accès au dépôt et dernier workflow',
            onTap: () async {
              Fx.tick();
              await _push(const SubPage(
                'Diagnostic des services',
                child: DiagnosticsScreen(),
              ));
            },
          ),
          _ligne(
            c,
            'save',
            'Sauvegarde des paramètres',
            'Exporter ou restaurer les préférences sans les secrets',
            onTap: () async {
              Fx.tick();
              await _push(const SubPage(
                'Sauvegarde des paramètres',
                child: SettingsBackupScreen(),
              ));
            },
          ),
        ]),
        /* groupe Sécurité */
        _groupe(c, [
          _ligne(
            c,
            'shield',
            'Verrouillage',
            "Protégé par le verrou d'écran du téléphone",
          ),
          _ligne(
            c,
            'save',
            'Sauvegarde des règles',
            subSauv,
            onTap: _ouvrirSauvegarde,
          ),
          _ligne(
            c,
            'info',
            'À propos',
            'Version ${_version.isEmpty ? '...' : _version}',
            onTap: () async {
              Fx.tick();
              await _push(const _AProposPage());
              _loadVersion();
            },
          ),
        ]),
      ],
    );
  }

  /* ---------- carte profil (profile-card maquette) ---------- */

  Widget _profil(Palette c, String name) {
    final fans = _page == null
        ? 0
        : (_page!['fan_count'] is num
              ? _page!['fan_count'] as num
              : (_page!['followers_count'] is num
                    ? _page!['followers_count']
                    : 0));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          /* avatar lg : pastille encrée entourée d'un anneau accent */
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.accent, width: 1.5),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: c.ink,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: c.bg,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.title(c).copyWith(fontSize: 15.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Picto(
                        'check',
                        size: 10,
                        color: c.onAccent,
                        stroke: 2.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _page == null
                      ? 'Page Facebook · apparaît après le premier cycle'
                      : '${fans > 0 ? "${nf(fans)} J'aime · " : ""}Page Facebook',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption(c),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          /* bouton Modifier (btn-xs maquette) */
          Press(
            onTap: _ouvrirConnexion,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: c.line),
              ),
              child: Text(
                'Modifier',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ---------- groupe de lignes (setgroup maquette) ---------- */

  Widget _groupe(Palette c, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: c.line),
            rows[i],
          ],
        ],
      ),
    );
  }

  /* ---------- pastille carrée d'icône (set-ic maquette) ---------- */

  Widget _pastille(Palette c, String picto) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Picto(picto, size: 15),
    );
  }

  /* ---------- ligne standard (setrow maquette) ---------- */

  Widget _ligne(
    Palette c,
    String picto,
    String titre,
    String sub, {
    VoidCallback? onTap,
  }) {
    return Press(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            _pastille(c, picto),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, style: T.strong(c).copyWith(fontSize: 14.5)),
                  Text(sub, style: T.caption(c)),
                ],
              ),
            ),
            if (onTap != null) Chev(size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }

  /* ---------- ligne Thème : segmented à droite (maquette) ---------- */

  Widget _ligneTheme(Palette c, int modeIdx) {
    final sub = switch (modeIdx) {
      1 => 'Clair',
      2 => 'Sombre',
      _ => 'Système',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          _pastille(c, 'moon'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thème', style: T.strong(c).copyWith(fontSize: 14.5)),
                Text(sub, style: T.caption(c)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 190,
            child: KSegmented(
              const ['Système', 'Clair', 'Sombre'],
              sel: modeIdx,
              fontSize: 12,
              onSelect: (i) async {
                Fx.tick();
                final v = switch (i) {
                  1 => ThemeMode.light,
                  2 => ThemeMode.dark,
                  _ => ThemeMode.system,
                };
                Bus.themeMode.value = v;
                await Store.set('theme_mode', switch (i) {
                  1 => 'light',
                  2 => 'dark',
                  _ => 'system',
                });
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  /* ---------- ligne Sons : interrupteur à droite ---------- */

  Widget _ligneSons(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      child: ValueListenableBuilder<bool>(
        valueListenable: Fx.sons,
        builder: (_, on, __) => Row(
          children: [
            _pastille(c, 'bell'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sons et vibrations',
                    style: T.strong(c).copyWith(fontSize: 14.5),
                  ),
                  Text('Tic de 40 ms à chaque touche', style: T.caption(c)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: .9,
              child: Switch.adaptive(
                value: on,
                activeThumbColor: c.accent,
                activeTrackColor: c.accent.withValues(alpha: .35),
                inactiveTrackColor: c.line,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  Fx.tick();
                  Fx.setSons(v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneNotifs(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      child: ValueListenableBuilder<bool>(
        valueListenable: Notifs.activ,
        builder: (_, on, __) => Row(
          children: [
            _pastille(c, 'bell'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notifications',
                    style: T.strong(c).copyWith(fontSize: 14.5),
                  ),
                  Text(
                    'Commentaires urgents et jeton Facebook',
                    style: T.caption(c),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: .9,
              child: Switch.adaptive(
                value: on,
                activeThumbColor: c.accent,
                activeTrackColor: c.accent.withValues(alpha: .35),
                inactiveTrackColor: c.line,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  Fx.tick();
                  Notifs.set(v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ---------- date lisible (port du « Dernière : hier à 22:10 ») ---------- */

  String _dateLisible(String isoS) {
    final d = DateTime.parse(isoS).toLocal();
    final now = DateTime.now();
    final hh =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final jours = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (jours == 0) return "aujourd'hui à $hh";
    if (jours == 1) return 'hier à $hh';
    return '${d.day}/${d.month} à $hh';
  }
}

/* ================================================================
   Sous-page Connexion : jeton, dépôts, expiration, tests de droits.
   ================================================================ */

class ConnexionPage extends StatefulWidget {
  const ConnexionPage();
  @override
  _ConnexionPageState createState() => _ConnexionPageState();
}

class _ConnexionPageState extends State<ConnexionPage> {
  late final TextEditingController _tok = TextEditingController(text: Api.tok);
  late final TextEditingController _nouveau = TextEditingController();
  late final TextEditingController _dr = TextEditingController(text: Api.data);
  late final TextEditingController _mr = TextEditingController(text: Api.mgr);
  String _expiry = Api.exp;
  final List<Map<String, String>> _checks = [];

  @override
  void dispose() {
    _tok.dispose();
    _nouveau.dispose();
    _dr.dispose();
    _mr.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    Fx.tick();
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2024),
      lastDate: DateTime(2036),
    );
    if (d == null || !mounted) return;
    setState(
      () => _expiry =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    );
  }

  /* ---------- puce d'état : jours restants du jeton ---------- */

  Widget _chipExp(Palette c) {
    final j = Api.joursAvantExp(_expiry);
    if (j == null) return const SizedBox.shrink();
    final String label;
    final int kind;
    if (j < 0) {
      label = 'Expiré';
      kind = 3;
    } else if (j == 0) {
      label = "Dernier jour";
      kind = 3;
    } else if (j <= 3) {
      label = 'J-$j';
      kind = 3;
    } else if (j <= 7) {
      label = 'J-$j';
      kind = 5;
    } else {
      label = 'J-$j';
      kind = 4;
    }
    return StatusChip(label, kind: kind);
  }

  Future<void> _save() async {
    final t = _tok.text.trim();
    final d = _dr.text.trim();
    final m = _mr.text.trim();
    if (t.isEmpty) throw Exception('Colle ton jeton.');
    Api.tok = t;
    if (d.isNotEmpty) Api.data = d;
    if (m.isNotEmpty) Api.mgr = m;
    Api.exp = _expiry;
    Api.resetCache();
    await Store.set('gh_token', Api.tok);
    await Store.set('cfg_data', Api.data);
    await Store.set('cfg_mgr', Api.mgr);
    if (_expiry.isEmpty) {
      await Store.del('cfg_exp');
    } else {
      await Store.set('cfg_exp', _expiry);
    }
    await _tests();
    if (!mounted) return;
    final echecs = _checks.where((o) => o['msg']!.isNotEmpty).length;
    kToast(
      context,
      echecs == 0
          ? 'Connexion enregistrée et testée.'
          : 'Enregistré, mais $echecs test(s) en échec — détail en haut de page.',
      bad: echecs > 0,
    );
  }

  /* les 3 tests de droits, partagés entre enregistrement et renouvellement */
  Future<void> _tests() async {
    final names = [
      'Données : lecture (${Api.data})',
      'Actions : lecture (${Api.mgr})',
      'Variables : lecture',
    ];
    final out = <Map<String, String>>[];
    for (var i = 0; i < 3; i++) {
      var msg = '';
      try {
        if (i == 0) {
          await Api.req('GET', '/repos/${Api.data}/contents/README.md');
        } else if (i == 1) {
          await Api.req('GET', '/repos/${Api.mgr}/actions/workflows');
        } else {
          await Api.req('GET', '/repos/${Api.mgr}/actions/variables');
        }
      } catch (e) {
        msg = Api.hint(e);
      }
      out.add({'name': names[i], 'msg': msg});
    }
    if (!mounted) return;
    setState(
      () => _checks
        ..clear()
        ..addAll(out),
    );
  }

  /* ---------- renouvellement du jeton en un tap ---------- */

  Future<void> _renouvelle() async {
    Fx.tick();
    final t = _nouveau.text.trim();
    if (t.isEmpty) throw Exception('Colle le nouveau jeton.');
    Api.tok = t;
    _tok.text = t;
    Api.exp = _expiry;
    Api.resetCache();
    await Store.set('gh_token', Api.tok);
    if (_expiry.isEmpty) {
      await Store.del('cfg_exp');
    } else {
      await Store.set('cfg_exp', _expiry);
    }
    await _tests();
    await Journal.ajoute('app', 'Jeton GitHub renouvelé');
    if (!mounted) return;
    setState(() => _nouveau.clear());
    final echecs = _checks.where((o) => o['msg']!.isNotEmpty).length;
    kToast(
      context,
      echecs == 0
          ? 'Nouveau jeton opérationnel — dépôts et réglages conservés.'
          : 'Jeton remplacé, mais $echecs test(s) en échec — détail en haut de page.',
      bad: echecs > 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return SubPage(
      'Jeton et dépôts',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 40),
        children: [
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Renouveler le jeton',
                  style: T.title(c).copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  "Colle un nouveau jeton : il remplace l'ancien, les dépôts et "
                  'les réglages sont conservés, le test se relance tout seul.',
                  style: T.body(c).copyWith(color: c.muted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Text('NOUVEAU JETON', style: T.micro(c)),
                const SizedBox(height: 6),
                KEdit(
                  controller: _nouveau,
                  hint: 'github_pat_...',
                  obscure: true,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expiry.isEmpty
                            ? 'Expiration : non renseignée'
                            : 'Expiration : $_expiry',
                        style: _expiry.isEmpty
                            ? T.body(c).copyWith(color: c.muted)
                            : T.body(c),
                      ),
                    ),
                    ActionBtn(
                      'Choisir',
                      height: 38,
                      variant: KBtnVariant.ghost,
                      icon: Icons.event_outlined,
                      job: _pickDate,
                    ),
                  ],
                ),
                if (_expiry.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _chipExp(c),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ActionBtn('Renouveler et tester', job: _renouvelle),
                ),
                if (_checks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final o in _checks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o['name']!, style: T.body(c)),
                                if (o['msg']!.isNotEmpty)
                                  Text(o['msg']!, style: T.caption(c)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(
                            o['msg']!.isEmpty ? 'OK' : 'Échec',
                            kind: o['msg']!.isEmpty ? 1 : 3,
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jeton (chiffré dans le coffre du téléphone)',
                  style: T.micro(c),
                ),
                const SizedBox(height: 6),
                KEdit(controller: _tok, hint: 'github_pat_...', obscure: true),
                const SizedBox(height: 12),
                Text('Dépôt des données (privé)', style: T.micro(c)),
                const SizedBox(height: 6),
                KEdit(controller: _dr, hint: 'proprietaire/depot'),
                const SizedBox(height: 12),
                Text('Dépôt du code (public)', style: T.micro(c)),
                const SizedBox(height: 6),
                KEdit(controller: _mr, hint: 'proprietaire/depot'),
                const SizedBox(height: 12),
                Text("Date d'expiration du jeton (rappel)", style: T.micro(c)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expiry.isEmpty ? 'Aucune date' : _expiry,
                        style: _expiry.isEmpty
                            ? T.body(c).copyWith(color: c.muted)
                            : T.body(c),
                      ),
                    ),
                    ActionBtn(
                      'Choisir',
                      height: 38,
                      variant: KBtnVariant.ghost,
                      icon: Icons.event_outlined,
                      job: _pickDate,
                    ),
                    if (_expiry.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _clearExpiry(c),
                    ],
                  ],
                ),
                if (_expiry.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _chipExp(c),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ActionBtn('Enregistrer et tester', job: _save),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          KSection('Droits du jeton'),
          KCard(
            child: Text(
              "Sur les deux dépôts : Contents (écriture), Actions (écriture), Variables (écriture). "
              'Sans Actions ni Variables, seuls Médias, Publier et Avis fonctionnent.',
              style: T.body(c),
            ),
          ),
          const SizedBox(height: 16),
          KSection('Sécurité'),
          KCard(
            child: SizedBox(
              width: double.infinity,
              child: ActionBtn(
                'Oublier le jeton sur ce téléphone',
                icon: Icons.delete_outline,
                variant: KBtnVariant.danger,
                job: () async {
                  if (!await kConfirm(
                    context,
                    'Effacer le jeton de ce téléphone ?',
                  )) {
                    throw Cancelled();
                  }
                  await Store.del('gh_token');
                  await HorsLigne.oublieTout();
                  Api.tok = '';
                  if (!mounted) return;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _clearExpiry(Palette c) {
    return Press(
      onTap: () {
        Fx.tick();
        setState(() => _expiry = '');
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: c.line),
        ),
        child: Icon(Icons.close, size: 16, color: c.ink),
      ),
    );
  }
}

/* ================================================================
   Sous-page Sauvegarde des règles : copier le JSON, restaurer.
   ================================================================ */

class _SauvegardePage extends StatefulWidget {
  const _SauvegardePage();
  @override
  _SauvegardePageState createState() => _SauvegardePageState();
}

class _SauvegardePageState extends State<_SauvegardePage> {
  List<Regle> _regles = const [];
  String _savedAt = '';

  @override
  void initState() {
    super.initState();
    _charge();
  }

  Future<void> _charge() async {
    try {
      final rs = await Regles.charge();
      final s = await Store.get('regles_saved_at');
      if (!mounted) return;
      setState(() {
        _regles = rs;
        _savedAt = s;
      });
    } catch (e) {
      if (!mounted) return;
      kToast(context, Api.hint(e), bad: true);
    }
  }

  Future<void> _exporter() async {
    if (_regles.isEmpty) {
      kToast(context, "Aucune règle à copier pour l'instant.");
      return;
    }
    const enc = JsonEncoder.withIndent('  ');
    final s = enc.convert([for (final r in _regles) r.toMap()]);
    await Clipboard.setData(ClipboardData(text: s));
    await Store.set(
      'regles_saved_at',
      DateTime.now().toUtc().toIso8601String(),
    );
    await Journal.ajoute(
      'regle',
      'Règles copiées en sauvegarde (${_regles.length})',
    );
    if (mounted) {
      final n = _regles.length;
      kToast(
        context,
        '$n règle${n > 1 ? 's' : ''} copiée${n > 1 ? 's' : ''} : colle-les dans un fichier de secours.',
      );
    }
    _charge();
  }

  Future<void> _importer() async {
    final ed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: ctx.p.line),
        ),
        title: Text('Restaurer les règles', style: T.title(ctx.p)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Colle ici la sauvegarde JSON copiée plus tôt.',
              style: T.caption(ctx.p),
            ),
            const SizedBox(height: 8),
            KEdit(controller: ed, hint: '[ { "id": ... } ]', minLines: 5),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: TextStyle(color: ctx.p.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Restaurer',
              style: TextStyle(
                color: ctx.p.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final v = Api.jsonDecodeSafe(ed.text);
    if (v is! List) {
      kToast(context, 'JSON illisible : rien restauré.', bad: true);
      return;
    }
    final rs = <Regle>[];
    for (final e in v) {
      final r = Regle.fromMap(asObj(e));
      if (r.id.isNotEmpty) rs.add(r);
    }
    if (rs.isEmpty) {
      kToast(context, 'Aucune règle trouvée dans le JSON.', bad: true);
      return;
    }
    await Regles.ecrire(rs);
    await Journal.ajoute('regle', 'Règles restaurées (${rs.length})');
    _charge();
    if (mounted) {
      kToast(
        context,
        '${rs.length} règle${rs.length > 1 ? 's' : ''} restaurée${rs.length > 1 ? 's' : ''}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return SubPage(
      'Sauvegarde des règles',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 40),
        children: [
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _regles.isEmpty
                      ? "Aucune règle dans glm/regles.json pour l'instant. Crée des règles dans Bot & Règles, puis reviens ici pour les copier en JSON ou les restaurer sur un autre téléphone."
                      : '${_regles.length} règle${_regles.length > 1 ? 's' : ''} dans glm/regles.json. Copie-les en JSON pour les garder de côté, puis restaure-les après une perte ou sur un autre téléphone.',
                  style: T.caption(c),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ActionBtn(
                        'Copier le JSON',
                        height: 38,
                        variant: KBtnVariant.ghost,
                        icon: Icons.copy_outlined,
                        job: _exporter,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ActionBtn(
                        'Restaurer',
                        height: 38,
                        variant: KBtnVariant.ghost,
                        icon: Icons.paste_outlined,
                        job: _importer,
                      ),
                    ),
                  ],
                ),
                if (_savedAt.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Dernière : ${_dateLisible(_savedAt)}',
                    style: T.caption(c).copyWith(color: c.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _dateLisible(String isoS) {
    final d = DateTime.parse(isoS).toLocal();
    final now = DateTime.now();
    final hh =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final jours = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (jours == 0) return "aujourd'hui à $hh";
    if (jours == 1) return 'hier à $hh';
    return '${d.day}/${d.month} à $hh';
  }
}

/* ================================================================
   Sous-page À propos : version, mise à jour de l'application.
   ================================================================ */

class _AProposPage extends StatefulWidget {
  const _AProposPage();
  @override
  _AProposPageState createState() => _AProposPageState();
}

class _AProposPageState extends State<_AProposPage> {
  String _version = '';
  bool _auto = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final n = await Native.versionName();
      final code = await Native.versionCode();
      if (!mounted) return;
      setState(() => _version = '$n ($code)');
    } catch (_) {}
    try {
      final v = await Store.get('upd_auto');
      if (!mounted) return;
      setState(() => _auto = v != '0');
    } catch (_) {}
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      final info = await Updater.check();
      if (!mounted) return;
      if (info.available) {
        await kUpdateFlow(context, info);
      } else {
        kToast(context, 'Tu as déjà la dernière version.');
      }
    } catch (e) {
      if (mounted) kToast(context, Api.hint(e), bad: true);
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return SubPage(
      'À propos',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 40),
        children: [
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KI DAS — Contrôle de Page Facebook',
                  style: T.title(c).copyWith(fontSize: 15.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Version installée : ${_version.isEmpty ? '...' : _version}',
                  style: T.body(c),
                ),
                const SizedBox(height: 12),
                KSwitchRow(
                  'Vérifier au démarrage',
                  desc: 'Cherche une nouvelle version à chaque ouverture',
                  value: _auto,
                  job: (v) async {
                    if (v) {
                      await Store.del('upd_auto');
                    } else {
                      await Store.set('upd_auto', '0');
                    }
                    if (mounted) setState(() => _auto = v);
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _checking
                      ? const KSkeleton(44, radius: 12)
                      : ActionBtn(
                          'Rechercher une mise à jour',
                          icon: Icons.refresh,
                          job: _checkUpdate,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
