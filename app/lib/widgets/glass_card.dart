import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
    this.radius = 20,
    this.onTap,
    this.background,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: background ?? const Color(0xB81A2430),
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(color: AppColors.white(0.08)),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // Highlight superior sutil: reflejo de "vidrio" pop-futurista.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.white(0.05), Colors.transparent],
              stops: const [0, 0.35],
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }
}
