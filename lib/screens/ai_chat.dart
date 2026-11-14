import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';

/// Écran de discussion avec l'IA : le contexte de la Page (personnalisation,
/// ligne éditoriale, faits, chiffres, commentaires en attente) est injecté au
/// démarrage, la conversation est sauvegardée dans glm/chat.json (dépôt de
/// données) pour la retrouver même après une réinstallation.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

/// Un message de la discussion (local ou chargé du dépôt).
class _Msg {
  final bool me;
  final String t;
  final int at;
  const _Msg(this.me, this.t, this.at);
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _ta = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  String _ctx = '';
  bool _loading = true, _thinking = false, _failed = false;

  static const _suggestions = [
    'Résume ce qui attend ma réponse sur la Page.',
    'Propose 3 idées de publications pour cette semaine.',
    'Que disent les derniers commentaires ?',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ta.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<dynamic> hist = const [];
    var ctx = '';
    await Future.wait<dynamic>([
      Api.readArr('glm/chat.json')
          .then((v) { hist = v; })
          .catchError((Object e) {}),
      Ai.context().then((v) { ctx = v; }).catchError((Object e) {}),
    ]);
    if (!mounted) return;
    setState(() {
      _ctx = ctx;
      for (final e in hist) {
        final m = asObj(e);
        final t = m.os('t');
        if (t.isEmpty) continue;
        _msgs.add(_Msg(m.os('r') == 'u', t, Api.iso(m.os('at'))));
      }
      if (_msgs.length > 80) _msgs.removeRange(0, _msgs.length - 80);
      _loading = false;
    });
    _bottom();
  }

  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Historique récent envoyé au modèle (le contexte système est déjà là).
  List<Map<String, String>> _apiMsgs() {
    final out = <Map<String, String>>[
      {'role': 'system', 'content': _ctx},
    ];
    final hist = _msgs.where((m) => m.t.isNotEmpty).toList();
    final start = hist.length > 14 ? hist.length - 14 : 0;
    for (var i = start; i < hist.length; i++) {
      out.add({
        'role': hist[i].me ? 'user' : 'assistant',
        'content': hist[i].t,
      });
    }
    return out;
  }

  Future<void> _save(String role, String text) async {
    await Api.updateJson('glm/chat.json', true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList()
        ..add({'r': role, 't': text, 'at': Api.isoNow()});
      return a;
    }, 'Assistant IA');
  }

  Future<void> _send(String raw) async {
    final t = raw.trim();
    if (t.isEmpty || _thinking) return;
    Fx.tick();
    setState(() {
      _msgs.add(_Msg(true, t, DateTime.now().millisecondsSinceEpoch));
      _thinking = true;
      _failed = false;
      _ta.clear();
    });
    _bottom();
    try {
      await _save('u', t);
      final reply = await Ai.chat(_apiMsgs());
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(false, reply, DateTime.now().millisecondsSinceEpoch));
        _thinking = false;
      });
      _bottom();
      await _save('a', reply);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _failed = true;
      });
      kToast(context, Api.hint(e), bad: true);
    }
  }

  Future<void> _retry() async {
    if (_thinking) return;
    setState(() => _thinking = true);
    try {
      final reply = await Ai.chat(_apiMsgs());
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(false, reply, DateTime.now().millisecondsSinceEpoch));
        _thinking = false;
        _failed = false;
      });
      _bottom();
      await _save('a', reply);
    } catch (e) {
      if (!mounted) return;
      setState(() => _thinking = false);
      kToast(context, Api.hint(e), bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          KSkeleton(60),
          SizedBox(height: 10),
          KSkeleton(40, radius: 14),
          SizedBox(height: 10),
          KSkeleton(60),
        ],
      );
    }
    return Column(children: [
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          children: [
            _intro(c),
            for (var i = 0; i < _msgs.length; i++) _bubble(c, _msgs[i]),
            if (_thinking) _typing(c),
            if (_failed && !_thinking) _retryChip(c),
            const SizedBox(height: 4),
          ],
        ),
      ),
      _input(c),
    ]);
  }

  /* ---------- état vide + suggestions ---------- */

  Widget _intro(Palette c) {
    if (_msgs.isNotEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ton assistant IA', style: T.title(c)),
        const SizedBox(height: 6),
        Text(
          'Il connaît ta ligne éditoriale, tes chiffres et les commentaires en '
          'attente. Demande un résumé, une réponse à préparer ou des idées de posts.',
          style: T.body(c).copyWith(color: c.muted),
        ),
        const SizedBox(height: 12),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Press(
              onTap: () => _send(s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line)),
                child: Row(children: [
                  Icon(Icons.auto_awesome, size: 15, color: c.accent),
                  const SizedBox(width: 9),
                  Expanded(child: Text(s, style: T.body(c))),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  /* ---------- bulles ---------- */

  Widget _bubble(Palette c, _Msg m) {
    return Container(
      margin: EdgeInsets.only(
          top: 8, left: m.me ? 44 : 0, right: m.me ? 0 : 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: m.me ? c.accent : c.card,
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomLeft:
              m.me ? const Radius.circular(16) : const Radius.circular(4),
          bottomRight:
              m.me ? const Radius.circular(4) : const Radius.circular(16),
        ),
        border: m.me ? null : Border.all(color: c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(m.t,
            style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: m.me ? c.onAccent : c.ink)),
        const SizedBox(height: 3),
        Text(m.at <= 0 ? '' : relMs(m.at),
            style: TextStyle(
                fontSize: 10.5,
                color: m.me
                    ? c.onAccent.withValues(alpha: .8)
                    : c.muted)),
      ]),
    );
  }

  Widget _typing(Palette c) {
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line)),
      child: Row(children: [
        SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(c.accent))),
        const SizedBox(width: 9),
        Text("L'IA écrit…", style: T.caption(c)),
      ]),
    );
  }

  Widget _retryChip(Palette c) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Press(
        onTap: _retry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: c.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh, size: 14, color: c.ink),
            const SizedBox(width: 6),
            Text('Réessayer',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: c.ink)),
          ]),
        ),
      ),
    );
  }

  /* ---------- barre de saisie ---------- */

  Widget _input(Palette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(color: c.bg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: KEdit(
            controller: _ta,
            hint: 'Écris à ton assistant…',
            minLines: 1,
            maxLines: 4,
          ),
        ),
        const SizedBox(width: 8),
        Press(
          onTap: _thinking ? null : () => _send(_ta.text),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: _thinking ? c.muted : c.accent,
                shape: BoxShape.circle),
            child: _thinking
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(c.onAccent)))
                : Icon(Icons.send_rounded, size: 19, color: c.onAccent),
          ),
        ),
      ]),
    );
  }
}
