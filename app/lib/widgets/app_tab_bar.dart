import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import 'bball_glyph.dart';

enum AppTab { home, list, plus, chat, profile }

/// Barra de navegación retro-pop: pill blanca con botones circulares. El
/// indicador activo es UNA pelota de básquet naranja (con sus líneas, como la
/// "O" del logo) que SALTA en arco hasta la pestaña elegida. La pelota no
/// lleva ícono: actúa como "máscara" de color — cuando pasa por encima de un
/// ícono, ese ícono se pinta de blanco.
class AppTabBar extends StatefulWidget {
  final AppTab active;
  final ValueChanged<AppTab> onChange;

  const AppTabBar({super.key, required this.active, required this.onChange});

  @override
  State<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends State<AppTabBar>
    with SingleTickerProviderStateMixin {
  static const List<AppTab> _slots = [
    AppTab.home,
    AppTab.list,
    AppTab.plus,
    AppTab.chat,
    AppTab.profile,
  ];
  static const double _item = 46; // diámetro de cada botón circular
  static const double _hop = 26; // altura del salto de la pelota

  /// Naranja pelota de básquet (como la "O" del logo).
  static const Color _ballOrange = Color(0xFFFF6B1A);

  // El salto va de [_from] a [_to] mientras corre el controller.
  late AppTab _from = widget.active;
  late AppTab _to = widget.active;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1, // sin animación inicial: la pelota arranca apoyada
  );

  @override
  void didUpdateWidget(covariant AppTabBar old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      setState(() {
        _from = _to;
        _to = widget.active;
      });
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  IconData _iconFor(AppTab t) => switch (t) {
        AppTab.home => Icons.map_outlined,
        AppTab.list => Icons.sports_basketball_outlined,
        AppTab.plus => Icons.add,
        AppTab.chat => Icons.chat_bubble_outline,
        AppTab.profile => Icons.person_outline,
      };

  /// Centro horizontal del slot [i] dentro del ancho interno [innerW]
  /// (la Row usa spaceBetween con items de ancho fijo).
  double _slotCenter(double innerW, int i) {
    final gap = (innerW - _slots.length * _item) / (_slots.length - 1);
    return i * (_item + gap) + _item / 2;
  }

  /// Posición X actual del centro de la pelota (interpolando el salto).
  double _ballX(double innerW) {
    final t = Curves.easeInOut.transform(_ctrl.value);
    final fromX = _slotCenter(innerW, _slots.indexOf(_from));
    final toX = _slotCenter(innerW, _slots.indexOf(_to));
    return fromX + (toX - fromX) * t;
  }

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
      child: LayoutBuilder(
        builder: (context, cons) {
          final innerW = cons.maxWidth;
          return SizedBox(
            height: _item,
            child: Stack(
              clipBehavior: Clip.none, // la pelota se eleva por fuera del pill
              children: [
                // Capa 1: fondos de los botones (capturan los taps).
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final t in _slots)
                      t == AppTab.plus
                          ? _PlusButton(
                              color: _ballOrange,
                              onTap: () => widget.onChange(t))
                          : _TabCircle(onTap: () => widget.onChange(t)),
                  ],
                ),
                // Capa 2: la pelota de básquet (sin ícono), saltando en arco
                // con squash & stretch (se estira al volar, se aplasta al aterrizar).
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final x = _ballX(innerW);
                    final t = _ctrl.value;
                    // Arco del salto: sube y baja una sola vez.
                    final y = -_hop * math.sin(math.pi * t);
                    // Squash & stretch: deform es 0 en suelo (t=0,1) y 1 en el
                    // pico (t=0.5). scaleY se estira en el aire, scaleX se
                    // contrae para preservar volumen. Al tocar el suelo ambos
                    // vuelven a 1.0.
                    final deform = math.sin(math.pi * t);
                    final scaleY = 1.0 + 0.12 * deform;
                    final scaleX = 1.0 / math.sqrt(scaleY);
                    return Positioned(
                      left: x - _item / 2,
                      top: y,
                      child: IgnorePointer(
                        child: Transform.scale(
                          scaleX: scaleX,
                          scaleY: scaleY,
                          // Relleno + sombra ABAJO, líneas del glyph al medio y
                          // el aro negro arriba (si la sombra fuera del aro
                          // transparente, se pintaría sobre el glyph y taparía
                          // la pelota con un disco negro).
                          child: Container(
                            width: _item,
                            height: _item,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _ballOrange,
                              boxShadow:
                                  AppFx.hardShadow(offset: const Offset(2, 2)),
                            ),
                            child: Stack(
                              children: [
                                // ClipOval: las costuras del glyph no deben
                                // sobrepasar el límite del círculo.
                                const Positioned.fill(
                                  child: ClipOval(
                                    child: BBallGlyph(
                                        size: _item, color: _ballOrange),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: AppColors.ink, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Capa 3: los íconos, por ENCIMA de la pelota. Quedan siempre
                // en su pestaña; cuando la pelota está debajo se pintan de
                // blanco (efecto "máscara"). El + va siempre blanco (su botón
                // es naranja).
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final ballX = _ballX(innerW);
                    return IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < _slots.length; i++)
                            SizedBox(
                              width: _item,
                              height: _item,
                              child: Icon(
                                _iconFor(_slots[i]),
                                size: _slots[i] == AppTab.plus ? 24 : 21,
                                color: _slots[i] == AppTab.plus ||
                                        (ballX - _slotCenter(innerW, i))
                                                .abs() <
                                            _item / 2
                                    ? Colors.white
                                    : AppColors.ink,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Fondo circular de pestaña (sin ícono: los íconos van en una capa superior).
class _TabCircle extends StatelessWidget {
  final VoidCallback onTap;

  const _TabCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.card,
          border: Border.all(color: AppColors.ink, width: 2),
        ),
      ),
    );
  }
}

class _PlusButton extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  const _PlusButton({required this.color, required this.onTap});

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
                      color:
                          widget.color.withAlpha(((1 - t) * 110).round()),
                    ),
                  ),
                Transform.scale(scale: scale, child: child),
              ],
            );
          },
          // Naranja pelota (el ícono "+" vive en la capa de íconos de la
          // barra, así la pelota que se posa encima no lo tapa).
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              border: Border.all(color: AppColors.ink, width: 2),
              boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
            ),
          ),
        ),
      ),
    );
  }
}
