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
      CourtStatus.busy => (AppColors.busy, 'OCUPADA'),
      CourtStatus.closed => (AppColors.closed, 'CERRADA'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cuadradito plano (neobrutalismo): sin glow, el color habla solo.
        Container(width: 8, height: 8, color: color),
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
