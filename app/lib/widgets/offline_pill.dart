import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import 'busy_overlay.dart';
import 'pressable_widget.dart';

/// Para acciones que solo funcionan con conexión (cambiar handle, agregar
/// amigos, eliminar la cuenta…). En modo offline avisa y devuelve false.
bool requireOnline(BuildContext context) {
  if (!context.read<Session>().offline) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Necesitás conexión para hacer esto.',
          style: AppText.grotesk(size: 13)),
      backgroundColor: AppColors.bgElev,
    ));
  return false;
}

/// Botón flotante del modo offline: avisa que no hay conexión y, al tocarlo,
/// reintenta hablar con el backend ([Session.reconnect]). Lo registrado sin
/// conexión ya está guardado en el celu; esto solo lo sube.
class OfflinePill extends StatelessWidget {
  const OfflinePill({super.key});

  Future<void> _tap(BuildContext context) async {
    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await session.reconnect();
    if (ok) return;
    // Si la sesión venció, `reconnect` ya mandó al login: no hay nada que avisar.
    if (!session.isLoggedIn) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Seguís sin conexión. Tus sesiones se guardan en el celu y se suben '
          'cuando vuelva internet.',
          style: AppText.grotesk(size: 13),
        ),
        backgroundColor: AppColors.bgElev,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select<Session, bool>((s) => s.reconnecting);
    return PressableWidget(
      onTap: busy ? null : () => _tap(context),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.accent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(110),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.white(0.7)),
            const SizedBox(width: 10),
            Text('Sin conexión',
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.white(0.7))),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: AppColors.white(0.15),
            ),
            if (busy)
              const BusySpinner(size: 16)
            else
              Text('INICIAR SESIÓN',
                  style: AppText.archivo(
                      size: 12,
                      weight: FontWeight.w900,
                      color: AppColors.accent,
                      letterSpacing: 0.06)),
          ],
        ),
      ),
    );
  }
}
