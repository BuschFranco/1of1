import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

enum AppTab { home, list, plus, chat, profile }

/// Barra de navegación neobrutalista: pill oscura con botones circulares.
/// La pestaña activa es un círculo relleno de acento con ícono negro; las
/// inactivas son círculos oscuros con ícono blanco. Sin labels ni subrayado.
class AppTabBar extends StatelessWidget {
  final AppTab active;
  final ValueChanged<AppTab> onChange;

  const AppTabBar({super.key, required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.line, width: 2),
        boxShadow: AppFx.hardShadow(),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _TabCircle(
            active: active == AppTab.home,
            icon: Icons.map_outlined,
            onTap: () => onChange(AppTab.home),
          ),
          _TabCircle(
            active: active == AppTab.list,
            icon: Icons.sports_basketball_outlined,
            onTap: () => onChange(AppTab.list),
          ),
          _PlusButton(onTap: () => onChange(AppTab.plus)),
          _TabCircle(
            active: active == AppTab.chat,
            icon: Icons.chat_bubble_outline,
            onTap: () => onChange(AppTab.chat),
          ),
          _TabCircle(
            active: active == AppTab.profile,
            icon: Icons.person_outline,
            onTap: () => onChange(AppTab.profile),
          ),
        ],
      ),
    );
  }
}

/// Botón circular de pestaña: relleno de acento + ícono negro si está activa;
/// círculo oscuro + ícono blanco si no.
class _TabCircle extends StatelessWidget {
  final bool active;
  final IconData icon;
  final VoidCallback onTap;

  const _TabCircle({
    required this.active,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.accent : AppColors.card,
          border: Border.all(color: AppColors.ink, width: 2),
          boxShadow: active ? AppFx.hardShadow(offset: const Offset(2, 2)) : null,
        ),
        child: Icon(
          icon,
          size: 21,
          // Activo: círculo rojo → ícono blanco. Inactivo: crema → ícono negro.
          color: active ? Colors.white : AppColors.ink,
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
        width: 46,
        height: 46,
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
                    width: 46 + t * 34,
                    height: 46 + t * 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withAlpha(((1 - t) * 110).round()),
                    ),
                  ),
                Transform.scale(scale: scale, child: child),
              ],
            );
          },
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
              border: Border.all(color: AppColors.ink, width: 2),
              boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
