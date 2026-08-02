import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

/// Dialog de "Partido personalizado": muestra las recompensas y reglas
/// (configuraciones personalizadas) de un pickup antes de que el usuario se
/// una. Se dispara UNA vez por usuario y por pickup (flag en prefs), la
/// primera vez que abre el chat. El botón Continuar lo cierra.
Future<void> showPickupRulesDialog(BuildContext context, Pickup pickup) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PickupRulesDialog(pickup: pickup),
  );
}

IconData settingIcon(String type) {
  switch (type) {
    case 'edad':
      return Icons.cake_outlined;
    case 'altura':
      return Icons.height;
    case 'peso':
      return Icons.monitor_weight_outlined;
    case 'nivel':
      return Icons.military_tech_outlined;
    case 'modalidad':
      return Icons.emoji_events_outlined;
    case 'marca':
      return Icons.branding_watermark_outlined;
  }
  return Icons.tune;
}

class _PickupRulesDialog extends StatelessWidget {
  final Pickup pickup;
  const _PickupRulesDialog({required this.pickup});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(AppShape.rCard),
          border: Border.all(color: AppColors.white(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 20, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Partido personalizado',
                      style: AppText.archivo(
                          size: 17, weight: FontWeight.w900, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Antes de unirte, tené en cuenta las reglas de este pickup:',
                style: AppText.grotesk(size: 12, color: AppColors.white(0.55))),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pickup.rewards.isNotEmpty) ...[
                      _sectionLabel('Recompensa'),
                      for (final r in pickup.rewards) _row(r.label),
                    ],
                    if (pickup.settings.isNotEmpty) ...[
                      if (pickup.rewards.isNotEmpty) const SizedBox(height: 8),
                      _sectionLabel('Reglas'),
                      for (final s in pickup.settings) _row(s.label),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            PressableWidget(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rField),
                ),
                child: Text('CONTINUAR',
                    style: AppText.grotesk(
                        size: 13,
                        weight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.08)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(text.toUpperCase(),
            style: AppText.grotesk(
                size: 11,
                weight: FontWeight.w700,
                color: AppColors.white(0.45),
                letterSpacing: 0.08)),
      );

  Widget _row(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: AppText.grotesk(
                      size: 13, color: AppColors.white(0.9))),
            ),
          ],
        ),
      );
}
