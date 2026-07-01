import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final String? right;
  final VoidCallback? onRight;

  const SectionTitle({super.key, required this.title, this.right, this.onRight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kicker neón: barrita de acento con glow antes del título.
              Container(
                width: 4,
                height: 16,
                margin: const EdgeInsets.only(right: 9, bottom: 1),
                decoration: BoxDecoration(
                  gradient: AppFx.accentGradient(),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow:
                      AppFx.neonGlow(AppColors.accent, blur: 8, alpha: 120),
                ),
              ),
              Text(
                title.toUpperCase(),
                style: AppText.archivo(
                  size: 13,
                  weight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          if (right != null)
            GestureDetector(
              onTap: onRight,
              child: Text(
                right!,
                style: AppText.grotesk(
                  size: 11,
                  weight: FontWeight.w600,
                  color: AppColors.accent,
                  letterSpacing: 0.04,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
