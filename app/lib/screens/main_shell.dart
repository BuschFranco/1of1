import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_loading_state.dart';
import '../services/courts_provider.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_loader.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/form_style.dart';
import '../widgets/match_status_pill.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/reward_banner.dart';
import 'crew_screen.dart';
import 'create_screen.dart';
import 'detail_screen.dart';
import 'filters_screen.dart';
import 'home_screen.dart';
import 'list_screen.dart';
import 'match_detail_screen.dart';
import 'profile_screen.dart';

/// ValueNotifier global para el badge de activity en el tab de crew.
/// Se setea desde pickup_create_screen al crear un chat de equipo, y se limpia
/// cuando el usuario abre la pestaña de crew.
final ValueNotifier<bool> crewActivityNotifier = ValueNotifier<bool>(false);

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppTab _tab = AppTab.home;
  AppTab _previousTab = AppTab.home;

  // Subpestaña del Perfil (0 = Perfil, 1 = Amigos). Vive acá para que el swipe
  // del shell pueda alternarla antes de saltar a otra pestaña principal.
  int _profileTab = 0;

  // Tope de seguridad del loader: si las señales (mapa/GPS/canchas) no llegan,
  // igual lo ocultamos a los 6s para no dejar la app tapada.
  bool _loaderTimedOut = false;
  Timer? _loaderTimer;

  // Badge de activity en el tab de crew (punto rojo).
  // ValueNotifier estático para que pickup_create_screen pueda setearlo sin
  // necesidad de Provider (solo escribe en SharedPreferences + dispara).
  // Definido como variable global en main_shell.dart (crewActivityNotifier).

  @override
  void initState() {
    super.initState();
    // Usar la pestaña de inicio elegida por el usuario (Personalización).
    final defaultTab = context.read<Session>().defaultTab;
    _tab = _tabFromName(defaultTab);
    _previousTab = _tab;
    _loaderTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _loaderTimedOut = true);
    });
    _loadCrewActivity();
    crewActivityNotifier.addListener(_onCrewActivityChanged);
    // Mensaje de bienvenida tras un login/registro explícito (una sola vez).
    if (context.read<Session>().consumeJustAuthenticated()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWelcome());
    }
  }

  /// Agradecimiento de bienvenida (fase temprana pero estable). Se muestra una
  /// vez, justo después de que el usuario entra por login o registro.
  void _showWelcome() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElev,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShape.rCard)),
        title: Text('¡Gracias por sumarte!',
            style: AppText.archivo(size: 19, weight: FontWeight.w900)),
        content: Text(
          'Gracias por instalar 1of1. La app está en una fase temprana, así que '
          'todavía falta un mundo de opciones y mejoras para que la experiencia '
          'sea completa. Aun así, ya es una versión estable y nos entusiasma '
          'mejorarla junto a la comunidad.\n\n'
          'La desarrollamos con el propósito de unir y seguir fortaleciendo la '
          'comunidad del básquet. Por eso nos importa mucho tu feedback: contanos '
          'qué funciona mal, qué podría funcionar mejor y qué características '
          'nuevas te gustaría ver.',
          style: AppText.grotesk(
              size: 14, color: AppColors.white(0.8), height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('¡A jugar!',
                style: AppText.archivo(
                    size: 13,
                    weight: FontWeight.w900,
                    color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    crewActivityNotifier.removeListener(_onCrewActivityChanged);
    _loaderTimer?.cancel();
    super.dispose();
  }

  void _onCrewActivityChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCrewActivity() async {
    final prefs = await SharedPreferences.getInstance();
    crewActivityNotifier.value = prefs.getBool('crew_activity') ?? false;
  }

  /// Convierte un nombre de string a AppTab, con fallback a home.
  static AppTab _tabFromName(String name) => switch (name) {
        'list' => AppTab.list,
        'plus' => AppTab.plus,
        'chat' => AppTab.chat,
        'profile' => AppTab.profile,
        _ => AppTab.home,
      };


  String? _detailCourtId;
  bool _filtersOpen = false;
  bool _resultPromptOpen = false;

  // +1 → new screen enters from the right (going "forward"),
  // -1 → enters from the left (going "back").
  int _slideDir = 1;

  // Cancha a centrar en el mapa al volver al Home (desde el detalle).
  String? _focusCourtId;

  // Unique key for the currently visible screen, so AnimatedSwitcher
  // knows when to run the transition.
  String get _screenKey {
    if (_filtersOpen) return 'filters';
    if (_detailCourtId != null) return 'detail:$_detailCourtId';
    return 'tab:${_tab.name}';
  }

  // Historial de pestañas visitadas, para que el botón "atrás" del sistema
  // vuelva a la anterior en vez de salir de la app.
  final List<AppTab> _tabHistory = [];

  // Color de fondo por pestaña (retro-pop, un color por sección). El del
  // perfil lo elige el usuario (tuerquita → Fondo del perfil; default oliva).
  Color _bgForTab(AppTab t) => switch (t) {
        AppTab.home => AppColors.cream,
        AppTab.list => AppColors.lilac,
        AppTab.plus => AppColors.cream,
        // Tiene que coincidir con el color que pinta crew_screen: si no, el
        // slide de entrada muestra un color y al asentarse salta al otro.
        AppTab.chat => AppColors.lilac,
        AppTab.profile =>
          AppColors.profileBg(context.watch<Session>().profileBg),
      };

  void _selectTab(AppTab t) {
    if (t == _tab) return;
    setState(() {
      _tabHistory.add(_tab);
      if (_tabHistory.length > 20) _tabHistory.removeAt(0);
      _slideDir = t.index >= _tab.index ? 1 : -1;
      _previousTab = _tab;
      _tab = t;
    });
    // Limpiar badge de activity al entrar a crew.
    if (t == AppTab.chat && crewActivityNotifier.value) {
      crewActivityNotifier.value = false;
      SharedPreferences.getInstance().then((p) => p.setBool('crew_activity', false));
    }
  }

  /// Botón "atrás" del sistema (Android): cierra overlays o vuelve a la pestaña
  /// anterior en vez de salir de la app. Devuelve true si consumió el gesto;
  /// false si no hay a dónde volver (recién ahí se permite salir).
  bool _handleBack() {
    if (_filtersOpen) {
      _closeFilters();
      return true;
    }
    if (_detailCourtId != null) {
      _closeDetail();
      return true;
    }
    // En Perfil, si estás en Amigos, atrás vuelve a Perfil (como el swipe).
    if (_tab == AppTab.profile && _profileTab == 1) {
      setState(() => _profileTab = 0);
      return true;
    }
    if (_tabHistory.isNotEmpty) {
      final prev = _tabHistory.removeLast();
      setState(() {
        _slideDir = -1;
        _previousTab = _tab;
        _tab = prev;
      });
      return true;
    }
    if (_tab != AppTab.home) {
      setState(() {
        _slideDir = -1;
        _previousTab = _tab;
        _tab = AppTab.home;
      });
      return true;
    }
    return false;
  }

  // Orden de las pestañas navegables por swipe (todas menos el mapa). Deslizar
  // hacia la izquierda avanza a la siguiente; hacia la derecha, a la anterior.
  static const List<AppTab> _swipeTabs = [
    AppTab.list,
    AppTab.plus,
    AppTab.chat,
    AppTab.profile,
  ];

  void _handleTabSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v == 0) return;
    // Dentro del Perfil, el swipe alterna entre las subpestañas Perfil/Amigos.
    // Solo cae a la navegación entre pestañas principales cuando ya está en el
    // extremo (izquierda desde Perfil → nada; derecha desde Perfil → anterior).
    if (_tab == AppTab.profile) {
      if (v < 0 && _profileTab == 0) {
        setState(() => _profileTab = 1); // swipe izquierda → Amigos
        return;
      }
      if (v > 0 && _profileTab == 1) {
        setState(() => _profileTab = 0); // swipe derecha → Perfil
        return;
      }
    }
    // Desde Canchas, deslizar a la derecha vuelve al Mapa. (Al revés NO: en el
    // Mapa no hay capa de swipe, así que sus gestos quedan intactos.)
    if (v > 0 && _tab == AppTab.list) {
      _selectTab(AppTab.home);
      return;
    }
    final idx = _swipeTabs.indexOf(_tab);
    if (idx < 0) return; // estamos en el mapa: no aplica
    if (v < 0 && idx < _swipeTabs.length - 1) {
      _selectTab(_swipeTabs[idx + 1]); // swipe a la izquierda → siguiente
    } else if (v > 0 && idx > 0) {
      _selectTab(_swipeTabs[idx - 1]); // swipe a la derecha → anterior
    }
  }

  void _openDetail(String id) {
    setState(() {
      _slideDir = 1;
      _detailCourtId = id;
    });
    // Refresca presencia para "Jugando ahora" en el detalle.
    context.read<ProfilesProvider>().load();
  }

  void _closeDetail() => setState(() {
        _slideDir = -1;
        _detailCourtId = null;
      });

  void _openFilters() => setState(() {
        _slideDir = 1;
        _filtersOpen = true;
      });

  void _closeFilters() => setState(() {
        _slideDir = -1;
        _filtersOpen = false;
      });

  // Desde el detalle: ir al mapa (Home) centrado en la cancha.
  void _showOnMap(String courtId) => setState(() {
        _slideDir = -1;
        _detailCourtId = null;
        _filtersOpen = false;
        _previousTab = _tab;
        _tab = AppTab.home;
        _focusCourtId = courtId;
      });

  Widget _slideTransition(Widget child, Animation<double> animation, Key currentKey) {
    final incoming = child.key == currentKey;
    final beginX = (incoming ? _slideDir : -_slideDir) * 0.22;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(beginX, 0), end: Offset.zero)
            .animate(animation),
        child: child,
      ),
    );
  }

  /// Cierre del partido: UN solo sheet con resultado, formato, puntos y
  /// desglose. Antes eran dos encadenados (resultado → estadísticas), lo que se
  /// sentía como dos pantallas para una sola pregunta.
  Future<void> _askResult(PlaySession s) async {
    final play = context.read<PlaySessionService>();

    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MatchStatsSheet(
        courtName: s.courtName,
        duration: PlaySessionService.fmt(s.seconds),
        multiplier: PlaySessionService.multiplierFor(s.seconds),
        session: s,
      ),
    );

    // Descartar el sheet (swipe o tap afuera) ⇒ null ⇒ "Sin información", igual
    // que cuando el resultado se elegía en un sheet aparte.
    final chosen = PlayResultX.fromName(res?['result'] as String?);
    if (chosen != null && mounted) {
      await play.resolvePending(
        chosen,
        userPoints: res?['pts'],
        userPts3: res?['p3'],
        userPts2: res?['p2'],
        userPts1: res?['p1'],
        // Desglose de la sesión: null salvo que haya abierto "Fue más de un
        // partido". Es lo que hace que los contadores y los logros cuenten
        // varios partidos en vez de uno.
        matchCount: res?['nMatches'],
        trainingCount: res?['nTrainings'],
        winCount: res?['nWins'],
        gamePoints: (res?['gamePts'] as List?)?.cast<int>(),
        gameFormats: (res?['gameFmt'] as List?)?.cast<int>(),
      );
      if (res?['viewDetail'] == true && mounted) {
        final updated = play.log.firstWhere(
          (e) => e.endedAtMillis == s.endedAtMillis,
          orElse: () => s,
        );
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MatchDetailScreen(session: updated),
            ),
          );
        }
      }
    } else {
      await play.resolvePending(PlayResult.notCounted);
    }
    if (mounted) setState(() => _resultPromptOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final courtsProvider = context.watch<CourtsProvider>();
    final courts = courtsProvider.courts;
    final hideTabs = _detailCourtId != null || _filtersOpen;

    // Loader de arranque: visible hasta que el mapa esté listo, haya primer GPS
    // y las canchas hayan cargado (o se agote el tope de seguridad).
    final loading = context.watch<AppLoadingState>();
    final loaderReady =
        loading.mapReady && loading.gpsReady && !courtsProvider.loading;
    final loaderVisible = !loaderReady && !_loaderTimedOut;

    // Estado del partido (para el aura del ícono del mapa y la píldora que
    // sigue al usuario fuera del Home). Mismos colores que el banner del mapa.
    final ps = context.watch<PlaySessionService>();
    final Color? matchGlow = ps.isPlaying
        ? (ps.isPaused ? AppColors.white(0.7) : AppColors.open)
        : (ps.isDwelling ? AppColors.accent : null);

    // Si hay un partido terminado sin resultado, preguntamos cómo le fue.
    final pending = ps.pending;
    if (pending != null && !_resultPromptOpen) {
      _resultPromptOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askResult(pending);
      });
    }

    // Home (mapa) persistente: queda SIEMPRE montado (no se recrea el platform
    // view) y solo se oculta con Offstage cuando no estás en Home o hay overlay,
    // para no renderizarlo de gusto. Lo demás se anima con slide por encima.
    final homeLayer = Offstage(
      offstage: _tab != AppTab.home || hideTabs,
      child: HomeScreen(
        courts: courts,
        focusCourtId: _focusCourtId,
        onFocusConsumed: () => _focusCourtId = null,
        onSelectCourt: _openDetail,
        onOpenFilters: _openFilters,
      ),
    );

    // Contenido de la pestaña activa (transparente sobre el mapa en Home).
    final Widget tabContent = switch (_tab) {
      AppTab.home => const IgnorePointer(
          key: ValueKey('tab:home'),
          child: SizedBox.expand(),
        ),
      AppTab.list => ListScreen(
          key: const ValueKey('tab:list'),
          courts: courts,
          onSelectCourt: _openDetail,
          // Las cards entran deslizando en la misma dirección que la pantalla
          // (el lado contrario a la pestaña de la que venís).
          enterDir: _slideDir,
        ),
      AppTab.plus => const CreateScreen(key: ValueKey('tab:plus')),
      AppTab.chat => const CrewScreen(key: ValueKey('tab:chat')),
      AppTab.profile => ProfileScreen(
          key: const ValueKey('tab:profile'),
          onSelectCourt: _openDetail,
          activeTab: _profileTab,
          onTabChange: (t) => setState(() => _profileTab = t),
        ),
    };
    final tabKey = ValueKey('tab:${_tab.name}');

    // Overlay (detalle / filtros) por encima de todo, con slide.
    Widget overlay = const SizedBox.shrink(key: ValueKey('none'));
    if (_filtersOpen) {
      overlay = FiltersScreen(key: const ValueKey('filters'), onBack: _closeFilters);
    } else if (_detailCourtId != null) {
      overlay = DetailScreen(
        key: ValueKey('detail:$_detailCourtId'),
        courtId: _detailCourtId!,
        courts: courts,
        onBack: _closeDetail,
        onShowOnMap: _showOnMap,
      );
    }
    final overlayKey = ValueKey(_screenKey);

    return PopScope(
      // Nunca dejamos que el back del sistema saque de la app directamente:
      // lo manejamos nosotros (cerrar overlay / volver a la pestaña anterior) y
      // solo salimos si no hay a dónde volver.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_handleBack()) SystemNavigator.pop();
      },
      child: Scaffold(
      // Retro-pop: cada pestaña tiene su color de fondo saturado. Acompaña el
      // slide entre pestañas (las pantallas repintan su propio PopBackground).
      backgroundColor: _bgForTab(_tab),
      body: Stack(
        children: [
          Positioned.fill(child: homeLayer),
          // Pestañas (no-Home) con slide horizontal direccional.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => _slideTransition(child, anim, tabKey),
              child: KeyedSubtree(key: tabKey, child: tabContent),
            ),
          ),
          // Deslizar horizontalmente para navegar entre pestañas (todas menos el
          // mapa). Translúcido: los taps y el scroll vertical pasan al contenido;
          // solo se activa fuera del mapa y sin overlays. En el mapa no está en
          // el árbol, así que sus gestos quedan intactos.
          if (_tab != AppTab.home && !hideTabs)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: _handleTabSwipe,
              ),
            ),
          // Overlay detalle/filtros.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !hideTabs,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => _slideTransition(child, anim, overlayKey),
                child: KeyedSubtree(key: overlayKey, child: overlay),
              ),
            ),
          ),
          if (!hideTabs)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom,
                ),
                child: AppTabBar(
                  active: _tab,
                  previous: _previousTab,
                  onChange: _selectTab,
                  crewHasActivity: crewActivityNotifier.value,
                  homeGlow: matchGlow,
                ),
              ),
            ),
          // Píldora de estado del partido: sigue al usuario fuera del mapa
          // (en Home ya está el banner completo). Se auto-oculta sin actividad.
          if (_tab != AppTab.home && !hideTabs)
            Positioned(
              top: MediaQuery.of(context).viewPadding.top + 10,
              left: 0,
              right: 0,
              child: Center(
                child: MatchStatusPill(onTap: () => _selectTab(AppTab.home)),
              ),
            ),
          // Entramos sin poder verificar contra el backend (sin red) porque hay
          // un partido sin terminar: hay que decirlo. Si no, el usuario ve
          // listas vacías y no entiende dónde se está registrando su partido.
          if (context.watch<Session>().startedOffline && !hideTabs)
            Positioned(
              top: MediaQuery.of(context).viewPadding.top,
              left: 0,
              right: 0,
              child: _offlineBanner(),
            ),
          // Banner de recompensas (logro/título/nivel) por encima de todo.
          // Va dentro de un Positioned para no alterar el tamaño del Stack.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: RewardOverlay(
              rewards: context.watch<PlaySessionService>().rewards,
              onConsume: () =>
                  context.read<PlaySessionService>().acknowledgeReward(),
            ),
          ),
          // Loader de carga inicial (mapa/canchas/GPS), por encima de todo.
          Positioned.fill(child: AppLoader(visible: loaderVisible)),
        ],
      ),
      ),
    );
  }

  /// Aviso de que entramos sin conexión (hay un partido sin terminar). Tranquiliza
  /// sobre lo importante: el partido no se pierde. Se va solo al recuperar la red.
  Widget _offlineBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgElev,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.busy.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.busy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin conexión. Tu sesión se registra igual y se sube cuando vuelva el internet.',
              style: AppText.grotesk(
                  size: 12, color: AppColors.white(0.75), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet ÚNICO de cierre de partido: resultado, formato, puntos y desglose.
///
/// Antes eran dos sheets encadenados (elegir resultado → cargar estadísticas).
/// Se unificaron porque son una sola pregunta —"¿qué pasó en la cancha?"— y
/// encadenar dos hojas para eso se sentía como dos pantallas distintas.
///
/// El resultado es lo único OBLIGATORIO: sin él no hay nada que registrar, así
/// que los botones quedan deshabilitados hasta elegirlo. Descartar el sheet
/// devuelve null y el partido se guarda como "Sin información".
class _MatchStatsSheet extends StatefulWidget {
  final String courtName;
  final String duration;
  final double multiplier;
  final PlaySession session;

  const _MatchStatsSheet({
    required this.courtName,
    required this.duration,
    required this.multiplier,
    required this.session,
  });

  @override
  State<_MatchStatsSheet> createState() => _MatchStatsSheetState();
}

class _MatchStatsSheetState extends State<_MatchStatsSheet> {
  /// Resultado elegido. null = todavía no eligió ⇒ no se puede guardar.
  PlayResult? _result;

  /// Formato cuando NO hay desglose (jugadores por equipo, 1..5).
  int _format = 3;

  final _ptsCtrl = TextEditingController();
  final _p3Ctrl = TextEditingController();
  final _p2Ctrl = TextEditingController();
  final _p1Ctrl = TextEditingController();

  // ── Desglose "Fue más de un partido" ─────────────────────────────────────
  // Cerrado por defecto: el caso común sigue siendo un solo partido y no vale la
  // pena alargarle el formulario a todo el mundo.
  bool _multi = false;
  int _matches = 2;
  int _trainings = 0;
  int _wins = 0;
  bool _perGame = false;
  final List<TextEditingController> _gameCtrls = [];

  /// Un formato por partido: se puede mezclar 3v3 con 1v1 en la misma tarde.
  final List<int> _gameFmts = [];

  @override
  void dispose() {
    _ptsCtrl.dispose();
    _p3Ctrl.dispose();
    _p2Ctrl.dispose();
    _p1Ctrl.dispose();
    for (final c in _gameCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Mantiene un controller y un formato por partido al cambiar la cantidad. Se
  /// conservan los valores ya cargados: bajar y volver a subir la cantidad no
  /// debería borrar lo que el usuario venía poniendo.
  void _syncPerGame() {
    while (_gameCtrls.length < _matches) {
      _gameCtrls.add(TextEditingController());
    }
    while (_gameCtrls.length > _matches) {
      _gameCtrls.removeLast().dispose();
    }
    while (_gameFmts.length < _matches) {
      _gameFmts.add(_format); // arranca con el formato general
    }
    while (_gameFmts.length > _matches) {
      _gameFmts.removeLast();
    }
  }

  /// Suma de los puntos por partido, o null si no se cargó ninguno.
  int? get _gamePointsTotal {
    if (!_multi || !_perGame) return null;
    var total = 0;
    var any = false;
    for (final c in _gameCtrls) {
      final v = int.tryParse(c.text.trim());
      if (v != null) {
        total += v;
        any = true;
      }
    }
    return any ? total : null;
  }

  Map<String, dynamic> _payload({required bool viewDetail}) {
    final perGameTotal = _gamePointsTotal;
    return {
      'result': _result!.name,
      'pts': perGameTotal ?? int.tryParse(_ptsCtrl.text),
      'p3': int.tryParse(_p3Ctrl.text),
      'p2': int.tryParse(_p2Ctrl.text),
      'p1': int.tryParse(_p1Ctrl.text),
      // Con desglose va un formato por partido; sin desglose, uno solo. Siempre
      // lista, para que el modelo no tenga dos caminos.
      'gameFmt': _multi ? List<int>.from(_gameFmts) : <int>[_format],
      if (_multi) ...{
        'nMatches': _matches,
        'nTrainings': _trainings,
        'nWins': _wins,
        if (_perGame && perGameTotal != null)
          'gamePts': [
            for (final c in _gameCtrls) int.tryParse(c.text.trim()) ?? 0,
          ],
      },
      'viewDetail': viewDetail,
    };
  }

  // ── Piezas de UI ─────────────────────────────────────────────────────────

  InputDecoration _numDeco(double size) => InputDecoration(
        hintText: '0',
        hintStyle: AppText.display(size: size, color: AppColors.white(0.14)),
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.only(bottom: 6, top: 2),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.white(0.12)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
      );

  Widget _numField(String label, TextEditingController ctrl,
      {bool isLast = false}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          microLabel(label),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textInputAction:
                isLast ? TextInputAction.done : TextInputAction.next,
            style: AppText.display(size: 24, height: 1.0),
            cursorColor: AppColors.accent,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: _numDeco(16),
          ),
        ],
      ),
    );
  }

  /// Fila de resultado: barra de color + label. Al elegir NO cierra el sheet
  /// (antes sí): queda marcada y el usuario sigue cargando lo demás.
  Widget _resultRow(PlayResult r, IconData icon, Color color) {
    final sel = _result == r;
    return PressableWidget(
      onTap: () => setState(() => _result = r),
      child: Container(
        color: sel ? color.withAlpha(28) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        child: Row(
          children: [
            Container(width: 4, height: 24, color: color),
            const SizedBox(width: 14),
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(r.label.toUpperCase(),
                  style: AppText.archivo(
                      size: 15,
                      weight: FontWeight.w800,
                      letterSpacing: 0.02,
                      color: sel ? Colors.white : AppColors.white(0.7))),
            ),
            if (sel) Icon(Icons.check_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  /// Selector de formato 1v1..5v5. [compact] para las filas por partido, donde
  /// no hay ancho para el segmentado grande.
  Widget _formatPicker(int value, ValueChanged<int> onChanged,
      {bool compact = false}) {
    return Row(
      children: [
        for (var n = 1; n <= 5; n++) ...[
          if (n > 1) SizedBox(width: compact ? 4 : 6),
          Expanded(
            child: PressableWidget(
              onTap: () => onChanged(n),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: compact ? 6 : 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == n ? AppColors.accent : Colors.transparent,
                  border: Border.all(
                    color:
                        value == n ? AppColors.accent : AppColors.white(0.12),
                  ),
                  borderRadius: BorderRadius.circular(AppShape.rChip),
                ),
                child: Text('${n}v$n',
                    style: AppText.archivo(
                        size: compact ? 10.5 : 13,
                        weight: FontWeight.w800,
                        color: value == n
                            ? Colors.white
                            : AppColors.white(0.6))),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Contador compacto con -/+. Se usa en vez de un input porque los límites
  /// (victorias ≤ partidos) quedan garantizados por construcción.
  Widget _counter(String label, int value, int min, int max,
      ValueChanged<int> onChanged) {
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) =>
        PressableWidget(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(icon,
                size: 16,
                color: enabled ? AppColors.white(0.8) : AppColors.white(0.2)),
          ),
        );
    return Expanded(
      child: Column(
        children: [
          Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.grotesk(
                  size: 9,
                  weight: FontWeight.w700,
                  color: AppColors.white(0.4),
                  letterSpacing: 0.06)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.white(0.12))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                btn(Icons.remove, value > min, () => onChanged(value - 1)),
                Text('$value', style: AppText.display(size: 22, height: 1.0)),
                btn(Icons.add, value < max, () => onChanged(value + 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Desglose de la sesión: cuántos partidos/entrenamientos/victorias y, por
  /// partido, su formato y sus puntos.
  Widget _multiSection() {
    return Column(
      children: [
        PressableWidget(
          onTap: () => setState(() {
            _multi = !_multi;
            if (_multi) _syncPerGame();
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Icon(Icons.groups_2_outlined,
                    size: 18,
                    color: _multi ? AppColors.accent : AppColors.white(0.45)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('FUE MÁS DE UN PARTIDO',
                      style: AppText.archivo(
                          size: 13,
                          weight: FontWeight.w800,
                          letterSpacing: 0.04,
                          color:
                              _multi ? Colors.white : AppColors.white(0.7))),
                ),
                Icon(_multi ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: AppColors.white(0.4)),
              ],
            ),
          ),
        ),
        if (_multi)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _counter('Partidos', _matches, 0, 12, (v) {
                      setState(() {
                        _matches = v;
                        // Las victorias no pueden superar a los partidos: el
                        // tope se ajusta solo al bajar la cantidad.
                        if (_wins > _matches) _wins = _matches;
                        _syncPerGame();
                        if (_matches < 2) _perGame = false;
                      });
                    }),
                    const SizedBox(width: 8),
                    _counter('Entrenam.', _trainings, 0, 12,
                        (v) => setState(() => _trainings = v)),
                    const SizedBox(width: 8),
                    _counter('Victorias', _wins, 0, _matches,
                        (v) => setState(() => _wins = v)),
                  ],
                ),
                if (_matches >= 2) ...[
                  const SizedBox(height: 14),
                  PressableWidget(
                    onTap: () => setState(() => _perGame = !_perGame),
                    child: Row(
                      children: [
                        Icon(
                          _perGame
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 18,
                          color:
                              _perGame ? AppColors.accent : AppColors.white(0.4),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Cargar los puntos de cada partido',
                              style: AppText.grotesk(
                                  size: 12.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.white(0.75))),
                        ),
                      ],
                    ),
                  ),
                ],
                // Una fila por partido: su formato y, si se pidió, sus puntos.
                if (_gameFmts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  microLabel('Formato de cada partido'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _gameFmts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text('P${i + 1}',
                                style: AppText.grotesk(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: AppColors.white(0.45))),
                          ),
                          Expanded(
                            child: _formatPicker(
                              _gameFmts[i],
                              (n) => setState(() => _gameFmts[i] = n),
                              compact: true,
                            ),
                          ),
                          if (_perGame) ...[
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 54,
                              child: TextField(
                                controller: _gameCtrls[i],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: AppText.display(size: 18, height: 1.0),
                                cursorColor: AppColors.accent,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                // Refresca el total de arriba, que es la suma.
                                onChanged: (_) => setState(() {}),
                                decoration: _numDeco(14),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final puedeGuardar = _result != null;

    // El total lo manda la suma por partido mientras esa carga esté activa.
    final perGameTotal = _gamePointsTotal;
    if (perGameTotal != null && _ptsCtrl.text != '$perGameTotal') {
      _ptsCtrl.text = '$perGameTotal';
    }

    return Padding(
      // El padding del teclado va AFUERA del container: así el sheet flota por
      // encima del teclado y el contenido nunca queda tapado.
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: screenH * 0.9),
        decoration: const BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.white(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  displayTitle('¿CÓMO TE FUE?', size: 30),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.courtName.isEmpty ? 'Cancha' : widget.courtName}  ·  ${widget.duration}  ·  x${widget.multiplier.toStringAsFixed(2)}',
                    style:
                        AppText.grotesk(size: 12, color: AppColors.white(0.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1) Resultado (obligatorio)
                    for (final o in <(PlayResult, IconData, Color)>[
                      (PlayResult.win, Icons.emoji_events, AppColors.open),
                      (PlayResult.loss, Icons.thumb_down_alt_outlined,
                          AppColors.accentDark),
                      (PlayResult.tie, Icons.handshake_outlined,
                          AppColors.white(0.7)),
                      (PlayResult.training, Icons.fitness_center,
                          AppColors.accent),
                      (PlayResult.notCounted, Icons.not_interested,
                          AppColors.white(0.4)),
                    ]) ...[
                      if (o.$1 != PlayResult.win) hairline(),
                      _resultRow(o.$1, o.$2, o.$3),
                    ],
                    const SizedBox(height: 20),
                    // 2) Formato general. Con desglose no va: ahí cada partido
                    //    tiene el suyo y tener los dos confundiría.
                    if (!_multi) ...[
                      microLabel('Formato'),
                      const SizedBox(height: 8),
                      _formatPicker(
                          _format, (n) => setState(() => _format = n)),
                      const SizedBox(height: 20),
                    ],
                    // 3) Puntos
                    microLabel(perGameTotal != null
                        ? 'Puntos anotados (suma)'
                        : 'Puntos anotados'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _ptsCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.next,
                      // Con los puntos cargados partido por partido el total es
                      // la suma y se bloquea: dos fuentes editables para el
                      // mismo número solo generan contradicciones.
                      readOnly: perGameTotal != null,
                      style: AppText.display(size: 48, height: 1.0),
                      cursorColor: AppColors.accent,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: _numDeco(20),
                    ),
                    const SizedBox(height: 16),
                    // Desglose por VALOR del tiro: en 3x3 los tiros valen 1 y 2,
                    // así que "triple" sería un nombre equivocado.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _numField('Pts de 3', _p3Ctrl),
                        const SizedBox(width: 10),
                        _numField('Pts de 2', _p2Ctrl),
                        const SizedBox(width: 10),
                        _numField('Pts de 1', _p1Ctrl, isLast: true),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 4) Desglose de la sesión
                    _multiSection(),
                    const SizedBox(height: 14),
                    Text(
                      'No importa si no es exacto: con el tiempo se arma tu promedio.',
                      style: AppText.grotesk(
                          size: 11.5,
                          color: AppColors.white(0.4),
                          height: 1.4),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Container(
              // El bottom fijo (24) no alcanza con la barra de gestos/HUD de
              // Samsung: sin sumar el viewPadding, "VER RESULTADO" queda tapado
              // por la barra del sistema. El teclado ya se maneja aparte, con el
              // Padding que envuelve todo el sheet (viewInsets, más arriba).
              padding: EdgeInsets.fromLTRB(
                  24, 12, 24, 24 + MediaQuery.of(context).viewPadding.bottom),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: puedeGuardar
                          ? () =>
                              Navigator.pop(context, _payload(viewDetail: false))
                          : null,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppShape.rChip),
                          side:
                              BorderSide(color: AppColors.white(0.12), width: 1),
                        ),
                      ),
                      child: Text('LISTO',
                          style: AppText.archivo(
                              size: 13,
                              weight: FontWeight.w800,
                              letterSpacing: 0.06,
                              color: puedeGuardar
                                  ? AppColors.white(0.75)
                                  : AppColors.white(0.3))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextButton(
                      onPressed: puedeGuardar
                          ? () =>
                              Navigator.pop(context, _payload(viewDetail: true))
                          : null,
                      style: TextButton.styleFrom(
                        backgroundColor: puedeGuardar
                            ? AppColors.accent
                            : AppColors.white(0.08),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shadowColor: Colors.black,
                        elevation: puedeGuardar ? 6 : 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppShape.rChip),
                        ),
                      ),
                      child: Text(
                          puedeGuardar ? 'VER RESULTADO' : 'ELEGÍ UN RESULTADO',
                          style: AppText.archivo(
                              size: 13,
                              weight: FontWeight.w800,
                              letterSpacing: 0.06,
                              color: puedeGuardar
                                  ? Colors.white
                                  : AppColors.white(0.35))),
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
