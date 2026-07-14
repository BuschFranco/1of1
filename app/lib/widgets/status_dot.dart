import 'package:flutter/material.dart';
import '../data/courts.dart';
import '../theme/app_theme.dart';

class StatusDot extends StatelessWidget {
  final CourtStatus status;
  const StatusDot({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      CourtStatus.open => (AppColors.open, 'ABIERTA'),
      CourtStatus.closed => (AppColors.closed, 'CERRADA'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Punto redondo con borde negro (retro-pop): el color habla solo.
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.grotesk(
            size: 11,
            weight: FontWeight.w600,
            color: color,
            letterSpacing: 0.02,
          ),
        ),
      ],
    );
  }
}
