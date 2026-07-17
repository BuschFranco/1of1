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

    return GestureDetector(
      // Deslizar a la derecha (fuera de las tarjetas) vuelve a la pantalla
      // anterior, como en el resto de las pestañas. Sobre una tarjeta el
      // gesto lo captura su Dismissible (descartar).
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 0) Navigator.pop(context);
      },
      child: Scaffold(
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
                            _dismissibleInvite(p),
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
                            _dismissibleRow(n),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // Rojo destructivo (descartar). Local: AppColors no tiene token de peligro.
  static const Color _danger = Color(0xFFEF4444);

  /// Fondo que se revela al arrastrar una tarjeta a la derecha (mismo lenguaje
  /// que las notificaciones de Android): superficie sutil + tacho.
  Widget _dismissBg() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      decoration: BoxDecoration(
        color: _danger.withAlpha(22),
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: const Icon(Icons.delete_outline, size: 22, color: _danger),
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

  /// Invitación deslizable: descartarla equivale a RECHAZAR (el usuario
  /// desestimó la notificación). Se resuelve dentro de confirmDismiss y se
  /// devuelve false: la tarjeta desaparece sola cuando el provider la saca de
  /// las pendientes (evita el error de Dismissible aún montado), y si falla
  /// la red vuelve a su lugar.
  Widget _dismissibleInvite(Pickup p) {
    return Dismissible(
      key: ValueKey('invite-${p.pageId}'),
      direction: DismissDirection.startToEnd,
      background: _dismissBg(),
      confirmDismiss: (_) async {
        await _respond(p, false);
        return false;
      },
      child: _inviteCard(p),
    );
  }

  /// Notificación del historial deslizable: descartar la borra (como las
  /// notificaciones de Android).
  Widget _dismissibleRow(AppNotification n) {
    return Dismissible(
      key: ValueKey('notif-${n.kind.name}-${n.refId}-${n.atMillis}'),
      direction: DismissDirection.startToEnd,
      background: _dismissBg(),
      onDismissed: (_) =>
          context.read<PlaySessionService>().removeNotification(n),
      child: _row(n),
    );
  }

  Widget _inviteCard(Pickup p) {
    final busy = _working.contains(p.pageId);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Riel acento: es la única invitación "viva" del listado.
            Container(width: 3, color: AppColors.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withAlpha(26),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.sports_basketball,
                              size: 18, color: AppColors.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TE INVITARON A UN PICKUP',
                                  style: AppText.grotesk(
                                      size: 10,
                                      weight: FontWeight.w700,
                                      letterSpacing: 0.08,
                                      color: AppColors.white(0.45))),
                              const SizedBox(height: 3),
                              Text(p.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.archivo(
                                      size: 15,
                                      weight: FontWeight.w800,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Meta (cancha · fecha) alineada con el texto, no al ícono.
                    Padding(
                      padding: const EdgeInsets.only(left: 50),
                      child: Text(
                        '${_courtName(p.courtId)} · ${_dateLabel(p.dateTime)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.grotesk(
                            size: 12, color: AppColors.white(0.5)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ghostBtn(
                              'Rechazar', busy, () => _respond(p, false)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _solidBtn(
                              'Aceptar', busy, () => _respond(p, true)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Acción primaria: pill llena en acento (jerarquía clara sobre el ghost).
  Widget _solidBtn(String label, bool busy, VoidCallback onTap) {
    return PressableWidget(
      onTap: busy ? null : onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black),
              )
            : Text(label,
                style: AppText.archivo(
                    size: 13.5,
                    weight: FontWeight.w800,
                    color: Colors.black)),
      ),
    );
  }

  /// Acción secundaria: pill fantasma neutra (no compite con la primaria).
  Widget _ghostBtn(String label, bool busy, VoidCallback onTap) {
    return PressableWidget(
      onTap: busy ? null : onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.white(0.22), width: 1),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.white(0.5)),
              )
            : Text(label,
                style: AppText.archivo(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.75))),
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
      // El color del evento vive en el riel izquierdo y el ícono; el resto de
      // la tarjeta queda neutro (hairline) para que respire.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Riel de color: la firma del evento, sin encerrar la tarjeta.
            Container(width: 3, color: e.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: e.color.withAlpha(26),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(e.icon, size: 18, color: e.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.headline.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.grotesk(
                                    size: 10,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0.08,
                                    color: AppColors.white(0.45),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _ago(n.atMillis),
                                style: AppText.grotesk(
                                    size: 10.5,
                                    color: AppColors.white(0.35)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.archivo(
                              size: 15,
                              weight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
