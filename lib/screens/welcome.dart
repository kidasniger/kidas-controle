import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/palette.dart';
import '../core/store.dart';
import '../ui/common.dart';
import '../ui/shell.dart' show SubPage;
import 'settings.dart';

/// Premier lancement : 3 écrans d'introduction, puis la fiche jeton.
/// Port fidèle de WelcomeScreen.java.
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
      'Votre bot, sous contrôle',
      "Publications, commentaires, réponses : suis l'activité de Kidas sur ta Page Facebook, en temps réel."
    ],
    [
      'Règles et réponses auto',
      "Like, réponse IA, Messenger : les règles du bot se gèrent dans l'onglet Réponses."
    ],
    [
      'Statistiques en direct',
      "Abonnés, vues, interactions : tout ce que le bot accomplit est mesuré dans l'onglet Stats."
    ],
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
    if (!_checked) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: _intro ? _slides2(c) : _tokenCard(c),
    );
  }

  List<Widget> _slides2(Palette c) {
    return [
      const SizedBox(height: 18),
      Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
              color: c.ink, borderRadius: BorderRadius.circular(22)),
          child: Center(
              child: Text('K',
                  style: TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w900, color: c.bg))),
        ),
      ),
      const SizedBox(height: 26),
      Text(_slides[_step][0],
          textAlign: TextAlign.center, style: T.title(c).copyWith(fontSize: 21)),
      const SizedBox(height: 8),
      Text(_slides[_step][1],
          textAlign: TextAlign.center,
          style: T.body(c).copyWith(color: c.muted, fontSize: 14)),
      const SizedBox(height: 22),
      Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: i == _step ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                  color: i == _step ? c.ink : c.line,
                  borderRadius: BorderRadius.circular(99)),
            ),
        ]),
      ),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(
          child: KBtnGhost('Passer', onTap: _finish),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: KBtn(_step < 2 ? 'Suivant' : 'Commencer', onTap: () {
            Fx.tick();
            if (_step < 2) {
              setState(() => _step++);
            } else {
              _finish();
            }
          }),
        ),
      ]),
      const SizedBox(height: 14),
      Text(
        "L'appli pilote le bot via GitHub. Ton jeton restera chiffré dans le téléphone.",
        textAlign: TextAlign.center,
        style: T.caption(c),
      ),
    ];
  }

  List<Widget> _tokenCard(Palette c) {
    return [
      KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PulseDot(c.accent),
          const SizedBox(height: 6),
          Text('Connecte le bot', style: T.title(c).copyWith(fontSize: 21)),
          const SizedBox(height: 8),
          Text(
            "Cette appli pilote ton bot : publication, commentaires, médias, statistiques. Elle utilise un jeton GitHub, chiffré dans le coffre du téléphone.",
            style: T.body(c).copyWith(color: c.muted, fontSize: 14),
          ),
          const SizedBox(height: 14),
          Text('DROITS DU JETON (FINE-GRAINED)', style: T.micro(c)),
          const SizedBox(height: 6),
          for (final r in const [
            'Contents : Read and write',
            'Actions : Read and write',
            'Variables : Read and write',
            'Metadata : Read-only (automatique)'
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(Icons.circle, size: 4, color: c.ink),
                const SizedBox(width: 8),
                Text(r, style: T.body(c)),
              ]),
            ),
          const SizedBox(height: 10),
          Text(
            "Sur les deux dépôts : facebook-data et facebook-manager.",
            style: T.caption(c),
          ),
          const SizedBox(height: 14),
          KBtn('Ouvrir les réglages', onTap: () {
            Fx.tick();
            Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SubPage('Réglages', child: SettingsScreen())));
          }),
        ]),
      ),
      const SizedBox(height: 8),
      Press(
        onTap: () => setState(() {
          _intro = true;
          _step = 0;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
              child: Text('Revoir l\'introduction',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.muted))),
        ),
      ),
    ];
  }
}
