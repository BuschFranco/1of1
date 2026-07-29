import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../services/courts_provider.dart';
import '../services/friends_service.dart';
import '../services/notifications_service.dart';
import '../services/pickups_provider.dart';
import '../services/play_session_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/pickup_schedule_picker.dart';
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
  // Visibilidad pública: SOLO visual por ahora (feature en construcción). No se
  // envía al backend ni cambia el flujo de creación; es un adelanto de UI.
  bool _isPublic = false;
  final List<String> _teamAMembers = [];
  final List<String> _teamBMembers = [];
  final _notesCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
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
    _titleCtrl.dispose();
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
      final customTitle = _titleCtrl.text.trim();
      final pickupTitle =
          customTitle.isNotEmpty ? customTitle : 'Pickup en ${_selected!.name}';
      // El código de invitación de 5 dígitos lo genera el SERVER (viene en el
      // pickup creado). Solo lo ve el creador dentro del chat del pickup.
      final created = await pickupsProvider.create(Pickup(
        title: pickupTitle,
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
        name: pickupTitle,
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
        unawaited(pickupsProvider.loadForUser(_userEmail, force: true));
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
      // translucent: sin esto el gesto no se capta sobre el contenido (solo
      // en zonas vacías), igual que en auth_screen.
      behavior: HitTestBehavior.translucent,
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
                    const SizedBox(height: 16),
                    _label('Título (opcional)'),
                    TextField(
                      controller: _titleCtrl,
                      maxLength: 40,
                      style: AppText.grotesk(size: 14, color: Colors.white),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration(
                        hintText: 'Pickup en ${_selected?.name ?? "cancha"}',
                        hintStyle: AppText.grotesk(
                            size: 14, color: AppColors.white(0.35)),
                        counterStyle: AppText.grotesk(
                            size: 10, color: AppColors.white(0.3)),
                        filled: true,
                        fillColor: AppColors.white(0.05),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppColors.accent, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Visibilidad (feature en construcción, solo visual) ──
              _visibilityCard(),
              const SizedBox(height: 12),

              // ── Formato + Puntuación ──
              _sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Formato'),
                    const SizedBox(height: 4),
                    _segmented([
                      for (var n = 1; n <= 5; n++)
                        (
                          label: '${n}v$n',
                          active: _teamSize == n,
                          onTap: () => setState(() => _teamSize = n),
                        ),
                    ]),
                    const SizedBox(height: 18),
                    _label('Puntuación objetivo'),
                    const SizedBox(height: 4),
                    _segmented([
                      for (final s in [11, 15, 21, 31])
                        (
                          label: '$s',
                          active: _targetScore == s,
                          onTap: () => setState(() => _targetScore = s),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Center(child: _scoreStepper()),
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

  // ── Visibilidad: toggle "público" adelantado. Es SOLO visual: al tocarlo
  // cambia el switch pero no altera la creación (la unión abierta desde el mapa
  // todavía está en construcción). El badge lo deja claro. ──
  Widget _visibilityCard() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _label('Visibilidad'),
              const SizedBox(width: 8),
              _soonBadge(),
            ],
          ),
          const SizedBox(height: 4),
          PressableWidget(
            onTap: () => setState(() => _isPublic = !_isPublic),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isPublic
                        ? AppColors.accent.withAlpha(30)
                        : AppColors.white(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _isPublic ? Icons.public : Icons.lock_outline,
                    size: 20,
                    color: _isPublic ? AppColors.accent : AppColors.white(0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pickup público',
                          style: AppText.grotesk(
                              size: 14,
                              weight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                        'Cualquiera podrá unirse desde el mapa, sin invitación.',
                        style: AppText.grotesk(
                            size: 11, color: AppColors.white(0.45)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Switch plano (mismo lenguaje que el resto: pill + acento).
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 46,
                  height: 28,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _isPublic
                        ? AppColors.accent
                        : AppColors.white(0.12),
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                  ),
                  alignment:
                      _isPublic ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Badge chico "EN CONSTRUCCIÓN": marca features que todavía no funcionan.
  static Widget _soonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.busy.withAlpha(38),
        borderRadius: BorderRadius.circular(AppShape.rChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction, size: 11, color: AppColors.busy),
          const SizedBox(width: 4),
          Text('EN CONSTRUCCIÓN',
              style: AppText.grotesk(
                size: 9,
                weight: FontWeight.w800,
                color: AppColors.busy,
                letterSpacing: 0.06,
              )),
        ],
      ),
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

  Widget _datePicker() {
    return PressableWidget(
      // El picker vive en un helper compartido con la edición desde el chat del
      // pickup: una sola fuente para la lógica de horarios de cancha.
      onTap: () async {
        final picked =
            await pickPickupDateTime(context, _selected, initial: _when);
        if (picked == null || !mounted) return;
        setState(() => _when = picked);
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

  /// Selector segmentado: una sola barra con opciones de igual ancho, la activa
  /// tintada con el acento. Reemplaza los chips sueltos (que se amontonaban y
  /// desbordaban) por un control cohesivo, alineado al brand.
  static Widget _segmented(
      List<({String label, bool active, VoidCallback onTap})> segments) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white(0.05),
        borderRadius: BorderRadius.circular(AppShape.rChip),
      ),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              child: PressableWidget(
                onTap: s.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s.active ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppShape.rChip),
                  ),
                  child: Text(
                    s.label,
                    style: AppText.grotesk(
                      size: 13,
                      weight: FontWeight.w700,
                      color: s.active ? Colors.white : AppColors.white(0.55),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Ajuste fino de la puntuación (para valores que no son preset). Pill con
  /// [−] valor pts [+], en la misma lengua visual que el resto.
  Widget _scoreStepper() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.white(0.05),
        borderRadius: BorderRadius.circular(AppShape.rBtn),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _smallBtn(Icons.remove, () {
            if (_targetScore > 1) setState(() => _targetScore--);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$_targetScore',
                    style: AppText.archivo(
                        size: 24,
                        weight: FontWeight.w900,
                        color: Colors.white)),
                const SizedBox(width: 4),
                Text('pts',
                    style:
                        AppText.grotesk(size: 11, color: AppColors.white(0.4))),
              ],
            ),
          ),
          _smallBtn(Icons.add, () {
            if (_targetScore < 99) setState(() => _targetScore++);
          }),
        ],
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
