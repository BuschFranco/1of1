import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

enum AppTab { home, list, plus, chat, profile }

class AppTabBar extends StatelessWidget {
  final AppTab active;
  final ValueChanged<AppTab> onChange;

  const AppTabBar({super.key, required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xE011181F),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.white(0.08)),
            boxShadow: [
              BoxShadow(
                color: AppColors.black(0.35),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
              // Glow neón tenue de la barra (pop-futurismo).
              BoxShadow(
                color: AppColors.accent.withAlpha(28),
                blurRadius: 30,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _tabItem(AppTab.home, 'Mapa', Icons.map_outlined),
              _tabItem(AppTab.list, 'Canchas', Icons.sports_basketball_outlined),
              _PlusButton(onTap: () => onChange(AppTab.plus)),
              _tabItem(AppTab.chat, 'Crew', Icons.chat_bubble_outline),
              _tabItem(AppTab.profile, 'Perfil', Icons.person_outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabItem(AppTab tab, String label, IconData icon) {
    final isActive = active == tab;
    final color = isActive ? AppColors.accent : AppColors.white(0.55);
    return GestureDetector(
      onTap: () => onChange(tab),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícono activo con glow neón.
            Container(
              decoration: isActive
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: AppFx.neonGlow(AppColors.accent,
                          blur: 12, spread: 0, alpha: 130),
                    )
                  : null,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 3),
            // Indicador neón bajo la pestaña activa.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: isActive ? 16 : 0,
              height: 2,
              decoration: BoxDecoration(
                gradient: isActive ? AppFx.accentGradient() : null,
                borderRadius: BorderRadius.circular(2),
                boxShadow: isActive
                    ? AppFx.neonGlow(AppColors.accent, blur: 6, alpha: 140)
                    : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppText.grotesk(
                size: 10,
                weight: FontWeight.w600,
                color: color,
                letterSpacing: 0.02,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _PlusButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PlusButton({required this.onTap});

  @override
  State<_PlusButton> createState() => _PlusButtonState();
}

class _PlusButtonState extends State<_PlusButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      // Espacio fijo en el layout: la animación se desborda visualmente
      // (Clip.none) sin agrandar el botón ni mover al resto de la barra.
      child: SizedBox(
        width: 48,
        height: 48,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value;
            // Rebote rápido: el botón crece y vuelve (0 → 1 → 0).
            final scale = 1 + 0.14 * math.sin(t * math.pi);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Anillo de pulso que se expande y desvanece al tocar.
                if (t > 0 && t < 1)
                  Container(
                    width: 48 + t * 34,
                    height: 48 + t * 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16 + t * 12),
                      color: AppColors.accent.withAlpha(((1 - t) * 110).round()),
                    ),
                  ),
                Transform.scale(scale: scale, child: child),
              ],
            );
          },
          child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent, AppColors.accentDark],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withAlpha(85),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 24),
        ),
        ),
      ),
    );
  }
}
