import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/palette.dart';
import '../core/store.dart';
import '../ui/common.dart';
import '../ui/shell.dart' show SubPage;
import 'settings.dart';

/// Onboarding et connexion initiale, sans modifier le parcours de configuration.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _intro = true;
  bool _checked = false;
  int _step = 0;

  static const _slides = [
    [
      'Votre Page, en un seul endroit',
      "Retrouvez les conversations, les publications et l'activité de votre Page dans un espace de pilotage clair."
    ],
    [
      'Un bot que vous gardez en main',
      "Configurez les règles, contrôlez les automatisations et consultez les exécutions sans perdre la visibilité."
    ],
    [
      'Des décisions guidées par les données',
      "Suivez les statistiques, les rapports et les alertes pour comprendre ce qui se passe sur votre Page."
    ],
  ];

  static const _icons = [
    Icons.dashboard_customize_rounded,
    Icons.smart_toy_rounded,
    Icons.insights_rounded,
  ];

  @override
  void initState() {
    super.initState();
    Store.get('onb').then((v) {
      if (!mounted) return;
      setState(() {
        _intro = v != '1';
        _checked = true;
      });
    });
  }

  Future<void> _finish() async {
    Fx.tick();
    await Store.set('onb', '1');
    if (mounted) setState(() => _intro = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (!_checked) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
      children: _intro ? _slides2(c) : _tokenCard(c),
    );
  }

  List<Widget> _slides2(Palette c) {
    return [
      Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: c.ink,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text('K',
                  style: TextStyle(
                    color: c.bg,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  )),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KIDAS CONTRÔLE',
                    style: T.strong(c).copyWith(letterSpacing: 1.1)),
                Text('VOTRE ESPACE DE PILOTAGE',
                    style: T.micro(c).copyWith(fontSize: 9)),
              ],
            ),
          ),
          TextButton(onPressed: _finish, child: const Text('Passer')),
        ],
      ),
      const SizedBox(height: 28),
      KHero(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(_icons[_step], color: c.accent, size: 29),
            ),
            const SizedBox(height: 30),
            Text('0${_step + 1} / 03',
                style: T.micro(c).copyWith(color: c.heroMut)),
            const SizedBox(height: 10),
            Text(
              _slides[_step][0],
              style: T.hero(c).copyWith(fontSize: 27),
            ),
            const SizedBox(height: 12),
            Text(
              _slides[_step][1],
              style: T.body(c).copyWith(color: c.heroMut, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: List.generate(
                3,
                (i) => Expanded(
                  child: AnimatedContainer(
                    duration: KAnim.med,
                    height: 4,
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: i <= _step ? c.accent : c.heroMut.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          if (_step > 0)
            Expanded(
              child: KBtnGhost('Retour', onTap: () {
                Fx.tick();
                setState(() => _step--);
              }),
            ),
          if (_step > 0) const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: KBtn(_step < 2 ? 'Continuer' : 'Configurer mon accès',
                onTap: () {
              Fx.tick();
              if (_step < 2) {
                setState(() => _step++);
              } else {
                _finish();
              }
            }),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Center(
        child: Text(
          'Simple à piloter · Sécurisé · Toujours sous contrôle',
          textAlign: TextAlign.center,
          style: T.caption(c),
        ),
      ),
    ];
  }

  List<Widget> _tokenCard(Palette c) {
    return [
      KHero(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_rounded, color: c.accent, size: 30),
            const SizedBox(height: 16),
            Text('Dernière étape', style: T.micro(c).copyWith(color: c.heroMut)),
            const SizedBox(height: 7),
            Text('Connectez votre espace',
                style: T.hero(c).copyWith(fontSize: 25)),
            const SizedBox(height: 10),
            Text(
              "Ajoutez le jeton GitHub pour relier l'application à vos dépôts. Il sera conservé dans le coffre sécurisé du téléphone.",
              style: T.body(c).copyWith(color: c.heroMut),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      KCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AUTORISATIONS NÉCESSAIRES', style: T.micro(c)),
            const SizedBox(height: 12),
            for (final r in const [
              ('Contents', 'Read and write'),
              ('Actions', 'Read and write'),
              ('Variables', 'Read and write'),
              ('Metadata', 'Read-only (automatique)'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 17, color: c.accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.$1, style: T.strong(c))),
                    Text(r.$2, style: T.caption(c)),
                  ],
                ),
              ),
            const Divider(height: 22),
            Text(
              'Dépôts concernés : facebook-data et facebook-manager.',
              style: T.caption(c),
            ),
            const SizedBox(height: 16),
            KBtn(
              'Ouvrir les réglages',
              onTap: () {
                Fx.tick();
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      const SubPage('Réglages', child: SettingsScreen()),
                ));
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: TextButton.icon(
          onPressed: () => setState(() {
            _intro = true;
            _step = 0;
          }),
          icon: const Icon(Icons.replay_rounded, size: 17),
          label: const Text("Revoir l'introduction"),
        ),
      ),
    ];
  }
}
