import 'package:flutter/material.dart';

/// Palette « Noir & blanc + » — transposée 1:1 depuis la maquette validée
/// (download/maquettes-ui-kidas-controle.html).
class Palette {
  final Color bg, card, soft, ink, muted, line;
  final Color heroBg, heroInk, heroMut;
  final Color accent, onAccent, accBr;
  final Color navBg, navLine;

  const Palette({
    required this.bg,
    required this.card,
    required this.soft,
    required this.ink,
    required this.muted,
    required this.line,
    required this.heroBg,
    required this.heroInk,
    required this.heroMut,
    required this.accent,
    required this.onAccent,
    required this.accBr,
    required this.navBg,
    required this.navLine,
  });

  static const dark = Palette(
    bg: Color(0xFF060607),
    card: Color(0xFF131317),
    soft: Color(0xFF1D1D23),
    ink: Color(0xFFF6F6F7),
    muted: Color(0xFF9A9AA2),
    line: Color(0xFF26262D),
    heroBg: Color(0xFFF6F6F7),
    heroInk: Color(0xFF0A0A0B),
    heroMut: Color(0xFF5C5C63),
    accent: Color(0xFF1877F2),
    onAccent: Color(0xFFFFFFFF),
    accBr: Color(0xFF4D9AFF),
    navBg: Color(0xD1131317), // rgba(19,19,23,.82)
    navLine: Color(0xFF26262D),
  );

  static const light = Palette(
    bg: Color(0xFFFAFAF9),
    card: Color(0xFFFFFFFF),
    soft: Color(0xFFF0F0EE),
    ink: Color(0xFF0B0B0C),
    muted: Color(0xFF6F6F76),
    line: Color(0xFFE8E8E5),
    heroBg: Color(0xFF0B0B0C),
    heroInk: Color(0xFFFAFAF9),
    heroMut: Color(0xFFABABB1),
    accent: Color(0xFF1877F2),
    onAccent: Color(0xFFFFFFFF),
    accBr: Color(0xFF1877F2),
    navBg: Color(0xDBFFFFFF), // rgba(255,255,255,.86)
    navLine: Color(0xFFE8E8E5),
  );

  static Palette of(Brightness b) => b == Brightness.dark ? dark : light;
}

extension PaletteCtx on BuildContext {
  /// Palette du thème courant (sombre ou clair).
  Palette get p => Palette.of(Theme.of(this).brightness);
}

/// Typo « Compact pro » — micro-labels 10, corps 13, titres 15.5/900, KPI 21.
class T {
  static TextStyle micro(Palette c) => TextStyle(
      fontSize: 10, height: 1.25, fontWeight: FontWeight.w700,
      letterSpacing: .8, color: c.muted);
  static TextStyle microInk(Palette c) => TextStyle(
      fontSize: 10, height: 1.25, fontWeight: FontWeight.w700,
      letterSpacing: .8, color: c.ink);
  static TextStyle caption(Palette c) =>
      TextStyle(fontSize: 11.5, height: 1.35, color: c.muted);
  static TextStyle body(Palette c) =>
      TextStyle(fontSize: 13, height: 1.45, color: c.ink);
  static TextStyle strong(Palette c) => TextStyle(
      fontSize: 13, height: 1.4, fontWeight: FontWeight.w700, color: c.ink);
  static TextStyle title(Palette c) => TextStyle(
      fontSize: 15.5, height: 1.2, fontWeight: FontWeight.w900,
      letterSpacing: .5, color: c.ink);
  static TextStyle kpi(Palette c) => TextStyle(
      fontSize: 21, height: 1.1, fontWeight: FontWeight.w800,
      letterSpacing: -.3, color: c.ink);
  static TextStyle hero(Palette c) => TextStyle(
      fontSize: 26, height: 1.12, fontWeight: FontWeight.w900,
      letterSpacing: -.4, color: c.heroInk);
}

/// Animations partagées — rebond printemps + fondu, comme dans la maquette.
class KAnim {
  static const fast = Duration(milliseconds: 160);
  static const med = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 520);
  static const spring = Curves.easeOutBack;
  static const ease = Curves.easeOutCubic;
}

/// Rayons et espacements standard.
class KDim {
  static const rCard = 16.0;
  static const rBtn = 12.0;
  static const rBadge = 99.0;
  static const pad = 12.0;
}
