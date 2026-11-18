import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';
import '../ui/pictos.dart';

/// Pilule flottante de la maquette : fond #101014, 4 onglets + bouton « + »
/// bleu central. Onglet actif = fond blanc translucide.
/// Index : 0 Accueil, 1 Boîte, 2 + (fab), 3 Bot, 4 Stats.
class PillNav extends StatelessWidget {
  final int sel; // 0..4, -1 = aucune
  final ValueChanged<int> onTab;
  final VoidCallback onFab;
  final int badge; // badge sur Boîte
  const PillNav({
    super.key,
    required this.sel,
    required this.onTab,
    required this.onFab,
    this.badge = 0,
  });

  static const _labels = ['Accueil', 'Boîte', '', 'Bot', 'Stats'];
  static const _pictos = ['home', 'inbox', '', 'bot', 'chart'];

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              color: c.pill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x12FFFFFF)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .5),
                  blurRadius: 38,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tab(c, 0),
                const SizedBox(width: 2),
                _tab(c, 1),
                const SizedBox(width: 2),
                _fab(c),
                const SizedBox(width: 2),
                _tab(c, 3),
                const SizedBox(width: 2),
                _tab(c, 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fab(Palette c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.mediumImpact();
        onFab();
      },
      child: Container(
        width: 47,
        height: 47,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: c.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: c.accent.withValues(alpha: .42),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Picto('plus', size: 20, color: Colors.white),
      ),
    );
  }

  Widget _tab(Palette c, int i) {
    final active = sel == i;
    final col = active ? c.pillInk : c.pillMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (sel != i) {
          HapticFeedback.selectionClick();
          onTab(i);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.pillOn : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Picto(_pictos[i], size: 19, color: col),
                if (i == 1 && badge > 0)
                  Positioned(
                    right: -8,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.pill, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          fontSize: 8.5,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2.5),
            Text(
              _labels[i],
              maxLines: 1,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
                color: col,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
