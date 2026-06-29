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
        Icon(Icons.star_rounded, size: size + 2, color: c),
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
