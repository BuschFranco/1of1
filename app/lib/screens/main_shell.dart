import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/analytics_service.dart';
import '../services/app_loading_state.dart';
import '../services/courts_provider.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_loader.dart';
import '../widgets/app_tour.dart';
import '../widgets/permissions_modal.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/form_style.dart';
import '../widgets/match_status_pill.dart';
import '../widgets/offline_pill.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/reward_banner.dart';
import 'create_screen.dart';
import 'detail_screen.dart';
import 'filters_screen.dart';
import 'home_screen.dart';
import 'list_screen.dart';
import 'match_detail_screen.dart';
import 'profile_screen.dart';
import 'social_screen.dart';

/// ValueNotifier global para el badge de activity en el tab de crew.
/// Se setea desde pickup_create_screen al crear un chat de equipo, y se limpia
/// cuando el usuario abre la pestaña de crew.
final ValueNotifier<bool> crewActivityNotifier = ValueNotifier<bool>(false);

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with RestorationMixin {
  AppTab _tab = AppTab.home;

  // Pestaña y subpestañas para la restauración de estado (ver
  // `restorationScopeId` en main.dart). -1 = nada que restaurar.
  final RestorableInt _savedTab = RestorableInt(-1);
  final RestorableInt _savedProfileTab = RestorableInt(0);
  final RestorableInt _savedSocialTab = RestorableInt(0);

  @override
  String get restorationId => 'main_shell';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_savedTab, 'tab');
    registerForRestoration(_savedProfileTab, 'profile_tab');
    registerForRestoration(_savedSocialTab, 'social_tab');
    final i = _savedTab.value;
    if (i < 0 || i >= AppTab.values.length) return;
    final t = AppTab.values[i];
    // Sin red no se puede volver a una pestaña que la necesita.
    if (context.read<Session>().offline && _offlineBlocked.contains(t)) return;
    _tab = t;
    _previousTab = t;
    _profileTab = _savedProfileTab.value;
    _socialTab = _savedSocialTab.value;
  }

  /// Guarda dónde está el usuario. Se llama en cada build en vez de en cada
  /// cambio de pestaña porque `_tab` se asigna en varios lugares (tap, swipe,
  /// back, offline); escribir un valor igual no hace nada.
  void _saveTabs() {
    _savedTab.value = _tab.index;
    _savedProfileTab.value = _profileTab;
    _savedSocialTab.value = _socialTab;
  }
  AppTab _previousTab = AppTab.home;

  // Subpestaña del Perfil (0 = Perfil, 1 = Amigos). Vive acá para que el swipe
  // del shell pueda alternarla antes de saltar a otra pestaña principal.
  int _profileTab = 0;

  // Subpestaña de Social (0 = Crew, 1 = Noticias). Mismo motivo que _profileTab.
  int _socialTab = 0;

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
    if (context.read<Session>().offline && _offlineBlocked.contains(_tab)) {
      _tab = AppTab.home;
    }
    _previousTab = _tab;
    _loaderTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _loaderTimedOut = true);
    });
    _loadCrewActivity();
    crewActivityNotifier.addListener(_onCrewActivityChanged);
    // Bienvenida tras un login/registro explícito (una sola vez). Se muestra
    // dentro de la secuencia del primer ingreso, no suelta.
    _welcomePending = context.read<Session>().consumeJustAuthenticated();
    appTourRequest.addListener(_onTourRequested);
  }

  // ── Primer ingreso: bienvenida → permisos → tour ─────────────────────────
  // Antes la bienvenida y el pedido de permisos salían a la vez y se pisaban;
  // el tour habría sido un tercero encima. Ahora van en fila, y recién cuando
  // el loader del arranque ya se fue (el tour necesita el mapa a la vista).

  bool _welcomePending = false;
  bool _firstRunStarted = false;
  bool _tourRunning = false;

  void _onTourRequested() => unawaited(_runTour());

  // Tour corto por pestaña (Crear, Social, Perfil): la primera vez que el
  // usuario entra a cada una, DESPUÉS del tour principal. Flag por pestaña y
  // por usuario (`tour_seen_<tab>::uk`).
  AppTab? _tabTourChecked;

  void _maybeTabTour() {
    final tab = _tab;
    if (_tabTourChecked == tab) return;
    _tabTourChecked = tab;
    final steps = _tabTourSteps[tab];
    if (steps == null || !_firstRunDone) return;
    unawaited(() async {
      // Que termine la animación de entrada de la pestaña.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || _tab != tab || _tourRunning) return;
      final uk = (context.read<Session>().email ?? '').trim().toLowerCase();
      if (uk.isEmpty) return;
      final key = 'tour_seen_${tab.name}::$uk';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return;
      if (!mounted || _tab != tab || _tourRunning) return;
      _tourRunning = true;
      try {
        await runAppTour(context, steps, id: tab.name);
      } finally {
        _tourRunning = false;
      }
      // El tour del Perfil baja hasta los Logros: devolverlo arriba.
      final sc = TourKeys.profileScroll;
      if (tab == AppTab.profile && sc != null && sc.hasClients) {
        unawaited(sc.animateTo(0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut));
      }
      await prefs.setBool(key, true);
    }());
  }

  // Recién cuando terminó la secuencia del primer ingreso (con o sin tour
  // principal) pueden salir los de cada pestaña: si no, se apilarían.
  bool _firstRunDone = false;

  static final Map<AppTab, List<TourStep>> _tabTourSteps = {
    AppTab.plus: [
      TourStep(
        TourKeys.createPickup,
        'Armá un pickup',
        'Elegí la cancha, el día y el horario, el formato (de 1v1 a 5v5) y a '
            'cuántos puntos se juega. Puede ser público, para que se sume '
            'cualquiera, o privado, solo con el código de invitación. Al '
            'crearlo se abre un chat para coordinar con tu crew.',
      ),
      TourStep(
        TourKeys.joinPickup,
        'Unite con un código',
        '¿Te pasaron el código de un pickup? Ingresalo acá y entrás directo '
            'al chat.',
      ),
      TourStep(
        TourKeys.addCourt,
        'Sumá una cancha',
        'Si conocés una que no está en el mapa, proponela. La revisamos y te '
            'avisamos cuando se aprueba.',
      ),
    ],
    AppTab.chat: [
      TourStep(
        TourKeys.socialTabs,
        'Crew y Noticias',
        'En Crew están los chats de tus pickups; en Noticias, lo último de la '
            'NBA, la WNBA, la Liga Nacional y el 3x3.',
      ),
      TourStep(
        TourKeys.crewList,
        'Tus pickups',
        'Acá aparecen los pickups que creaste o aceptaste. Tocá uno para abrir '
            'el chat y coordinar. Las invitaciones nuevas te llegan a la '
            'campanita del Perfil.',
      ),
    ],
    AppTab.profile: [
      TourStep(
        TourKeys.profileTabs,
        'Amigos',
        'Buscá jugadores por su usuario, agregalos y mirá cuándo están '
            'jugando.',
        scroll: () => TourKeys.profileScroll,
      ),
      TourStep(
        TourKeys.profileNotif,
        'Notificaciones',
        'Invitaciones a pickups y avisos de la app.',
        scroll: () => TourKeys.profileScroll,
      ),
      TourStep(
        TourKeys.profileSettings,
        'Ajustes',
        'Privacidad, permisos y salud, personalización, y este tutorial si '
            'querés volver a verlo.',
        scroll: () => TourKeys.profileScroll,
      ),
      TourStep(
        TourKeys.profileLevel,
        'Tu nivel',
        'Sumás EXP con cada sesión de juego: por el tiempo en la cancha, los '
            'partidos ganados, las rachas y las canchas nuevas.',
        scroll: () => TourKeys.profileScroll,
      ),
      TourStep(
        TourKeys.profileStats,
        'Tus números',
        'Partidos, canchas, racha y ranking. Tocá la racha o el ranking para '
            'ver el detalle.',
        scroll: () => TourKeys.profileScroll,
      ),
      TourStep(
        TourKeys.profileClan,
        'Tu clan',
        'Elegí la insignia de tu clan. El clan que más puntos suma en una '
            'cancha la conquista, y su insignia aparece en el mapa.',
        scroll: () => TourKeys.profileScroll,
      ),
      TourStep(
        TourKeys.profileTitles,
        'Títulos',
        'Se desbloquean completando logros y tienen rareza: común, raro, épico '
            'y legendario. Equipá uno y se muestra debajo de tu nombre.',
        scroll: () => TourKeys.profileScroll,
      ),
      TourStep(
        TourKeys.profileAchievements,
        'Logros',
        'Desafíos que se cumplen jugando: sesiones, canchas distintas, rachas '
            'y más. Cada logro te acerca a un título nuevo.',
        scroll: () => TourKeys.profileScroll,
      ),
    ],
  };

  Future<void> _firstRunSequence() async {
    // Que termine el fade del loader.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (_welcomePending) {
      _welcomePending = false;
      await _showWelcome();
      if (!mounted) return;
    }
    await PermissionsModal.showOnceIfNeeded(context);
    if (!mounted) return;
    final uk = (context.read<Session>().email ?? '').trim().toLowerCase();
    if (uk.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('tour_seen::$uk') ?? false) return;
    // El sheet de cierre de una sesión de juego tiene prioridad: el tour queda
    // para la próxima apertura (sin marcar el flag).
    if (_resultPromptOpen || !mounted) return;
    await _runTour();
    await prefs.setBool('tour_seen::$uk', true);
  }

  /// Envuelve la secuencia para marcar el final pase lo que pase (un return
  /// temprano también cuenta: no hay nada más que esperar).
  Future<void> _runFirstRun() async {
    try {
      await _firstRunSequence();
    } finally {
      _firstRunDone = true;
      // Si el usuario ya estaba en una pestaña con tour propio, mostrarlo.
      _tabTourChecked = null;
      if (mounted) _maybeTabTour();
    }
  }

  Future<void> _runTour() async {
    if (_tourRunning || !mounted) return;
    _tourRunning = true;
    try {
      // El tour arranca en el mapa (ahí está casi todo lo que recorre).
      if (_tab != AppTab.home) {
        _selectTab(AppTab.home);
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
      }
      await runAppTour(context, _tourSteps, id: 'main');
    } finally {
      _tourRunning = false;
    }
  }

  // Textos del tour. Vocabulario de app/CLAUDE.md: lo que se detecta es una
  // "sesión de juego"; un "partido" es uno de los juegos de adentro.
  static final List<TourStep> _tourSteps = [
    TourStep(
      TourKeys.timer,
      'Tus sesiones se registran solas',
      'Llegá a una cancha y a los 6 minutos arranca tu sesión de juego, '
          'aunque tengas la app cerrada. Cuando te vas, cargás cómo te fue.',
    ),
    TourStep(
      TourKeys.courtCard,
      'Canchas cerca tuyo',
      'Deslizá para ver más. En "Ver detalle" tenés reseñas, el rey y el clan '
          'de la cancha; con "Pickup" armás un partido ahí.',
    ),
    TourStep(
      TourKeys.search,
      'Buscá por barrio',
      'Escribí un barrio o una zona y el mapa te lleva ahí. Con los filtros '
          '(el botón de al lado y los chips de abajo) ves solo las abiertas '
          'ahora, iluminadas, gratis o techadas.',
    ),
    TourStep(
      TourKeys.ranking,
      'Ranking',
      'Los mejores jugadores y clanes de 1of1. Jugá para escalar.',
    ),
    TourStep(
      TourKeys.tab(AppTab.list),
      'Todas las canchas',
      'La lista completa, ordenada por cercanía, rating o actividad.',
    ),
    TourStep(
      TourKeys.tab(AppTab.plus),
      'Armá un pickup',
      'Elegí cancha y horario, invitá a tus amigos y coordiná en el chat.',
    ),
    TourStep(
      TourKeys.tab(AppTab.chat),
      'Social',
      'Tu crew, los chats de tus pickups y noticias de básquet.',
    ),
    TourStep(
      TourKeys.tab(AppTab.profile),
      'Tu perfil',
      'Tu nivel, EXP, rachas, logros y el historial de tus sesiones.',
    ),
  ];

  /// Agradecimiento de bienvenida (fase temprana pero estable). Se muestra una
  /// vez, justo después de que el usuario entra por login o registro.
  Future<void> _showWelcome() async {
    if (!mounted) return;
    await showDialog<void>(
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
    appTourRequest.removeListener(_onTourRequested);
    _loaderTimer?.cancel();
    _savedTab.dispose();
    _savedProfileTab.dispose();
    _savedSocialTab.dispose();
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

  /// Pestañas que necesitan red: en modo offline no se puede entrar.
  static const Set<AppTab> _offlineBlocked = {AppTab.plus, AppTab.chat};

  bool get _offline => context.read<Session>().offline;

  // Último estado de conexión visto en build (null = primer build), para
  // avisar solo en los cambios.
  bool? _lastOffline;

  /// Aviso al cortarse / volver la red. Va por el ScaffoldMessenger de la app,
  /// así se ve también dentro de pantallas abiertas encima (chat, detalle).
  void _showConnectivityNotice(bool offline) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
            offline
                ? 'Te quedaste sin conexión. Lo que registres se guarda en el '
                    'celu y se sube cuando vuelva.'
                : 'Volvió la conexión.',
            style: AppText.grotesk(size: 13)),
        backgroundColor: AppColors.bgElev,
      ));
  }

  // Última pantalla registrada en Analytics. Se loguea desde build() porque a
  // la pestaña se llega por varios caminos (tap, swipe, atrás, "ver en mapa").
  String? _loggedScreen;

  void _logScreen() {
    final name = _detailCourtId != null
        ? 'cancha_detalle'
        : _filtersOpen
            ? 'filtros'
            : switch (_tab) {
                AppTab.home => 'mapa',
                AppTab.list => 'canchas',
                AppTab.plus => 'crear',
                AppTab.chat => 'social',
                AppTab.profile => 'perfil',
              };
    if (name == _loggedScreen) return;
    _loggedScreen = name;
    AnalyticsService.screen(name);
  }

  void _selectTab(AppTab t) {
    if (t == _tab) return;
    if (_offline && _offlineBlocked.contains(t)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Disponible cuando tengas conexión.',
              style: AppText.grotesk(size: 13)),
          backgroundColor: AppColors.bgElev,
        ));
      return;
    }
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
    // Ídem en Social: si estás en Noticias, atrás vuelve a Crew.
    if (_tab == AppTab.chat && _socialTab == 1) {
      setState(() => _socialTab = 0);
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
    // Ídem, para el segmento Crew/Noticias de Social.
    if (_tab == AppTab.chat) {
      if (v < 0 && _socialTab == 0) {
        setState(() => _socialTab = 1); // swipe izquierda → Noticias
        return;
      }
      if (v > 0 && _socialTab == 1) {
        setState(() => _socialTab = 0); // swipe derecha → Crew
        return;
      }
    }
    // Desde Canchas, deslizar a la derecha vuelve al Mapa. (Al revés NO: en el
    // Mapa no hay capa de swipe, así que sus gestos quedan intactos.)
    if (v > 0 && _tab == AppTab.list) {
      _selectTab(AppTab.home);
      return;
    }
    // Offline, el swipe saltea las pestañas bloqueadas.
    final tabs = _offline
        ? [for (final t in _swipeTabs) if (!_offlineBlocked.contains(t)) t]
        : _swipeTabs;
    final idx = tabs.indexOf(_tab);
    if (idx < 0) return; // estamos en el mapa: no aplica
    if (v < 0 && idx < tabs.length - 1) {
      _selectTab(tabs[idx + 1]); // swipe a la izquierda → siguiente
    } else if (v > 0 && idx > 0) {
      _selectTab(tabs[idx - 1]); // swipe a la derecha → anterior
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
    _logScreen();
    final courtsProvider = context.watch<CourtsProvider>();
    final courts = courtsProvider.courts;
    final hideTabs = _detailCourtId != null || _filtersOpen;
    final offline = context.select<Session, bool>((s) => s.offline);
    _saveTabs();
    // El modo offline puede llegar con la app en uso (se cortó la red, o el
    // `GET /me` del arranque falló con el shell ya montado). NO se echa al
    // usuario de la pestaña en la que está (p. ej. escribiendo en un chat): se
    // avisa, y lo que necesita red queda bloqueado si sale y quiere volver
    // (`_selectTab`, `requireOnline`).
    if (offline != _lastOffline) {
      final was = _lastOffline;
      _lastOffline = offline;
      if (was != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showConnectivityNotice(offline));
      }
    }

    // Loader de arranque: visible hasta que el mapa esté listo, haya primer GPS
    // y las canchas hayan cargado (o se agote el tope de seguridad).
    final loading = context.watch<AppLoadingState>();
    final loaderReady =
        loading.mapReady && loading.gpsReady && !courtsProvider.loading;
    final loaderVisible = !loaderReady && !_loaderTimedOut;
    if (!loaderVisible && !_firstRunStarted) {
      _firstRunStarted = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_runFirstRun()));
    }
    if (_tabTourChecked != _tab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeTabTour();
      });
    }

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
      AppTab.chat => SocialScreen(
          key: const ValueKey('tab:chat'),
          activeTab: _socialTab,
          onTabChange: (t) => setState(() => _socialTab = t),
        ),
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
                  disabled: offline ? _offlineBlocked : const {},
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
          // Modo offline: botón flotante para reconectar, siguiendo al usuario
          // por las pestañas. En el mapa ocupa el lugar del buscador (que sin
          // red no funciona), así que lo pinta HomeScreen; acá va arriba de la
          // barra de pestañas.
          if (offline && !hideTabs && _tab != AppTab.home)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).viewPadding.bottom + 92,
              child: const Center(child: OfflinePill()),
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
}

/// Qué hizo el usuario en la sesión. Es la PRIMERA pregunta del sheet y la que
/// decide qué pasos siguen; antes esto venía mezclado con el resultado en una
/// sola lista de cinco filas, que juntaba dos preguntas distintas ("qué hiciste"
/// y "cómo te fue") en un mismo control.
enum _Actividad { partidos, entrenamiento, ambas }

/// Cómo carga sus puntos el usuario. UNO A LA VEZ, a propósito: antes el total
/// a mano, el desglose por valor de tiro y los puntos por partido convivían y
/// ninguno se validaba contra los otros, así que se podía guardar un total de 30
/// con un desglose que sumaba 12. Con un solo modo activo la contradicción es
/// imposible por construcción y no hace falta inventar validación cruzada.
enum _ModoPuntos { total, porValor, porPartido }

/// Colores del desglose por valor de tiro. Gemelos de los de
/// `game_stats_screen.dart`: el input y el gráfico tienen que leerse como la
/// misma cosa.
const _dot3 = Color(0xFF3B82F6);
const _dot2 = Color(0xFFA855F7);
const _dot1 = Color(0xFFEAB308);

/// Sheet ÚNICO de cierre de la sesión de juego: qué hiciste, el marcador, el
/// formato y los puntos.
///
/// Antes eran dos sheets encadenados (elegir resultado → cargar estadísticas).
/// Se unificaron porque son una sola pregunta —"¿qué pasó en la cancha?"— y
/// encadenar dos hojas para eso se sentía como dos pantallas distintas.
///
/// **El resultado NO se elige: se deriva del marcador.** Elegirlo a mano y
/// cargar aparte cuántos partidos se ganaron permitía contradecirse (marcar
/// VICTORIA con 1 de 3 ganados), y la app lo tapaba por atrás con
/// [PlaySession.displayResult], que mostraba lo contrario de lo que el usuario
/// acababa de elegir sin explicar por qué. Ahora el marcador es la entrada y el
/// resultado es su consecuencia, visible en vivo mientras se carga.
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
  // ── Paso 1: qué hiciste ──────────────────────────────────────────────────
  _Actividad _actividad = _Actividad.partidos;

  /// "No cuentes esta sesión": reemplaza a la fila SIN INFORMACIÓN. Cuando está
  /// activo, todo lo demás deja de preguntarse.
  bool _noCuenta = false;

  // ── Paso 2: el marcador ──────────────────────────────────────────────────
  int _partidos = 1;
  int _ganados = 0;
  int _entrenamientos = 1;

  /// Resultado del único partido cuando [_partidos] == 1. Con un solo partido
  /// un contador 0..1 sería un control raro para una pregunta de tres opciones.
  PlayResult? _unico;

  // ── Paso 3: formato ──────────────────────────────────────────────────────
  /// Formato general (jugadores por equipo, 1..5). `null` = el usuario no
  /// eligió. **No hay default**: antes arrancaba en 3 y el payload lo escribía
  /// siempre, así que toda sesión decía "3v3" aunque nadie hubiera mirado el
  /// control, y `hasFormats` no significaba nada.
  int? _formato;

  /// Un formato por partido: se puede mezclar 3v3 con 1v1 en la misma tarde.
  final List<int?> _fmts = [];

  // ── Paso 4: puntos ───────────────────────────────────────────────────────
  _ModoPuntos _modo = _ModoPuntos.total;
  final _ptsCtrl = TextEditingController();
  final _p3Ctrl = TextEditingController();
  final _p2Ctrl = TextEditingController();
  final _p1Ctrl = TextEditingController();
  final List<TextEditingController> _gameCtrls = [];

  @override
  void initState() {
    super.initState();
    _sync();
  }

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
  void _sync() {
    // Ojo: la cantidad de filas depende de la ACTIVIDAD, no de [_noCuenta].
    // Si dependiera de `_hayPartidos`, tildar "no cuentes esta sesión" borraría
    // los formatos y los puntos ya cargados, y destildarlo no los devolvería.
    final n = _actividad == _Actividad.entrenamiento ? 0 : _partidos;
    while (_gameCtrls.length < n) {
      _gameCtrls.add(TextEditingController());
    }
    while (_gameCtrls.length > n) {
      _gameCtrls.removeLast().dispose();
    }
    while (_fmts.length < n) {
      _fmts.add(_formato);
    }
    while (_fmts.length > n) {
      _fmts.removeLast();
    }
    if (_ganados > _partidos) _ganados = _partidos;
    // "Por partido" no tiene sentido con uno solo: ahí el total YA es el del
    // partido. Se cae a "Total" sin avisar, igual que antes se apagaba el check.
    if (_partidos < 2 && _modo == _ModoPuntos.porPartido) {
      _modo = _ModoPuntos.total;
    }
    if (!_hayPartidos) _modo = _ModoPuntos.total;
  }

  bool get _hayPartidos =>
      !_noCuenta &&
      (_actividad == _Actividad.partidos || _actividad == _Actividad.ambas);

  bool get _hayEntrenamiento =>
      !_noCuenta &&
      (_actividad == _Actividad.entrenamiento ||
          _actividad == _Actividad.ambas);

  /// Formatos efectivamente elegidos, sin repetir. Vacío = el usuario no eligió
  /// ninguno.
  Set<int> get _formatosElegidos => {for (final f in _fmts) ?f};

  /// Valores de tiro que existen en esta sesión.
  ///
  /// En media cancha (1v1 a 4v4) los tiros valen **1 y 2**; en 5v5 valen **2 y
  /// 3**, más el libre. Una sesión mixta ofrece los tres porque pasaron las dos
  /// cosas. Sin formato elegido se muestran los tres: no hay con qué descartar.
  Set<int> get _valoresDeTiro {
    final f = _formatosElegidos;
    if (f.isEmpty) return {3, 2, 1};
    return {
      if (f.any((n) => n >= 5)) 3,
      2,
      1,
    };
  }

  // ── Resultado DERIVADO ────────────────────────────────────────────────────

  /// El resultado que se va a guardar. Nunca lo elige el usuario cuando hubo
  /// más de un partido: sale del marcador, con la MISMA regla que
  /// [PlaySession.displayResult] usaba para mostrar.
  ///
  /// Con un solo partido sí es una elección directa (ganamos/perdimos/empate),
  /// porque ahí el marcador no agrega información.
  PlayResult? get _resultado {
    if (_noCuenta) return PlayResult.notCounted;
    if (!_hayPartidos) return PlayResult.training;
    if (_partidos == 1) return _unico;
    final perdidos = _partidos - _ganados;
    if (_ganados > perdidos) return PlayResult.win;
    if (_ganados < perdidos) return PlayResult.loss;
    return PlayResult.tie;
  }

  /// Victorias que se guardan. Con un solo partido salen del selector directo,
  /// no del contador.
  int get _ganadosEfectivos =>
      _partidos == 1 ? (_unico == PlayResult.win ? 1 : 0) : _ganados;

  Color _colorDe(PlayResult? r) => switch (r) {
        PlayResult.win => AppColors.open,
        PlayResult.loss => AppColors.accentDark,
        PlayResult.tie => AppColors.white(0.7),
        PlayResult.training => AppColors.accent,
        _ => AppColors.white(0.4),
      };

  // ── Totales calculados ────────────────────────────────────────────────────

  int _val(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// Total en modo "Por valor": la cuenta que el usuario ve en pantalla.
  int get _totalPorValor =>
      _val(_p3Ctrl) * 3 + _val(_p2Ctrl) * 2 + _val(_p1Ctrl);

  /// Total en modo "Por partido": la suma de las filas.
  int get _totalPorPartido => _gameCtrls.fold(0, (a, c) => a + _val(c));

  /// El número grande de arriba, o null si es editable a mano. En los modos
  /// calculados es read-only: dos fuentes editables para el mismo número solo
  /// generan contradicciones.
  int? get _totalCalculado => switch (_modo) {
        _ModoPuntos.total => null,
        _ModoPuntos.porValor => _totalPorValor,
        _ModoPuntos.porPartido => _totalPorPartido,
      };

  Map<String, dynamic> _payload({required bool viewDetail}) {
    final calc = _totalCalculado;
    final total = calc ?? int.tryParse(_ptsCtrl.text.trim());
    final porValor = _modo == _ModoPuntos.porValor;
    return {
      'result': _resultado!.name,
      // 0 no es un puntaje cargado, es "no cargué nada". Guardarlo metería la
      // sesión en los promedios con cero puntos.
      'pts': (total ?? 0) > 0 ? total : null,
      'p3': porValor && _val(_p3Ctrl) > 0 ? _val(_p3Ctrl) : null,
      'p2': porValor && _val(_p2Ctrl) > 0 ? _val(_p2Ctrl) : null,
      'p1': porValor && _val(_p1Ctrl) > 0 ? _val(_p1Ctrl) : null,
      // El desglose de la sesión va SIEMPRE que haya algo cargado, no solo
      // cuando fue más de un partido: con un solo partido `nMatches: 1` es
      // exactamente lo que los getters ya devolvían por defecto, así que no
      // cambia ningún conteo, pero deja de haber dos caminos.
      if (!_noCuenta) ...{
        'nMatches': _hayPartidos ? _partidos : 0,
        'nTrainings': _hayEntrenamiento ? _entrenamientos : 0,
        'nWins': _hayPartidos ? _ganadosEfectivos : 0,
      },
      // Solo si el usuario eligió: una lista con formatos inventados haría que
      // el detalle mostrara un "3v3" que nadie cargó.
      if (_hayPartidos && _formatosElegidos.isNotEmpty)
        'gameFmt': [for (final f in _fmts) f ?? _formato ?? 3],
      if (_modo == _ModoPuntos.porPartido && _totalPorPartido > 0)
        'gamePts': [for (final c in _gameCtrls) _val(c)],
      'viewDetail': viewDetail,
    };
  }

  // ── Piezas de UI ─────────────────────────────────────────────────────────

  /// Encabezado de paso. Reemplaza al `microLabel` de 10 px al 45 %: a ese
  /// tamaño los pasos no se leían como pasos y el sheet era un scroll plano.
  Widget _paso(String n, String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(n, style: AppText.display(size: 15, color: AppColors.accent)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(titulo.toUpperCase(),
                  style: AppText.archivo(
                      size: 12.5,
                      weight: FontWeight.w800,
                      letterSpacing: 0.06,
                      color: AppColors.white(0.85))),
            ),
          ],
        ),
      );

  /// Segmentado genérico de chips. Es el mismo control que ya usaba el selector
  /// de formato, extraído para que todas las preguntas del sheet se elijan
  /// igual.
  Widget _segment<T>(
    List<(T, String)> opciones,
    T? value,
    ValueChanged<T> onChanged, {
    bool compact = false,
  }) =>
      Row(
        children: [
          for (var i = 0; i < opciones.length; i++) ...[
            if (i > 0) SizedBox(width: compact ? 4 : 6),
            Expanded(
              child: PressableWidget(
                onTap: () => onChanged(opciones[i].$1),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: compact ? 8 : 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == opciones[i].$1
                        ? AppColors.accent
                        : Colors.transparent,
                    border: Border.all(
                      color: value == opciones[i].$1
                          ? AppColors.accent
                          : AppColors.white(0.14),
                    ),
                    borderRadius: BorderRadius.circular(AppShape.rChip),
                  ),
                  child: Text(opciones[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.archivo(
                          size: compact ? 11.5 : 12.5,
                          weight: FontWeight.w800,
                          color: value == opciones[i].$1
                              ? Colors.white
                              : AppColors.white(0.65))),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _formatPicker(int? value, ValueChanged<int> onChanged,
          {bool compact = false}) =>
      _segment<int>(
        [for (var n = 1; n <= 5; n++) (n, '${n}v$n')],
        value,
        onChanged,
        compact: compact,
      );

  /// Fila de contador -/+ con la etiqueta a la izquierda, a tamaño legible.
  ///
  /// Antes iban tres contadores en una fila con etiquetas de 9 px al 40 % que
  /// no entraban ("ENTRENAM." truncado). Una pregunta por fila entra completa.
  Widget _contador(String label, int value, int min, int max,
      ValueChanged<int> onChanged) {
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) =>
        PressableWidget(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? AppColors.white(0.06) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 18,
                color: enabled ? AppColors.white(0.85) : AppColors.white(0.18)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppText.grotesk(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: AppColors.white(0.8))),
          ),
          btn(Icons.remove, value > min, () => onChanged(value - 1)),
          SizedBox(
            width: 46,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: AppText.display(size: 24, height: 1.0)),
          ),
          btn(Icons.add, value < max, () => onChanged(value + 1)),
        ],
      ),
    );
  }

  /// Campo numérico DENTRO de una caja. El underline pelado sobre `bgElev`
  /// prácticamente no se veía: no había forma de saber dónde se escribía.
  Widget _numBox(
    String label,
    TextEditingController ctrl, {
    Color? dot,
    bool isLast = false,
    double size = 22,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.archivo(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.white(0.65))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textInputAction:
                isLast ? TextInputAction.done : TextInputAction.next,
            style: AppText.display(size: size, height: 1.0),
            cursorColor: AppColors.accent,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            // El total de arriba es la suma de estos campos: se refresca a
            // medida que se escribe, NO dentro del build (antes `_ptsCtrl.text`
            // se mutaba ahí, que es un efecto secundario durante el layout).
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle:
                  AppText.display(size: size, color: AppColors.white(0.14)),
              filled: true,
              fillColor: AppColors.card,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShape.rField),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShape.rField),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          ),
        ],
      );

  Widget _nota(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text,
            style: AppText.grotesk(
                size: 11.5, color: AppColors.white(0.42), height: 1.4)),
      );

  // ── Pasos ────────────────────────────────────────────────────────────────

  /// Paso 2: el marcador. Todo lo que se carga acá desemboca en la franja de
  /// resultado, que se actualiza en vivo.
  Widget _pasoMarcador() {
    final r = _resultado;
    final ganados = _ganadosEfectivos;
    final perdidos = _partidos - ganados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paso('2', _hayPartidos ? 'El marcador' : 'Cuánto entrenaste'),
        if (_hayPartidos) ...[
          _contador('Partidos jugados', _partidos, 1, 12, (v) {
            setState(() {
              _partidos = v;
              _sync();
            });
          }),
          if (_partidos == 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _segment<PlayResult>(
                const [
                  (PlayResult.win, 'GANAMOS'),
                  (PlayResult.loss, 'PERDIMOS'),
                  (PlayResult.tie, 'EMPATE'),
                ],
                _unico,
                (v) => setState(() => _unico = v),
              ),
            )
          else
            _contador('Cuántos ganaste', _ganados, 0, _partidos,
                (v) => setState(() => _ganados = v)),
        ],
        if (_hayEntrenamiento)
          _contador('Entrenamientos', _entrenamientos, 1, 12,
              (v) => setState(() => _entrenamientos = v)),
        // Franja de resultado derivado: es la respuesta a "cómo te fue" y se ve
        // MIENTRAS se carga el marcador, en vez de contradecirlo después.
        if (_hayPartidos) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            decoration: BoxDecoration(
              color: _colorDe(r).withAlpha(r == null ? 10 : 28),
              borderRadius: BorderRadius.circular(AppShape.rField),
              border:
                  Border.all(color: _colorDe(r).withAlpha(r == null ? 30 : 90)),
            ),
            child: r == null
                ? Text('Elegí cómo terminó para poder guardar',
                    style: AppText.grotesk(
                        size: 12.5, color: AppColors.white(0.5)))
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          // Con un solo partido no hay marcador que mostrar: el
                          // resultado ES la elección, no su consecuencia.
                          _partidos == 1
                              ? 'Un partido'
                              : '$ganados ${ganados == 1 ? "ganado" : "ganados"}  ·  $perdidos ${perdidos == 1 ? "perdido" : "perdidos"}',
                          style: AppText.grotesk(
                              size: 12.5, color: AppColors.white(0.7)),
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded,
                          size: 15, color: AppColors.white(0.35)),
                      const SizedBox(width: 10),
                      Text(r.label.toUpperCase(),
                          style: AppText.archivo(
                              size: 14,
                              weight: FontWeight.w800,
                              letterSpacing: 0.04,
                              color: _colorDe(r))),
                    ],
                  ),
          ),
          if (_partidos > 1)
            _nota(
                'El resultado sale del marcador: no hace falta elegirlo aparte.'),
        ],
      ],
    );
  }

  /// Paso 3: formato. Es lo que define cuánto vale cada tiro, así que va ANTES
  /// de los puntos.
  Widget _pasoFormato() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paso('3', _partidos == 1 ? 'Formato' : 'Formato de cada partido'),
          if (_partidos == 1)
            _formatPicker(
              _fmts.isEmpty ? _formato : _fmts.first,
              (n) => setState(() {
                _formato = n;
                if (_fmts.isNotEmpty) _fmts[0] = n;
              }),
            )
          else
            for (var i = 0; i < _fmts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text('P${i + 1}',
                          style: AppText.archivo(
                              size: 12,
                              weight: FontWeight.w800,
                              color: AppColors.white(0.6))),
                    ),
                    Expanded(
                      child: _formatPicker(
                        _fmts[i],
                        (n) => setState(() {
                          _fmts[i] = n;
                          _formato ??= n;
                        }),
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
          _nota(
              'En 1v1 a 4v4 los tiros valen 1 y 2. En 5v5, 2 y 3, más el libre.'),
        ],
      );

  /// Paso 4: los puntos. Un modo de carga a la vez (ver [_ModoPuntos]).
  Widget _pasoPuntos() {
    final calc = _totalCalculado;
    final valores = _valoresDeTiro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paso('4', 'Tus puntos'),
        _segment<_ModoPuntos>(
          [
            (_ModoPuntos.total, 'TOTAL'),
            (_ModoPuntos.porValor, 'POR VALOR'),
            if (_partidos >= 2) (_ModoPuntos.porPartido, 'POR PARTIDO'),
          ],
          _modo,
          (v) => setState(() => _modo = v),
          compact: true,
        ),
        const SizedBox(height: 16),
        // El número grande. Editable solo en modo "Total"; en los otros dos es
        // la cuenta de lo de abajo y se muestra bloqueado.
        if (calc == null)
          TextField(
            controller: _ptsCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            style: AppText.display(size: 48, height: 1.0),
            cursorColor: AppColors.accent,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(
              hintText: '0',
              hintStyle:
                  AppText.display(size: 48, color: AppColors.white(0.12)),
              filled: true,
              fillColor: AppColors.card,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShape.rField),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShape.rField),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppShape.rField),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                Text('$calc',
                    style: AppText.display(
                        size: 48,
                        height: 1.0,
                        color:
                            calc > 0 ? AppColors.ink : AppColors.white(0.18))),
                const SizedBox(height: 4),
                Text(
                  _modo == _ModoPuntos.porValor
                      ? _cuentaPorValor()
                      : 'Suma de tus $_partidos partidos',
                  style:
                      AppText.grotesk(size: 11, color: AppColors.white(0.42)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (_modo == _ModoPuntos.porValor)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (valores.contains(3)) ...[
                Expanded(child: _numBox('Pts de 3', _p3Ctrl, dot: _dot3)),
                const SizedBox(width: 10),
              ],
              Expanded(child: _numBox('Pts de 2', _p2Ctrl, dot: _dot2)),
              const SizedBox(width: 10),
              Expanded(
                  child:
                      _numBox('Pts de 1', _p1Ctrl, dot: _dot1, isLast: true)),
            ],
          ),
        if (_modo == _ModoPuntos.porPartido)
          Column(
            children: [
              for (var i = 0; i < _gameCtrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _numBox(
                    'Partido ${i + 1}${_fmts[i] != null ? "  ·  ${_fmts[i]}v${_fmts[i]}" : ""}',
                    _gameCtrls[i],
                    size: 18,
                    isLast: i == _gameCtrls.length - 1,
                  ),
                ),
            ],
          ),
        _nota(_hayEntrenamiento
            ? 'Los entrenamientos no suman puntos: esto es lo que anotaste jugando. No importa si no es exacto, con el tiempo se arma tu promedio.'
            : 'No importa si no es exacto: con el tiempo se arma tu promedio.'),
      ],
    );
  }

  /// La cuenta a la vista, para que el número grande no salga de la nada.
  String _cuentaPorValor() {
    final partes = <String>[
      if (_valoresDeTiro.contains(3) && _val(_p3Ctrl) > 0) '${_val(_p3Ctrl)}×3',
      if (_val(_p2Ctrl) > 0) '${_val(_p2Ctrl)}×2',
      if (_val(_p1Ctrl) > 0) '${_val(_p1Ctrl)}',
    ];
    return partes.isEmpty ? 'Cargá tus tiros abajo' : partes.join('  +  ');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final puedeGuardar = _resultado != null;

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
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Paso 1: qué hiciste ──────────────────────────────
                    _paso('1', '¿Qué hiciste?'),
                    _segment<_Actividad>(
                      const [
                        (_Actividad.partidos, 'PARTIDOS'),
                        (_Actividad.entrenamiento, 'ENTRENÉ'),
                        (_Actividad.ambas, 'LAS DOS'),
                      ],
                      _noCuenta ? null : _actividad,
                      (v) => setState(() {
                        _actividad = v;
                        _noCuenta = false;
                        _sync();
                      }),
                      compact: true,
                    ),
                    const SizedBox(height: 10),
                    PressableWidget(
                      onTap: () => setState(() {
                        _noCuenta = !_noCuenta;
                        _sync();
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              _noCuenta
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 17,
                              color: _noCuenta
                                  ? AppColors.accent
                                  : AppColors.white(0.35),
                            ),
                            const SizedBox(width: 8),
                            Text('No cuentes esta sesión',
                                style: AppText.grotesk(
                                    size: 12.5,
                                    color: _noCuenta
                                        ? AppColors.white(0.85)
                                        : AppColors.white(0.55))),
                          ],
                        ),
                      ),
                    ),
                    if (!_noCuenta) ...[
                      const SizedBox(height: 22),
                      _pasoMarcador(),
                      if (_hayPartidos) ...[
                        const SizedBox(height: 26),
                        _pasoFormato(),
                        const SizedBox(height: 26),
                        _pasoPuntos(),
                      ],
                    ],
                    const SizedBox(height: 24),
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
                          puedeGuardar
                              ? 'VER RESULTADO'
                              : 'ELEGÍ CÓMO TERMINÓ',
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
