import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../services/courts_provider.dart';
import '../services/friends_service.dart';
import '../services/local_chat_service.dart';
import '../services/notifications_service.dart';
import '../services/pickups_provider.dart';
import '../services/play_session_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_widget.dart';
import 'main_shell.dart';

class PickupCreateScreen extends StatefulWidget {
  /// Cancha preseleccionada (al venir desde el mapa o el detalle de una cancha).
  final Court? initialCourt;
  const PickupCreateScreen({super.key, this.initialCourt});

  @override
  State<PickupCreateScreen> createState() => _PickupCreateScreenState();
}

class _PickupCreateScreenState extends State<PickupCreateScreen> {
  late final List<Court> _courts;
  late final String _userEmail;
  late final List<Friend> _friends;

  Court? _selected;
  DateTime? _when;
  int _teamSize = 3;
  String _teamAName = 'Equipo A';
  String _teamBName = 'Equipo B';
  String _teamAColor = '#FF6B1A';
  String _teamBColor = '#3B82F6';
  int _targetScore = 21;
  final List<String> _teamAMembers = [];
  final List<String> _teamBMembers = [];
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  // Fondo alineado al brand de la app (oscuro neobrutalista), no el violeta.
  static const _bgColor = AppColors.bg;

  static const _presetColors = [
    ('#FF6B1A', Color(0xFFFF6B1A)),
    ('#3B82F6', Color(0xFF3B82F6)),
    ('#22C55E', Color(0xFF22C55E)),
    ('#EF4444', Color(0xFFEF4444)),
    ('#A855F7', Color(0xFFA855F7)),
    ('#EAB308', Color(0xFFEAB308)),
  ];

  @override
  void initState() {
    super.initState();
    _courts = context.read<CourtsProvider>().courts;
    // Preseleccionar la cancha recibida (por id, para tomar la instancia de la
    // lista) o la primera disponible.
    final initial = widget.initialCourt;
    if (initial != null && _courts.isNotEmpty) {
      // Tomar la instancia de la lista (el Dropdown exige que el value sea uno
      // de sus items); si no está, caer a la primera.
      _selected = _courts.firstWhere((c) => c.id == initial.id,
          orElse: () => _courts.first);
    } else {
      _selected = initial ?? (_courts.isNotEmpty ? _courts.first : null);
    }
    _userEmail = context.read<Session>().email ?? '';
    _friends = [];
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    if (_userEmail.isEmpty) return;
    try {
      final svc = FriendsService();
      final list = await svc.listFriends(_userEmail);
      if (mounted) setState(() => _friends.addAll(list));
    } catch (_) {}
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Color _hex(String hex) =>
      Color(int.parse(hex.replaceFirst('#', '0xFF')));

  Future<void> _create() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);
    try {
      final pickupsProvider = context.read<PickupsProvider>();
      final totalPlayers =
          _teamSize * 2 + _teamAMembers.length + _teamBMembers.length;
      // El código de invitación de 5 dígitos lo genera el SERVER (viene en el
      // pickup creado). Solo lo ve el creador dentro del chat del pickup.
      final created = await pickupsProvider.create(Pickup(
        title: 'Pickup en ${_selected!.name}',
        courtId: _selected!.id,
        createdBy: _userEmail,
        dateTime: _when?.toIso8601String(),
        maxPlayers: totalPlayers,
        vibe: _selected!.vibe,
        notes: _notesCtrl.text.trim(),
        teamSize: _teamSize,
        teamAName: _teamAName,
        teamBName: _teamBName,
        teamAColor: _teamAColor,
        teamBColor: _teamBColor,
        teamAMembers: _teamAMembers,
        teamBMembers: _teamBMembers,
        targetScore: _targetScore,
      ));

      final chat = CrewChat(
        name: 'Pickup en ${_selected!.name}',
        pickupId: created.pageId,
        createdBy: _userEmail,
        date: _when?.toIso8601String() ?? DateTime.now().toIso8601String(),
        teamAName: _teamAName,
        teamBName: _teamBName,
        teamAColor: _teamAColor,
        teamBColor: _teamBColor,
        lastMessage: '${_teamSize}v$_teamSize · $_targetScore pts',
        createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await LocalChatService(_userEmail).saveChat(chat);

      // Notificar al usuario que se creó el chat.
      if (mounted) {
        context.read<PlaySessionService>().addChatNotification(chat.name);
        // Notificación del sistema con botón "Ir al chat".
        if (created.pageId.isNotEmpty) {
          unawaited(NotificationsService.instance.showPickupChat(
              'Pickup creado 🏀',
              'Tocá para ir al chat y pasar el código.',
              created.pageId));
        }
        // Marcar activity en el tab de crew (via ValueNotifier global).
        crewActivityNotifier.value = true;
        SharedPreferences.getInstance().then((p) => p.setBool('crew_activity', true));
      }

      // Metadata del chat en la BD (best-effort; null si la feature está off).
      try {
        await pickupsProvider.createChat(chat);
      } catch (_) {}

      // Refrescar la lista de pickups para que aparezca al instante en Crew.
      if (mounted) {
        unawaited(pickupsProvider.loadForUser(_userEmail));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo crear el pickup.',
                style: AppText.grotesk(size: 13)),
            backgroundColor: AppColors.bg,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 0) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Nuevo pickup',
              style: AppText.archivo(size: 20, weight: FontWeight.w900, color: Colors.white)),
          centerTitle: true,
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + bottomPad),
            children: [
              // ── Cancha ──
              _sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Cancha'),
                    _courtDropdown(),
                    const SizedBox(height: 16),
                    _label('Cuándo'),
                    _datePicker(),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Formato + Puntuación ──
              _sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Formato'),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (var n = 1; n <= 5; n++) ...[
                          _chip('${n}v$n', _teamSize == n,
                              () => setState(() => _teamSize = n)),
                          if (n < 5) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _label('Puntuación objetivo'),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (final s in [11, 15, 21, 31]) ...[
                          _chip('$s', _targetScore == s,
                              () => setState(() => _targetScore = s)),
                          if (s != 31) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _smallBtn(Icons.remove, () {
                            if (_targetScore > 1) setState(() => _targetScore--);
                          }),
                          const SizedBox(width: 16),
                          Text('$_targetScore',
                              style: AppText.archivo(
                                  size: 22, weight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(width: 16),
                          _smallBtn(Icons.add, () {
                            if (_targetScore < 99) setState(() => _targetScore++);
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Equipos ──
              _sectionCard(
                child: Column(
                  children: [
                    _teamSection('Equipo A', _teamAName, _teamAColor, true,
                        (v) { _teamAName = v.isEmpty ? 'Equipo A' : v; },
                        (c) => setState(() => _teamAColor = c)),
                    const SizedBox(height: 16),
                    Container(height: 1, color: AppColors.white(0.08)),
                    const SizedBox(height: 16),
                    _teamSection('Equipo B', _teamBName, _teamBColor, false,
                        (v) { _teamBName = v.isEmpty ? 'Equipo B' : v; },
                        (c) => setState(() => _teamBColor = c)),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Invitar amigos ──
              if (_friends.isNotEmpty) ...[
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Invitar amigos'),
                      for (var i = 0; i < _friends.length; i++) ...[
                        if (i > 0)
                          Container(height: 1, color: AppColors.white(0.06)),
                        _friendRow(_friends[i]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Notas ──
              _sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Notas (opcional)'),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      style: AppText.grotesk(size: 14, color: Colors.white),
                      cursorColor: AppColors.accent,
                      // Input plano: filled sin borde; el foco se marca con acento.
                      decoration: InputDecoration(
                        hintText: 'Ej. nivel intermedio, traer pelota',
                        hintStyle: AppText.grotesk(size: 13, color: AppColors.white(0.35)),
                        filled: true,
                        fillColor: AppColors.white(0.05),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Crear ──
              PressableWidget(
                onTap: _saving ? null : _create,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  // CTA plano: acento pleno, sin borde negro ni sombra dura
                  // (mismo lenguaje que "Compartir resultado" del detalle).
                  decoration: BoxDecoration(
                    color: _saving ? AppColors.white(0.1) : AppColors.accent,
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                  ),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
                        )
                      : Text('CREAR PICKUP',
                          style: AppText.archivo(
                              size: 14, weight: FontWeight.w800, letterSpacing: 0.04, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Card de sección: fill sutil, sin borde ni sombra (mismo lenguaje
  // editorial que el perfil: un solo nivel de "caja" por sección). ──
  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: child,
    );
  }

  // ── Sección de equipo (label + nombre + colores) ──
  Widget _teamSection(String label, String name, String colorHex, bool isA,
      ValueChanged<String> onNameChanged, ValueChanged<String> onColorChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 4),
        _teamNameField(name, _hex(colorHex), onNameChanged),
        const SizedBox(height: 10),
        _colorRow(colorHex, onColorChanged),
      ],
    );
  }

  Widget _courtDropdown() {
    if (_selected == null) {
      return Text('No hay canchas disponibles',
          style: AppText.grotesk(size: 14, color: AppColors.white(0.4)));
    }
    // Input plano: fill sutil, sin borde (el chevron del dropdown ya da la
    // affordance).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.white(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<Court>(
        value: _selected,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: _bgColor,
        style: AppText.grotesk(size: 14, color: Colors.white),
        iconEnabledColor: AppColors.white(0.5),
        items: [
          for (final c in _courts)
            DropdownMenuItem(value: c, child: Text(c.name)),
        ],
        // Al cambiar de cancha, el horario elegido puede quedar fuera del nuevo
        // rango: lo limpiamos para forzar re-selección dentro del horario válido.
        onChanged: (c) => setState(() {
          _selected = c ?? _selected!;
          _when = null;
        }),
      ),
    );
  }

  /// Genera los horarios disponibles (cada 30 min) según el horario de la
  /// cancha seleccionada. 24h o sin horario parseable → todo el día. Maneja
  /// rangos que cruzan medianoche (ej. 18:00–02:00).
  List<TimeOfDay> _courtSlots(Court c) {
    final slots = <TimeOfDay>[];
    if (c.is24h || c.openTod == null || c.closeTod == null) {
      for (var m = 0; m < 24 * 60; m += 30) {
        slots.add(TimeOfDay(hour: m ~/ 60, minute: m % 60));
      }
      return slots;
    }
    final start = c.openTod!.hour * 60 + c.openTod!.minute;
    var end = c.closeTod!.hour * 60 + c.closeTod!.minute;
    if (end <= start) end += 24 * 60; // cruza medianoche
    for (var m = start; m < end; m += 30) {
      final mm = m % (24 * 60);
      slots.add(TimeOfDay(hour: mm ~/ 60, minute: mm % 60));
    }
    return slots;
  }

  /// Bottom sheet compacto para elegir un horario: una rueda que se desliza
  /// entre los slots válidos de la cancha (sin la grilla saturada anterior).
  Future<TimeOfDay?> _pickTimeSlot(DateTime date) async {
    final court = _selected;
    if (court == null) return null;
    final slots = _courtSlots(court);
    if (slots.isEmpty) return null;
    final subtitle = court.is24h
        ? 'Abierta 24h'
        : (court.openTod != null && court.closeTod != null
            ? court.hoursLabel
            : 'Horario libre');

    // Arranca en el primer slot >= ahora (si la fecha es hoy); si no, en el primero.
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    var startIndex = slots.indexWhere((s) => s.hour * 60 + s.minute >= nowMin);
    if (startIndex < 0) startIndex = 0;

    var selected = startIndex;
    final controller = FixedExtentScrollController(initialItem: startIndex);

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: AppColors.bgElev,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.white(0.2),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 16),
              Text('Elegí un horario',
                  style: AppText.archivo(
                      size: 18, weight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.schedule, size: 13, color: AppColors.accent),
                  const SizedBox(width: 5),
                  Text(subtitle,
                      style:
                          AppText.grotesk(size: 12, color: AppColors.white(0.5))),
                ],
              ),
              const SizedBox(height: 12),
              // Rueda de horarios con banda de selección al centro.
              SizedBox(
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Banda de selección: tinte de acento plano, sin borde.
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(26),
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                      controller: controller,
                      itemExtent: 44,
                      diameterRatio: 1.6,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (i) => selected = i,
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: slots.length,
                        builder: (_, i) {
                          final s = slots[i];
                          return Center(
                            child: Text(
                              '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}',
                              style: AppText.archivo(
                                  size: 20,
                                  weight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PressableWidget(
                onTap: () => Navigator.pop(ctx, slots[selected]),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                  ),
                  child: Text('CONFIRMAR',
                      style: AppText.archivo(
                          size: 14,
                          weight: FontWeight.w800,
                          letterSpacing: 0.04,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Widget _datePicker() {
    return PressableWidget(
      onTap: () async {
        final datePicked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 90)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AppColors.accent,
                  surface: _bgColor,
                ),
              ),
              child: child!,
            );
          },
        );
        if (datePicked == null || !mounted) return;
        final slot = await _pickTimeSlot(datePicked);
        if (slot == null || !mounted) return;
        setState(() => _when = DateTime(
              datePicked.year, datePicked.month, datePicked.day,
              slot.hour, slot.minute,
            ));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: AppColors.white(0.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _when == null
                    ? 'Elegir fecha y hora'
                    : '${_when!.day}/${_when!.month}/${_when!.year} · ${_when!.hour.toString().padLeft(2, '0')}:${_when!.minute.toString().padLeft(2, '0')}',
                style: AppText.grotesk(
                  size: 14,
                  color: _when == null ? AppColors.white(0.4) : Colors.white,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.3)),
          ],
        ),
      ),
    );
  }

  Widget _teamNameField(String value, Color cursorColor, ValueChanged<String> onChanged) {
    return TextField(
      controller: TextEditingController(text: value),
      onChanged: onChanged,
      style: AppText.grotesk(size: 14, color: Colors.white),
      cursorColor: cursorColor,
      // Input plano: filled sin borde; el foco toma el color del equipo.
      decoration: InputDecoration(
        hintText: 'Nombre del equipo',
        hintStyle: AppText.grotesk(size: 13, color: AppColors.white(0.3)),
        filled: true,
        fillColor: AppColors.white(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cursorColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _colorRow(String current, ValueChanged<String> onSelect) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final pc in _presetColors) ...[
          _colorCircle(pc.$2, current == pc.$1, () => onSelect(pc.$1)),
          if (pc != _presetColors.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _friendRow(Friend f) {
    final name = f.friendName.isNotEmpty ? f.friendName : f.friendHandle;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final inA = _teamAMembers.contains(f.friendEmail);
    final inB = _teamBMembers.contains(f.friendEmail);
    final assignedColor = inA ? _hex(_teamAColor) : (inB ? _hex(_teamBColor) : null);

    // Fila plana (sin box por amigo): la asignación se lee en el color del
    // avatar y los toggles A/B; las filas se separan con hairlines.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: assignedColor ?? AppColors.white(0.15),
            child: Text(initial,
                style: AppText.grotesk(
                    size: 12, weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(size: 13, weight: FontWeight.w600, color: Colors.white)),
                if (f.friendHandle.isNotEmpty)
                  Text(f.friendHandle,
                      style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
              ],
            ),
          ),
          _teamToggle('A', inA, _hex(_teamAColor), () {
            setState(() {
              if (_teamAMembers.contains(f.friendEmail)) {
                _teamAMembers.remove(f.friendEmail);
              } else {
                _teamAMembers.add(f.friendEmail);
                _teamBMembers.remove(f.friendEmail);
              }
            });
          }),
          const SizedBox(width: 6),
          _teamToggle('B', inB, _hex(_teamBColor), () {
            setState(() {
              if (_teamBMembers.contains(f.friendEmail)) {
                _teamBMembers.remove(f.friendEmail);
              } else {
                _teamBMembers.add(f.friendEmail);
                _teamAMembers.remove(f.friendEmail);
              }
            });
          }),
        ],
      ),
    );
  }

  // ── Helpers ──

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

  static Widget _chip(String label, bool active, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        // Chip plano: acento pleno si está activo, fill sutil si no (sin borde).
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.white(0.06),
          borderRadius: BorderRadius.circular(AppShape.rChip),
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
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.white(0.08),
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  static Widget _colorCircle(Color color, bool active, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? Colors.white : Colors.transparent,
            width: 3,
          ),
        ),
        child: active
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }

  static Widget _teamToggle(
      String label, bool active, Color teamColor, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: active ? teamColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? teamColor : AppColors.white(0.2),
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
}
