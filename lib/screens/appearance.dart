import 'package:flutter/material.dart';
import '../core/fx.dart';
import '../core/notifs.dart';
import '../core/palette.dart';
import '../core/store.dart';
import '../ui/common.dart';
import '../ui/forms.dart' show KSegmented;
import '../ui/pictos.dart';
import '../ui/shell.dart' show Bus;

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final mode = Bus.themeMode.value;
    final selected = mode == ThemeMode.light ? 1 : mode == ThemeMode.dark ? 2 : 0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(c, 'APPARENCE', 'Personnalise ton expérience', Text('Configure le thème, les sons, les vibrations et les notifications.', style: T.caption(c))),
      const SizedBox(height: 12),
      _card(c, 'AFFICHAGE', 'Thème', SizedBox(width: double.infinity, child: KSegmented(const ['Système', 'Clair', 'Sombre'], sel: selected, fontSize: 12, onSelect: (i) async {
        Fx.tick();
        Bus.themeMode.value = i == 1 ? ThemeMode.light : i == 2 ? ThemeMode.dark : ThemeMode.system;
        await Store.set('theme_mode', i == 1 ? 'light' : i == 2 ? 'dark' : 'system');
      }))),
      const SizedBox(height: 12),
      _card(c, 'CONFORT', 'Sons et vibrations', ValueListenableBuilder<bool>(valueListenable: Fx.sons, builder: (_, v, __) => SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Sons et vibrations'), subtitle: const Text('Retour sonore lors des interactions'), value: v, onChanged: (n) { Fx.tick(); Fx.setSons(n); }))),
      const SizedBox(height: 12),
      _card(c, 'ALERTES', 'Notifications', ValueListenableBuilder<bool>(valueListenable: Notifs.activ, builder: (_, v, __) => SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Notifications'), subtitle: const Text('Commentaires urgents et alertes du jeton Facebook'), value: v, onChanged: Notifs.set))),
    ]);
  }
  Widget _card(Palette c, String tag, String title, Widget child) => Container(margin: const EdgeInsets.only(bottom: 2), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tag, style: T.caption(c).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)), const SizedBox(height: 5), Text(title, style: T.title(c).copyWith(fontSize: 17)), const SizedBox(height: 12), child]));
}
