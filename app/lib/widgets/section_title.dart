import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final String? right;
  final VoidCallback? onRight;

  const SectionTitle({
    super.key,
    required this.title,
    this.right,
    this.onRight,
  });

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
              // Etiqueta de sección: sin sombra ni glow. Son 13px, y cualquier
              // blur a ese tamaño se lee como texto sucio en vez de aura.
              Text(
                title.toUpperCase(),
                style: AppText.archivo(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          if (right != null)
            PressableWidget(
              onTap: onRight,
              child: Text(
                right!,
                style: AppText.grotesk(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: 0.04,
                  height: 1,
                ).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
