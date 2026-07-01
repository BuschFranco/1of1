import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// CTA primario pop-futurista: fondo con degradado de acento (naranja→ámbar),
/// glow neón, texto display (Chakra Petch) en mayúsculas con tracking y un leve
/// "scale" al presionar. Reemplaza los ElevatedButton/containers de CTA inline.
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

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final content = widget.loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.label.toUpperCase(),
                style: AppText.display(
                  size: 14,
                  weight: FontWeight.w700,
                  letterSpacing: 0.06,
                ),
              ),
              if (widget.icon != null) ...[
                const SizedBox(width: 8),
                Icon(widget.icon, size: 18, color: Colors.white),
              ],
            ],
          );

    return GestureDetector(
      onTap: enabled ? widget.onPressed : null,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding: widget.expand
              ? null
              : const EdgeInsets.symmetric(horizontal: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled
                ? AppFx.accentGradient()
                : LinearGradient(colors: [
                    AppColors.white(0.10),
                    AppColors.white(0.06),
                  ]),
            borderRadius: BorderRadius.circular(100),
            boxShadow: enabled
                ? AppFx.neonGlow(AppColors.accent, blur: 24, alpha: 105)
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}
