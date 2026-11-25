import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/shell.dart' show Bus;

/// Écran de discussion avec l'IA selon la maquette 08 : accueil avec les
/// compteurs réels de la Page, bulles aux coins maquette, relances rapides
/// dans la dernière réponse, indicateur « l'IA écrit » à trois points,
/// chips de suggestion pointillées et barre de saisie en pilule. La
/// conversation est sauvegardée dans glm/chat.json (dépôt de données) et le
/// relais Actions écrit la réponse au même endroit : on la retrouve même
/// après une réinstallation.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  AiChatScreenState createState() => AiChatScreenState();
}

/// State public : le bouton d'actualisation de l'en-tête (SubPage) appelle
/// [reload] pour relire l'historique et le contexte depuis le dépôt.
class AiChatScreenState extends State<AiChatScreen> {
  final _ta = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _loading = true, _thinking = false, _failed = false;

  /* chips de la maquette : rédiger / idées / résumé semaine */
  static const _sugg = [
    (
      'Rédiger un post',
      'Écris un post Facebook engageant pour la Page, en français, 3 à 5 phrases.',
    ),
    ('Idées de contenu', 'Propose 3 idées de publications pour cette semaine.'),
    (
      'Résumé semaine',
      'Résume la semaine : abonnés, interactions, commentaires en attente et délai de réponse moyen.',
    ),
  ];

  /* relances dans la dernière réponse IA (mini-chips de la maquette) */
  static const _relances = [
    (
      "Répondre à l'urgence",
      'Propose une réponse polie et utile au commentaire le plus récent sans réponse, prête à envoyer.',
    ),
    (
      'Tout répondre',
      'Propose une réponse prête à envoyer pour chaque commentaire en attente, une par ligne.',
    ),
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

  /// Recharge l'historique et le contexte (bouton d'actualisation).
  void reload() => _load();

  Future<void> _load() async {
    List<dynamic> hist = const [];
    try {
      hist = await Api.readArr('glm/chat.json');
    } catch (_) {
      hist = const [];
    }
    if (!mounted) return;
    setState(() {
      _msgs.clear();
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
      final reply = await Ai.chat();
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(false, reply, DateTime.now().millisecondsSinceEpoch));
        _thinking = false;
      });
      _bottom();
      /* la réponse est déjà persistée par le relais dans glm/chat.json */
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
      final reply = await Ai.chat();
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(false, reply, DateTime.now().millisecondsSinceEpoch));
        _thinking = false;
        _failed = false;
      });
      _bottom();
      /* la réponse est déjà persistée par le relais dans glm/chat.json */
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
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: const [
            KSkeleton(74),
            SizedBox(height: 12),
            KSkeleton(52),
            SizedBox(height: 9),
            KSkeleton(64),
            Spacer(),
            KSkeleton(42),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            children: [
              if (_msgs.isEmpty) _accueil(c),
              for (var i = 0; i < _msgs.length; i++)
                _bubble(
                  c,
                  _msgs[i],
                  relances: !_thinking && !_failed && !_msgs[i].me && i == _msgs.length - 1,
                ),
              if (_thinking) _typing(c),
              if (_failed && !_thinking) _retryChip(c),
              const SizedBox(height: 8),
            ],
          ),
        ),
        _suggBar(c),
        _input(c),
      ],
    );
  }

  /* ---------- accueil : bulle + compteurs réels (maquette) ---------- */

  String _bonjour() {
    final avis = Bus.avis.value, msg = Bus.msg.value;
    if (avis > 0 && msg > 0) {
      return 'Bonjour. $avis avis en attente, $msg messages non lus. '
          'Je peux résumer la journée ou répondre à l\'urgence.';
    }
    if (avis > 0) {
      return 'Bonjour. $avis avis en attente. Je peux résumer la journée '
          'ou préparer tes réponses.';
    }
    if (msg > 0) {
      return 'Bonjour. $msg messages non lus. Je peux résumer la journée '
          'ou préparer tes réponses.';
    }
    return 'Bonjour. Tout est à jour sur la Page. Je peux rédiger un post, '
        'proposer des idées ou résumer la semaine.';
  }

  Widget _accueil(Palette c) {
    final avis = Bus.avis.value;
    final messages = Bus.msg.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.waving_hand_outlined, color: c.accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Bonjour 👋', style: T.title(c))),
                ],
              ),
              const SizedBox(height: 10),
              Text(_bonjour(), style: T.body(c).copyWith(height: 1.5)),
              if (avis > 0 || messages > 0) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (avis > 0) _contextPill(c, Icons.rate_review_outlined, '$avis avis en attente'),
                    if (messages > 0) _contextPill(c, Icons.mark_unread_chat_alt_outlined, '$messages messages non lus'),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('Que voulez-vous faire ?', style: T.title(c)),
        const SizedBox(height: 4),
        Text('Choisissez un raccourci ou écrivez votre demande.', style: T.caption(c)),
        const SizedBox(height: 10),
        for (var i = 0; i < _sugg.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Press(
              onTap: _thinking ? null : () => _send(_sugg[i].$2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(11)),
                      child: Icon(
                        [Icons.edit_note_rounded, Icons.lightbulb_outline_rounded, Icons.insights_rounded][i],
                        size: 18,
                        color: c.accent,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(child: Text(_sugg[i].$1, style: T.strong(c).copyWith(fontSize: 13))),
                    Icon(Icons.arrow_forward_rounded, size: 17, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _contextPill(Palette c, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c.accent),
          const SizedBox(width: 5),
          Text(label, style: T.caption(c).copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }

  /* ---------- chips de suggestion pointillées (maquette sugg) ---------- */

  Widget _suggBar(Palette c) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shrinkWrap: true,
        children: [
          for (final (label, prompt) in _sugg)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Press(
                onTap: _thinking ? null : () => _send(prompt),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: CustomPaint(
                    painter: _DashedLine(c.line),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /* ---------- bulles ---------- */

  Widget _bubble(Palette c, _Msg m, {bool relances = false}) {
    return Padding(
      padding: EdgeInsets.only(top: 10, left: m.me ? 42 : 0, right: m.me ? 0 : 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: m.me ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!m.me) ...[
            Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(color: c.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.auto_awesome_rounded, size: 15, color: c.accent),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: m.me ? c.accent : c.card,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: m.me ? const Radius.circular(4) : const Radius.circular(16),
                  bottomLeft: m.me ? const Radius.circular(16) : const Radius.circular(4),
                ),
                border: m.me ? null : Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _messageContent(c, m),
                  if (m.at > 0) ...[
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        relMs(m.at),
                        style: TextStyle(fontSize: 10, color: m.me ? c.onAccent.withValues(alpha: .78) : c.muted),
                      ),
                    ),
                  ],
                  if (relances) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (label, prompt) in _relances)
                          Press(
                            onTap: _thinking ? null : () => _send(prompt),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: c.soft,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: c.line),
                              ),
                              child: Text(label, style: T.caption(c).copyWith(color: c.ink, fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (m.me) ...[
            const SizedBox(width: 7),
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
              child: Icon(Icons.person_outline_rounded, size: 15, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// Rendu Markdown léger sans dépendance externe.
  Widget _messageContent(Palette c, _Msg m) {
    final color = m.me ? c.onAccent : c.ink;
    final lines = m.t.replaceAll('\r\n', '\n').split('\n');
    final spans = <InlineSpan>[];
    var inCode = false;
    final fence = List.filled(3, String.fromCharCode(96)).join();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith(fence)) { inCode = !inCode; continue; }
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      if (line.trim().isEmpty) continue;
      if (inCode) {
        spans.add(TextSpan(text: line, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color)));
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.+)
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 44),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: c.line),
      ),
      child: const _Dots(),
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
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 14, color: c.ink),
              const SizedBox(width: 6),
              Text(
                'Réessayer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------- barre de saisie en pilule (maquette chatbar) ---------- */

  Widget _input(Palette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 5, 5, 5),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ta,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _thinking ? null : _send,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: "Posez votre question à l'IA…",
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: _thinking ? null : () => _send(_ta.text),
                child: Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(color: _thinking ? c.muted : c.accent, shape: BoxShape.circle),
                  child: _thinking
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(c.onAccent)),
                        )
                      : Icon(Icons.arrow_upward_rounded, size: 19, color: c.onAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/* ---------- indicateur « l'IA écrit » : trois points (maquette dots) ---------- */

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          FadeTransition(
            opacity: Tween(begin: .25, end: 1.0).animate(
              CurvedAnimation(
                parent: _a,
                curve: Interval(i * .2, i * .2 + .5, curve: Curves.easeInOut),
              ),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
            ),
          ),
        ],
      ],
    );
  }
}

/* ---------- bordure pointillée des chips de suggestion ---------- */

class _DashedLine extends CustomPainter {
  final Color color;
  _DashedLine(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(99),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final e = (d + 4).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, e), paint);
        d = e + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

/// Un message de la discussion (local ou chargé du dépôt).
class _Msg {
  final bool me;
  final String t;
  final int at;
  const _Msg(this.me, this.t, this.at);
}
).firstMatch(line);
      final bullet = RegExp(r'^\s*[-*]\s+(.+)
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 44),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: c.line),
      ),
      child: const _Dots(),
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
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 14, color: c.ink),
              const SizedBox(width: 6),
              Text(
                'Réessayer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------- barre de saisie en pilule (maquette chatbar) ---------- */

  Widget _input(Palette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 5, 5, 5),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ta,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _thinking ? null : _send,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: "Posez votre question à l'IA…",
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: _thinking ? null : () => _send(_ta.text),
                child: Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(color: _thinking ? c.muted : c.accent, shape: BoxShape.circle),
                  child: _thinking
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(c.onAccent)),
                        )
                      : Icon(Icons.arrow_upward_rounded, size: 19, color: c.onAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/* ---------- indicateur « l'IA écrit » : trois points (maquette dots) ---------- */

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          FadeTransition(
            opacity: Tween(begin: .25, end: 1.0).animate(
              CurvedAnimation(
                parent: _a,
                curve: Interval(i * .2, i * .2 + .5, curve: Curves.easeInOut),
              ),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
            ),
          ),
        ],
      ],
    );
  }
}

/* ---------- bordure pointillée des chips de suggestion ---------- */

class _DashedLine extends CustomPainter {
  final Color color;
  _DashedLine(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(99),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final e = (d + 4).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, e), paint);
        d = e + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

/// Un message de la discussion (local ou chargé du dépôt).
class _Msg {
  final bool me;
  final String t;
  final int at;
  const _Msg(this.me, this.t, this.at);
}
).firstMatch(line);
      final numbered = RegExp(r'^\s*\d+[.)]\s+(.+)
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 44),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: c.line),
      ),
      child: const _Dots(),
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
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 14, color: c.ink),
              const SizedBox(width: 6),
              Text(
                'Réessayer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------- barre de saisie en pilule (maquette chatbar) ---------- */

  Widget _input(Palette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 5, 5, 5),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ta,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _thinking ? null : _send,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: "Posez votre question à l'IA…",
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: _thinking ? null : () => _send(_ta.text),
                child: Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(color: _thinking ? c.muted : c.accent, shape: BoxShape.circle),
                  child: _thinking
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(c.onAccent)),
                        )
                      : Icon(Icons.arrow_upward_rounded, size: 19, color: c.onAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/* ---------- indicateur « l'IA écrit » : trois points (maquette dots) ---------- */

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          FadeTransition(
            opacity: Tween(begin: .25, end: 1.0).animate(
              CurvedAnimation(
                parent: _a,
                curve: Interval(i * .2, i * .2 + .5, curve: Curves.easeInOut),
              ),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
            ),
          ),
        ],
      ],
    );
  }
}

/* ---------- bordure pointillée des chips de suggestion ---------- */

class _DashedLine extends CustomPainter {
  final Color color;
  _DashedLine(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(99),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final e = (d + 4).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, e), paint);
        d = e + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

/// Un message de la discussion (local ou chargé du dépôt).
class _Msg {
  final bool me;
  final String t;
  final int at;
  const _Msg(this.me, this.t, this.at);
}
).firstMatch(line);
      final quote = RegExp(r'^\s*>\s?(.*)
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 44),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: c.line),
      ),
      child: const _Dots(),
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
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 14, color: c.ink),
              const SizedBox(width: 6),
              Text(
                'Réessayer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------- barre de saisie en pilule (maquette chatbar) ---------- */

  Widget _input(Palette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 5, 5, 5),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ta,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _thinking ? null : _send,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: "Posez votre question à l'IA…",
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: _thinking ? null : () => _send(_ta.text),
                child: Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(color: _thinking ? c.muted : c.accent, shape: BoxShape.circle),
                  child: _thinking
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(c.onAccent)),
                        )
                      : Icon(Icons.arrow_upward_rounded, size: 19, color: c.onAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/* ---------- indicateur « l'IA écrit » : trois points (maquette dots) ---------- */

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          FadeTransition(
            opacity: Tween(begin: .25, end: 1.0).animate(
              CurvedAnimation(
                parent: _a,
                curve: Interval(i * .2, i * .2 + .5, curve: Curves.easeInOut),
              ),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
            ),
          ),
        ],
      ],
    );
  }
}

/* ---------- bordure pointillée des chips de suggestion ---------- */

class _DashedLine extends CustomPainter {
  final Color color;
  _DashedLine(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(99),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final e = (d + 4).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, e), paint);
        d = e + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

/// Un message de la discussion (local ou chargé du dépôt).
class _Msg {
  final bool me;
  final String t;
  final int at;
  const _Msg(this.me, this.t, this.at);
}
).firstMatch(line);
      if (heading != null) {
        spans.addAll(_inlineMarkdown(heading.group(2)!, color, weight: FontWeight.w800, size: heading.group(1)!.length == 1 ? 16 : 14));
      } else if (bullet != null) {
        spans.add(const TextSpan(text: '•  '));
        spans.addAll(_inlineMarkdown(bullet.group(1)!, color));
      } else if (numbered != null) {
        spans.addAll(_inlineMarkdown(line.trimLeft(), color));
      } else if (quote != null) {
        spans.add(TextSpan(text: '│  ', style: TextStyle(color: c.accent)));
        spans.addAll(_inlineMarkdown(quote.group(1)!, color, italic: true));
      } else {
        spans.addAll(_inlineMarkdown(line, color));
      }
    }
    return SelectableText.rich(TextSpan(children: spans, style: TextStyle(fontSize: 13.5, height: 1.55, color: color)));
  }

  List<InlineSpan> _inlineMarkdown(String text, Color color, {FontWeight weight = FontWeight.normal, double size = 13.5, bool italic = false}) {
    final out = <InlineSpan>[];
    final tick = String.fromCharCode(96);
    final pattern = RegExp(r'(\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_|' + tick + '[^' + tick + ']+' + tick + r')');
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) out.add(TextSpan(text: text.substring(start, match.start)));
      final token = match.group(0)!;
      final code = token.startsWith(tick);
      final bold = token.startsWith('**') || token.startsWith('__');
      final content = token.substring(bold || code ? 2 : 1, token.length - (bold || code ? 2 : 1));
      out.add(TextSpan(text: content, style: TextStyle(
        fontWeight: bold ? FontWeight.w800 : weight,
        fontStyle: (!bold && !code) || italic ? FontStyle.italic : FontStyle.normal,
        fontFamily: code ? 'monospace' : null,
        fontSize: code ? 12 : size,
        color: color,
        backgroundColor: code ? Colors.black.withValues(alpha: .10) : null,
      )));
      start = match.end;
    }
    if (start < text.length) out.add(TextSpan(text: text.substring(start)));
    return out;
  }

  Widget _typing(Palette c) {
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 44),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: c.line),
      ),
      child: const _Dots(),
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
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 14, color: c.ink),
              const SizedBox(width: 6),
              Text(
                'Réessayer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------- barre de saisie en pilule (maquette chatbar) ---------- */

  Widget _input(Palette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 5, 5, 5),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ta,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _thinking ? null : _send,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: "Posez votre question à l'IA…",
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: _thinking ? null : () => _send(_ta.text),
                child: Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(color: _thinking ? c.muted : c.accent, shape: BoxShape.circle),
                  child: _thinking
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(c.onAccent)),
                        )
                      : Icon(Icons.arrow_upward_rounded, size: 19, color: c.onAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/* ---------- indicateur « l'IA écrit » : trois points (maquette dots) ---------- */

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          FadeTransition(
            opacity: Tween(begin: .25, end: 1.0).animate(
              CurvedAnimation(
                parent: _a,
                curve: Interval(i * .2, i * .2 + .5, curve: Curves.easeInOut),
              ),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
            ),
          ),
        ],
      ],
    );
  }
}

/* ---------- bordure pointillée des chips de suggestion ---------- */

class _DashedLine extends CustomPainter {
  final Color color;
  _DashedLine(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(99),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final e = (d + 4).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, e), paint);
        d = e + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

/// Un message de la discussion (local ou chargé du dépôt).
class _Msg {
  final bool me;
  final String t;
  final int at;
  const _Msg(this.me, this.t, this.at);
}
