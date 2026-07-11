import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/achievements.dart';
import '../data/cosmetics.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../services/courts_provider.dart';
import '../services/pickups_provider.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_widget.dart';

/// Chat de un pickup: solo lectura (no se puede escribir todavía), con un panel
/// desplegable desde el título que muestra descripción, lugar/fecha/hora, los
/// equipos con sus miembros y el estado de cada uno (aceptó / pendiente /
/// rechazó). El invitado puede aceptar o rechazar; el creador puede mover
/// miembros entre equipos, quitarlos y eliminar el pickup.
class PickupChatScreen extends StatefulWidget {
  final String pickupId;
  const PickupChatScreen({super.key, required this.pickupId});

  @override
  State<PickupChatScreen> createState() => _PickupChatScreenState();
}

class _PickupChatScreenState extends State<PickupChatScreen> {
  bool _infoOpen = true; // arranca desplegado para que la info sea visible
  bool _busy = false;

  String get _myEmail =>
      (context.read<Session>().email ?? '').trim().toLowerCase();

  Color _hex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.accent;
    }
  }

  String _courtName(Pickup p) {
    for (final Court c in context.read<CourtsProvider>().courts) {
      if (c.id == p.courtId) return c.name;
    }
    return 'Cancha';
  }

  String _dateLabel(String? iso) {
    if (iso == null || iso.isEmpty) return 'Sin fecha';
    try {
      final dt = DateTime.parse(iso);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month}/${dt.year} · $h:$m';
    } catch (_) {
      return 'Sin fecha';
    }
  }

  /// Nombre visible de un email (handle / nombre / "Vos" / email crudo).
  String _memberName(String email) {
    if (email.trim().toLowerCase() == _myEmail) return 'Vos';
    final p = context.read<ProfilesProvider>().byEmail(email);
    if (p != null && p.handle.isNotEmpty) return p.handle;
    if (p != null && p.name.isNotEmpty) return p.name;
    return email;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar. Revisá la conexión.',
                style: AppText.grotesk(size: 13)),
            backgroundColor: AppColors.bgElev,
          ),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // Pickup en vivo desde el provider (refleja movimientos/aceptaciones).
    final pickup = context.watch<PickupsProvider>().byId(widget.pickupId);
    if (pickup == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Text('Este pickup ya no está disponible.',
              style: AppText.grotesk(size: 14, color: AppColors.white(0.6))),
        ),
      );
    }

    final isCreator = pickup.isCreator(_myEmail);
    final iAmInvited = pickup.teamOf(_myEmail) != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(pickup.title,
            style: AppText.archivo(
                size: 18, weight: FontWeight.w900, color: Colors.white)),
        actions: [
          if (isCreator)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _busy ? null : () => _confirmDelete(pickup),
            )
          else if (iAmInvited)
            IconButton(
              tooltip: 'Abandonar pickup',
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _busy ? null : () => _confirmLeave(pickup),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _infoHeader(pickup),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  clipBehavior: Clip.hardEdge,
                  child: _infoOpen
                      ? _infoPanel(pickup, isCreator)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 20),
                _chatPlaceholder(),
              ],
            ),
          ),
          _disabledInputBar(),
        ],
      ),
    );
  }

  // Título tocable que despliega/colapsa el panel de info.
  Widget _infoHeader(Pickup pickup) {
    return PressableWidget(
      onTap: () => setState(() => _infoOpen = !_infoOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
          border: Border.all(color: AppColors.line, width: 2),
          boxShadow: AppFx.hardShadow(),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Info del pickup',
                  style: AppText.grotesk(
                      size: 13, weight: FontWeight.w700, color: Colors.white)),
            ),
            Icon(_infoOpen ? Icons.expand_less : Icons.expand_more,
                color: AppColors.white(0.6)),
          ],
        ),
      ),
    );
  }

  Widget _infoPanel(Pickup pickup, bool isCreator) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgElev,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lugar / fecha / formato.
          _infoRow(Icons.place_outlined, _courtName(pickup)),
          const SizedBox(height: 8),
          _infoRow(Icons.calendar_today_outlined, _dateLabel(pickup.dateTime)),
          const SizedBox(height: 8),
          _infoRow(Icons.sports_basketball_outlined,
              '${pickup.teamSize}v${pickup.teamSize} · a ${pickup.targetScore} pts'),
          if (pickup.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            _label('Descripción'),
            const SizedBox(height: 4),
            Text(pickup.notes,
                style:
                    AppText.grotesk(size: 13, color: AppColors.white(0.8))),
          ],
          const SizedBox(height: 16),
          _label('Equipos'),
          const SizedBox(height: 8),
          _teamBlock(pickup, 'A', pickup.teamAName, pickup.teamAColor,
              pickup.teamAMembers, isCreator),
          const SizedBox(height: 12),
          _teamBlock(pickup, 'B', pickup.teamBName, pickup.teamBColor,
              pickup.teamBMembers, isCreator),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.white(0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: AppText.grotesk(size: 13, color: AppColors.white(0.85))),
        ),
      ],
    );
  }

  Widget _label(String t) => Text(t.toUpperCase(),
      style: AppText.grotesk(
          size: 11,
          weight: FontWeight.w700,
          color: AppColors.white(0.45),
          letterSpacing: 0.08));

  Widget _teamBlock(Pickup pickup, String team, String name, String colorHex,
      List<String> members, bool isCreator) {
    final color = _hex(colorHex);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(name,
                  style: AppText.grotesk(
                      size: 13, weight: FontWeight.w800, color: Colors.white)),
              const SizedBox(width: 6),
              Text('${members.length}',
                  style:
                      AppText.grotesk(size: 12, color: AppColors.white(0.4))),
            ],
          ),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2),
              child: Text('Sin jugadores',
                  style:
                      AppText.grotesk(size: 12, color: AppColors.white(0.35))),
            )
          else
            for (final m in members) _memberRow(pickup, m, team, isCreator),
        ],
      ),
    );
  }

  /// Perfil del miembro: el propio si soy yo (más fresco), o el del cache.
  Profile? _profileFor(String email) {
    if (email.trim().toLowerCase() == _myEmail) {
      return context.read<Session>().profile;
    }
    return context.read<ProfilesProvider>().byEmail(email);
  }

  Widget _memberRow(Pickup pickup, String email, String team, bool isCreator) {
    final accepted = pickup.hasAccepted(email);
    final isMe = email.trim().toLowerCase() == _myEmail;

    final profile = _profileFor(email);
    final name = _memberName(email);
    final title = (profile?.title ?? '').trim();
    final level = (profile?.level ?? '').trim().isEmpty
        ? '1'
        : profile!.level.trim();

    // Colores: aceptados = normales, no aceptados = gris.
    final nameColor = !accepted
        ? AppColors.white(0.3)
        : isMe
            ? AppColors.accent
            : Colors.white;
    final titleColor = !accepted
        ? AppColors.white(0.2)
        : titleByName(title)?.color ?? AppColors.accent;
    final levelBg = !accepted
        ? AppColors.white(0.1)
        : AppColors.accent.withAlpha(28);
    final levelBorder = !accepted
        ? AppColors.white(0.15)
        : AppColors.accent;
    final levelText = !accepted
        ? AppColors.white(0.25)
        : AppColors.accent;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Izquierda: insignia de clan (o inicial).
          _clanInsignia(profile, name.isNotEmpty ? name[0].toUpperCase() : '?',
              grey: !accepted),
          const SizedBox(width: 10),
          // Centro: nombre + nivel inline + título (abajo).
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name + (email == pickup.createdBy ? ' · creador' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.grotesk(
                            size: 13,
                            weight: isMe ? FontWeight.w800 : FontWeight.w700,
                            color: nameColor),
                      ),
                    ),
                    // Nivel inline: solo el número, pegado a la derecha.
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: levelBg,
                        borderRadius: BorderRadius.circular(AppShape.rChip),
                        border: Border.all(color: levelBorder, width: 1),
                      ),
                      child: Text(level,
                          style: AppText.archivo(
                              size: 10,
                              weight: FontWeight.w900,
                              color: levelText)),
                    ),
                  ],
                ),
                if (title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.grotesk(
                          size: 11,
                          weight: FontWeight.w700,
                          color: titleColor),
                    ),
                  ),
              ],
            ),
          ),
          // Gestión (solo creador): mover / quitar / reenviar.
          if (isCreator) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: _busy ? null : () => _memberActions(pickup, email, team),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_vert,
                    size: 16,
                    color: accepted ? AppColors.white(0.5) : AppColors.white(0.2)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Insignia de clan del miembro (mismo look que en el perfil): fondo con su
  /// color, letras del clan y marco equipado. Fallback: la inicial.
  Widget _clanInsignia(Profile? p, String fallbackInitial, {bool grey = false}) {
    final hasClan = (p?.clan ?? '').trim().isNotEmpty;
    final color = grey ? AppColors.white(0.1) : clanColor(p?.avatarColor ?? '');
    final textColor = grey ? AppColors.white(0.2) : clanTextColor(p?.clanTextColor ?? '');
    final label = hasClan ? p!.clan.trim().toUpperCase() : fallbackInitial;
    final inner = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(
            color: grey ? AppColors.white(0.1) : AppColors.line, width: 1),
        color: color,
        boxShadow: grey ? null : AppFx.hardShadow(offset: const Offset(2, 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              style: clanFontStyle(p?.clanFont ?? '',
                  size: hasClan ? 14 : 17, color: textColor)),
        ),
      ),
    );
    return framedAvatar(frameById(p?.avatarFrame ?? ''), AppShape.rBtn, inner);
  }

  void _memberActions(Pickup pickup, String email, String team) {
    final toTeam = team == 'A' ? 'B' : 'A';
    final toName = toTeam == 'A' ? pickup.teamAName : pickup.teamBName;
    final declined = pickup.hasDeclined(email);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgElev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_memberName(email),
                  style: AppText.archivo(
                      size: 15, weight: FontWeight.w800, color: Colors.white)),
            ),
            // Solo tiene sentido reenviar si el miembro rechazó la invitación.
            if (declined)
              ListTile(
                leading: Icon(Icons.send_outlined, color: AppColors.accent),
                title: Text('Reenviar invitación',
                    style: AppText.grotesk(size: 14, color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(() => context
                      .read<PickupsProvider>()
                      .resendInvite(pickup, email));
                },
              ),
            ListTile(
              leading: Icon(Icons.swap_horiz, color: AppColors.accent),
              title: Text('Mover a $toName',
                  style: AppText.grotesk(size: 14, color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _run(() => context
                    .read<PickupsProvider>()
                    .moveMember(pickup, email, toTeam));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: AppColors.closed),
              title: Text('Quitar del pickup',
                  style: AppText.grotesk(size: 14, color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _run(() => context
                    .read<PickupsProvider>()
                    .removeMember(pickup, email));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _chatPlaceholder() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Icon(Icons.forum_outlined, size: 32, color: AppColors.white(0.2)),
        const SizedBox(height: 10),
        Text('El chat en vivo llega pronto',
            style: AppText.grotesk(
                size: 13, weight: FontWeight.w700, color: AppColors.white(0.5))),
        const SizedBox(height: 4),
        Text('Por ahora podés ver y organizar el pickup desde la info de arriba.',
            textAlign: TextAlign.center,
            style: AppText.grotesk(size: 12, color: AppColors.white(0.35))),
      ],
    );
  }

  // Barra de input DESHABILITADA: comunica que todavía no se puede escribir.
  Widget _disabledInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.line, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.white(0.05),
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                  border: Border.all(color: AppColors.white(0.1), width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 15, color: AppColors.white(0.3)),
                    const SizedBox(width: 8),
                    Text('El chat todavía no está disponible',
                        style: AppText.grotesk(
                            size: 12, color: AppColors.white(0.3))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Pickup pickup) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar pickup',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: Text(
            '¿Seguro que querés eliminar "${pickup.title}"? Esta acción no se puede deshacer.',
            style: AppText.grotesk(size: 13, color: AppColors.white(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.closed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await context.read<PickupsProvider>().deletePickup(pickup);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _confirmLeave(Pickup pickup) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Abandonar pickup',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: Text(
            '¿Seguro que querés salir de "${pickup.title}"? Para volver, el creador '
            'tendrá que invitarte de nuevo.',
            style: AppText.grotesk(size: 13, color: AppColors.white(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Abandonar',
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.closed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await context
          .read<PickupsProvider>()
          .leave(pickup, context.read<Session>().email ?? '');
      if (mounted) Navigator.pop(context);
    });
  }
}
