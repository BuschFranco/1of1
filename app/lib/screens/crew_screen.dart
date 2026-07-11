import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../services/pickups_provider.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/basketball_graffiti.dart';
import '../widgets/pressable_widget.dart';
import 'pickup_chat_screen.dart';

class CrewScreen extends StatefulWidget {
  const CrewScreen({super.key});

  @override
  State<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends State<CrewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final email = context.read<Session>().email ?? '';
    await context.read<PickupsProvider>().loadForUser(email);
  }

  Color _hex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.accent;
    }
  }

  String _dateLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month}/${dt.year} · $h:$m';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PickupsProvider>();
    final myEmail = (context.read<Session>().email ?? '').trim().toLowerCase();
    // En Crew solo van los pickups donde participo de verdad: creados por mí o
    // que ya acepté. Las invitaciones pendientes viven en las notificaciones del
    // perfil; las rechazadas no se muestran hasta que el creador reenvíe.
    final pickups = provider.pickups
        .where((p) => p.isCreator(myEmail) || p.hasAccepted(myEmail))
        .toList();

    return Container(
      color: AppColors.lilac,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: BasketballGraffiti(size: 300, color: AppColors.white(0.08)),
            ),
          ),
          RefreshIndicator(
            onRefresh: _load,
            color: AppColors.accent,
            backgroundColor: AppColors.bgElev,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
              children: [
                Text(
                  'Crew',
                  style: AppText.archivo(
                    size: 34,
                    weight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.01,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tus pickups e invitaciones',
                  style: AppText.grotesk(size: 13, color: AppColors.white(0.6)),
                ),
                const SizedBox(height: 20),
                if (provider.loading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white(0.4)),
                    ),
                  )
                else if (pickups.isEmpty)
                  _emptyState()
                else
                  for (final p in pickups) _pickupCard(p, myEmail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Icon(Icons.groups_outlined, size: 44, color: AppColors.white(0.25)),
          const SizedBox(height: 12),
          Text('Todavía no tenés pickups',
              style: AppText.grotesk(
                  size: 15, weight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Creá un pickup desde el botón + o esperá una invitación de tu crew.',
            textAlign: TextAlign.center,
            style: AppText.grotesk(size: 13, color: AppColors.white(0.5)),
          ),
        ],
      ),
    );
  }

  /// Etiqueta de estado del pickup respecto al usuario.
  (String, Color) _statusFor(Pickup p, String myEmail) {
    if (p.isCreator(myEmail)) return ('CREADO POR VOS', AppColors.accent);
    if (p.hasDeclined(myEmail)) return ('RECHAZADO', AppColors.closed);
    if (p.hasAccepted(myEmail)) return ('CONFIRMADO', AppColors.open);
    return ('INVITACIÓN', AppColors.busy);
  }

  Widget _pickupCard(Pickup p, String myEmail) {
    final colorA = _hex(p.teamAColor);
    final colorB = _hex(p.teamBColor);
    final (statusText, statusColor) = _statusFor(p, myEmail);
    final date = _dateLabel(p.dateTime);
    final total = p.invitedMembers.length;
    final accepted = p.acceptedMembers.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableWidget(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PickupChatScreen(pickupId: p.pageId),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line, width: 1),
            borderRadius: BorderRadius.circular(AppShape.rCard),
            boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar: dos círculos con los colores de equipo.
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 4,
                          child: _teamDot(colorA, p.teamAName, 'A'),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 4,
                          child: _teamDot(colorB, p.teamBName, 'B'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.archivo(
                              size: 15, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: colorA, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(p.teamAName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.grotesk(
                                      size: 11,
                                      color: AppColors.white(0.6),
                                      weight: FontWeight.w600)),
                            ),
                            Text(' vs ',
                                style: AppText.grotesk(
                                    size: 11, color: AppColors.white(0.35))),
                            Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: colorB, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(p.teamBName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.grotesk(
                                      size: 11,
                                      color: AppColors.white(0.6),
                                      weight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        if (date.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(date,
                              style: AppText.grotesk(
                                  size: 11,
                                  color: AppColors.accent,
                                  weight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.white(0.3)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _badge(statusText, statusColor),
                  const Spacer(),
                  Icon(Icons.people_outline,
                      size: 13, color: AppColors.white(0.4)),
                  const SizedBox(width: 4),
                  Text('$accepted/$total confirmados',
                      style: AppText.grotesk(
                          size: 10, color: AppColors.white(0.45))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamDot(Color color, String name, String fallback) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.bg, width: 2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : fallback,
          style: AppText.grotesk(
              size: 14, weight: FontWeight.w800, color: Colors.white),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(AppShape.rChip),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(text,
          style: AppText.grotesk(
              size: 8,
              weight: FontWeight.w800,
              color: color,
              letterSpacing: 0.06)),
    );
  }
}
