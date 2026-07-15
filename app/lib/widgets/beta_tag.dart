import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Marca de versión "fase BETA": chiquita y gris, para una esquina de las
/// pantallas de entrada (onboarding / login).
class BetaTag extends StatelessWidget {
  const BetaTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'fase BETA',
      style: AppText.grotesk(
        size: 10,
        weight: FontWeight.w600,
        color: AppColors.white(0.35),
        letterSpacing: 0.12,
      ),
    );
  }
}
