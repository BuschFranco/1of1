import 'package:flutter/material.dart';

/// Widget que se anima con slide-up + fade-in cuando es construido.
/// Para ListViews, usarlo como item builder con `addAutomaticKeepAlives: false`.
class SlideUpOnScroll extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Offset slideOffset;

  const SlideUpOnScroll({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
    this.slideOffset = const Offset(0, 30),
  });

  @override
  State<SlideUpOnScroll> createState() => _SlideUpOnScrollState();
}

class _SlideUpOnScrollState extends State<SlideUpOnScroll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: widget.slideOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    // Disparar animación después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
