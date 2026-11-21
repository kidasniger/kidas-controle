import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/palette.dart';
import '../core/updater.dart';
import 'common.dart';
import 'pictos.dart';

/// Bus d'état partagé : badges, thème, recherche de l'accueil, marqueur
/// d'écran externe.
class Bus {
  static final ValueNotifier<int> avis = ValueNotifier(0);
  static final ValueNotifier<int> msg = ValueNotifier(0);
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.system,
  );

  /// Vrai une fois le jeton et les dépôts chargés du coffre : les écrans
  /// qui lisent le dépôt au démarrage attendent ce signal pour relire
  /// (sinon leurs lectures partent sans jeton et échouent en silence).
  static final ValueNotifier<bool> cfgReady = ValueNotifier(false);
  static final ValueNotifier<bool> chercher = ValueNotifier(false);
  static final ValueNotifier<String> requete = ValueNotifier('');
  static bool external = false;

  static void setAvis(int n) => avis.value = n;
  static void setMsg(int n) => msg.value = n;

  static ThemeMode parse(String s) => s == 'light'
      ? ThemeMode.light
      : s == 'dark'
      ? ThemeMode.dark
      : ThemeMode.system;
}

/* ---------- dialogue de mise à jour avec progression ---------- */

Future<void> kUpdateFlow(BuildContext context, UpdInfo info) async {
  Bus.external = true;
  var progress = 0.0;
  var phase = 'Téléchargement...';
  var failed = '';
  var started = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final c = ctx.p;
      return StatefulBuilder(
        builder: (ctx2, setD) {
          Future<void> start() async {
            try {
              final f = await Updater.download(info, (done, total) {
                if (total > 0) setD(() => progress = done / total);
              });
              setD(() => phase = 'Installation...');
              Bus.external = true;
              await Updater.install(f);
              if (ctx2.mounted) Navigator.pop(ctx2);
            } catch (e) {
              setD(() {
                failed = e.toString();
                phase = '';
              });
            }
          }

          // lancement unique au premier build du dialogue
          if (!started) {
            started = true;
            Future.microtask(start);
          }
          return AlertDialog(
            backgroundColor: c.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: c.line),
            ),
            title: Text(
              info.mandatory
                  ? 'Mise à jour obligatoire'
                  : 'Mise à jour disponible',
              style: T.title(c).copyWith(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.notes.isNotEmpty) ...[
                  Text(info.notes, style: T.body(c)),
                  const SizedBox(height: 12),
                ],
                if (failed.isEmpty && phase.isNotEmpty) ...[
                  Text(phase, style: T.caption(c)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: phase == 'Installation...' ? null : progress,
                      minHeight: 6,
                      backgroundColor: c.soft,
                      valueColor: AlwaysStoppedAnimation(c.accent),
                    ),
                  ),
                ],
                if (failed.isNotEmpty) Text(failed, style: T.body(c)),
              ],
            ),
            actions: [
              if (failed.isEmpty && !info.mandatory)
                TextButton(
                  onPressed: () {
                    Updater.cancelDownload();
                    Navigator.pop(ctx2);
                  },
                  child: Text('Plus tard', style: TextStyle(color: c.muted)),
                ),
              if (failed.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setD(() {
                      failed = '';
                      phase = 'Téléchargement...';
                      progress = 0;
                    });
                    Future.microtask(start);
                  },
                  child: Text(
                    'Réessayer',
                    style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (failed.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: Text('Fermer', style: TextStyle(color: c.muted)),
                ),
            ],
          );
        },
      );
    },
  );
}

/* ---------- écran secondaire plein écran (port du header v1) ---------- */

class SubPage extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const SubPage(this.title, {super.key, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Press(
                        onTap: () {
                          Fx.tick();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.line),
                          ),
                          child: Picto('back', size: 17, color: c.ink),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.title(c),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      color: c.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            const BandeauHorsLigne(),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
