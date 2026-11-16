import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'core/api.dart';
import 'core/fx.dart';
import 'core/native.dart';
import 'core/palette.dart';
import 'core/store.dart';
import 'core/updater.dart';
import 'screens/ai_chat.dart';
import 'screens/boite.dart';
import 'screens/bot_rules.dart';
import 'screens/composer.dart';
import 'screens/journal.dart';
import 'screens/home.dart';
import 'screens/medias.dart';
import 'screens/moderation.dart';
import 'screens/settings.dart';
import 'screens/stats.dart';
import 'screens/welcome.dart';
import 'ui/common.dart';
import 'ui/shell.dart';
import 'widgets/pill_nav.dart';
import 'widgets/post_card.dart' show badgeVerifie;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const KidasApp());
}

class KidasApp extends StatelessWidget {
  const KidasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Bus.themeMode,
      builder: (_, mode, _) => MaterialApp(
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
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.card,
        dialBackgroundColor: c.soft,
      ),
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
    await Fx.init();
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
          !Bus.external &&
          DateTime.now().difference(bg) > const Duration(seconds: 60)) {
        _checkLock();
      }
      Bus.external = false;
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
      if (info.available && mounted) {
        await kUpdateFlow(context, info);
      }
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
  // onglets de la maquette : 0 Accueil, 1 Boîte, 3 Bot, 4 Stats (2 = bouton +)
  int _tab = 0;
  int _gen = 0; // incrémente au bouton rafraîchir
  String _pageName = 'KI DAS';

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  /// Nom réel de la Page (données du bot) pour l'en-tête d'identité.
  Future<void> _loadPage() async {
    Map<String, dynamic>? pg;
    try {
      final st = await Api.readObj('inbox/statistiques.json');
      final cm = await Api.readObj('inbox/commentaires.json');
      for (final o in [st?['page'], cm?['page']]) {
        if (o is Map<String, dynamic> && o.os('name').isNotEmpty) {
          pg = o;
          break;
        }
      }
    } catch (_) {
      // sans données, l'en-tête garde la marque KI DAS
    }
    if (pg != null && mounted) {
      setState(() => _pageName = pg!.os('name'));
    }
  }

  Widget _screen(int t) {
    if (Api.tok.isEmpty) return const WelcomeScreen();
    switch (t) {
      case 1:
        return const BoiteScreen();
      case 3:
        return const BotRulesScreen();
      case 4:
        return const StatsScreen();
      default:
        return HomeScreen(gen: _gen);
    }
  }

  void _refresh() {
    Api.resetCache();
    setState(() => _gen++);
  }

  /* ---------- bouton + : le composer en plein écran ---------- */

  Future<void> _openPlus() async {
    Fx.medium();
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const SubPage('Composer', child: ComposerScreen())));
    if (mounted) _refresh();
  }

  /* ---------- menu « ... » : écrans de gestion ---------- */

  Future<void> _openMenu() async {
    Fx.tick();
    final t = await kSheet<String>(context, title: 'Gestion de la Page', children: [
      _sheetRow(context, Icons.shield_outlined, 'Modération', 'mod',
          sub: 'Commentaires à traiter'),
      _sheetRow(context, Icons.image_outlined, 'Studio Médias', 'med',
          sub: 'Bibliothèque, étiquettes, sélection'),
      _sheetRow(context, Icons.smart_toy_outlined, 'Bot & Règles', 'bot',
          sub: 'Pilotage, verrous, règles, exécutions'),
      _sheetRow(context, Icons.receipt_long_outlined, "Journal d'activité", 'log',
          sub: 'Application et bot, tout est tracé'),
      _sheetRow(context, Icons.settings_outlined, 'Réglages', 'set',
          sub: 'Apparence, connexion, sécurité'),
    ]);
    if (t == null || !mounted) return;
    final screens = <String, Widget Function()>{
      'mod': () => const SubPage('Modération', child: ModerationScreen()),
      'med': () => const SubPage('Studio Médias', child: MediasScreen()),
      'bot': () => const SubPage('Bot & Règles', child: BotRulesScreen()),
      'log': () => const SubPage("Journal d'activité", child: JournalScreen()),
      'set': () => const SubPage('Réglages', child: SettingsScreen()),
    };
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => screens[t]!()));
  }

  Widget _sheetRow(BuildContext ctx, IconData ic, String label, String v,
      {String sub = ''}) {
    final c = ctx.p;
    return Press(
      onTap: () {
        Fx.tick();
        Navigator.pop(ctx, v);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          IconBox(ic),
          const SizedBox(width: 13),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700, color: c.ink)),
                if (sub.isNotEmpty)
                  Text(sub, style: TextStyle(fontSize: 11.5, color: c.muted)),
              ])),
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
            if (_tab == 0 && Api.tok.isNotEmpty) _header(c),
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
          valueListenable: Bus.avis,
          builder: (_, a, __) => ValueListenableBuilder<int>(
            valueListenable: Bus.msg,
            builder: (_, m, ___) => PillNav(
              sel: _tab,
              badge: a + m,
              onTab: (i) => setState(() => _tab = i),
              onFab: _openPlus,
            ),
          ),
        ),
      ),
    );
  }

  /* ---------- en-tête d'identité de la Page (écran Accueil) ---------- */

  Widget _header(Palette c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
          child: Text('K',
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: c.bg)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(_pageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800,
                        color: c.ink)),
              ),
              const SizedBox(width: 5),
              badgeVerifie(c, 15),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              PulseDot(c.accent, size: 5),
              const SizedBox(width: 5),
              Text('En ligne',
                  style: TextStyle(fontSize: 10.5, color: c.muted,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        _ibtn(c, Icons.search_outlined, () {
          Fx.tick();
          Bus.requete.value = '';
          Bus.chercher.value = !Bus.chercher.value;
          if (_tab != 0) setState(() => _tab = 0);
        }),
        const SizedBox(width: 6),
        _cloche(c),
        const SizedBox(width: 6),
        _ibtn(c, Icons.more_horiz, () {
          _openMenu();
        }),
      ]),
    );
  }

  Widget _cloche(Palette c) {
    return ValueListenableBuilder<int>(
      valueListenable: Bus.avis,
      builder: (_, a, __) => ValueListenableBuilder<int>(
        valueListenable: Bus.msg,
        builder: (_, m, ___) {
          final n = a + m;
          return _ibtn(c, Icons.notifications_outlined, () {
            Fx.tick();
            if (_tab != 1) setState(() => _tab = 1);
          }, badge: n);
        },
      ),
    );
  }

  Widget _ibtn(Palette c, IconData ic, VoidCallback f, {int badge = 0}) {
    return Press(
      onTap: f,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.line)),
        child: Stack(clipBehavior: Clip.none, children: [
          Center(child: Icon(ic, size: 17, color: c.ink)),
          if (badge > 0)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                    color: c.ink, borderRadius: BorderRadius.circular(99)),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 15),
                alignment: Alignment.center,
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: c.bg),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
