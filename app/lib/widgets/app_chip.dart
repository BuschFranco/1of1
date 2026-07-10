import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

class AppChip extends StatelessWidget {
  final String label;
  final bool active;
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
    final bg = tint ?? (active ? AppColors.accent : AppColors.paper);
    final col = (tint != null || active) ? Colors.white : AppColors.ink;

    return PressableWidget(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppShape.rChip),
          border: Border.all(color: AppColors.line, width: active ? 1.5 : 1),
          boxShadow: (active || tint != null)
              ? AppFx.hardShadow(offset: const Offset(1, 2))
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
