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
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color, blurRadius: 8),
            ],
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
