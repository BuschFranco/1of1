import 'package:flutter/material.dart';

/// Wraps [child] with a slide-up + fade-in that triggers when the widget
/// scrolls into the viewport while scrolling DOWN. Scrolling back up never
/// triggers reveals, avoiding awkward reverse animations.
class RevealOnScroll extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double slideDistance;

  const RevealOnScroll({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.slideDistance = 12,
  });

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _revealed = false;
  double _lastPos = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.slideDistance),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    if (!mounted) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final viewport = MediaQuery.of(context).size.height;

    // Above viewport: user scrolled UP to it → reveal instantly, no animation
    if (offset.dy < 0) {
      _revealInstantly();
      return;
    }

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    _lastPos = scrollable.position.pixels;

    // Initial load (scroll at top): reveal immediately if on screen
    if (_lastPos <= 1 && offset.dy < viewport) {
      _reveal();
      return;
    }

    // Below viewport, or visible after scroll: listen for scroll-down
    scrollable.position.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted || _revealed) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;

    final currentPixels = scrollable.position.pixels;
    if (currentPixels <= _lastPos) {
      _lastPos = currentPixels;
      return;
    }
    _lastPos = currentPixels;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final viewport = MediaQuery.of(context).size.height;

    if (offset.dy < 0 || offset.dy >= viewport) return;
    if (offset.dy < viewport - widget.slideDistance) {
      _reveal();
    }
  }

  void _reveal() {
    _revealed = true;
    _ctrl.forward();
    final scrollable = Scrollable.maybeOf(context);
    scrollable?.position.removeListener(_onScroll);
  }

  void _revealInstantly() {
    _revealed = true;
    _ctrl.value = 1;
    final scrollable = Scrollable.maybeOf(context);
    scrollable?.position.removeListener(_onScroll);
  }

  @override
  void dispose() {
    final scrollable = Scrollable.maybeOf(context);
    scrollable?.position.removeListener(_onScroll);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
