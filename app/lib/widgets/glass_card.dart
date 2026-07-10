import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

/// Card retro-pop modernizada: superficie sólida, borde fino y sombra suave.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? background;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppShape.rCard,
    this.onTap,
    this.background,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: background ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: AppColors.line, width: 1),
        boxShadow: AppFx.hardShadow(),
      ),
      padding: padding,
      child: child,
    );
    if (onTap != null) {
      return PressableWidget(onTap: onTap, child: content);
    }
    return content;
  }
}
