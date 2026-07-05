import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Logo de la app (1of1). Muestra la imagen de marca escalada a [height]. Si el
/// asset todavía no está disponible, cae al wordmark de texto para no romper la
/// UI (así el código funciona aunque falte el PNG).
class AppLogo extends StatelessWidget {
  final double height;
  const AppLogo({super.key, this.height = 40});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_1of1.webp',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => _wordmark(),
    );
  }

  /// Fallback: el wordmark "1of1" en texto (mismo estilo que usaba la marca).
  Widget _wordmark() {
    final size = height * 0.52;
    return RichText(
      text: TextSpan(
        style: AppText.archivo(size: size, weight: FontWeight.w900),
        children: [
          const TextSpan(text: '1'),
          TextSpan(
            text: 'of',
            style: AppText.archivo(
                size: size, weight: FontWeight.w900, color: AppColors.accent),
          ),
          const TextSpan(text: '1'),
        ],
      ),
    );
  }
}
