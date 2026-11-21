import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

/// Palette « Noir & blanc + » — transposée 1:1 depuis la maquette v2
/// (maquette-complete-kidas-10-ecrans.html).
class Palette {
  final Color bg, card, soft, ink, muted, line;
  final Color card2, chip;
  final Color heroBg, heroInk, heroMut;
  final Color accent, onAccent, accBr;
  final Color navBg, navLine;
  final Color pill, pillInk, pillMuted, pillOn;

  const Palette({
    required this.bg,
    required this.card,
    required this.soft,
    required this.ink,
    required this.muted,
    required this.line,
    required this.card2,
    required this.chip,
    required this.heroBg,
    required this.heroInk,
    required this.heroMut,
    required this.accent,
    required this.onAccent,
    required this.accBr,
    required this.navBg,
    required this.navLine,
    required this.pill,
    required this.pillInk,
    required this.pillMuted,
    required this.pillOn,
  });

  static const dark = Palette(
    bg: Color(0xFF0A1020),
    card: Color(0xFF111C2E),
    soft: Color(0xFF1A2940),
    ink: Color(0xFFF3F6FC),
    muted: Color(0xFF9AA9BF),
    line: Color(0xFF263750),
    card2: Color(0xFF17243A),
    chip: Color(0xFF1B2940),
    heroBg: Color(0xFFF3F6FC),
    heroInk: Color(0xFF0A0A0B),
    heroMut: Color(0xFF5C5C63),
    accent: Color(0xFF1877F2),
    onAccent: Color(0xFFFFFFFF),
    accBr: Color(0xFF4D9AFF),
    navBg: Color(0xFF101827),
    navLine: Color(0x12FFFFFF),
    pill: Color(0xFF101827),
    pillInk: Color(0xFFF3F6FC),
    pillMuted: Color(0xFF808088),
    pillOn: Color(0x17FFFFFF), // .09
  );

  static const light = Palette(
    bg: Color(0xFFF5F7FB),
    card: Color(0xFFFFFFFF),
    soft: Color(0xFFF0F4FA),
    ink: Color(0xFF17243A),
    muted: Color(0xFF65758B),
    line: Color(0xFFE4EAF2),
    card2: Color(0xFFEDF2F9),
    chip: Color(0xFFEAF0F8),
    heroBg: Color(0xFF182338),
    heroInk: Color(0xFFF4F7FC),
    heroMut: Color(0xFFABABB1),
    accent: Color(0xFF1877F2),
    onAccent: Color(0xFFFFFFFF),
    accBr: Color(0xFF1877F2),
    navBg: Color(0xFF101827),
    navLine: Color(0x12FFFFFF),
    pill: Color(0xFF101827),
    pillInk: Color(0xFFF3F6FC),
    pillMuted: Color(0xFF8A8A92),
    pillOn: Color(0x1FFFFFFF), // .12
  );

  static Palette of(Brightness b) => b == Brightness.dark ? dark : light;
}

extension PaletteCtx on BuildContext {
  /// Palette du thème courant (sombre ou clair).
  Palette get p => Palette.of(Theme.of(this).brightness);
}

/// Polices de la maquette : Archivo (titres, chiffres) + Inter (texte).
const kDisp = 'Archivo';
const kBody = 'Inter';

class T {
  static TextStyle micro(Palette c) => TextStyle(
      fontSize: 10, height: 1.3, fontWeight: FontWeight.w700,
      letterSpacing: 1.6, color: c.muted);
  static TextStyle microInk(Palette c) => TextStyle(
      fontSize: 10, height: 1.25, fontWeight: FontWeight.w700,
      letterSpacing: 1.6, color: c.ink);
  static TextStyle caption(Palette c) =>
      TextStyle(fontSize: 12, height: 1.4, color: c.muted);
  static TextStyle body(Palette c) =>
      TextStyle(fontSize: 13.5, height: 1.55, color: c.ink);
  static TextStyle strong(Palette c) => TextStyle(
      fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w700, color: c.ink);
  static TextStyle title(Palette c) => TextStyle(
      fontFamily: kDisp, fontSize: 16, height: 1.25,
      fontWeight: FontWeight.w700, letterSpacing: -.2, color: c.ink);
  static TextStyle kpi(Palette c) => TextStyle(
      fontFamily: kDisp, fontSize: 15, height: 1.1,
      fontWeight: FontWeight.w800, letterSpacing: -.15, color: c.ink,
      fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle hero(Palette c) => TextStyle(
      fontFamily: kDisp, fontSize: 27, height: 1.15,
      fontWeight: FontWeight.w800, letterSpacing: -.5, color: c.heroInk);
}

/// Animations partagées.
class KAnim {
  static const fast = Duration(milliseconds: 160);
  static const med = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 520);
  static const spring = Curves.easeOutBack;
  static const ease = Curves.easeOutCubic;
}

/// Rayons et espacements standard.
class KDim {
  static const rCard = 18.0;
  static const rBtn = 13.0;
  static const rBadge = 99.0;
  static const pad = 14.0;
}
