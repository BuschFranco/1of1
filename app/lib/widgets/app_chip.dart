import 'package:flutter/material.dart';
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
    final bg = tint != null
        ? tint.withAlpha(28)
        : (active ? AppColors.accent : AppColors.white(0.06));
    final col = tint ?? (active ? Colors.white : const Color(0xFFF5F7FA));
    final border = tint != null
        ? tint.withAlpha(120)
        : (active ? AppColors.accent : AppColors.white(0.10));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: border),
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
