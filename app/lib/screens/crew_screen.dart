import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/bball_glyph.dart';
import '../widgets/under_construction.dart';

class CrewScreen extends StatelessWidget {
  const CrewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const chats = [
      ('Lezama Crew', '¿Quién se prende hoy?', '2m'),
      ('Polideportivo Norte', 'Reserva confirmada 20hs', '14m'),
      ('Pickup Martes', 'Faltan 2 para 5v5', '1h'),
    ];

    return Container(
      color: AppColors.red,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
        children: [
          Row(
            children: [
              Text(
                'Crew',
                style: AppText.archivo(
                  size: 34,
                  weight: FontWeight.w900,
                  color: AppColors.blush,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(width: 10),
              const UnderConstructionBadge(),
            ],
          ),
          const SizedBox(height: 16),
          const UnderConstructionBanner(
            text: 'El chat con tu crew todavía no está conectado. Los mensajes de abajo son de ejemplo.',
          ),
          Text(
            '3 CHATS ACTIVOS',
            style: AppText.grotesk(
              size: 11,
              weight: FontWeight.w700,
              color: AppColors.blush,
              letterSpacing: 0.16,
            ),
          ),
          const SizedBox(height: 20),
          for (final c in chats)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              // Card de chat: sólida, borde franco y sombra dura.
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line, width: 2),
                borderRadius: BorderRadius.circular(AppShape.rCard),
                boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    // Avatar: acento plano + borde negro (sin degradado).
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppShape.rBtn),
                      color: AppColors.accent,
                      border: Border.all(color: AppColors.ink, width: 2),
                    ),
                    child: const Center(child: BBallGlyph(size: 24)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              c.$1,
                              style: AppText.archivo(
                                size: 15,
                                weight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              c.$3,
                              style: AppText.grotesk(
                                size: 10,
                                color: AppColors.white(0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          c.$2,
                          style: AppText.grotesk(
                            size: 12,
                            color: AppColors.white(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
