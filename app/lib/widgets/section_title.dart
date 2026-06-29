import 'package:flutter/material.dart';
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
          Text(
            title.toUpperCase(),
            style: AppText.archivo(
              size: 13,
              weight: FontWeight.w800,
              letterSpacing: 0.12,
            ),
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
