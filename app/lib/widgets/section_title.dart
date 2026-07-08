import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final String? right;
  final VoidCallback? onRight;

  /// Sobre fondos saturados oscuros (lila/oliva/rojo del perfil): título en
  /// blanco con la sombra dura clásica del brand, y link en blanco.
  final bool onDark;

  const SectionTitle({
    super.key,
    required this.title,
    this.right,
    this.onRight,
    this.onDark = false,
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
              // Kicker retro-pop: punto redondo de acento con borde negro
              // (mismo lenguaje que los chips/círculos de la referencia).
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(right: 8, bottom: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.ink, width: 1.5),
                ),
              ),
              Text(
                title.toUpperCase(),
                style: AppText.archivo(
                  size: 13,
                  weight: FontWeight.w700,
                  color: onDark ? Colors.white : AppColors.ink,
                  letterSpacing: 0.1,
                ).copyWith(
                  shadows: onDark
                      ? const [
                          Shadow(color: AppColors.ink, offset: Offset(2, 2)),
                        ]
                      : null,
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
                  weight: FontWeight.w700,
                  color: onDark ? Colors.white : AppColors.ink,
                  letterSpacing: 0.04,
                  height: 1,
                ).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: onDark ? Colors.white : AppColors.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
