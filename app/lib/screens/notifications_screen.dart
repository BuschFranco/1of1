import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../services/courts_provider.dart';
import '../services/pickups_provider.dart';
import '../services/play_session_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_widget.dart';

/// Listado de notificaciones: arriba las invitaciones a pickup pendientes (con
/// Aceptar/Rechazar), abajo el historial (logros, títulos, subidas de nivel).
/// Se abre desde el botón de campana. Al entrar marca el historial como leído.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // pageIds de invitaciones que están actualizándose (muestran loader).
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    // Marcar leídas tras el primer frame (no durante el build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlaySessionService>().markNotificationsRead();
    });
  }

  String get _myEmail =>
      (context.read<Session>().email ?? '').trim().toLowerCase();

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

  String _courtName(String courtId) {
    for (final Court c in context.read<CourtsProvider>().courts) {
      if (c.id == courtId) return c.name;
    }
    return 'Cancha';
  }

  String _dateLabel(String? iso) {
    if (iso == null || iso.isEmpty) return 'Sin fecha';
    try {
      final dt = DateTime.parse(iso);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month} · $h:$m';
    } catch (_) {
      return 'Sin fecha';
    }
  }

  Future<void> _respond(Pickup p, bool accept) async {
    if (_working.contains(p.pageId)) return;
    setState(() => _working.add(p.pageId));
    try {
      final email = context.read<Session>().email ?? '';
      final provider = context.read<PickupsProvider>();
      if (accept) {
        await provider.accept(p, email);
      } else {
        await provider.decline(p, email);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo responder. Revisá la conexión.',
                style: AppText.grotesk(size: 13)),
            backgroundColor: AppColors.bgElev,
          ),
        );
      }
    }
    if (mounted) setState(() => _working.remove(p.pageId));
  }

  @override
  Widget build(BuildContext context) {
    final notifs = context.watch<PlaySessionService>().notifications;
    final invites = context.watch<PickupsProvider>().pendingInvitesFor(_myEmail);

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
              child: (invites.isEmpty && notifs.isEmpty)
                  ? _empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        if (invites.isNotEmpty) ...[
                          _sectionLabel('INVITACIONES A PICKUP'),
                          const SizedBox(height: 10),
                          for (final p in invites) ...[
                            _inviteCard(p),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 6),
                        ],
                        if (notifs.isNotEmpty) ...[
                          if (invites.isNotEmpty) ...[
                            _sectionLabel('HISTORIAL'),
                            const SizedBox(height: 10),
                          ],
                          for (final n in notifs) ...[
                            _row(n),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: AppText.grotesk(
          size: 11,
          weight: FontWeight.w700,
          color: AppColors.white(0.45),
          letterSpacing: 0.1,
        ),
      );

  Widget _inviteCard(Pickup p) {
    final busy = _working.contains(p.pageId);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(32),
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                  border: Border.all(color: AppColors.accent, width: 1.5),
                ),
                child: Icon(Icons.mail_outline, size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Te invitaron a un pickup',
                        style: AppText.grotesk(
                            size: 11,
                            weight: FontWeight.w600,
                            color: AppColors.white(0.55))),
                    const SizedBox(height: 2),
                    Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.archivo(
                            size: 15,
                            weight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('${_courtName(p.courtId)} · ${_dateLabel(p.dateTime)}',
                        style: AppText.grotesk(
                            size: 12, color: AppColors.white(0.5))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _respondBtn(
                    'RECHAZAR', AppColors.closed, busy, () => _respond(p, false)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _respondBtn(
                    'ACEPTAR', AppColors.accent, busy, () => _respond(p, true)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _respondBtn(
      String label, Color color, bool busy, VoidCallback onTap) {
    return PressableWidget(
      onTap: busy ? null : onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: color, width: 1.5),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Text(label,
                style: AppText.archivo(
                    size: 13,
                    weight: FontWeight.w900,
                    letterSpacing: 0.04,
                    color: color)),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.white(0.25), width: 1.5),
        ),
        child: Icon(icon, color: AppColors.ink, size: 18),
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
            'Acá vas a ver tus invitaciones a pickup,\nlogros, títulos y subidas de nivel.',
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
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        // Borde pleno del color del evento (estado franco).
        border: Border.all(color: e.color, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: e.color.withAlpha(32),
              borderRadius: BorderRadius.circular(AppShape.rBtn),
              border: Border.all(color: e.color, width: 1.5),
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
