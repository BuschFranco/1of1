import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

/// Panel neobrutalista: relleno SÓLIDO, borde franco del color del ring y
/// sombra dura opcional ([glow] la activa, manteniendo el nombre histórico).
/// Sin highlight de vidrio ni degradados.
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
    this.radius = AppShape.rCard,
    this.ringColor = AppColors.ink,
    this.fill = AppColors.panel,
    this.onTap,
    this.glow = false,
    this.ringAlpha = 255,
  });

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ringColor.withAlpha(ringAlpha), width: 1),
        boxShadow: glow ? AppFx.hardShadow() : null,
      ),
      child: child,
    );
    if (onTap != null) {
      return PressableWidget(
        onTap: onTap,
        child: panel,
      );
    }
    return panel;
  }
}
