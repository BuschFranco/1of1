import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<String> _teamAMembers = [];
  final List<String> _teamBMembers = [];
  // Recompensas elegidas (1 por tipo): monetaria guarda amount, el resto detail.
  final List<PickupReward> _rewards = [];
  // Requisitos/configuraciones personalizadas (1 por tipo, informativas).
  final List<PickupSetting> _settings = [];
  bool _configOpen = false;
  final _notesCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  bool _saving = false;
  bool _isPublic = false;

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
    // El creador SIEMPRE participa del pickup: arranca en el Equipo A, pero
    // puede pasarse al B con los toggles de su fila "Vos" (el server respeta
    // el equipo elegido al crear).
    if (_userEmail.isNotEmpty) _teamAMembers.add(_userEmail);
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
    for (final c in _rewardCtrls.values) {
      c.dispose();
    }
    for (final c in _settingCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Color _hex(String hex) =>
      Color(int.parse(hex.replaceFirst('#', '0xFF')));

  Future<void> _create() async {
    if (_selected == null || _saving) return;
    // Fecha y horario son obligatorios: sin fecha no se crea (los partidos
    // necesitan cuándo para el chat, los recordatorios y el detalle público).
    if (_when == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Elegí fecha y horario para el pickup.',
            style: AppText.grotesk(size: 13)),
        backgroundColor: AppColors.bgElev,
        behavior: SnackBarBehavior.floating,
      ));
      unawaited(_openDatePicker());
      return;
    }
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
        dateTime: _when!.toIso8601String(),
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
        isPublic: _isPublic,
        // Solo mandan las recompensas completas; el server descarta las que
        // no estén (monetaria sin monto, tipo sin detalle).
        rewards: _rewards
            .where((r) => r.isMonetary
                ? (r.amount ?? 0) > 0
                : (r.detail ?? '').trim().isNotEmpty)
            .toList(),
        // Ídem para los requisitos: solo viajan los bien formados.
        settings: _settings.where((s) => s.isWellFormed).toList(),
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
      // Con la creación en vuelo no se sale: el pickup ya se está creando en el
      // server y salir dejaba al usuario sin saber si quedó hecho (y sin el
      // refresh de la lista ni la notificación).
      onHorizontalDragEnd: (d) {
        if (_saving) return;
        if ((d.primaryVelocity ?? 0) > 0) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
            onPressed: _saving ? null : () => Navigator.pop(context),
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

              // ── Visibilidad ──
              _visibilityCard(),
              const SizedBox(height: 12),

              // ── Configuraciones personalizadas (recompensa + requisitos) ──
              _customConfigCard(),
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
                      _youRow(),
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

  // ── Visibilidad: pickup público = se muestra en el detalle de la cancha y
  // cualquiera puede unirse sin código de invitación. ──
  Widget _visibilityCard() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Visibilidad'),
          const SizedBox(height: 4),
          Row(
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
                child: Icon(_isPublic ? Icons.public : Icons.lock_outline,
                    size: 20,
                    color: _isPublic ? AppColors.accent : AppColors.white(0.5)),
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
                      _isPublic
                          ? 'Se va a mostrar en el detalle de la cancha. Cualquiera podrá unirse sin invitación.'
                          : 'Solo se unen quienes reciban tu invitación.',
                      style: AppText.grotesk(
                          size: 11, color: AppColors.white(0.45)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: _isPublic,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _isPublic = v),
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.white(0.12),
                inactiveThumbColor: AppColors.white(0.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Configuraciones personalizadas (box desplegable): recompensas
  // (1 o varios tipos a la vez) + requisitos/reglas (informativos). ──
  static const _rewardTypes = [
    ('monetaria', Icons.payments_outlined, 'Monetaria'),
    ('indumentaria', Icons.checkroom_outlined, 'Indumentaria'),
    ('accesorios', Icons.sports_baseball_outlined, 'Accesorios'),
    ('otro', Icons.category_outlined, 'Otro'),
  ];

  final Map<String, TextEditingController> _rewardCtrls = {};
  final Map<String, TextEditingController> _settingCtrls = {};

  TextEditingController _rewardCtrl(String type) =>
      _rewardCtrls.putIfAbsent(type, () => TextEditingController());

  TextEditingController _settingCtrl(String type) =>
      _settingCtrls.putIfAbsent(type, () => TextEditingController());

  PickupReward? _rewardOf(String type) {
    for (final r in _rewards) {
      if (r.type == type) return r;
    }
    return null;
  }

  void _setReward(PickupReward r) {
    final i = _rewards.indexWhere((x) => x.type == r.type);
    setState(() {
      if (i >= 0) {
        _rewards[i] = r;
      } else {
        _rewards.add(r);
      }
    });
  }

  // ── Requisitos: 1 sola config por tipo. Los numéricos arrancan con su
  // valor default al encender el toggle; el resto se completa al tipar. ──
  bool _settingOn(String type) => _settingOf(type) != null;

  PickupSetting? _settingOf(String type) {
    for (final s in _settings) {
      if (s.type == type) return s;
    }
    return null;
  }

  void _setSetting(PickupSetting s) {
    final i = _settings.indexWhere((x) => x.type == s.type);
    setState(() {
      if (i >= 0) {
        _settings[i] = s;
      } else {
        _settings.add(s);
      }
    });
  }

  void _toggleSetting(String type, PickupSetting seed) {
    setState(() {
      final i = _settings.indexWhere((x) => x.type == type);
      if (i >= 0) {
        _settings.removeAt(i);
        _settingCtrl(type).clear();
      } else {
        _settingCtrl(type).text = seed.min != null ? '${seed.min}' : '';
        _settings.add(seed);
      }
    });
  }

  /// Chips pick-one mutuamente excluyentes (nivel/modalidad): tocar el activo
  /// lo apaga; tocar el otro cambia la variante.
  void _pickSetting(String type, String value) {
    setState(() {
      final i = _settings.indexWhere((x) => x.type == type);
      if (i >= 0 && _settings[i].value == value) {
        _settings.removeAt(i);
        return;
      }
      if (i >= 0) {
        _settings[i] = PickupSetting(type: type, value: value);
      } else {
        _settings.add(PickupSetting(type: type, value: value));
      }
    });
  }

  /// Cuántas configs activas y bien formadas hay (badge del header).
  int get _configCount =>
      _rewards.length + _settings.where((s) => s.isWellFormed).length;

  Widget _customConfigCard() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressableWidget(
            onTap: _saving
                ? null
                : () => setState(() => _configOpen = !_configOpen),
            child: Row(
              children: [
                Icon(Icons.tune,
                    size: 18,
                    color: _configCount > 0
                        ? AppColors.accent
                        : AppColors.white(0.55)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Configuraciones personalizadas',
                      style: AppText.grotesk(
                          size: 13,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ),
                if (_configCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppShape.rChip),
                    ),
                    child: Text('$_configCount',
                        style: AppText.grotesk(
                            size: 11,
                            weight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(_configOpen ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.white(0.6)),
              ],
            ),
          ),
          // Cuerpo desplegable: recompensas + requisitos.
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _configOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Container(height: 1, color: AppColors.white(0.06)),
                const SizedBox(height: 14),
                _label('Recompensa (opcional)'),
                const SizedBox(height: 2),
                Text(
                    'Premiá al ganador del pickup. Podés elegir 1 o varios tipos.',
                    style:
                        AppText.grotesk(size: 11, color: AppColors.white(0.45))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (type, icon, label) in _rewardTypes)
                      _rewardChip(
                        type,
                        icon,
                        label,
                        active: _rewardOf(type) != null,
                        onTap: () {
                          setState(() {
                            final i =
                                _rewards.indexWhere((r) => r.type == type);
                            if (i >= 0) {
                              _rewards.removeAt(i);
                              _rewardCtrl(type).clear();
                            } else {
                              _rewards.add(PickupReward(type: type));
                            }
                          });
                        },
                      ),
                  ],
                ),
                for (final r in _rewards) ...[
                  const SizedBox(height: 12),
                  if (r.isMonetary)
                    _configField(
                      _rewardCtrl(r.type),
                      numeric: true,
                      hint: 'Monto en pesos (ARS)',
                      prefix: '\$ ',
                      onChanged: (v) => _setReward(PickupReward(
                        type: r.type,
                        amount: int.tryParse(v) ?? 0,
                      )),
                    )
                  else
                    _configField(
                      _rewardCtrl(r.type),
                      numeric: false,
                      hint: r.type == 'indumentaria'
                          ? 'Ej. remera, short, zapatillas'
                          : r.type == 'accesorios'
                              ? 'Ej. muñequeras, cinta, pelota'
                              : 'La coca',
                      onChanged: (v) => _setReward(
                          PickupReward(type: r.type, detail: v.trim())),
                    ),
                ],
                const SizedBox(height: 18),
                Container(height: 1, color: AppColors.white(0.06)),
                const SizedBox(height: 14),
                _requirementsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requirementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Requisitos'),
        const SizedBox(height: 2),
        Text('Reglas para unirse a este pickup (informativas).',
            style: AppText.grotesk(size: 11, color: AppColors.white(0.45))),
        const SizedBox(height: 10),
        _toggleRow(
          'edad',
          'Edad mínima',
          Icons.cake_outlined,
        ),
        if (_settingOn('edad')) ...[
          const SizedBox(height: 8),
          _configField(
            _settingCtrl('edad'),
            numeric: true,
            hint: 'Años (ej. 18)',
            prefix: '+',
            onChanged: (v) => _setSetting(PickupSetting(
              type: 'edad',
              min: int.tryParse(v) ?? 0,
            )),
          ),
        ],
        const SizedBox(height: 8),
        _toggleRow(
          'altura',
          'Altura mínima',
          Icons.height,
        ),
        if (_settingOn('altura')) ...[
          const SizedBox(height: 8),
          _configField(
            _settingCtrl('altura'),
            numeric: true,
            hint: 'Altura en cm (ej. 180)',
            onChanged: (v) => _setSetting(PickupSetting(
              type: 'altura',
              minCm: int.tryParse(v) ?? 0,
            )),
          ),
        ],
        const SizedBox(height: 8),
        _toggleRow(
          'peso',
          'Peso máximo',
          Icons.monitor_weight_outlined,
        ),
        if (_settingOn('peso')) ...[
          const SizedBox(height: 8),
          _configField(
            _settingCtrl('peso'),
            numeric: true,
            hint: 'Peso en kg (ej. 90)',
            onChanged: (v) => _setSetting(PickupSetting(
              type: 'peso',
              maxKg: int.tryParse(v) ?? 0,
            )),
          ),
        ],
        const SizedBox(height: 16),
        _label('Nivel'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _requirementChip(
              'Solo profesionales',
              _settingOf('nivel')?.value == 'profesional',
              () => _pickSetting('nivel', 'profesional'),
            ),
            _requirementChip(
              'Amateurs',
              _settingOf('nivel')?.value == 'amateur',
              () => _pickSetting('nivel', 'amateur'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _label('Modalidad'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _requirementChip(
              'Competencia',
              _settingOf('modalidad')?.value == 'competencia',
              () => _pickSetting('modalidad', 'competencia'),
            ),
            _requirementChip(
              'Casual',
              _settingOf('modalidad')?.value == 'casual',
              () => _pickSetting('modalidad', 'casual'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _toggleRow(
          'marca',
          'Partido de una marca',
          Icons.branding_watermark_outlined,
          subtitle: 'Por ej. un evento organizado por una marca',
        ),
        if (_settingOn('marca')) ...[
          const SizedBox(height: 8),
          _configField(
            _settingCtrl('marca'),
            numeric: false,
            hint: 'Nombre de la marca (ej. Nike)',
            onChanged: (v) => _setSetting(PickupSetting(
              type: 'marca',
              brand: v.trim(),
              useKit: _settingOf('marca')?.useKit ?? false,
            )),
          ),
          const SizedBox(height: 8),
          _toggleRow(
            'marca-kit',
            'Jugar con la indumentaria de la marca',
            Icons.checkroom_outlined,
            onChanged: (v) {
              final cur = _settingOf('marca');
              if (cur == null) return;
              _setSetting(PickupSetting(
                type: 'marca',
                brand: cur.brand,
                useKit: v,
              ));
            },
            value: _settingOf('marca')?.useKit ?? false,
          ),
        ],
      ],
    );
  }

  Widget _toggleRow(
    String type,
    String label,
    IconData icon, {
    String? subtitle,
    bool? value,
    ValueChanged<bool>? onChanged,
  }) {
    final on = value ?? _settingOn(type);
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.white(0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppText.grotesk(
                      size: 13, color: AppColors.white(0.85))),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(subtitle,
                    style: AppText.grotesk(
                        size: 11, color: AppColors.white(0.45))),
              ],
            ],
          ),
        ),
        Switch(
          value: on,
          onChanged: _saving
              ? null
              : (v) => onChanged != null
                  ? onChanged(v)
                  : _toggleSetting(type, PickupSetting(type: type)),
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: AppColors.white(0.12),
          inactiveThumbColor: AppColors.white(0.5),
        ),
      ],
    );
  }

  Widget _requirementChip(String label, bool active, VoidCallback onTap) {
    return PressableWidget(
      onTap: _saving ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.white(0.05),
          borderRadius: BorderRadius.circular(AppShape.rChip),
        ),
        child: Text(label,
            style: AppText.grotesk(
              size: 12,
              weight: FontWeight.w700,
              color: active ? Colors.white : AppColors.white(0.7),
            )),
      ),
    );
  }

  Widget _rewardChip(String type, IconData icon, String label,
      {required bool active, required VoidCallback onTap}) {
    return PressableWidget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.white(0.05),
          borderRadius: BorderRadius.circular(AppShape.rChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color:
                    active ? Colors.white : AppColors.white(0.55)),
            const SizedBox(width: 6),
            Text(label,
                style: AppText.grotesk(
                  size: 12,
                  weight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.white(0.7),
                )),
          ],
        ),
      ),
    );
  }

  Widget _configField(TextEditingController ctrl,
      {required bool numeric,
      required String hint,
      String? prefix,
      required ValueChanged<String> onChanged}) {
    return TextField(
      controller: ctrl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: AppText.grotesk(size: 14, color: Colors.white),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefix,
        hintStyle: AppText.grotesk(size: 13, color: AppColors.white(0.35)),
        prefixStyle: AppText.grotesk(size: 13, color: AppColors.white(0.45)),
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
      onChanged: onChanged,
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
      onTap: _openDatePicker,
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

  /// Abre el picker de fecha/horario (compartido con el chat). También lo
  /// dispara el guard de creación cuando falta fecha.
  Future<void> _openDatePicker() async {
    if (_selected == null) return;
    final picked =
        await pickPickupDateTime(context, _selected, initial: _when);
    if (picked == null || !mounted) return;
    setState(() => _when = picked);
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

  /// Equipos completos: no deja asignar más amigos (el cupo lo marca
  /// `teamSize * 2`, contando al creador, esté en A o en B).
  bool get _teamsFull =>
      _teamAMembers.length + _teamBMembers.length >= _teamSize * 2;

  /// Mueve al creador de equipo (los toggles de su fila). Nunca lo saca del
  /// pickup: cambiar de equipo solo re-asigna su email entre las dos listas.
  void _moveSelfTo(bool toB) {
    if (_userEmail.isEmpty) return;
    setState(() {
      if (toB) {
        if (_teamBMembers.contains(_userEmail)) return;
        _teamAMembers.remove(_userEmail);
        _teamBMembers.add(_userEmail);
      } else {
        if (_teamAMembers.contains(_userEmail)) return;
        _teamBMembers.remove(_userEmail);
        _teamAMembers.add(_userEmail);
      }
    });
  }

  /// Fila "Vos": el creador siempre participa y elige en qué equipo juega
  /// (Equipo A por default). Sin toggle de remoción: solo A/B.
  Widget _youRow() {
    final inA = _teamAMembers.contains(_userEmail);
    final inB = _teamBMembers.contains(_userEmail);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: inB ? _hex(_teamBColor) : _hex(_teamAColor),
            child: const Icon(Icons.person, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Vos',
                style: AppText.grotesk(
                    size: 13, weight: FontWeight.w600, color: Colors.white)),
          ),
          _teamToggle('A', inA, _hex(_teamAColor),
              _saving ? () {} : () => _moveSelfTo(false)),
          const SizedBox(width: 6),
          _teamToggle('B', inB, _hex(_teamBColor),
              _saving ? () {} : () => _moveSelfTo(true)),
        ],
      ),
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
              } else if (!_teamsFull) {
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
              } else if (!_teamsFull) {
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
