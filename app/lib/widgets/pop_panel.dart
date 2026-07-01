import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// Panel glass pop-futurista: borde "hairline" con degradado (ring neón) +
/// relleno oscuro + glow opcional + un highlight superior sutil. Bloque base
/// que estandariza los paneles `Color(0x..1A2430)` dispersos por la app.
class PopPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color ringColor;
  final Color fill;
  final VoidCallback? onTap;
  final bool glow;
  final int ringAlpha;

  const PopPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.ringColor = AppColors.accent,
    this.fill = AppColors.panel,
    this.onTap,
    this.glow = false,
    this.ringAlpha = 120,
  });

  @override
  Widget build(BuildContext context) {
    final panel = GradientRing(
      radius: radius,
      ringColor: ringColor,
      ringTopAlpha: ringAlpha,
      fill: fill,
      glow: glow ? AppFx.neonGlow(ringColor, blur: 22, alpha: 60) : null,
      child: Stack(
        children: [
          // Highlight superior sutil (reflejo de "vidrio").
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: radius + 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius - 1)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.white(0.05), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: panel,
      );
    }
    return panel;
  }
}
