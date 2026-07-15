import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/notifications_service.dart';
import '../services/pickups_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/basketball_graffiti.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/under_construction.dart';
import 'add_court_screen.dart';
import 'main_shell.dart';
import 'pickup_chat_screen.dart';
import 'pickup_create_screen.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  static const _options = [
    ('Crear pickup game', 'Organizá un partido en cualquier cancha', Icons.sports_basketball),
    ('Unirse a pickup game', 'Entrá con el código que te pasaron', Icons.key_outlined),
    ('Agregar cancha', '¿Conocés una cancha que no está?', Icons.add_location_alt_outlined),
    ('Reservar cancha', 'Reservá un horario', Icons.event_available_outlined),
  ];

  // La opción 3 (Reservar) todavía no tiene backend.
  static const _wip = {3};

  void _onTap(BuildContext context, int i) {
    if (i == 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PickupCreateScreen()),
      );
    } else if (i == 1) {
      _showJoinDialog(context);
    } else if (i == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddCourtScreen()),
      );
    } else {
      showUnderConstruction(context, _options[i].$1);
    }
  }

  /// Modal para unirse a un pickup con el código de 5 dígitos que pasa el
  /// creador. Éxito → notificación, badge de Crew y directo al chat del pickup.
  void _showJoinDialog(BuildContext context) {
    final codeCtrl = TextEditingController();
    var busy = false;
    String? error;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> join() async {
            if (busy) return;
            setState(() {
              busy = true;
              error = null;
            });
            final email = ctx.read<Session>().email ?? '';
            final res = await ctx
                .read<PickupsProvider>()
                .joinByCode(codeCtrl.text, email);
            if (!ctx.mounted) return;
            if (res.error != null) {
              setState(() {
                busy = false;
                error = res.error;
              });
              return;
            }
            // Dentro: avisar (con botón "Ir al chat") y caer directo en el chat.
            unawaited(NotificationsService.instance.showPickupChat(
                '¡Estás dentro! 🏀',
                'Tocá para ir al chat del pickup.',
                res.pickupId!));
            crewActivityNotifier.value = true;
            Navigator.of(dialogCtx).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PickupChatScreen(pickupId: res.pickupId!),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: AppColors.bgElev,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppShape.rCard)),
            title: Text('Unirse a pickup game',
                style: AppText.archivo(size: 18, weight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ingresá el código de 5 dígitos que te pasó quien creó el pickup.',
                  style:
                      AppText.grotesk(size: 13, color: AppColors.white(0.65)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  enabled: !busy,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  textAlign: TextAlign.center,
                  style: AppText.archivo(
                      size: 24,
                      weight: FontWeight.w900,
                      color: AppColors.accent,
                      letterSpacing: 0.35),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '·····',
                    hintStyle: AppText.archivo(
                        size: 24,
                        weight: FontWeight.w900,
                        color: AppColors.white(0.2),
                        letterSpacing: 0.35),
                    filled: true,
                    fillColor: AppColors.white(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => join(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      textAlign: TextAlign.center,
                      style: AppText.grotesk(
                          size: 12,
                          weight: FontWeight.w600,
                          color: AppColors.busy)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(dialogCtx).pop(),
                child: Text('Cancelar',
                    style: AppText.grotesk(
                        size: 13, color: AppColors.white(0.6))),
              ),
              TextButton(
                onPressed: busy ? null : join,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent),
                      )
                    : Text('UNIRME',
                        style: AppText.archivo(
                            size: 13,
                            weight: FontWeight.w900,
                            color: AppColors.accent,
                            letterSpacing: 0.08)),
              ),
            ],
          );
        },
      ),
    );
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
                'Juego',
                style: AppText.archivo(
                  size: 34,
                  weight: FontWeight.w900,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 20),
              // Una sola card con las opciones como filas planas separadas por
              // hairlines (mismo lenguaje editorial que el perfil).
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppShape.rCard),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _options.length; i++) ...[
                      if (i > 0)
                        Container(height: 1, color: AppColors.white(0.06)),
                      PressableWidget(
                        onTap: () => _onTap(context, i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          child: Row(
                            children: [
                              Icon(_options[i].$3,
                                  size: 24, color: AppColors.accent),
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
                                            style: AppText.archivo(
                                                size: 16,
                                                weight: FontWeight.w800),
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
                                      style: AppText.grotesk(
                                          size: 12,
                                          color: AppColors.white(0.55)),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: AppColors.white(0.35), size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
