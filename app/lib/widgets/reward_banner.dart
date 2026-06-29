import 'dart:async';
import 'package:flutter/material.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';

/// Overlay que muestra, de a uno y con animación, los eventos de recompensa
/// encolados en [PlaySessionService] (logro/título desbloqueado, subida de
/// nivel). Cada banner entra desde arriba, se queda unos segundos y sale solo;
/// al salir descarta el evento ([onConsume]) y muestra el siguiente.
class RewardOverlay extends StatefulWidget {
  final List<RewardEvent> rewards;
  final VoidCallback onConsume;

  const RewardOverlay({
    super.key,
    required this.rewards,
    required this.onConsume,
  });

  @override
  State<RewardOverlay> createState() => _RewardOverlayState();
}

class _RewardOverlayState extends State<RewardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
  Timer? _timer;
  RewardEvent? _current;

  static const _dwell = Duration(milliseconds: 3000);

  @override
  void initState() {
    super.initState();
    _maybeShowNext();
  }

  @override
  void didUpdateWidget(covariant RewardOverlay old) {
    super.didUpdateWidget(old);
    _maybeShowNext();
  }

  void _maybeShowNext() {
    if (_current != null || widget.rewards.isEmpty) return;
    _current = widget.rewards.first;
    _ctrl.forward(from: 0);
    _timer?.cancel();
    _timer = Timer(_dwell, _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    if (!mounted) return;
    setState(() => _current = null);
    widget.onConsume(); // saca el evento de la cola → rebuild → próximo
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _current;
    // IMPORTANTE: este widget se monta como hijo de un Positioned en el Stack
    // del MainShell. Devuelve siempre contenido común (no un Positioned), así
    // nunca altera el tamaño del Stack (un hijo no-posicionado lo colapsa).
    if (r == null) return const SizedBox.shrink();
    final topInset = MediaQuery.of(context).padding.top;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topInset > 0 ? 8 : 12, 16, 0),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1.2),
            end: Offset.zero,
          ).animate(_anim),
          child: FadeTransition(
            opacity: _ctrl,
            child: _card(r),
          ),
        ),
      ),
    );
  }

  Widget _card(RewardEvent r) {
    return GestureDetector(
      onTap: _dismiss,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: r.color.withAlpha(120)),
          boxShadow: [
            BoxShadow(
              color: r.color.withAlpha(40),
              blurRadius: 24,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: AppColors.black(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: r.color.withAlpha(36),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: r.color.withAlpha(110)),
              ),
              child: Icon(r.icon, size: 22, color: r.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.headline,
                    style: AppText.grotesk(
                      size: 11,
                      weight: FontWeight.w600,
                      color: AppColors.white(0.6),
                      letterSpacing: 0.02,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.archivo(
                      size: 16,
                      weight: FontWeight.w800,
                      color: r.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
