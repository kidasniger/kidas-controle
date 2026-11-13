import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/palette.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show Bus, SubPage;
import 'comments.dart';
import 'messages.dart';
import 'publish.dart';

/// Onglet Réponses : état des réponses automatiques, accès aux interactions
/// et règles du bot. Port fidèle de RulesScreen.java.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});
  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  Bot? _bot;
  Dash? _dash;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    Bot? bot;
    Dash? dash;
    await Future.wait<dynamic>([
      Api.botState().then((v) { bot = v; return null; }).catchError((Object e) { return null; }),
      Api.dash().then((v) { dash = v; return null; }).catchError((Object e) { return null; }),
    ]);
    if (!mounted) return;
    setState(() {
      _bot = bot;
      _dash = dash;
      _busy = false;
    });
    if (_dash?.cm != null) {
      final all = Api.flatComments(_dash!.cm);
      Bus.setAvis(Api.unanswered(all, Api.pageId(_dash!.st, _dash!.cm)).length);
    }
  }

  bool _nested(String key) {
    final o = _bot?.cfg[key];
    return o is! Map<String, dynamic> || o.ob('actif', true);
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _bot == null && _dash == null) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        KSkeleton(100),
        SizedBox(height: 12),
        KSkeleton(80),
        SizedBox(height: 12),
        KSkeleton(80),
      ]);
    }
    final c = context.p;
    final bs = _bot;
    final on = bs != null && _nested('reponses');

    String t, s;
    if (bs == null) {
      t = 'État inconnu';
      s = 'Impossible de lire glm/config.json.';
    } else if (!on) {
      t = 'Réponses automatiques coupées';
      s = 'Le bot like et lit, mais ne répond plus.';
    } else if (bs.state == 'on') {
      t = 'Le bot répond tout seul';
      s = 'Il like et répond aux nouvelles interactions.';
    } else if (bs.state == 'wait') {
      t = 'En attente de session';
      s = 'Les réponses reprendront au prochain démarrage.';
    } else {
      t = 'Bot arrêté';
      s = "Relance une session depuis l'onglet Bot.";
    }

    final dash = _dash;
    final pid = dash == null ? '' : Api.pageId(dash.st, dash.cm);
    var nAvis = 0;
    if (dash != null && dash.cm != null) {
      final all = Api.flatComments(dash.cm);
      nAvis = Api.unanswered(all, pid).length;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        /* héro inversé */
        KHero(
          child: Row(children: [
            PulseDot(bs == null || !on ? c.heroMut : c.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: T.hero(c).copyWith(fontSize: 18)),
                Text(s, style: T.body(c).copyWith(color: c.heroMut)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        /* interrupteur IA réponse */
        if (bs != null) ...[
          KSection('IA réponse'),
          KCard(
            child: KSwitchRow('Répondre aux commentaires',
                desc: 'Le bot rédige et publie une réponse',
                value: on,
                job: (v) => Api.updateJson('glm/config.json', false, (cur) {
                      final o = asObj(cur);
                      final r = asObj(o['reponses']);
                      r['actif'] = v;
                      o['reponses'] = r;
                      return o;
                    }, 'Réponses automatiques ${v ? 'activées' : 'désactivées'}')),
          ),
          const SizedBox(height: 16),
        ],
        /* accès aux interactions */
        KSection('Interactions'),
        KCard(
          child: Column(children: [
            RouteRow(Icons.forum_outlined, 'Avis',
                sub: nAvis <= 0 ? 'Tout est traité' : '$nAvis sans réponse',
                onTap: () => _push(
                    const SubPage('Avis (commentaires)', child: CommentsScreen()))),
            const KDivider(),
            RouteRow(Icons.messenger_outline, 'Messages',
                sub: 'Conversations Messenger',
                onTap: () => _push(
                    const SubPage('Messages', child: MessagesScreen()))),
            const KDivider(),
            RouteRow(Icons.edit_outlined, 'Publier',
                sub: 'Nouveau post sur la Page',
                onTap: () => _push(
                    const SubPage('Publier', child: PublishScreen()))),
          ]),
        ),
        const SizedBox(height: 16),
        /* règles actives */
        KSection('Règles du bot'),
        KCard(
          child: Column(children: [
            RuleRow('Like automatique',
                desc: 'Chaque nouveau commentaire est aimé', active: on),
            const KDivider(),
            RuleRow('Réponse rédigée',
                desc: 'GLM adapte la réponse au commentaire', active: on),
            const KDivider(),
            RuleRow('Publications automatiques',
                desc: 'Posts planifiés par le bot',
                active: bs != null && _nested('posts')),
          ]),
        ),
        const SizedBox(height: 12),
        const NoteBox('Règles avancées (délai, mots-clés) : ',
            'à venir dans une prochaine version du bot.'),
      ],
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _load();
  }
}
