import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Corre [action] mostrando un overlay bloqueante hasta que termine.
///
/// Para escrituras que NO tienen un botón donde meter un spinner: borrados
/// desde un menú contextual, acciones de un bottom sheet que se cierra al
/// tocarlas, o cualquier cosa que desmonte el árbol al terminar. Sin esto el
/// usuario toca, no pasa nada visible por segundos (el backend duerme y puede
/// tardar 30-60 s en despertar) y vuelve a tocar.
///
/// Bloquea la pantalla a propósito: es lo que evita el doble disparo, que en un
/// borrado significa dos peticiones de baja.
///
/// El navigator y el messenger se resuelven ANTES de empezar, así el overlay se
/// puede cerrar y el error mostrar aunque [context] ya esté desmontado (típico:
/// la acción cierra la pantalla que la disparó).
///
/// Devuelve lo que devuelva [action], o null si lanzó. Con [errorMessage] se
/// muestra un SnackBar ante una excepción; sin él, el error se propaga al caller.
Future<T?> runBusy<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? errorMessage,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  nav.push(
    DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.black(0.45),
      builder: (_) => const Center(child: BusySpinner()),
    ),
  );

  try {
    return await action();
  } catch (e) {
    if (errorMessage == null) rethrow;
    messenger.showSnackBar(
      SnackBar(
        content: Text(errorMessage, style: AppText.grotesk(size: 13)),
        backgroundColor: AppColors.bgElev,
      ),
    );
    return null;
  } finally {
    // Cierra el overlay incluso si la acción lanzó o si el árbol de abajo
    // cambió mientras estaba en vuelo.
    nav.pop();
  }
}

/// Spinner de la app, para no repetir los mismos cuatro parámetros en cada
/// lugar donde hace falta uno.
class BusySpinner extends StatelessWidget {
  final double size;
  final Color? color;

  const BusySpinner({super.key, this.size = 28, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        // El trazo acompaña al diámetro: a 8px un stroke de 2 se ve como una
        // mancha.
        strokeWidth: size <= 12
            ? 1.5
            : size <= 20
                ? 2
                : 2.5,
        color: color ?? AppColors.accent,
      ),
    );
  }
}
