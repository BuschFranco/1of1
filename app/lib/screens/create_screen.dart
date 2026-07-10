import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import '../services/courts_provider.dart';
import '../services/friends_service.dart';
import '../services/notion_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/basketball_graffiti.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/under_construction.dart';
import 'add_court_screen.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  static const _options = [
    ('Crear pickup game', 'Organizá un partido en cualquier cancha', Icons.sports_basketball),
    ('Agregar cancha', '¿Conocés una cancha que no está?', Icons.add_location_alt_outlined),
    ('Reservar cancha', 'Reservá un horario', Icons.event_available_outlined),
  ];

  void _onTap(BuildContext context, int i) {
    if (i == 0) {
      _openPickupSheet(context);
    } else if (i == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddCourtScreen()),
      );
    } else {
      showUnderConstruction(context, _options[i].$1);
    }
  }

  // La opción 1 (Reservar) todavía no tiene backend.
  static const _wip = {2};

  Future<void> _openPickupSheet(BuildContext context) async {
    final courts = context.read<CourtsProvider>().courts;
    final session = context.read<Session>();
    if (session.email == null) return;
    if (courts.isEmpty) return;

    final notion = NotionService();
    final friendsSvc = FriendsService();
    final profiles = context.read<ProfilesProvider>();
    Court selected = courts.first;
    DateTime? when;
    int teamSize = 3;
    String teamAName = 'Equipo A';
    String teamBName = 'Equipo B';
    String teamAColor = '#FF6B1A';
    String teamBColor = '#3B82F6';
    int targetScore = 21;
    List<String> teamAMembers = [];
    List<String> teamBMembers = [];
    final notesCtrl = TextEditingController();
    bool saving = false;

    // Cargar amigos.
    List<Friend> friends = [];
    try {
      friends = await friendsSvc.listFriends(session.email!);
    } catch (_) {}

    const presetColors = [
      ('#FF6B1A', Color(0xFFFF6B1A)),
      ('#3B82F6', Color(0xFF3B82F6)),
      ('#22C55E', Color(0xFF22C55E)),
      ('#EF4444', Color(0xFFEF4444)),
      ('#A855F7', Color(0xFFA855F7)),
      ('#EAB308', Color(0xFFEAB308)),
    ];

    Color hexToColor(String hex) =>
        Color(int.parse(hex.replaceFirst('#', '0xFF')));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nuevo pickup',
                      style: AppText.archivo(size: 22, weight: FontWeight.w900)),
                  const SizedBox(height: 18),

                  // ── Cancha ──
                  _label('Cancha'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.bgElev,
                      borderRadius: BorderRadius.circular(AppShape.rBtn),
                      border: Border.all(color: AppColors.line, width: 1.5),
                    ),
                    child: DropdownButton<Court>(
                      value: selected,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AppColors.bgElev,
                      style: AppText.grotesk(size: 14),
                      items: [
                        for (final c in courts)
                          DropdownMenuItem(value: c, child: Text(c.name)),
                      ],
                      onChanged: (c) => setLocal(() => selected = c ?? selected),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Cuándo ──
                  _label('Cuándo'),
                  PressableWidget(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (picked != null) setLocal(() => when = picked);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.bgElev,
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        border: Border.all(color: AppColors.line, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 16, color: AppColors.white(0.6)),
                          const SizedBox(width: 10),
                          Text(
                            when == null
                                ? 'Elegir fecha'
                                : '${when!.day}/${when!.month}/${when!.year}',
                            style: AppText.grotesk(
                              size: 14,
                              color: when == null
                                  ? AppColors.white(0.4)
                                  : AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Formato (NxN) ──
                  _label('Formato'),
                  Row(
                    children: [
                      for (var n = 1; n <= 5; n++) ...[
                        _formatChip(
                          '${n}v$n',
                          teamSize == n,
                          () => setLocal(() => teamSize = n),
                        ),
                        if (n < 5) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Puntuación objetivo ──
                  _label('Puntuación objetivo'),
                  Row(
                    children: [
                      for (final s in [11, 15, 21, 31]) ...[
                        _formatChip(
                          '$s',
                          targetScore == s,
                          () => setLocal(() => targetScore = s),
                        ),
                        if (s != 31) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _smallBtn(Icons.remove, () {
                        if (targetScore > 1) setLocal(() => targetScore--);
                      }),
                      const SizedBox(width: 12),
                      Text('$targetScore',
                          style: AppText.archivo(
                              size: 18, weight: FontWeight.w800)),
                      const SizedBox(width: 12),
                      _smallBtn(Icons.add, () {
                        if (targetScore < 99) setLocal(() => targetScore++);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Equipo A ──
                  _label('Equipo A'),
                  TextField(
                    controller: TextEditingController(text: teamAName),
                    onChanged: (v) => teamAName = v.isEmpty ? 'Equipo A' : v,
                    style: AppText.grotesk(size: 14),
                    cursorColor: hexToColor(teamAColor),
                    decoration: InputDecoration(
                      hintText: 'Nombre del equipo',
                      hintStyle: AppText.grotesk(
                          size: 13, color: AppColors.white(0.35)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        borderSide:
                            BorderSide(color: AppColors.line, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        borderSide: BorderSide(
                            color: hexToColor(teamAColor), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final pc in presetColors) ...[
                        _colorCircle(
                          pc.$2,
                          teamAColor == pc.$1,
                          () => setLocal(() => teamAColor = pc.$1),
                        ),
                        if (pc != presetColors.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Equipo B ──
                  _label('Equipo B'),
                  TextField(
                    controller: TextEditingController(text: teamBName),
                    onChanged: (v) => teamBName = v.isEmpty ? 'Equipo B' : v,
                    style: AppText.grotesk(size: 14),
                    cursorColor: hexToColor(teamBColor),
                    decoration: InputDecoration(
                      hintText: 'Nombre del equipo',
                      hintStyle: AppText.grotesk(
                          size: 13, color: AppColors.white(0.35)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        borderSide:
                            BorderSide(color: AppColors.line, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        borderSide: BorderSide(
                            color: hexToColor(teamBColor), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final pc in presetColors) ...[
                        _colorCircle(
                          pc.$2,
                          teamBColor == pc.$1,
                          () => setLocal(() => teamBColor = pc.$1),
                        ),
                        if (pc != presetColors.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Invitar amigos ──
                  if (friends.isNotEmpty) ...[
                    _label('Invitar amigos'),
                    for (final f in friends)
                      _friendRow(
                        f,
                        teamAMembers.contains(f.friendEmail),
                        teamBMembers.contains(f.friendEmail),
                        hexToColor(teamAColor),
                        hexToColor(teamBColor),
                        () => setLocal(() {
                          if (teamAMembers.contains(f.friendEmail)) {
                            teamAMembers.remove(f.friendEmail);
                          } else {
                            teamAMembers.add(f.friendEmail);
                            teamBMembers.remove(f.friendEmail);
                          }
                        }),
                        () => setLocal(() {
                          if (teamBMembers.contains(f.friendEmail)) {
                            teamBMembers.remove(f.friendEmail);
                          } else {
                            teamBMembers.add(f.friendEmail);
                            teamAMembers.remove(f.friendEmail);
                          }
                        }),
                      ),
                    const SizedBox(height: 8),
                  ],

                  // ── Notas ──
                  _label('Notas (opcional)'),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    style: AppText.grotesk(size: 14),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      hintText: 'Ej. nivel intermedio, traer pelota',
                      hintStyle: AppText.grotesk(
                          size: 13, color: AppColors.white(0.35)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        borderSide:
                            BorderSide(color: AppColors.line, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        borderSide:
                            const BorderSide(color: AppColors.accent, width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Crear ──
                  PressableWidget(
                    onTap: saving
                        ? null
                        : () async {
                            setLocal(() => saving = true);
                            try {
                              final totalPlayers =
                                  teamSize * 2 + teamAMembers.length + teamBMembers.length;
                              await notion.createPage(
                                NotionConfig.dbPickups,
                                Pickup(
                                  title: 'Pickup en ${selected.name}',
                                  courtId: selected.id,
                                  createdBy: session.email!,
                                  dateTime: when?.toIso8601String(),
                                  maxPlayers: totalPlayers,
                                  vibe: selected.vibe,
                                  notes: notesCtrl.text.trim(),
                                  teamSize: teamSize,
                                  teamAName: teamAName,
                                  teamBName: teamBName,
                                  teamAColor: teamAColor,
                                  teamBColor: teamBColor,
                                  teamAMembers: teamAMembers,
                                  teamBMembers: teamBMembers,
                                  targetScore: targetScore,
                                ).toNotionProperties(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('¡Pickup creado!',
                                        style: AppText.grotesk(size: 13)),
                                    backgroundColor: AppColors.accent,
                                  ),
                                );
                              }
                            } catch (_) {
                              setLocal(() => saving = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('No se pudo crear el pickup.',
                                        style: AppText.grotesk(size: 13)),
                                    backgroundColor: AppColors.bg,
                                  ),
                                );
                              }
                            }
                          },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: saving ? AppColors.white(0.1) : AppColors.accent,
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        border: saving
                            ? null
                            : Border.all(color: AppColors.accentDark, width: 1),
                      ),
                      alignment: Alignment.center,
                      child: saving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white(0.6)),
                            )
                          : Text('CREAR PICKUP',
                              style: AppText.archivo(
                                  size: 14,
                                  weight: FontWeight.w900,
                                  letterSpacing: 0.04)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: AppText.grotesk(
            size: 11,
            weight: FontWeight.w700,
            color: AppColors.white(0.45),
            letterSpacing: 0.08,
          ),
        ),
      );

  static Widget _formatChip(String label, bool active, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rChip),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.line,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppText.grotesk(
            size: 13,
            weight: FontWeight.w700,
            color: active ? Colors.white : AppColors.white(0.6),
          ),
        ),
      ),
    );
  }

  static Widget _smallBtn(IconData icon, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.line, width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  static Widget _colorCircle(Color color, bool active, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: active
              ? [BoxShadow(color: color.withAlpha(80), blurRadius: 8)]
              : null,
        ),
        child: active
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }

  static Widget _friendRow(
    Friend f,
    bool inA,
    bool inB,
    Color colorA,
    Color colorB,
    VoidCallback onTapA,
    VoidCallback onTapB,
  ) {
    final name = f.friendName.isNotEmpty ? f.friendName : f.friendHandle;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final assignedColor = inA ? colorA : (inB ? colorB : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(
          color: assignedColor ?? AppColors.line,
          width: assignedColor != null ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: assignedColor ?? AppColors.paper,
            child: Text(initial,
                style: AppText.grotesk(
                    size: 12,
                    weight: FontWeight.w700,
                    color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(
                        size: 13, weight: FontWeight.w600)),
                if (f.friendHandle.isNotEmpty)
                  Text(f.friendHandle,
                      style: AppText.grotesk(
                          size: 10, color: AppColors.white(0.4))),
              ],
            ),
          ),
          _teamToggle('A', inA, colorA, onTapA),
          const SizedBox(width: 6),
          _teamToggle('B', inB, colorB, onTapB),
        ],
      ),
    );
  }

  static Widget _teamToggle(
      String label, bool active, Color teamColor, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: active ? teamColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? teamColor : AppColors.line,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppText.grotesk(
            size: 12,
            weight: FontWeight.w800,
            color: active ? Colors.white : AppColors.white(0.4),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: Stack(
        children: [
          // Capa de graffiti decorativa centrada en el fondo.
          const Positioned.fill(
            child: Center(
              child: BasketballGraffiti(size: 300, color: AppColors.ink),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
            children: [
              Text(
                'Nuevo',
                style: AppText.archivo(
                  size: 34,
                  weight: FontWeight.w900,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < _options.length; i++)
                PressableWidget(
                  onTap: () => _onTap(context, i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(18),
                    // Card de opción: sólida con borde claro franco.
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.line, width: 1),
                      borderRadius: BorderRadius.circular(AppShape.rCard),
                    ),
                    child: Row(
                      children: [
                        Icon(_options[i].$3, size: 28, color: AppColors.accent),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _options[i].$1,
                                      style: AppText.archivo(size: 16, weight: FontWeight.w800),
                                    ),
                                  ),
                                  if (_wip.contains(i)) ...[
                                    const SizedBox(width: 8),
                                    const UnderConstructionBadge(),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _options[i].$2,
                                style: AppText.grotesk(size: 12, color: AppColors.white(0.55)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
