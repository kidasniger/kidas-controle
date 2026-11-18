import 'package:flutter/material.dart';

import '../core/palette.dart';

/// Pictos exacts de la maquette (sprite SVG i-*) dessinés au canvas :
/// aucun paquet externe, seulement un petit traceur d'attribut d SVG vers
/// [Path] Flutter. Trait courant 1.8, extrémités et jonctions rondes,
/// comme la règle CSS du sprite de la maquette.

class _El {
  final String d; // attribut d du sprite (circle et rect déjà compilés)
  final bool fill; // rempli (étincelle) plutôt que tracé
  final double sw; // épaisseur du trait
  const _El(this.d, {this.fill = false, this.sw = 1.8});
}

/* ---------- table générée depuis maquette-complete-kidas-10-ecrans ---------- */

const Map<String, List<_El>> _spr = <String, List<_El>>{
  'home': [_El('M3.5 10.8 12 3.5l8.5 7.3'), _El('M5.8 9.8V20h12.4V9.8')],
  'inbox': [
    _El('M3 13.5h5.2l1.9 3h3.8l1.9-3H21'),
    _El(
      'M3 13.5V6.8A1.8 1.8 0 0 1 4.8 5h14.4A1.8 1.8 0 0 1 21 6.8v6.7M3 13.5V18a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-4.5',
    ),
  ],
  'bot': [
    _El(
      'M7.5 8.5h9a2.5 2.5 0 0 1 2.5 2.5v5a2.5 2.5 0 0 1 -2.5 2.5h-9a2.5 2.5 0 0 1 -2.5 -2.5v-5a2.5 2.5 0 0 1 2.5 -2.5z',
    ),
    _El('M12 8.5V5.6'),
    _El('M10.7 4.2a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0 -2.6 0'),
    _El('M9.3 13.2h.01M14.7 13.2h.01', sw: 2.6),
  ],
  'chart': [_El('M4.5 19.5V13M10.5 19.5V6.5M16.5 19.5v-9.5M21 19.5H3')],
  'plus': [_El('M12 5v14M5 12h14')],
  'thumb': [
    _El(
      'M7 10.7 10.7 4a1.9 1.9 0 0 1 3.5 1.3L13.6 9h4.6a1.8 1.8 0 0 1 1.8 2.1l-1.1 6.3a1.8 1.8 0 0 1-1.8 1.6H7',
    ),
    _El('M7 10.5H4.6A1.6 1.6 0 0 0 3 12.1v5.3A1.6 1.6 0 0 0 4.6 19H7'),
    _El('M7 19V10.5'),
  ],
  'comment': [
    _El(
      'M21 11.6a8.4 8.4 0 0 1-8.5 8.4 8.7 8.7 0 0 1-3.3-.7L3.5 20.5l1.3-5.4a8.4 8.4 0 1 1 16.2-3.5z',
    ),
  ],
  'share': [
    _El(
      'M13 5.5 20 12l-7 6.5v-3.7C8 14.8 5 16.6 3.5 19c.3-5.6 3.9-9.3 9.5-9.6z',
    ),
  ],
  'globe': [
    _El('M3.8 12a8.2 8.2 0 1 0 16.4 0a8.2 8.2 0 1 0 -16.4 0'),
    _El(
      'M3.8 12h16.4M12 3.8a12.6 12.6 0 0 1 0 16.4M12 3.8a12.6 12.6 0 0 0 0 16.4',
    ),
  ],
  'search': [
    _El('M4.7 11a6.3 6.3 0 1 0 12.6 0a6.3 6.3 0 1 0 -12.6 0'),
    _El('M20 20l-3.6-3.6'),
  ],
  'bell': [
    _El(
      'M17.8 9.2a5.8 5.8 0 1 0-11.6 0c0 5.3-2.2 6.6-2.2 6.6h16s-2.2-1.3-2.2-6.6',
    ),
    _El('M10 19.5a2.3 2.3 0 0 0 4 0'),
  ],
  'spark': [
    _El('M12 3.2l1.8 5 5 1.8-5 1.8-1.8 5-1.8-5-5-1.8 5-1.8z', fill: true),
    _El(
      'M18.6 15.4l.6 1.7 1.7.6-1.7.6-.6 1.7-.6-1.7-1.7-.6 1.7-.6z',
      fill: true,
    ),
  ],
  'image': [
    _El(
      'M5.7 5h12.6a2.2 2.2 0 0 1 2.2 2.2v9.6a2.2 2.2 0 0 1 -2.2 2.2h-12.6a2.2 2.2 0 0 1 -2.2 -2.2v-9.6a2.2 2.2 0 0 1 2.2 -2.2z',
    ),
    _El('M7.1 9.6a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0'),
    _El('M5 17.2l4.4-4.4 3 3 3.2-3.2 3.4 3.4'),
  ],
  'check': [_El('M5 12.6l4.3 4.4L19 7.4')],
  'eyeoff': [
    _El('M4 4l16 16'),
    _El(
      'M10.3 5.3A9 9 0 0 1 12 5.2c5.5 0 9 6.8 9 6.8a15.7 15.7 0 0 1-2.6 3.4M6.3 6.9A14.6 14.6 0 0 0 3 12s3.5 6.8 9 6.8a8.9 8.9 0 0 0 3.6-.75',
    ),
    _El('M10.4 10.6a2.4 2.4 0 0 0 3.3 3.3'),
  ],
  'trash': [
    _El(
      'M4.5 7h15M9.5 7V5h5v2M6.5 7l.9 12.5h9.2L17.5 7M10.3 10.5v5.5M13.7 10.5v5.5',
    ),
  ],
  'kebab': [_El('M12 5.5h.01M12 12h.01M12 18.5h.01', sw: 2.6)],
  'wifi': [
    _El(
      'M3 9.5a14 14 0 0 1 18 0M6 13a9.5 9.5 0 0 1 12 0M9 16.4a5 5 0 0 1 6 0M12 19.5h.01',
      sw: 2,
    ),
  ],
  'batt': [
    _El(
      'M4.7 8h12.6a2.2 2.2 0 0 1 2.2 2.2v3.6a2.2 2.2 0 0 1 -2.2 2.2h-12.6a2.2 2.2 0 0 1 -2.2 -2.2v-3.6a2.2 2.2 0 0 1 2.2 -2.2z',
    ),
    _El(
      'M5.7 10.2h6.5a1 1 0 0 1 1 1v1.6a1 1 0 0 1 -1 1h-6.5a1 1 0 0 1 -1 -1v-1.6a1 1 0 0 1 1 -1z',
      fill: true,
    ),
    _El('M21.8 11v2'),
  ],
  'signal': [_El('M4.5 18v-3M9 18v-6M13.5 18V8.5M18 18V5', sw: 2.2)],
  'back': [_El('M14.5 5 8 12l6.5 7')],
  'bolt': [_El('M13 2.5 4.5 13.5H11l-1.5 8L18.5 10H12z')],
  'gear': [
    _El('M8.8 12a3.2 3.2 0 1 0 6.4 0a3.2 3.2 0 1 0 -6.4 0'),
    _El(
      'M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.2 5.2l1.7 1.7M17.1 17.1l1.7 1.7M18.8 5.2l-1.7 1.7M6.9 17.1l-1.7 1.7',
    ),
  ],
  'clock': [
    _El('M3.8 12a8.2 8.2 0 1 0 16.4 0a8.2 8.2 0 1 0 -16.4 0'),
    _El('M12 7.5V12l3 2'),
  ],
  'send': [_El('M21 3 10.5 13.5M21 3l-6.5 18-4-8.5L2 8.5z')],
  'cal': [
    _El(
      'M5.7 5h12.6a2.2 2.2 0 0 1 2.2 2.2v11.1a2.2 2.2 0 0 1 -2.2 2.2h-12.6a2.2 2.2 0 0 1 -2.2 -2.2v-11.1a2.2 2.2 0 0 1 2.2 -2.2z',
    ),
    _El('M3.5 9.5h17M8 3v4M16 3v4'),
  ],
  'user': [
    _El('M8.2 8.2a3.8 3.8 0 1 0 7.6 0a3.8 3.8 0 1 0 -7.6 0'),
    _El('M4.5 20a7.5 7.5 0 0 1 15 0'),
  ],
  'shield': [
    _El('M12 3 5 5.5v5.6c0 4.4 3 7.7 7 9.9 4-2.2 7-5.5 7-9.9V5.5z'),
    _El('M9.2 12l2 2 3.6-4'),
  ],
  'info': [
    _El('M3.8 12a8.2 8.2 0 1 0 16.4 0a8.2 8.2 0 1 0 -16.4 0'),
    _El('M12 11v5M12 8h.01', sw: 2.2),
  ],
  'moon': [_El('M20.5 13.5A8.5 8.5 0 1 1 10.5 3.5a7 7 0 0 0 10 10z')],
  'edit': [
    _El('M4 20h4L20.5 7.5a2.1 2.1 0 0 0-3-3L5 17z'),
    _El('M13.5 6.5l3 3'),
  ],
  'doc': [_El('M7 3h7l4.5 4.5V21H7z'), _El('M14 3v5h4.5M10 12h5M10 15.5h5')],
  'refresh': [_El('M20 12a8 8 0 1 1-2.3-5.6'), _El('M20 3v4h-4')],
  'filter': [_El('M4 6h16M7 12h10M10 18h4')],
  'save': [
    _El('M12 3.5V15M7.5 10.5 12 15l4.5-4.5'),
    _El('M4.5 17v2.5a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5V17'),
  ],
  'x': [_El('M6 6l12 12M18 6 6 18')],
};

/* ---------- traceur : attribut d SVG -> Path ---------- */

Path _trace(String d) {
  final toks = RegExp('[A-Za-z]|-?[0-9]*\\.?[0-9]+')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  final p = Path();
  var i = 0;
  var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0, px = 0.0, py = 0.0;
  var cmd = '';
  var bez = false; // la commande précédente était une Bézier (réflexe S/T)

  double nb() => double.parse(toks[i++]);
  bool nbSuivant() => i < toks.length && double.tryParse(toks[i]) != null;

  while (i < toks.length) {
    if (!nbSuivant()) {
      cmd = toks[i];
      i++;
    }
    final up = cmd.toUpperCase();
    final rel = cmd != up;
    switch (up) {
      case 'M':
        var premier = true;
        while (nbSuivant()) {
          final x = nb() + (rel ? cx : 0);
          final y = nb() + (rel ? cy : 0);
          if (premier) {
            p.moveTo(x, y);
            premier = false;
          } else {
            p.lineTo(x, y);
          }
          cx = x;
          cy = y;
        }
        sx = cx;
        sy = cy;
        bez = false;
        cmd = rel ? 'l' : 'L';
        break;
      case 'L':
        while (nbSuivant()) {
          cx = nb() + (rel ? cx : 0);
          cy = nb() + (rel ? cy : 0);
          p.lineTo(cx, cy);
        }
        bez = false;
        break;
      case 'H':
        while (nbSuivant()) {
          cx = nb() + (rel ? cx : 0);
          p.lineTo(cx, cy);
        }
        bez = false;
        break;
      case 'V':
        while (nbSuivant()) {
          cy = nb() + (rel ? cy : 0);
          p.lineTo(cx, cy);
        }
        bez = false;
        break;
      case 'C':
        while (nbSuivant()) {
          final x1 = nb() + (rel ? cx : 0), y1 = nb() + (rel ? cy : 0);
          final x2 = nb() + (rel ? cx : 0), y2 = nb() + (rel ? cy : 0);
          final x = nb() + (rel ? cx : 0), y = nb() + (rel ? cy : 0);
          p.cubicTo(x1, y1, x2, y2, x, y);
          px = x2;
          py = y2;
          cx = x;
          cy = y;
          bez = true;
        }
        break;
      case 'S':
        while (nbSuivant()) {
          final x2 = nb() + (rel ? cx : 0), y2 = nb() + (rel ? cy : 0);
          final x = nb() + (rel ? cx : 0), y = nb() + (rel ? cy : 0);
          /* réflexe du 2e contrôle ; sinon le point courant contrôle */
          final rx = bez ? 2 * cx - px : cx;
          final ry = bez ? 2 * cy - py : cy;
          p.cubicTo(rx, ry, x2, y2, x, y);
          px = x2;
          py = y2;
          cx = x;
          cy = y;
          bez = true;
        }
        break;
      case 'Q':
        while (nbSuivant()) {
          final x1 = nb() + (rel ? cx : 0), y1 = nb() + (rel ? cy : 0);
          final x = nb() + (rel ? cx : 0), y = nb() + (rel ? cy : 0);
          p.quadraticBezierTo(x1, y1, x, y);
          px = x1;
          py = y1;
          cx = x;
          cy = y;
          bez = true;
        }
        break;
      case 'T':
        while (nbSuivant()) {
          final x = nb() + (rel ? cx : 0), y = nb() + (rel ? cy : 0);
          /* réflexe du contrôle ; sinon le point courant contrôle */
          final rx = bez ? 2 * cx - px : cx;
          final ry = bez ? 2 * cy - py : cy;
          p.quadraticBezierTo(rx, ry, x, y);
          px = rx;
          py = ry;
          cx = x;
          cy = y;
          bez = true;
        }
        break;
      case 'A':
        while (nbSuivant()) {
          final rx = nb(), ry = nb(), rot = nb();
          final la = nb(), swp = nb();
          final x = nb() + (rel ? cx : 0), y = nb() + (rel ? cy : 0);
          if (rx == 0 || ry == 0) {
            p.lineTo(x, y);
          } else {
            p.arcToPoint(
              Offset(x, y),
              radius: Radius.elliptical(rx, ry),
              rotation: rot,
              largeArc: la == 1,
              clockwise: swp == 1,
            );
          }
          cx = x;
          cy = y;
          bez = false;
        }
        break;
      case 'Z':
        p.close();
        cx = sx;
        cy = sy;
        bez = false;
        break;
      default:
        /* commande inconnue : on saute un token pour ne jamais bloquer */
        if (i < toks.length) {
          i++;
        }
    }
  }
  return p;
}

/* ---------- picto peint ---------- */

/// Un picto de la maquette : [name] sans préfixe i- (« home », « bot »…).
class Picto extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final double? stroke;
  const Picto(this.name, {super.key, this.size = 18, this.color, this.stroke});

  @override
  Widget build(BuildContext context) {
    final els = _spr[name];
    assert(els != null, 'Picto inconnu : i-$name');
    if (els == null) return SizedBox(width: size, height: size);
    final col = color ?? context.p.ink;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PictoPainter(els, col, stroke ?? 1.8)),
    );
  }
}

class _PictoPainter extends CustomPainter {
  final List<_El> els;
  final Color color;
  final double width;
  _PictoPainter(this.els, this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    for (final el in els) {
      final path = _trace(el.d);
      if (el.fill) {
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = el.sw
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PictoPainter old) =>
      old.color != color || old.width != width || !identical(old.els, els);
}

/* ---------- chevron fin de la maquette : i-back tourné vers la droite ---------- */

class Chev extends StatelessWidget {
  final double size;
  final Color? color;
  const Chev({super.key, this.size = 18, this.color});
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 3.14159,
      child: Picto('back', size: size, color: color),
    );
  }
}
