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
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            children: [
              if (_msgs.isEmpty) _accueil(c),
              for (var i = 0; i < _msgs.length; i++)
                _bubble(
                  c,
                  _msgs[i],
                  relances:
                      !_thinking &&
                      !_failed &&
                      !_msgs[i].me &&
                      i == _msgs.length - 1,
                ),
              if (_thinking) _typing(c),
              if (_failed && !_thinking) _retryChip(c),
              const SizedBox(height: 4),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bubble(c, _Msg(false, _bonjour(), 0)),
        const SizedBox(height: 18),
        Text('Pour commencer', style: T.title(c)),
        const SizedBox(height: 8),
        for (final (label, prompt) in _sugg)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Press(
              onTap: () => _send(prompt),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 15, color: c.accent),
                    const SizedBox(width: 9),
                    Expanded(child: Text(label, style: T.body(c))),
                  ],
                ),
              ),
            ),
          ),
      ],
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
    return Container(
      margin: EdgeInsets.only(
        top: 8,
        left: m.me ? 44 : 0,
        right: m.me ? 0 : 44,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: m.me ? c.accent : c.card2,
        borderRadius: BorderRadius.circular(16).copyWith(
          topLeft: m.me ? const Radius.circular(16) : const Radius.circular(4),
          topRight: m.me ? const Radius.circular(4) : const Radius.circular(16),
        ),
        border: m.me ? null : Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            m.t,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: m.me ? c.onAccent : c.ink,
            ),
          ),
          if (m.at > 0) ...[
            const SizedBox(height: 3),
            Text(
              relMs(m.at),
              style: TextStyle(
                fontSize: 10.5,
                color: m.me ? c.onAccent.withValues(alpha: .8) : c.muted,
              ),
            ),
          ],
          if (relances) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, prompt) in _relances)
                  Press(
                    onTap: _thinking ? null : () => _send(prompt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(6, 5, 5, 5),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ta,
              minLines: 1,
              maxLines: 4,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
              cursorColor: c.accent,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                counterText: '',
                hintText: "Écrire à l'IA…",
                hintStyle: TextStyle(fontSize: 13.5, color: c.muted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Press(
            onTap: _thinking ? null : () => _send(_ta.text),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _thinking ? c.muted : c.accent,
                shape: BoxShape.circle,
              ),
              child: _thinking
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(c.onAccent),
                      ),
                    )
                  : Icon(Icons.send_rounded, size: 16, color: c.onAccent),
            ),
          ),
        ],
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
