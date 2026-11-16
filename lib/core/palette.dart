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
    bg: Color(0xFF060607),
    card: Color(0xFF131317),
    soft: Color(0xFF1B1B21),
    ink: Color(0xFFF6F6F7),
    muted: Color(0xFF8E8E97),
    line: Color(0xFF24242A),
    card2: Color(0xFF18181E),
    chip: Color(0xFF1B1B21),
    heroBg: Color(0xFFF6F6F7),
    heroInk: Color(0xFF0A0A0B),
    heroMut: Color(0xFF5C5C63),
    accent: Color(0xFF1877F2),
    onAccent: Color(0xFFFFFFFF),
    accBr: Color(0xFF4D9AFF),
    navBg: Color(0xFF101014),
    navLine: Color(0x12FFFFFF),
    pill: Color(0xFF101014),
    pillInk: Color(0xFFF6F6F7),
    pillMuted: Color(0xFF808088),
    pillOn: Color(0x17FFFFFF), // .09
  );

  static const light = Palette(
    bg: Color(0xFFFAFAF9),
    card: Color(0xFFFFFFFF),
    soft: Color(0xFFEFEFEC),
    ink: Color(0xFF0B0B0C),
    muted: Color(0xFF6A6A72),
    line: Color(0xFFE7E7E3),
    card2: Color(0xFFF3F3F0),
    chip: Color(0xFFEFEFEC),
    heroBg: Color(0xFF0B0B0C),
    heroInk: Color(0xFFFAFAF9),
    heroMut: Color(0xFFABABB1),
    accent: Color(0xFF1877F2),
    onAccent: Color(0xFFFFFFFF),
    accBr: Color(0xFF1877F2),
    navBg: Color(0xFF101014),
    navLine: Color(0x12FFFFFF),
    pill: Color(0xFF101014),
    pillInk: Color(0xFFF6F6F7),
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
      fontSize: 10, height: 1.25, fontWeight: FontWeight.w700,
      letterSpacing: 1.6, color: c.muted);
  static TextStyle microInk(Palette c) => TextStyle(
      fontSize: 10, height: 1.25, fontWeight: FontWeight.w700,
      letterSpacing: 1.6, color: c.ink);
  static TextStyle caption(Palette c) =>
      TextStyle(fontSize: 11.5, height: 1.35, color: c.muted);
  static TextStyle body(Palette c) =>
      TextStyle(fontSize: 13, height: 1.5, color: c.ink);
  static TextStyle strong(Palette c) => TextStyle(
      fontSize: 13, height: 1.4, fontWeight: FontWeight.w700, color: c.ink);
  static TextStyle title(Palette c) => TextStyle(
      fontFamily: kDisp, fontSize: 15.5, height: 1.2,
      fontWeight: FontWeight.w700, letterSpacing: -.2, color: c.ink);
  static TextStyle kpi(Palette c) => TextStyle(
      fontFamily: kDisp, fontSize: 15, height: 1.1,
      fontWeight: FontWeight.w800, letterSpacing: -.15, color: c.ink,
      fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle hero(Palette c) => TextStyle(
      fontFamily: kDisp, fontSize: 26, height: 1.12,
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
  static const rCard = 16.0;
  static const rBtn = 12.0;
  static const rBadge = 99.0;
  static const pad = 12.0;
}
