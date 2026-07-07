import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// CTA primario retro-pop: pill rellena en crema/rosa (blush), borde negro
/// franco y sombra dura desplazada. Al presionar, el botón se "hunde": se
/// traslada hacia la sombra y la pierde (táctil clásico). Texto display negro
/// en mayúsculas.
class PopButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;

  const PopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
  });

  @override
  State<PopButton> createState() => _PopButtonState();
}

class _PopButtonState extends State<PopButton> {
  bool _down = false;

  static const _shadowOffset = Offset(4, 4);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final content = widget.loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.ink),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.label.toUpperCase(),
                style: AppText.display(
                  size: 14,
                  weight: FontWeight.w800,
                  letterSpacing: 0.04,
                ),
              ),
              if (widget.icon != null) ...[
                const SizedBox(width: 8),
                Icon(widget.icon, size: 18, color: AppColors.ink),
              ],
            ],
          );

    // Hundimiento: trasladamos el botón hacia donde estaba la sombra, así el
    // conjunto (botón+sombra) no cambia de tamaño y el layout no salta.
    final pressed = _down && enabled;
    return GestureDetector(
      onTap: enabled ? widget.onPressed : null,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
            pressed ? _shadowOffset.dx : 0, pressed ? _shadowOffset.dy : 0, 0),
        height: widget.height,
        width: widget.expand ? double.infinity : null,
        padding:
            widget.expand ? null : const EdgeInsets.symmetric(horizontal: 26),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.blush : AppColors.black(0.08),
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(
            color: enabled ? AppColors.ink : AppColors.black(0.25),
            width: 2,
          ),
          boxShadow: enabled && !pressed
              ? AppFx.hardShadow(offset: _shadowOffset)
              : null,
        ),
        child: content,
      ),
    );
  }
}
