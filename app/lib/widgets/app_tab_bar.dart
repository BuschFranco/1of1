import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppTab { home, list, plus, chat, profile }

/// Barra de navegación estilo Spotify: gradiente difuminado desde abajo con
/// íconos flotando encima. Sin pill ni bordes. El indicador activo es un
/// círculo naranja que se desliza horizontalmente.
class AppTabBar extends StatefulWidget {
  final AppTab active;
  final AppTab previous;
  final ValueChanged<AppTab> onChange;

  const AppTabBar({
    super.key,
    required this.active,
    required this.previous,
    required this.onChange,
  });

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
  static const double _item = 46;
  static const Color _indicatorColor = AppColors.accentAmber;

  late AppTab _from;
  late AppTab _to;

  final GlobalKey<_PlusButtonState> _plusKey = GlobalKey();

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && _to == AppTab.plus) {
        _plusKey.currentState?.pulse();
      }
    });

  @override
  void initState() {
    super.initState();
    _from = widget.previous;
    _to = widget.active;
    if (_from != _to) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ctrl
            ..stop()
            ..reset()
            ..forward();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppTabBar old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _from = widget.previous;
      _to = widget.active;
      _ctrl
        ..stop()
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _navigateDelta(int delta) {
    final current = _slots.indexOf(widget.active);
    final next = current + delta;
    if (next >= 0 && next < _slots.length) {
      widget.onChange(_slots[next]);
    }
  }

  IconData _iconFor(AppTab t, bool isActive) => switch (t) {
        AppTab.home => isActive ? Icons.map : Icons.map_outlined,
        AppTab.list =>
          isActive ? Icons.sports_basketball : Icons.sports_basketball_outlined,
        AppTab.plus => Icons.add,
        AppTab.chat =>
          isActive ? Icons.chat_bubble : Icons.chat_bubble_outline,
        AppTab.profile => isActive ? Icons.person : Icons.person_outline,
      };

  double _slotCenter(double innerW, int i) {
    final gap = (innerW - _slots.length * _item) / (_slots.length - 1);
    return i * (_item + gap) + _item / 2;
  }

  double _indicatorX(double innerW) {
    final t = Curves.easeInOut.transform(_ctrl.value);
    final fromX = _slotCenter(innerW, _slots.indexOf(_from));
    final toX = _slotCenter(innerW, _slots.indexOf(_to));
    return fromX + (toX - fromX) * t;
  }

  double _stretchFactor() {
    final t = _ctrl.value;
    if (t >= 1) return 1.0;
    return 1.0 + 0.25 * math.sin(math.pi * t);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          _navigateDelta(1);
        } else if (velocity > 200) {
          _navigateDelta(-1);
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Color(0xE60A0A0A),
              Color(0xF20A0A0A),
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        padding: const EdgeInsets.only(bottom: 12, top: 24),
        child: LayoutBuilder(
          builder: (context, cons) {
            final innerW = cons.maxWidth;
            return SizedBox(
              height: _item,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Capa 1: áreas de tap.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final t in _slots)
                        t == AppTab.plus
                            ? _PlusButton(
                                key: _plusKey,
                                color: _indicatorColor,
                                onTap: () => widget.onChange(t))
                            : _TabCircle(onTap: () => widget.onChange(t)),
                    ],
                  ),
                  // Capa 2: indicador pill deslizante + estiramiento.
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      final x = _indicatorX(innerW);
                      final stretch = _stretchFactor();
                      final baseSize = _item - 6;
                      return Positioned(
                        left: x - (baseSize * stretch) / 2,
                        top: 3,
                        child: IgnorePointer(
                          child: Container(
                            width: baseSize * stretch,
                            height: baseSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(baseSize / 2),
                              color: _indicatorColor,
                              boxShadow: [
                                BoxShadow(
                                  color: _indicatorColor.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Capa 3: íconos.
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      final indX = _indicatorX(innerW);
                      return IgnorePointer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var i = 0; i < _slots.length; i++)
                              SizedBox(
                                width: _item,
                                height: _item,
                                child: Icon(
                                  _iconFor(
                                      _slots[i],
                                      _slots[i] == AppTab.plus ||
                                          (indX - _slotCenter(innerW, i))
                                                  .abs() <
                                              _item / 2),
                                  size: _slots[i] == AppTab.plus ? 24 : 21,
                                  color: _slots[i] == AppTab.plus ||
                                          (indX - _slotCenter(innerW, i))
                                                  .abs() <
                                              _item / 2
                                      ? Colors.white
                                      : AppColors.white(0.6),
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
      ),
    );
  }
}

/// Área de tap para tabs (sin borde, sin fondo visible).
class _TabCircle extends StatelessWidget {
  final VoidCallback onTap;

  const _TabCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(width: 46, height: 46),
    );
  }
}

class _PlusButton extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  const _PlusButton({super.key, required this.color, required this.onTap});

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

  void pulse() => _ctrl.forward(from: 0);

  void _handleTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        height: 46,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value;
            final scale = 1 + 0.14 * math.sin(t * math.pi);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (t > 0 && t < 1)
                  Container(
                    width: 46 + t * 34,
                    height: 46 + t * 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withAlpha(((1 - t) * 110).round()),
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
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
