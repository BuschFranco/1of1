import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/basketball_graffiti.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/under_construction.dart';
import 'add_court_screen.dart';
import 'pickup_create_screen.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  static const _options = [
    ('Crear pickup game', 'Organizá un partido en cualquier cancha', Icons.sports_basketball),
    ('Agregar cancha', '¿Conocés una cancha que no está?', Icons.add_location_alt_outlined),
    ('Reservar cancha', 'Reservá un horario', Icons.event_available_outlined),
  ];

  // La opción 1 (Reservar) todavía no tiene backend.
  static const _wip = {2};

  void _onTap(BuildContext context, int i) {
    if (i == 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PickupCreateScreen()),
      );
    } else if (i == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddCourtScreen()),
      );
    } else {
      showUnderConstruction(context, _options[i].$1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: Stack(
        children: [
          // Capa de graffiti decorativa centrada en el fondo.
          const Positioned.fill(
            child: Center(
              child: BasketballGraffiti(size: 300, color: AppColors.ink),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
            children: [
              Text(
                'Nuevo',
                style: AppText.archivo(
                  size: 34,
                  weight: FontWeight.w900,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < _options.length; i++)
                PressableWidget(
                  onTap: () => _onTap(context, i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(18),
                    // Card de opción: sólida con borde claro franco.
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.line, width: 1),
                      borderRadius: BorderRadius.circular(AppShape.rCard),
                    ),
                    child: Row(
                      children: [
                        Icon(_options[i].$3, size: 28, color: AppColors.accent),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _options[i].$1,
                                      style: AppText.archivo(size: 16, weight: FontWeight.w800),
                                    ),
                                  ),
                                  if (_wip.contains(i)) ...[
                                    const SizedBox(width: 8),
                                    const UnderConstructionBadge(),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _options[i].$2,
                                style: AppText.grotesk(size: 12, color: AppColors.white(0.55)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
