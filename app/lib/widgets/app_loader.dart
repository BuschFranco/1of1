import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Overlay de carga a pantalla completa con el texto "1of1" (provisorio hasta
/// tener el logo). Hace un fade out suave cuando [visible] pasa a false y, al
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
        child: Container(
          color: AppColors.bg,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.accent, AppColors.accentDark],
                ).createShader(rect),
                child: Text(
                  '1of1',
                  style: AppText.archivo(
                    size: 46,
                    weight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.white(0.4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
