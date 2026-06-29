import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';

/// Listado del historial de notificaciones (logros, títulos y subidas de nivel).
/// Se abre desde el botón de campana. Al entrar marca todo como leído.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Marcar leídas tras el primer frame (no durante el build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlaySessionService>().markNotificationsRead();
    });
  }

  /// "hace 5 min" / "hace 2 h" / "hace 3 d" / fecha corta.
  static String _ago(int millis) {
    final d =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
    if (d.inMinutes < 1) return 'recién';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays < 7) return 'hace ${d.inDays} d';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final notifs = context.watch<PlaySessionService>().notifications;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  _iconBtn(Icons.arrow_back, () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Notificaciones',
                      style: AppText.archivo(size: 20, weight: FontWeight.w800),
                    ),
                  ),
                  if (notifs.isNotEmpty)
                    _iconBtn(Icons.delete_outline, () {
                      context.read<PlaySessionService>().clearNotifications();
                    }),
                ],
              ),
            ),
            Expanded(
              child: notifs.isEmpty
                  ? _empty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: notifs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _row(notifs[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.white(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.white(0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 48, color: AppColors.white(0.25)),
          const SizedBox(height: 14),
          Text(
            'Todavía no hay notificaciones',
            style: AppText.grotesk(size: 14, color: AppColors.white(0.5)),
          ),
          const SizedBox(height: 6),
          Text(
            'Acá vas a ver tus logros, títulos y\nsubidas de nivel.',
            textAlign: TextAlign.center,
            style: AppText.grotesk(size: 12, color: AppColors.white(0.35)),
          ),
        ],
      ),
    );
  }

  Widget _row(AppNotification n) {
    final e = n.event;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: e.color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: e.color.withAlpha(32),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: e.color.withAlpha(100)),
            ),
            child: Icon(e.icon, size: 20, color: e.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.headline,
                  style: AppText.grotesk(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.white(0.55),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.archivo(
                    size: 15,
                    weight: FontWeight.w800,
                    color: e.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _ago(n.atMillis),
            style: AppText.grotesk(size: 11, color: AppColors.white(0.4)),
          ),
        ],
      ),
    );
  }
}
