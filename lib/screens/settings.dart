import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/native.dart';
import '../core/palette.dart';
import '../core/store.dart';
import '../core/updater.dart';
import '../ui/shell.dart' show Bus, kUpdateFlow;
import '../ui/common.dart';
import '../ui/forms.dart';

/// Réglages : apparence (système/clair/sombre), sons, connexion GitHub,
/// droits, mise à jour de l'application, sécurité. Port de SettingsScreen.java.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _tok = TextEditingController(text: Api.tok);
  late final TextEditingController _dr = TextEditingController(text: Api.data);
  late final TextEditingController _mr = TextEditingController(text: Api.mgr);
  String _expiry = Api.exp;
  final List<Map<String, String>> _checks = [];
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final n = await Native.versionName();
    final code = await Native.versionCode();
    if (!mounted) return;
    setState(() => _version = '$n ($code)');
  }

  @override
  void dispose() {
    _tok.dispose();
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
    setState(() => _expiry =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  /* ---------- enregistrement + tests de droits ---------- */

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
    setState(() => _checks
      ..clear()
      ..addAll(out));
  }

  /* ---------- mise à jour ---------- */

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
    final mode = Bus.themeMode.value;
    final modeIdx = mode == ThemeMode.light
        ? 1
        : mode == ThemeMode.dark
            ? 2
            : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        /* apparence */
        KSection('Apparence'),
        KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KSegmented(
              const ['Système', 'Clair', 'Sombre'],
              sel: modeIdx,
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
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Système : suit le réglage du téléphone. Clair : fond blanc, texte noir. '
              'Sombre : fond noir, texte blanc. Le bleu ne sert que pour les actions.',
              style: T.caption(c),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        /* sons */
        KSection('Retour tactile'),
        KCard(
          child: ValueListenableBuilder<bool>(
            valueListenable: Fx.sons,
            builder: (_, on, __) => KSwitchRow('Sons et vibrations',
                desc: 'Tic de 40 ms et vibration à chaque touche',
                value: on,
                job: (v) => Fx.setSons(v)),
          ),
        ),
        const SizedBox(height: 16),
        /* connexion */
        KSection('Connexion GitHub'),
        KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Jeton (chiffré dans le coffre du téléphone)', style: T.micro(c)),
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
            Row(children: [
              Expanded(
                child: Text(
                  _expiry.isEmpty ? 'Aucune date' : _expiry,
                  style: _expiry.isEmpty
                      ? T.body(c).copyWith(color: c.muted)
                      : T.body(c),
                ),
              ),
              ActionBtn('Choisir',
                  height: 38,
                  variant: KBtnVariant.ghost,
                  icon: Icons.event_outlined,
                  job: _pickDate),
              if (_expiry.isNotEmpty) ...[
                const SizedBox(width: 8),
                _clearExpiry(c),
              ],
            ]),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: ActionBtn('Enregistrer et tester', job: _save)),
            if (_checks.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final o in _checks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o['name']!, style: T.body(c)),
                            if (o['msg']!.isNotEmpty)
                              Text(o['msg']!, style: T.caption(c)),
                          ]),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(o['msg']!.isEmpty ? 'OK' : 'Échec',
                        kind: o['msg']!.isEmpty ? 1 : 3),
                  ]),
                ),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        /* droits */
        KSection('Droits du jeton'),
        KCard(
          child: Text(
            "Sur les deux dépôts : Contents (écriture), Actions (écriture), Variables (écriture). "
            'Sans Actions ni Variables, seuls Médias, Publier et Avis fonctionnent.',
            style: T.body(c),
          ),
        ),
        const SizedBox(height: 16),
        /* mise à jour */
        KSection("Mise à jour de l'application"),
        KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Version installée : ${_version.isEmpty ? '...' : _version}',
                style: T.body(c)),
            const SizedBox(height: 8),
            KSwitchRow(
              'Vérifier au démarrage',
              desc: 'Cherche une nouvelle version à chaque ouverture',
              value: true,
              job: (v) async {
                if (v) {
                  await Store.del('upd_auto');
                } else {
                  await Store.set('upd_auto', '0');
                }
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _checking
                  ? const KSkeleton(44, radius: 12)
                  : ActionBtn('Rechercher une mise à jour',
                      icon: Icons.refresh, job: _checkUpdate),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        /* sécurité */
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
                    context, 'Effacer le jeton de ce téléphone ?')) {
                  throw Cancelled();
                }
                await Store.del('gh_token');
                Api.tok = '';
                if (!mounted) return;
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
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
            border: Border.all(color: c.line)),
        child: Icon(Icons.close, size: 16, color: c.ink),
      ),
    );
  }
}
