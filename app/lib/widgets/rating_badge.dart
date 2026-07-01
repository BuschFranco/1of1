import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RatingBadge extends StatelessWidget {
  final double value;
  final double size;
  final Color? color;

  const RatingBadge({
    super.key,
    required this.value,
    this.size = 12,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Glow neón tenue detrás de la estrella.
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: c.withAlpha(90), blurRadius: 10, spreadRadius: -2),
            ],
          ),
          child: Icon(Icons.star_rounded, size: size + 2, color: c),
        ),
        const SizedBox(width: 3),
        Text(
          value.toString(),
          style: AppText.grotesk(
            size: size + 1,
            weight: FontWeight.w700,
            color: c,
          ),
        ),
      ],
    );
  }
}
