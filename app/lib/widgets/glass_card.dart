import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// Card neobrutalista (conserva el nombre histórico para no tocar call-sites):
/// superficie SÓLIDA, borde franco y sombra dura desplazada. Sin blur, sin
/// highlight de vidrio.
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
        border: border ?? Border.all(color: AppColors.line, width: 2),
        boxShadow: AppFx.hardShadow(),
      ),
      padding: padding,
      child: child,
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }
}
