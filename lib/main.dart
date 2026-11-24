import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'core/api.dart';
import 'core/bot_notification_sync.dart';
import 'core/fx.dart';
import 'core/native.dart';
import 'core/notifs.dart';
import 'core/notification_center.dart';
import 'core/palette.dart';
import 'core/store.dart';
import 'core/updater.dart';
import 'screens/ai_chat.dart';
import 'screens/boite.dart';
import 'screens/bot_rules.dart';
import 'screens/composer.dart';
import 'screens/journal.dart';
import 'screens/home.dart';
import 'screens/global_search.dart';
import 'screens/medias.dart';
import 'screens/moderation.dart';
import 'screens/notifications.dart';
import 'screens/reports.dart';
import 'screens/settings.dart';
import 'screens/stats.dart';
import 'screens/welcome.dart';
import 'ui/common.dart';
import 'ui/pictos.dart';
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
      fontFamily: 'Inter',
      brightness: b,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: b,
      ).copyWith(primary: c.accent, secondary: c.accent, surface: c.card),
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: T.title(c).copyWith(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
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
  bool _ready = false, _locked = true, _autoChecked = false;
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
    try {
      // Seul le stockage local est nécessaire pour afficher l'application.
      // Une limite évite de conserver indéfiniment le splash si Android bloque
      // le Keystore ou la migration des préférences historiques.
      final all = await Store.all().timeout(const Duration(seconds: 15));

      // Migration du thème : ne jamais imposer le mode sombre par défaut.
      // L'ancienne valeur Java "dark" n'est utilisée que si elle existe réellement.
      // Les installations où les versions précédentes ont enregistré "dark"
      // automatiquement reviennent une seule fois au suivi du système.
      const themeMigrationKey = 'theme_mode_migrated_v230';
      final legacyDark = all['dark'];
      final migrationDone = all[themeMigrationKey] == '1';
      if (!all.containsKey('theme_mode')) {
        all['theme_mode'] = legacyDark == null
            ? 'system'
            : legacyDark == '0'
                ? 'light'
                : 'dark';
      } else if (!migrationDone &&
          all['theme_mode'] == 'dark' &&
          legacyDark == null) {
        // Dans les versions précédentes, l'absence de "dark" était
        // interprétée à tort comme "sombre". Corriger ce défaut historique.
        all['theme_mode'] = 'system';
      }

      if (!migrationDone) {
        all[themeMigrationKey] = '1';
        unawaited(
          Store.set('theme_mode', all['theme_mode']!)
              .timeout(const Duration(seconds: 5))
              .catchError((Object _) {}),
        );
        unawaited(
          Store.set(themeMigrationKey, '1')
              .timeout(const Duration(seconds: 5))
              .catchError((Object _) {}),
        );
      }

      Api.loadCfg(all);
      Bus.themeMode.value = Bus.parse(all['theme_mode'] ?? 'system');
      Bus.cfgReady.value = true;

      if (!mounted) return;
      setState(() => _ready = true);
      if (Store.isDegraded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            kToast(
              context,
              "Le coffre sécurisé est indisponible. Les réglages restent temporaires jusqu'au rétablissement du Keystore.",
              bad: true,
            );
          }
        });
      }

      // Ces tâches sont secondaires : elles ne doivent jamais retarder
      // l'ouverture de l'écran principal.
      unawaited(
        Fx.init()
            .timeout(const Duration(seconds: 8))
            .catchError((Object _) {}),
      );
      unawaited(
        Notifs.auDemarrage()
            .timeout(const Duration(seconds: 12))
            .catchError((Object _) {}),
      );
      unawaited(
        BotNotificationSync.sync()
            .timeout(const Duration(seconds: 20))
            .catchError((Object _) {}),
      );

      await _checkLock();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _locked = false;
      });
      kToast(
        context,
        "Le stockage sécurisé met trop de temps à répondre. L'application s'ouvre sans charger la connexion enregistrée.",
        bad: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _locked = false;
      });
      kToast(
        context,
        "Initialisation partielle : ${e.toString()}",
        bad: true,
      );
    }
  }

  /* ---------- verrouillage (port de MainActivity.lock) ---------- */

  bool _authenticating = false;

  Future<void> _unlockWithWarning(String message) async {
    if (!mounted) return;
    setState(() {
      _locked = false;
    });
    kToast(context, message, bad: true);
    _afterUnlock();
  }

  Future<void> _checkLock() async {
    if (_authenticating || !mounted) return;
    _authenticating = true;
    try {
      final supported = await _la
          .isDeviceSupported()
          .timeout(const Duration(seconds: 10));
      if (!supported) {
        await _unlockWithWarning(
          "Aucun verrouillage compatible détecté : l'application n'est pas protégée.",
        );
        return;
      }

      final ok = await _la
          .authenticate(
            localizedReason: 'Déverrouille pour continuer',
            options: const AuthenticationOptions(
              biometricOnly: false,
              stickyAuth: true,
            ),
          )
          .timeout(const Duration(seconds: 45));

      if (!mounted) return;
      setState(() => _locked = !ok);
      // En cas d'annulation volontaire, l'écran reste protégé et propose
      // un bouton pour relancer l'authentification.
      if (ok) _afterUnlock();
    } on TimeoutException {
      await _unlockWithWarning(
        "L'authentification n'a pas répondu à temps. Le verrouillage a été désactivé pour cette ouverture.",
      );
    } catch (e) {
      await _unlockWithWarning(
        "L'authentification est indisponible : ${e.toString()}",
      );
    } finally {
      _authenticating = false;
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
      kToast(
        context,
        msg == null || msg.isEmpty ? 'Installation interrompue.' : msg,
        bad: true,
      );
    }
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Stack(
      children: [
        const Positioned.fill(child: Shell()),
        if (!_ready || _locked)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.bg,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.bg, c.card, c.bg],
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          color: c.ink,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: c.accent.withValues(alpha: .22),
                              blurRadius: 34,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              'K',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -3,
                                color: c.bg,
                              ),
                            ),
                            Positioned(
                              right: 13,
                              bottom: 13,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: c.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: c.ink, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'KIDAS',
                        style: T.hero(c).copyWith(
                          color: c.ink,
                          fontSize: 30,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'CONTRÔLE DE VOTRE PAGE',
                        style: T.micro(c).copyWith(letterSpacing: 2.0),
                      ),
                      const SizedBox(height: 38),
                      SizedBox(
                        width: 156,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor: c.line,
                            valueColor: AlwaysStoppedAnimation(c.accent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _locked && _ready
                            ? 'Authentification sécurisée…'
                            : 'Préparation de votre espace…',
                        style: T.caption(c),
                      ),
                      if (_ready && _locked) ...[
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: _authenticating ? null : _checkLock,
                          icon: const Icon(Icons.lock_open_rounded, size: 17),
                          label: const Text('Réessayer le déverrouillage'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ---------- coquille : en-tête + écran courant + pilule flottante ---------- */

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  Timer? _liveRefreshTimer;
  bool _foreground = true;
  // onglets de la maquette : 0 Accueil, 1 Boîte, 3 Bot, 4 Stats (2 = bouton +)
  int _tab = 0;
  int _gen = 0; // incrémente au bouton rafraîchir
  String _pageName = 'KI DAS';
  String _pageUser = '';

  /// State de l'Assistant IA : le bouton d'actualisation de son en-tête
  /// relit l'historique et le contexte depuis le dépôt.
  final GlobalKey<AiChatScreenState> _aiKey = GlobalKey<AiChatScreenState>();

  /// State du Journal : le bouton filtre de son en-tête affiche ou masque
  /// les chips de filtre (maquette 09).
  final GlobalKey<JournalScreenState> _logKey = GlobalKey<JournalScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPage();
    NotificationCenter.load();
    // Synchronisation active : santé du bot + rechargement de l'écran ouvert.
    _liveRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground && mounted && Api.tok.isNotEmpty) _refresh();
    });
    // la lecture du nom réel échoue si le jeton n'est pas encore sorti du
    // coffre : on relit dès que la configuration est prête (Bus.cfgReady)
    Bus.cfgReady.addListener(_loadPage);
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    Bus.cfgReady.removeListener(_loadPage);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (mounted && Api.tok.isNotEmpty) _refresh();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
    }
  }

  /// Nom réel de la Page (données du bot) pour l'en-tête d'identité.
  Future<void> _loadPage() async {
    Map<String, dynamic>? pg;
    try {
      final st = await Api.readObj('inbox/statistiques.json');
      final cm = await Api.readObj('inbox/commentaires.json');
      for (final o in [cm?['page'], st?['page']]) {
        if (o is Map<String, dynamic> && o.os('name').isNotEmpty) {
          pg = o;
          break;
        }
      }
    } catch (_) {
      // sans données, l'en-tête garde la marque KI DAS
    }
    if (pg != null && mounted) {
      final page = pg;
      setState(() {
        _pageName = page.os('name');
        _pageUser = page.os('username');
      });
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
    BotNotificationSync.sync();
    _loadPage();
  }

  /* ---------- bouton + : le composer en plein écran ---------- */

  Future<void> _openPlus() async {
    Fx.medium();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SubPage('Composer', child: ComposerScreen()),
      ),
    );
    if (mounted) _refresh();
  }

  /* ---------- menu « ... » : écrans de gestion ---------- */

  Future<void> _openMenu() async {
    Fx.tick();
    final t = await kSheet<String>(
      context,
      title: 'Gestion de la Page',
      children: [
        _sheetRow(
          context,
          'gear',
          'Réglages',
          'set',
          sub: 'Apparence, connexion, sécurité',
        ),
        _sheetRow(
          context,
          'spark',
          'Assistant IA',
          'ia',
          sub: 'Résumés, idées de posts, réponses prêtes',
        ),
        _sheetRow(
          context,
          'shield',
          'Modération',
          'mod',
          sub: 'Commentaires à traiter',
        ),
        _sheetRow(
          context,
          'image',
          'Studio Médias',
          'med',
          sub: 'Bibliothèque, étiquettes, sélection',
        ),
        _sheetRow(
          context,
          'bot',
          'Bot & Règles',
          'bot',
          sub: 'Pilotage, verrous, règles, exécutions',
        ),
        _sheetRow(
          context,
          'doc',
          "Journal d'activité",
          'log',
          sub: 'Application et bot, tout est tracé',
        ),
        _sheetRow(
          context,
          'chart',
          'Rapports d’activité',
          'reports',
          sub: 'Bilans journaliers et hebdomadaires',
        ),
      ],
    );
    if (t == null || !mounted) return;
    final c = context.p;
    final screens = <String, Widget Function()>{
      'ia': () => SubPage(
        'Assistant IA',
        trailing: Press(
          onTap: () => _aiKey.currentState?.reload(),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: c.line),
            ),
            child: Picto('refresh', size: 17, color: c.ink),
          ),
        ),
        child: AiChatScreen(key: _aiKey),
      ),
      'mod': () => const SubPage('Modération', child: ModerationScreen()),
      'med': () => const SubPage('Studio Médias', child: MediasScreen()),
      'bot': () => const SubPage('Bot & Règles', child: BotRulesScreen()),
      'log': () => SubPage(
        "Journal d'activité",
        trailing: Press(
          onTap: () => _logKey.currentState?.toggleFiltres(),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: c.line),
            ),
            child: Picto('filter', size: 17, color: c.ink),
          ),
        ),
        child: JournalScreen(key: _logKey),
      ),
      'reports': () => const SubPage('Rapports', child: ReportsScreen()),
      'set': () => const SubPage('Réglages', child: SettingsScreen()),
    };
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screens[t]!()));
  }

  Widget _sheetRow(
    BuildContext ctx,
    String picto,
    String label,
    String v, {
    String sub = '',
  }) {
    final c = ctx.p;
    return Press(
      onTap: () {
        Fx.tick();
        Navigator.pop(ctx, v);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            /* set-ic maquette : carré 32 chip, picto 15 */
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Picto(picto, size: 18, color: c.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: T.strong(c).copyWith(fontSize: 15)),
                  if (sub.isNotEmpty) Text(sub, style: T.caption(c)),
                ],
              ),
            ),
            Chev(size: 16, color: c.muted),
          ],
        ),
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
          child: Column(
            children: [
              if (_tab == 0 && Api.tok.isNotEmpty) _header(c),
              if (_tab == 0 && Api.tok.isNotEmpty) _banniereJeton(c),
              const BandeauHorsLigne(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: KAnim.med,
                  switchInCurve: KAnim.ease,
                  transitionBuilder: (w, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, .02),
                        end: Offset.zero,
                      ).animate(a),
                      child: w,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey('$_tab-$_gen-${Api.tok.isEmpty}'),
                    child: _screen(_tab),
                  ),
                ),
              ),
            ],
          ),
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
      child: Row(
        children: [
          /* avatar.lg : cercle encré + anneau accent (maquette) */
          Container(
            width: 47,
            height: 47,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.accent, width: 1.5),
            ),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
              child: Text(
                _pageName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: c.bg,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _pageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    badgeVerifie(c, 15),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (_pageUser.isNotEmpty) ...[
                      Flexible(
                        child: Text(
                          '@$_pageUser',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    PulseDot(c.accent, size: 6),
                    const SizedBox(width: 5),
                    Text(
                      'En ligne',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: c.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _ibtn(c, 'search', () {
            Fx.tick();
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const GlobalSearchScreen(),
            ));
          }),
          const SizedBox(width: 6),
          _cloche(c),
          const SizedBox(width: 6),
          _ibtn(c, 'kebab', () {
            _openMenu();
          }),
        ],
      ),
    );
  }

  /* ---------- bannière d'expiration du jeton (Réglages > Connexion) ---------- */

  Widget _banniereJeton(Palette c) {
    final j = Api.joursAvantExp();
    if (j == null || j > 7) return const SizedBox.shrink();
    final bool grave = j <= 3;
    final String titre;
    final String sub;
    if (j < 0) {
      titre = 'Jeton expiré';
      final d = -j;
      sub = 'Depuis $d jour${d > 1 ? 's' : ''} — reconnecte-toi';
    } else if (j == 0) {
      titre = "Le jeton expire aujourd'hui";
      sub = 'Renouvelle-le dans Réglages';
    } else {
      titre = 'Jeton : $j jour${j > 1 ? 's' : ''} restant${j > 1 ? 's' : ''}';
      sub = grave
          ? 'Renouvelle-le vite dans Réglages'
          : 'Pense à le renouveler';
    }
    final Color col = grave ? c.ink : c.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Press(
        onTap: () async {
          Fx.tick();
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ConnexionPage()),
          );
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.withValues(alpha: grave ? .7 : .45)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Picto('clock', size: 15, color: col),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre, style: T.strong(c).copyWith(color: col)),
                    Text(sub, style: T.caption(c)),
                  ],
                ),
              ),
              StatusChip(
                j < 0
                    ? 'Expiré'
                    : j == 0
                    ? 'J-0'
                    : 'J-$j',
                kind: grave ? 3 : 5,
              ),
              const SizedBox(width: 8),
              Chev(size: 15, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cloche(Palette c) {
    return ValueListenableBuilder<int>(
      valueListenable: Bus.avis,
      builder: (_, a, __) => ValueListenableBuilder<int>(
        valueListenable: Bus.msg,
        builder: (_, m, ___) => ValueListenableBuilder<List<NotificationEntry>>(
          valueListenable: NotificationCenter.entries,
          builder: (_, entries, ____) {
            final n = a + m + entries.where((item) => !item.read).length;
            return _ibtn(c, 'bell', () async {
              Fx.tick();
              await NotificationCenter.load();
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SubPage(
                    'Notifications',
                    child: NotificationsScreen(),
                  ),
                ),
              );
            }, badge: n);
          },
        ),
      ),
    );
  }

  Widget _ibtn(Palette c, String picto, VoidCallback f, {int badge = 0}) {
    return Press(
      onTap: f,
      /* app-ic maquette : cercle plein chip, picto 17 */
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(child: Picto(picto, size: 17, color: c.ink)),
            if (badge > 0)
              Positioned(
                right: -5,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 15,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
