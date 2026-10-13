import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final String? right;
  final VoidCallback? onRight;
  final IconData? rightIcon;

  const SectionTitle({
    super.key,
    required this.title,
    this.right,
    this.onRight,
    this.rightIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          // Acción principal de la sección (Escribir / Publicar): botón relleno
          // con el acento. Como link subrayado de 11px el usuario ni lo veía.
          if (right != null)
            PressableWidget(
              onTap: onRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rChip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (rightIcon != null) ...[
                      Icon(rightIcon, size: 15, color: AppColors.bg),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      right!,
                      style: AppText.grotesk(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.bg,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
