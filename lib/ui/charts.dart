import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';
import '../core/util.dart';

/* ---------- courbe lissée qui se dessine, info-bulle au toucher ---------- */

class LineChart extends StatefulWidget {
  final List<double> vals;
  final List<String?>? labs;
  final Color color;
  const LineChart(this.vals, {super.key, this.labs, required this.color});
  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  int _sel = -1;

  @override
  void initState() {
    super.initState();
    _a.forward();
  }

  @override
  void didUpdateWidget(covariant LineChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.vals, widget.vals)) {
      _sel = -1;
      _a.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  void _pick(int i) {
    if (i < 0 || i >= widget.vals.length) return;
    if (_sel != i) {
      setState(() => _sel = i);
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return GestureDetector(
      onTapDown: (d) => _pick(_nearest(d.localPosition.dx)),
      onHorizontalDragUpdate: (d) => _pick(_nearest(d.localPosition.dx)),
      child: AnimatedBuilder(
        animation: _a,
        builder: (ctx, _) => CustomPaint(
          size: const Size(double.infinity, 200),
          painter: _LinePainter(
            vals: widget.vals,
            labs: widget.labs,
            color: widget.color,
            prog: CurvedAnimation(parent: _a, curve: Curves.easeOutCubic).value,
            sel: _sel,
            line: c.line,
            soft: c.soft,
            ink: c.ink,
            muted: c.muted,
            card: c.card,
          ),
        ),
      ),
    );
  }

  int _nearest(double x) {
    final n = widget.vals.length;
    if (n < 2) return -1;
    final rb = context.findRenderObject() as RenderBox;
    const l = 10.0;
    final r = rb.size.width - 10.0;
    final i = ((x - l) / (r - l) * (n - 1)).round();
    return i.clamp(0, n - 1);
  }
}

class _LinePainter extends CustomPainter {
  final List<double> vals;
  final List<String?>? labs;
  final Color color;
  final double prog;
  final int sel;
  final Color line, soft, ink, muted, card;
  _LinePainter({
    required this.vals,
    required this.labs,
    required this.color,
    required this.prog,
    required this.sel,
    required this.line,
    required this.soft,
    required this.ink,
    required this.muted,
    required this.card,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const l = 10.0, rr = 10.0;
    final r = w - rr;
    final t = 26.0, b = h - 26.0;
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line;
    for (var k = 0; k < 4; k++) {
      final y = t + (b - t) * k / 3.0;
      canvas.drawLine(Offset(l, y), Offset(r, y), grid);
    }
    final n = vals.length;
    if (n < 2) {
      _text(canvas, 'Pas assez de données', Offset(w / 2, h / 2),
          size: 11, color: muted, align: TextAlign.center, width: w);
      return;
    }
    var mn = vals[0], mx = vals[0];
    for (final v in vals) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    var lo = mn, hi = mx;
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < n; i++) {
      xs.add(l + (r - l) * i / (n - 1.0));
      ys.add(b - (vals[i] - lo) / (hi - lo) * (b - t));
    }
    final path = Path()..moveTo(xs[0], ys[0]);
    for (var i = 1; i < n; i++) {
      final cx = (xs[i - 1] + xs[i]) / 2.0;
      path.cubicTo(cx, ys[i - 1], cx, ys[i], xs[i], ys[i]);
    }
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.first;
    final len = m.length;
    final drawn = (len * prog.clamp(0.0, 1.0));
    final seg = m.extractPath(0, drawn);
    final tip = drawn > 0
        ? (m.getTangentForOffset(drawn)?.position ?? Offset(xs[0], ys[0]))
        : Offset(xs[0], ys[0]);

    // zone dégradée sous la courbe
    final base = color;
    final fillP = Path.from(seg)
      ..lineTo(tip.dx, b)
      ..lineTo(xs[0], b)
      ..close();
    canvas.drawPath(
      fillP,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base.withValues(alpha: .28), base.withValues(alpha: .02)],
        ).createShader(Rect.fromLTRB(0, t, w, b)),
    );
    canvas.drawPath(
      seg,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    _text(canvas, nf(mx), Offset(l, t - 8), size: 10.5, color: muted);
    _text(canvas, nf(mn), Offset(l, b - 6), size: 10.5, color: muted);
    if (labs != null) {
      final ly = h - 6.0;
      _text(canvas, labs![0] ?? '', Offset(l, ly), size: 10.5, color: muted);
      _text(canvas, labs![n - 1] ?? '', Offset(r, ly),
          size: 10.5, color: muted, align: TextAlign.right, anchor: r);
      if (n > 4) {
        _text(canvas, labs![n ~/ 2] ?? '', Offset(xs[n ~/ 2], ly),
            size: 10.5, color: muted,
            align: TextAlign.center, anchor: xs[n ~/ 2]);
      }
    }

    final dot = Paint()..color = color;
    if (sel >= 0 && sel < n) {
      canvas.drawLine(Offset(xs[sel], t), Offset(xs[sel], b),
          grid..color = color.withValues(alpha: .45));
      canvas.drawCircle(Offset(xs[sel], ys[sel]), 6, dot);
      canvas.drawCircle(Offset(xs[sel], ys[sel]), 3, Paint()..color = card);
      final label =
          nf(vals[sel]) + (labs != null ? '  ${labs![sel] ?? ''}' : '');
      _bubble(canvas, label, Offset(xs[sel], ys[sel]), w, size, soft, ink);
    } else if (prog > 0.98) {
      canvas.drawCircle(Offset(xs[n - 1], ys[n - 1]), 5, dot);
      canvas.drawCircle(Offset(xs[n - 1], ys[n - 1]), 9,
          dot..color = color.withValues(alpha: .33));
      // la pointe suit la courbe : halo animé
      canvas.drawCircle(tip, 3, dot..color = color);
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {required double size,
      required Color color,
      TextAlign align = TextAlign.left,
      double? anchor,
      double? width}) {
    final pb = TextPainter(
      text: TextSpan(
          text: s, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    double x = at.dx;
    if (align == TextAlign.center && anchor != null) x = anchor - pb.width / 2;
    if (align == TextAlign.right && anchor != null) x = anchor - pb.width;
    pb.paint(canvas, Offset(x, at.dy - pb.height / 2));
  }

  void _bubble(Canvas canvas, String s, Offset at, double w, Size size,
      Color bg, Color fg) {
    final pb = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800,
              color: fg)),
      textDirection: TextDirection.ltr,
    )..layout();
    const bw = 20.0, bh = 26.0;
    final bwAll = pb.width + bw;
    var bx = at.dx - bwAll / 2;
    bx = bx.clamp(2.0, w - bwAll - 2.0);
    var by = at.dy - 40;
    by = by.clamp(2.0, size.height - bh - 2.0);
    final rect = Rect.fromLTWH(bx, by, bwAll, bh);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()..color = bg);
    pb.paint(canvas, Offset(bx + 10, by + bh / 2 - pb.height / 2));
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.prog != prog ||
      old.sel != sel ||
      old.color != color ||
      !listEquals(old.vals, vals);
}

/* ---------- barres qui poussent les unes après les autres ---------- */

class BarChart extends StatefulWidget {
  final List<double> vals;
  final List<String?>? labs;
  final Color color;
  const BarChart(this.vals, {super.key, this.labs, required this.color});
  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  @override
  void initState() {
    super.initState();
    _a.forward();
  }

  @override
  void didUpdateWidget(covariant BarChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.vals, widget.vals)) _a.forward(from: 0);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return AnimatedBuilder(
      animation: _a,
      builder: (ctx, _) => CustomPaint(
        size: const Size(double.infinity, 190),
        painter: _BarPainter(
          vals: widget.vals,
          labs: widget.labs,
          color: widget.color,
          prog: _a.value,
          ink: c.ink,
          muted: c.muted,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<double> vals;
  final List<String?>? labs;
  final Color color;
  final double prog;
  final Color ink, muted;
  _BarPainter({
    required this.vals,
    required this.labs,
    required this.color,
    required this.prog,
    required this.ink,
    required this.muted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = vals.length;
    final w = size.width, h = size.height;
    if (n == 0) return;
    const l = 6.0;
    final r = w - 6.0, t = 24.0, b = h - 24.0;
    const gap = 8.0;
    final bw = (r - l - gap * (n - 1)) / n;
    var max = 1.0;
    for (final v in vals) {
      if (v > max) max = v;
    }
    // libellés de date : on en garde un échantillon lisible
    final step = n <= 12 ? 1 : (n / 10).ceil();
    for (var i = 0; i < n; i++) {
      var p = ((prog * (n + 3.0) - i) / 3.0).clamp(0.0, 1.0);
      p = 1 - math.pow(1 - p, 3).toDouble();
      final x = l + i * (bw + gap);
      final bh = math.max(0.0, vals[i]) / max * (b - t) * p;
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTRB(x, b - bh, x + bw, b), const Radius.circular(6));
      canvas.drawRRect(
          rect,
          Paint()
            ..color = i == n - 1
                ? color
                : color.withValues(alpha: .55));
      if (p > 0.85 && bw > 16) {
        _text(canvas, nf(vals[i]), x + bw / 2, b - bh - 6, ink, bold: true);
      }
      if (labs != null && i % step == 0) {
        _text(canvas, labs![i] ?? '', x + bw / 2, h - 6, muted);
      }
    }
  }

  void _text(Canvas canvas, String s, double cx, double cy, Color color,
      {bool bold = false}) {
    final pb = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    pb.paint(canvas, Offset(cx - pb.width / 2, cy - pb.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.prog != prog || old.color != color || !listEquals(old.vals, vals);
}

/* ---------- anneau de progression avec pourcentage ---------- */

class KRing extends StatefulWidget {
  final double p; // 0..1
  final Color color;
  final double size;
  const KRing(this.p, {super.key, required this.color, this.size = 88});
  @override
  State<KRing> createState() => _KRingState();
}

class _KRingState extends State<KRing> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));
  @override
  void initState() {
    super.initState();
    _a.forward();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return AnimatedBuilder(
      animation: _a,
      builder: (ctx, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _RingPainter(
            target: widget.p.clamp(0.0, 1.0),
            prog: CurvedAnimation(parent: _a, curve: Curves.easeOutCubic).value,
            color: widget.color,
            line: c.line,
            ink: c.ink,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double target, prog;
  final Color color, line, ink;
  _RingPainter({
    required this.target,
    required this.prog,
    required this.color,
    required this.line,
    required this.ink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final sw = s * 0.12;
    final rad = s / 2 - sw;
    final cx = size.width / 2, cy = size.height / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: rad);
    canvas.drawCircle(
        Offset(cx, cy), rad, Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = sw);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * target * prog, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round);
    final pctTxt = '${(target * prog * 100).round()}%';
    final pb = TextPainter(
      text: TextSpan(
          text: pctTxt,
          style: TextStyle(
              fontSize: s * 0.24, fontWeight: FontWeight.w800, color: ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    pb.paint(canvas, Offset(cx - pb.width / 2, cy - pb.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.prog != prog || old.target != target || old.color != color;
}

/* ---------- texte qui compte de 0 vers la valeur ---------- */

class CountUpText extends StatelessWidget {
  final double to;
  final TextStyle style;
  const CountUpText(this.to, {super.key, required this.style});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: to),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(nf(v), style: style),
    );
  }
}

/* ---------- pastille de variation ---------- */

Widget deltaChip(BuildContext context, double last, double prev) {
  final c = context.p;
  final p = pct(last, prev);
  if (p.isEmpty) return _delta(c, 'stable', fg: c.muted, bg: c.line);
  return last > prev
      ? _delta(c, p, fg: c.ink, bg: c.soft)
      : _delta(c, p, fg: c.bg, bg: c.ink);
}

Widget _delta(Palette c, String t, {required Color fg, required Color bg}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(t,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );

bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
