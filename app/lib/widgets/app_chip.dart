import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

class AppChip extends StatelessWidget {
  final String label;
  final bool active;
  // Variante coloreada (ej. la rareza de un título equipado). Tiñe fondo,
  // borde y texto con este color.
  final Color? color;
  final String? icon;
  final VoidCallback? onTap;

  const AppChip({
    super.key,
    required this.label,
    this.active = false,
    this.color,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color;
    // Neobrutalismo: rectángulo de radio chico, colores planos, borde franco
    // y sombra dura solo en el estado activo.
    final bg = tint != null
        ? tint.withAlpha(28)
        : (active ? AppColors.accent : AppColors.bgElev);
    final col = tint ?? (active ? Colors.white : const Color(0xFFF5F7FA));
    final border = tint != null
        ? tint.withAlpha(160)
        : (active ? AppColors.ink : AppColors.white(0.25));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppShape.rChip),
          border: Border.all(color: border, width: active ? 2 : 1.5),
          boxShadow:
              active ? AppFx.hardShadow(offset: const Offset(2, 2)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Text(icon!, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppText.grotesk(
                size: 12,
                weight: FontWeight.w600,
                color: col,
                letterSpacing: -0.01,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
