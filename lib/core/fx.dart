import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native.dart';
import 'store.dart';

/// Retour tactile + sons courts (40 ms, désactivables dans Réglages).
/// Port du plan UX validé : tick sur chaque touche, medium sur le « + ».
class Fx {
  static final ValueNotifier<bool> sons = ValueNotifier(true);
  static bool _loaded = false;

  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    sons.value = await Store.get('sons') != '0';
  }

  static Future<void> setSons(bool on) async {
    sons.value = on;
    await Store.set('sons', on ? '1' : '0');
    if (on) tick();
  }

  static void tick() {
    HapticFeedback.selectionClick();
    if (sons.value) Native.beep('tick');
  }

  static void medium() {
    HapticFeedback.mediumImpact();
    if (sons.value) Native.beep('ok');
  }

  static void error() {
    HapticFeedback.vibrate();
    if (sons.value) Native.beep('err');
  }
}
