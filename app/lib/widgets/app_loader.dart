import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'pop_background.dart';

/// Overlay de carga a pantalla completa con el logo de 1of1. Hace un fade out
/// suave cuando [visible] pasa a false y, al
/// terminar la animación, se quita del árbol (deja de pintar y de capturar
/// toques).
class AppLoader extends StatefulWidget {
  final bool visible;
  const AppLoader({super.key, required this.visible});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  // Una vez que el fade out terminó, dejamos de construir el overlay.
  bool _gone = false;

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        onEnd: () {
          if (!widget.visible && mounted) setState(() => _gone = true);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            const PopBackground(),
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo de 1of1 con glow neón de acento.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow:
                          AppFx.neonGlow(AppColors.accent, blur: 34, alpha: 90),
                    ),
                    child: const AppLogo(height: 120),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent.withAlpha(180)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
