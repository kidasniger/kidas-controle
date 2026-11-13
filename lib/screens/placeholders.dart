import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/palette.dart';
import '../ui/common.dart';

/// Écran transitoire : le port fidèle à la maquette arrive dans la passe UI.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String sub;
  const PlaceholderScreen(this.title, {super.key, this.sub = ''});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(title, style: T.title(c))),
              ]),
              const SizedBox(height: 6),
              Container(
                  height: 2,
                  decoration: BoxDecoration(
                      color: c.ink, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
          Expanded(
            child: KEmpty(Icons.construction_outlined, 'Port en cours',
                sub: "Écran « $title » — prochaine passe d'implémentation."),
          ),
        ]),
      ),
    );
  }
}

/// Écran sans jeton : invite à configurer (port léger de WelcomeScreen).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
                color: c.ink, borderRadius: BorderRadius.circular(22)),
            child: Center(
                child: Text('K',
                    style: TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w900, color: c.bg))),
          ),
          const SizedBox(height: 16),
          Text('KI DAS Contrôle', style: T.hero(c)),
          const SizedBox(height: 4),
          Text('Ton bot, sous contrôle',
              style: T.body(c).copyWith(color: c.muted)),
          const SizedBox(height: 22),
          KCard(
            child: Text(
              'Ajoute un jeton GitHub dans Réglages pour connecter le bot.',
              style: T.body(c),
            ),
          ),
        ]),
      ),
    );
  }
}
