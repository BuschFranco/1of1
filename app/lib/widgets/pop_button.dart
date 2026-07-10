import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// CTA primario retro-pop: pill rellena en crema/rosa (blush), borde fino
/// y sombra suave. Al presionar, el botón se encoge 5% (scale-down moderno).
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

class _PopButtonState extends State<PopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 100),
      lowerBound: 0,
      upperBound: 1,
    );
    _anim = Tween<double>(begin: 1, end: 0.95).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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

    return GestureDetector(
      onTap: enabled ? widget.onPressed : null,
      onTapDown: enabled ? (_) => _ctrl.forward() : null,
      onTapUp: enabled ? (_) => _ctrl.reverse() : null,
      onTapCancel: enabled ? () => _ctrl.reverse() : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, child) => Transform.scale(
          scale: _anim.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding:
              widget.expand ? null : const EdgeInsets.symmetric(horizontal: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? AppColors.accent : AppColors.black(0.08),
            borderRadius: BorderRadius.circular(AppShape.rBtn),
            border: Border.all(
              color: enabled ? AppColors.accentDark : AppColors.black(0.25),
              width: 1,
            ),
            boxShadow: enabled ? AppFx.hardShadow() : null,
          ),
          child: content,
        ),
      ),
    );
  }
}
