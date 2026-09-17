import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// Selector de dos o más segmentos, estilo pill retro-pop (papel + borde
/// negro + sombra dura). Generaliza el switch Perfil/Amigos de
/// `profile_screen.dart` para reusarlo en otras pantallas con sub-pestañas
/// deslizables (ver `SocialScreen`, Crew/Noticias). `ProfileScreen` en sí no
/// se tocó — sigue con su implementación propia, sin arriesgar algo que ya
/// funciona; este widget lo usan solo las pantallas nuevas que lo pidan.
class SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChange;

  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(color: AppColors.line, width: 1),
        boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) _tabBtn(labels[i], i),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int idx) {
    final active = activeIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChange(idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            // Radio chip por estar anidado dentro del selector rBtn.
            borderRadius: BorderRadius.circular(AppShape.rChip),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.grotesk(
              size: 13,
              weight: FontWeight.w700,
              color: active ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
