import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';

/* ---------- action annulée par l'utilisateur (pas de toast) ---------- */

class Cancelled implements Exception {
  @override
  String toString() => 'Annulé.';
}

/* ---------- presse : échelle + ressort + haptique ---------- */

class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  const Press(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.haptic = true});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? .96 : 1,
        duration: KAnim.fast,
        curve: _down ? Curves.easeOut : KAnim.spring,
        child: widget.child,
      ),
    );
  }
}

/* ---------- carte ---------- */

class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry pad;
  final Color? color;
  final double radius;
  final Border? border;
  const KCard(
      {super.key,
      required this.child,
      this.pad = const EdgeInsets.all(14),
      this.color,
      this.radius = KDim.rCard,
      this.border});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/* ---------- carte héros inversée (encre sur fond, ou l'inverse) ---------- */

class KHero extends StatelessWidget {
  final Widget child;
  const KHero({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.heroBg,
        borderRadius: BorderRadius.circular(KDim.rCard),
      ),
      child: child,
    );
  }
}

/* ---------- titre de section + règle encre 2px ---------- */

class KSection extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const KSection(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: T.title(c))),
        if (action != null)
          Press(
            onTap: onAction,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(action!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.accent))),
          ),
      ]),
      const SizedBox(height: 6),
      Container(
          height: 2,
          decoration: BoxDecoration(
              color: c.ink, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 10),
    ]);
  }
}

/* ---------- badge pastille ---------- */

class KBadge extends StatelessWidget {
  final String label;
  final Color? bg, fg;
  const KBadge(this.label, {super.key, this.bg, this.fg});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
          color: bg ?? c.ink, borderRadius: BorderRadius.circular(KDim.rBadge)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: fg ?? c.bg)),
    );
  }
}

/* ---------- pastille de statut animée (live) ---------- */

class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot(this.color, {super.key, this.size = 9});
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.6,
      height: widget.size * 2.6,
      child: Stack(alignment: Alignment.center, children: [
        FadeTransition(
          opacity: Tween(begin: .5, end: 0.0).animate(
              CurvedAnimation(parent: _a, curve: Curves.easeOut)),
          child: ScaleTransition(
            scale: Tween(begin: .6, end: 1.9).animate(
                CurvedAnimation(parent: _a, curve: Curves.easeOut)),
            child: Container(
                width: widget.size * 1.6,
                height: widget.size * 1.6,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle)),
          ),
        ),
        Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
                color: widget.color, shape: BoxShape.circle)),
      ]),
    );
  }
}

/* ---------- boutons ---------- */

class KBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color? bg, fg;
  const KBtn(this.label, {super.key, this.onTap, this.busy = false, this.bg, this.fg});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Press(
      onTap: busy ? null : onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (busy ? c.muted : (bg ?? c.accent)),
          borderRadius: BorderRadius.circular(KDim.rBtn),
        ),
        child: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(fg ?? c.onAccent)))
            : Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    letterSpacing: .2, color: fg ?? c.onAccent)),
      ),
    );
  }
}

class KBtnGhost extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const KBtnGhost(this.label, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Press(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(KDim.rBtn),
          border: Border.all(color: c.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: c.ink)),
      ),
    );
  }
}

/* ---------- toast ---------- */

void kToast(BuildContext context, String msg, {bool bad = false}) {
  final c = context.p;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: c.bg)),
      backgroundColor: c.ink,
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 78),
      duration: Duration(seconds: bad ? 5 : 2),
    ));
}

/* ---------- feuille du bas (menu +, réponses) ---------- */

Future<S?> kSheet<S>(BuildContext context,
    {required String title, required List<Widget> children}) {
  final c = context.p;
  return showModalBottomSheet<S>(
    context: context,
    backgroundColor: c.card,
    barrierColor: Colors.black.withValues(alpha: .45),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(99))),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(title, style: T.title(context.p)),
          ),
          ...children,
        ]),
      ),
    ),
  );
}

/* ---------- état vide ---------- */

class KEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? sub;
  const KEmpty(this.icon, this.text, {super.key, this.sub});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line)),
            child: Icon(icon, size: 24, color: c.muted),
          ),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: T.strong(c)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, textAlign: TextAlign.center, style: T.caption(c)),
          ],
        ]),
      ),
    );
  }
}

/* ---------- squelette de chargement ---------- */

class KSkeleton extends StatefulWidget {
  final double height;
  final double radius;
  const KSkeleton(this.height, {super.key, this.radius = 12});
  @override
  State<KSkeleton> createState() => _KSkeletonState();
}

class _KSkeletonState extends State<KSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return FadeTransition(
      opacity: Tween(begin: .35, end: .75).animate(
          CurvedAnimation(parent: _a, curve: Curves.easeInOut)),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/* ---------- champ icône carré (feuille +, lignes de liste) ---------- */

class IconBox extends StatelessWidget {
  final IconData icon;
  final double size;
  const IconBox(this.icon, {super.key, this.size = 18});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line)),
      child: Icon(icon, size: size, color: c.ink),
    );
  }
}

/* ---------- pastille de statut (port de Ui.chip) ---------- */

/// kind : 0 neutre, 1 ok, 2 attention, 3 erreur (inversée), 4 en cours,
/// 5 accent (live).
class StatusChip extends StatelessWidget {
  final String label;
  final int kind;
  const StatusChip(this.label, {super.key, this.kind = 0});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    Color fg = c.muted, bg = c.line;
    if (kind == 1 || kind == 2) {
      fg = c.ink;
      bg = c.soft;
    } else if (kind == 3) {
      fg = c.bg;
      bg = c.ink;
    } else if (kind == 4) {
      fg = c.muted;
      bg = c.soft;
    } else if (kind == 5) {
      fg = c.onAccent;
      bg = c.accent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label,
          style:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/* ---------- séparateur fin ---------- */

class KDivider extends StatelessWidget {
  const KDivider({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 10),
        color: context.p.line);
  }
}

/* ---------- bouton d'action avec occupé + erreurs (port de doAct) ---------- */

class ActionBtn extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function() job;
  final String? ok; // message de succès
  final VoidCallback? after;
  final KBtnVariant variant;
  final double height;
  const ActionBtn(this.label,
      {super.key,
      this.icon,
      required this.job,
      this.ok,
      this.after,
      this.variant = KBtnVariant.accent,
      this.height = 44});
  @override
  State<ActionBtn> createState() => _ActionBtnState();
}

enum KBtnVariant { accent, ghost, danger }

class _ActionBtnState extends State<ActionBtn> {
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    Fx.tick();
    try {
      await widget.job();
      if (!mounted) return;
      if (widget.ok != null) kToast(context, widget.ok!);
      setState(() => _busy = false);
      widget.after?.call();
    } on Cancelled {
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      Fx.error();
      kToast(context, Api.hint(e), bad: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final accent = widget.variant == KBtnVariant.accent;
    final danger = widget.variant == KBtnVariant.danger;
    return Press(
      onTap: _busy ? null : _go,
      child: Opacity(
        opacity: _busy ? .6 : 1,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent
                ? c.accent
                : danger
                    ? c.soft
                    : c.card,
            borderRadius: BorderRadius.circular(KDim.rBtn),
            border: Border.all(
                color: accent ? c.accent : danger ? c.line : c.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_busy) ...[
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(accent ? c.onAccent : c.ink))),
              const SizedBox(width: 8),
            ] else if (widget.icon != null) ...[
              Icon(widget.icon,
                  size: 16, color: accent ? c.onAccent : c.ink),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                      color: accent ? c.onAccent : c.ink)),
            ),
          ]),
        ),
      ),
    );
  }
}

/* ---------- ligne de routage (port de RulesScreen.routeRow) ---------- */

class RouteRow extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  final Widget? trailing;
  const RouteRow(this.icon, this.label,
      {super.key, required this.sub, required this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Press(
      onTap: () {
        Fx.tick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          IconBox(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: T.strong(c).copyWith(fontSize: 14.5)),
              Text(sub, style: T.caption(c)),
            ]),
          ),
          trailing ?? Icon(Icons.chevron_right, size: 18, color: c.muted),
        ]),
      ),
    );
  }
}

/* ---------- ligne de règle du bot (port de ruleRow) ---------- */

class RuleRow extends StatelessWidget {
  final String label, desc;
  final bool active;
  const RuleRow(this.label, {super.key, required this.desc, required this.active});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: T.strong(c).copyWith(fontSize: 14.5)),
            Text(desc, style: T.caption(c)),
          ]),
        ),
        const SizedBox(width: 8),
        StatusChip(active ? 'Actif' : 'Coupé', kind: active ? 1 : 0),
      ]),
    );
  }
}

/* ---------- exécution GitHub Actions (port de runRow / runChip) ---------- */

Widget runChip(BuildContext context, Map<String, dynamic> r) {
  final st = r.os('status');
  if (st != 'completed') {
    return StatusChip(st == 'queued' ? 'En file' : 'En cours', kind: 5);
  }
  final cl = r.os('conclusion');
  if (cl == 'success') return const StatusChip('Réussi', kind: 1);
  if (cl == 'failure' || cl == 'timed_out') return const StatusChip('Échec', kind: 3);
  if (cl == 'cancelled') return const StatusChip('Annulé', kind: 0);
  return StatusChip(cl == 'skipped' ? 'Ignoré' : (cl.isEmpty ? '?' : cl), kind: 0);
}

class RunRow extends StatelessWidget {
  final Map<String, dynamic> r;
  final bool withCancel;
  final VoidCallback? after;
  const RunRow(this.r, {super.key, this.withCancel = false, this.after});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.os('name').isEmpty ? 'Workflow' : r.os('name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.strong(c).copyWith(fontSize: 14.5)),
          Text(_desc(), style: T.caption(c)),
        ]),
      ),
      const SizedBox(width: 8),
      runChip(context, r),
      if (withCancel && r.os('status') != 'completed') ...[
        const SizedBox(width: 8),
        _CancelBtn(id: r.oi('id'), after: after),
      ],
    ]);
  }

  String _desc() {
    var d = '';
    if (r.os('status') == 'completed' && r.os('run_started_at').isNotEmpty) {
      final a = iso(r.os('run_started_at')), b = iso(r.os('updated_at'));
      if (a > 0 && b >= a) d = ' · ${dur(b - a)}';
    }
    return rel(r.os('created_at')) + d;
  }
}

class _CancelBtn extends StatefulWidget {
  final int id;
  final VoidCallback? after;
  const _CancelBtn({required this.id, this.after});
  @override
  State<_CancelBtn> createState() => _CancelBtnState();
}

class _CancelBtnState extends State<_CancelBtn> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Press(
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              Fx.tick();
              try {
                await Api.cancelRun(widget.id);
                await Future.delayed(const Duration(milliseconds: 800));
                if (mounted) kToast(context, 'Annulation demandée.');
                widget.after?.call();
              } catch (e) {
                if (mounted) kToast(context, Api.hint(e), bad: true);
              }
              if (mounted) setState(() => _busy = false);
            },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.line)),
        child: _busy
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: CircularProgressIndicator(
                    strokeWidth: 2, valueColor: AlwaysStoppedAnimation(c.ink)))
            : Icon(Icons.close, size: 15, color: c.ink),
      ),
    );
  }
}
