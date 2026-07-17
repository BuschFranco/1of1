import 'package:flutter/material.dart';

import '../services/play_session_service.dart';
import '../theme/app_theme.dart';

/// Cabecera de temporada: nombre, rango de fechas, días restantes y el aviso de
/// que las puntuaciones se reinician al terminar (nivel/logros se conservan).
/// [compact] achica el bloque para la hoja de ranking del perfil.
class SeasonBanner extends StatelessWidget {
  final bool compact;
  const SeasonBanner({super.key, this.compact = false});

  static const _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = PlaySessionService.seasonStart(now);
    // seasonEnd es exclusivo (1 jul / 1 ene): el último día jugable es el previo.
    final lastDay =
        PlaySessionService.seasonEnd(now).subtract(const Duration(days: 1));
    final firstHalf = start.month == 1;
    final title = 'Temporada ${firstHalf ? 'Ene–Jun' : 'Jul–Dic'} ${start.year}';
    final range =
        '${start.day} ${_months[start.month - 1]} → ${lastDay.day} ${_months[lastDay.month - 1]} ${lastDay.year}';
    final daysLeft = lastDay.difference(DateTime(now.year, now.month, now.day)).inDays;

    return Container(
      margin: EdgeInsets.fromLTRB(20, 0, 20, compact ? 12 : 14),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: AppColors.accent.withAlpha(20),
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.accent.withAlpha(90), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech,
                  size: compact ? 16 : 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppText.archivo(
                      size: compact ? 14 : 16,
                      weight: FontWeight.w900,
                      color: AppColors.accent),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rChip),
                ),
                child: Text(
                  daysLeft > 0 ? '$daysLeft días' : 'Último día',
                  style: AppText.grotesk(
                      size: 10,
                      weight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: 0.04),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(range,
              style: AppText.grotesk(size: 11, color: AppColors.white(0.6))),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(
              'Al terminar la temporada, las puntuaciones y conquistas se '
              'reinician. Tu nivel, logros y desbloqueos se conservan.',
              style: AppText.grotesk(
                  size: 11, color: AppColors.white(0.5), height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
