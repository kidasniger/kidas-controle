import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'core/api.dart';
import 'core/native.dart';
import 'core/palette.dart';
import 'core/store.dart';
import 'core/updater.dart';
import 'screens/home.dart';
import 'screens/placeholders.dart';
import 'ui/common.dart';
import 'widgets/pill_nav.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const KidasApp());
}

/// Bus d'état partagé : badges + mode de thème.
class Bus {
  static final ValueNotifier<int> notifs = ValueNotifier(0);
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);

  static ThemeMode parse(String s) =>
      s == 'light' ? ThemeMode.light : s == 'dark' ? ThemeMode.dark : ThemeMode.system;
}

class KidasApp extends StatelessWidget {
  const KidasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Bus.themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'KI DAS Contrôle',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: _theme(false),
        darkTheme: _theme(true),
        home: const Boot(),
      ),
    );
  }

  static ThemeData _theme(bool dark) {
    final b = dark ? Brightness.dark : Brightness.light;
    final c = Palette.of(b);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: c.accent, brightness: b)
          .copyWith(primary: c.accent, secondary: c.accent, surface: c.card),
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
    );
  }
}

/* ---------- démarrage : splash + verrouillage + mise à jour auto ---------- */

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> with WidgetsBindingObserver {
  bool _ready = false, _locked = true, _warned = false, _autoChecked = false;
  DateTime? _bgAt;
  final LocalAuthentication _la = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Native.init();
    Native.onInstallResult = _installResult;
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _boot() async {
    final all = await Store.all();
    // reprise du réglage sombre/clair de la v1 Java
    if (!all.containsKey('theme_mode')) {
      final legacy = all['dark'] ?? '1';
      all['theme_mode'] = legacy == '0' ? 'light' : 'dark';
      await Store.set('theme_mode', all['theme_mode']!);
    }
    Api.loadCfg(all);
    Bus.themeMode.value = Bus.parse(all['theme_mode'] ?? 'system');
    if (!mounted) return;
    setState(() => _ready = true);
    await _checkLock();
  }

  /* ---------- verrouillage (port de MainActivity.lock) ---------- */

  Future<void> _checkLock() async {
    final supported = await _la.isDeviceSupported();
    if (!supported) {
      if (!_warned && mounted) {
        _warned = true;
        kToast(context,
            "Aucun verrouillage d'écran : l'application n'est pas protégée.",
            bad: true);
      }
      if (mounted) setState(() => _locked = false);
      _afterUnlock();
      return;
    }
    try {
      final ok = await _la.authenticate(
          localizedReason: 'Déverrouille pour continuer',
          options: const AuthenticationOptions(
              biometricOnly: false, stickyAuth: true));
      if (!mounted) return;
      setState(() => _locked = !ok);
      if (ok) _afterUnlock();
    } catch (_) {
      if (mounted) setState(() => _locked = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _bgAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final bg = _bgAt;
      _bgAt = null;
      if (bg != null &&
          _ready &&
          DateTime.now().difference(bg) > const Duration(seconds: 60)) {
        _checkLock();
      }
    }
  }

  /* ---------- mise à jour automatique (port de Updater.autoCheck) ---------- */

  Future<void> _afterUnlock() async {
    if (_autoChecked) return;
    _autoChecked = true;
    Updater.cleanup();
    try {
      if ((await Store.get('upd_auto')) == '0') return;
      final info = await Updater.check();
      if (info.available && mounted) _showUpdate(info);
    } catch (_) {
      // silencieux
    }
  }

  void _installResult(int status, String? msg) {
    if (!mounted) return;
    if (status == 0) {
      kToast(context, 'Mise à jour installée, rouvre l\'application.');
    } else {
      kToast(context, msg == null || msg.isEmpty
          ? 'Installation interrompue.'
          : msg, bad: true);
    }
  }

  void _showUpdate(UpdInfo info) {
    final c = context.p;
    showDialog<void>(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: c.line)),
        title: Text(info.mandatory ? 'Mise à jour obligatoire' : 'Mise à jour disponible',
            style: T.title(c)),
        content: Text(
            info.notes.isEmpty
                ? 'Version ${info.name} disponible.'
                : 'Version ${info.name}\n\n${info.notes}',
            style: T.body(c)),
        actions: [
          if (!info.mandatory)
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Plus tard', style: TextStyle(color: c.muted))),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _doUpdate(info);
              },
              child: Text('Installer',
                  style: TextStyle(
                      color: c.accent, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Future<void> _doUpdate(UpdInfo info) async {
    try {
      kToast(context, 'Téléchargement...');
      final f = await Updater.download(info, null);
      await Updater.install(f);
    } catch (e) {
      if (mounted) kToast(context, e.toString(), bad: true);
    }
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Stack(children: [
      const Positioned.fill(child: Shell()),
      if (!_ready || _locked)
        Positioned.fill(
          child: Container(
            color: c.bg,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                      color: c.ink, borderRadius: BorderRadius.circular(26)),
                  child: Center(
                      child: Text('K',
                          style: TextStyle(
                              fontSize: 40, fontWeight: FontWeight.w900,
                              color: c.bg))),
                ),
                const SizedBox(height: 18),
                Text('KI DAS Contrôle', style: T.hero(c)),
                const SizedBox(height: 4),
                Text('Ton bot, sous contrôle', style: T.body(c).copyWith(color: c.muted)),
                const SizedBox(height: 34),
                SizedBox(
                    width: 120,
                    child: KSkeleton(4, radius: 2)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/* ---------- coquille : en-tête + écran courant + pilule flottante ---------- */

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0; // 0 Accueil, 1 Bot, 3 Réponses, 4 Stats (2 = bouton +)
  int _gen = 0; // incrémente au bouton rafraîchir

  static const _titles = [
    'Centre de contrôle',
    'Assistant',
    'Commentaires',
    'Statistiques',
  ];

  Widget _screen(int t) {
    if (Api.tok.isEmpty) return const WelcomeScreen();
    switch (t) {
      case 1:
        return const PlaceholderScreen('Bot', 'Assistant GLM');
      case 3:
        return const PlaceholderScreen('Réponses', 'Commentaires & avis');
      case 4:
        return const PlaceholderScreen('Stats', 'Statistiques');
      default:
        return HomeScreen(gen: _gen);
    }
  }

  void _refresh() {
    Api.resetCache();
    setState(() => _gen++);
  }

  /* ---------- menu du bouton + (port de MainActivity.openSheet) ---------- */

  Future<void> _openPlus() async {
    final t = await kSheet<int>(context, title: 'Actions rapides', children: [
      _sheetRow(context, Icons.edit_outlined, 'Publier', 0),
      _sheetRow(context, Icons.image_outlined, 'Médias', 1),
      _sheetRow(context, Icons.chat_bubble_outline, 'Avis (commentaires)', 2),
      _sheetRow(context, Icons.messenger_outline, 'Messages', 3),
    ]);
    if (t == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => switch (t) {
        0 => const PlaceholderScreen('Publier', 'Créer une publication'),
        1 => const PlaceholderScreen('Médias', 'Bibliothèque média'),
        2 => const PlaceholderScreen('Avis', 'Commentaires'),
        _ => const PlaceholderScreen('Messages', 'Messenger'),
      },
    ));
  }

  Widget _sheetRow(BuildContext ctx, IconData ic, String label, int v) {
    final c = ctx.p;
    return Press(
      onTap: () => Navigator.pop(ctx, v),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          IconBox(ic),
          const SizedBox(width: 13),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700, color: c.ink))),
          Icon(Icons.chevron_right, size: 18, color: c.muted),
        ]),
      ),
    );
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) setState(() => _tab = 0);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            _header(c),
            Expanded(
              child: AnimatedSwitcher(
                duration: KAnim.med,
                switchInCurve: KAnim.ease,
                transitionBuilder: (w, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, .02), end: Offset.zero)
                        .animate(a),
                    child: w,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey('$_tab-$_gen-${Api.tok.isEmpty}'),
                  child: _screen(_tab),
                ),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: Bus.notifs,
          builder: (_, badge, __) => PillNav(
            sel: _tab,
            badge: badge,
            onTab: (i) => setState(() => _tab = i),
            onFab: _openPlus,
          ),
        ),
      ),
    );
  }

  Widget _header(Palette c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 0),
      child: Column(children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: c.ink, borderRadius: BorderRadius.circular(9)),
            child: Center(
                child: Text('K',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900, color: c.bg))),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('KI DAS',
                  style: TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w900,
                      letterSpacing: .05 * 15.5, color: c.ink)),
              Text(_titles[_tab],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5, color: c.muted, height: 1.2)),
            ]),
          ),
          _ibtn(c, Icons.refresh_outlined, _refresh),
          const SizedBox(width: 6),
          _ibtn(c, Icons.settings_outlined, () {
            Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const PlaceholderScreen('Réglages', 'Réglages')));
          }),
        ]),
        const SizedBox(height: 10),
        Container(
            height: 2,
            decoration: BoxDecoration(
                color: c.ink, borderRadius: BorderRadius.circular(2))),
      ]),
    );
  }

  Widget _ibtn(Palette c, IconData ic, VoidCallback f) {
    return Press(
      onTap: f,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.line)),
        child: Icon(ic, size: 16, color: c.ink),
      ),
    );
  }
}
