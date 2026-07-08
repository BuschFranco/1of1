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
    // Retro-pop: pills planas con borde negro. La variante coloreada (ej. el
    // título equipado, con su color de rareza) va SÓLIDA con texto blanco y
    // sombra dura — como los chips de la referencia.
    final bg = tint ?? (active ? AppColors.accent : AppColors.paper);
    final col = (tint != null || active) ? Colors.white : AppColors.ink;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppShape.rChip),
          border: Border.all(color: AppColors.ink, width: active ? 2 : 1.5),
          boxShadow: (active || tint != null)
              ? AppFx.hardShadow(offset: const Offset(2, 2))
              : null,
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
