import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/palette.dart';
import '../core/updater.dart';
import 'common.dart';

/// Bus d'état partagé : badges, thème, marqueur d'écran externe.
class Bus {
  static final ValueNotifier<int> avis = ValueNotifier(0);
  static final ValueNotifier<int> msg = ValueNotifier(0);
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);
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
      return StatefulBuilder(builder: (ctx2, setD) {
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
              side: BorderSide(color: c.line)),
          title: Text(
              info.mandatory ? 'Mise à jour obligatoire' : 'Mise à jour disponible',
              style: T.title(c)),
          content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          ]),
          actions: [
            if (failed.isEmpty && !info.mandatory)
              TextButton(
                  onPressed: () {
                    Updater.cancelDownload();
                    Navigator.pop(ctx2);
                  },
                  child:
                      Text('Plus tard', style: TextStyle(color: c.muted))),
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
                  child: Text('Réessayer',
                      style: TextStyle(
                          color: c.accent, fontWeight: FontWeight.w800))),
            if (failed.isNotEmpty)
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: Text('Fermer', style: TextStyle(color: c.muted))),
          ],
        );
      });
    },
  );
}

/* ---------- écran secondaire plein écran (port du header v1) ---------- */

class SubPage extends StatelessWidget {
  final String title;
  final Widget child;
  const SubPage(this.title, {super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(children: [
              Row(children: [
                Press(
                  onTap: () {
                    Fx.tick();
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: c.line)),
                    child: Icon(Icons.arrow_back, size: 17, color: c.ink),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.title(c)),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                  height: 2,
                  decoration: BoxDecoration(
                      color: c.ink, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}
