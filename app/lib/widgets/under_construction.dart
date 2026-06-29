import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Chip chico "EN CONSTRUCCIÓN" para marcar secciones sin backend todavía.
class UnderConstructionBadge extends StatelessWidget {
  const UnderConstructionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB020).withAlpha(36),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: const Color(0xFFFFB020).withAlpha(110)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 11, color: Color(0xFFFFC457)),
          const SizedBox(width: 4),
          Text(
            'EN CONSTRUCCIÓN',
            style: AppText.grotesk(
              size: 9,
              weight: FontWeight.w700,
              color: const Color(0xFFFFC457),
              letterSpacing: 0.06,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner ancho para encabezar una pantalla en construcción.
class UnderConstructionBanner extends StatelessWidget {
  final String text;
  const UnderConstructionBanner({super.key, this.text = 'Sección en construcción — próximamente'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB020).withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB020).withAlpha(90)),
      ),
      child: Row(
        children: [
          const Icon(Icons.construction, size: 16, color: Color(0xFFFFC457)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.grotesk(size: 12.5, color: const Color(0xFFFFC457)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muestra un SnackBar de "en construcción".
void showUnderConstruction(BuildContext context, [String? feature]) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '${feature ?? 'Esta sección'} está en construcción',
        style: AppText.grotesk(size: 13),
      ),
      backgroundColor: AppColors.bgElev,
    ),
  );
}
