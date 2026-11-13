import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';

/// Navigation flottante : pilule dépolie, 4 onglets + bouton « + » central
/// surélevé. Port de NavBar.java avec le style validé de la maquette :
/// pilule accent qui glisse avec un ressort, contenu actif blanc.
class PillNav extends StatefulWidget {
  final int sel; // 0..4, -1 = aucune (écran hors onglets)
  final ValueChanged<int> onTab;
  final VoidCallback onFab;
  final int badge; // badge sur l'onglet Réponses (index 3 visuel, slot 2)
  const PillNav(
      {super.key,
      required this.sel,
      required this.onTab,
      required this.onFab,
      this.badge = 0});
  @override
  State<PillNav> createState() => _PillNavState();
}

class _PillNavState extends State<PillNav>
    with SingleTickerProviderStateMixin {
  static const _labels = ['Accueil', 'Bot', '', 'Réponses', 'Stats'];
  static const _icons = [
    Icons.home_outlined,
    Icons.smart_toy_outlined,
    Icons.add,
    Icons.forum_outlined,
    Icons.bar_chart_outlined,
  ];

  late final AnimationController _bounce = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    _bounce.forward();
  }

  @override
  void didUpdateWidget(covariant PillNav old) {
    super.didUpdateWidget(old);
    if (old.sel != widget.sel) _bounce.forward(from: .3);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      margin: const EdgeInsets.fromLTRB(11, 0, 11, 11),
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .38),
              blurRadius: 32,
              offset: const Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: c.navBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.navLine),
            ),
            child: LayoutBuilder(builder: (ctx, box) {
              final slot = box.maxWidth / 5;
              return Stack(children: [
                if (widget.sel >= 0 && widget.sel != 2)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    top: 6,
                    left: widget.sel * slot + 6,
                    width: slot - 12,
                    height: 47,
                    child: ScaleTransition(
                      scale: Tween(begin: .85, end: 1.0).animate(
                          CurvedAnimation(
                              parent: _bounce, curve: Curves.easeOutBack)),
                      child: Container(
                          decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(999))),
                    ),
                  ),
                Row(children: [
                  for (var i = 0; i < 5; i++)
                    Expanded(child: _slot(ctx, c, i, i == 2)),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _slot(BuildContext ctx, Palette c, int i, bool isFab) {
    if (isFab) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onFab();
        },
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -14),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: c.accent.withValues(alpha: .45),
                      blurRadius: 16,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Icon(Icons.add, size: 26, color: c.bg),
            ),
          ),
        ),
      );
    }
    final active = widget.sel == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (widget.sel != i) {
          HapticFeedback.selectionClick();
          widget.onTab(i);
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(_icons[i],
                size: 20, color: active ? c.onAccent : c.muted),
            if (i == 3 && widget.badge > 0)
              Positioned(
                right: -10,
                top: -5,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                      color: c.ink,
                      borderRadius: BorderRadius.circular(99)),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 15),
                  alignment: Alignment.center,
                  child: Text(
                    widget.badge > 99 ? '99+' : '${widget.badge}',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: c.bg),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 2),
          Text(_labels[i],
              maxLines: 1,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                  color: active ? c.onAccent : c.muted)),
        ],
      ),
    );
  }
}
