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
import '../widgets/match_status_pill.dart';
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
        AppTab.chat => AppColors.red,
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

  Future<void> _askResult(PlaySession s) async {
    final play = context.read<PlaySessionService>();
    Widget option(PlayResult r, IconData icon, Color color) {
      return GestureDetector(
        onTap: () => Navigator.pop(context, r),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.white(0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(r.label,
                    style:
                        AppText.grotesk(size: 14, weight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.25)),
            ],
          ),
        ),
      );
    }

    // Si el usuario descarta sin responder, se guarda como "Sin información".
    final chosen = await showDialog<PlayResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElev,
        scrollable: true,
        title: Text('¿Cómo te fue?',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${s.courtName.isEmpty ? 'Cancha' : s.courtName} · ${PlaySessionService.fmt(s.seconds)} · x${PlaySessionService.multiplierFor(s.seconds).toStringAsFixed(2)}',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.55)),
            ),
            option(PlayResult.win, Icons.emoji_events_outlined, AppColors.open),
            option(PlayResult.loss, Icons.thumb_down_outlined,
                AppColors.accentDark),
            option(PlayResult.tie, Icons.handshake_outlined, AppColors.white(0.7)),
            option(PlayResult.training, Icons.fitness_center, AppColors.accent),
            option(PlayResult.notCounted, Icons.not_interested,
                AppColors.white(0.5)),
          ],
        ),
      ),
    );

    // Si el usuario eligió un resultado, preguntar stats (opcional).
    if (chosen != null && mounted) {
      final stats = await _showMatchStats(s);
      await play.resolvePending(
        chosen,
        userPoints: stats?['pts'],
        userTriples: stats?['t3'],
        userDoubles: stats?['t2'],
        userFreeThrows: stats?['tl'],
      );
      // Si el usuario tocó "Ver resultado", navegar al detalle.
      if (stats?['viewDetail'] == true && mounted) {
        // Obtener la sesión actualizada del log.
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
      await play.resolvePending(chosen ?? PlayResult.notCounted);
    }
    if (mounted) setState(() => _resultPromptOpen = false);
  }

  /// Muestra un bottom sheet para ingresar stats del partido (opcional).
  /// Devuelve un map con los valores o null si el usuario omitió.
  Future<Map<String, dynamic>?> _showMatchStats(PlaySession s) async {
    final ptsCtrl = TextEditingController();
    final t3Ctrl = TextEditingController();
    final t2Ctrl = TextEditingController();
    final tlCtrl = TextEditingController();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MatchStatsSheet(
        courtName: s.courtName,
        duration: PlaySessionService.fmt(s.seconds),
        session: s,
        ptsCtrl: ptsCtrl,
        t3Ctrl: t3Ctrl,
        t2Ctrl: t2Ctrl,
        tlCtrl: tlCtrl,
      ),
    );

    ptsCtrl.dispose();
    t3Ctrl.dispose();
    t2Ctrl.dispose();
    tlCtrl.dispose();
    return result;
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

/// Bottom sheet para ingresar estadísticas del partido (opcional).
/// Se muestra después de elegir el resultado.
class _MatchStatsSheet extends StatefulWidget {
  final String courtName;
  final String duration;
  final PlaySession session;
  final TextEditingController ptsCtrl;
  final TextEditingController t3Ctrl;
  final TextEditingController t2Ctrl;
  final TextEditingController tlCtrl;

  const _MatchStatsSheet({
    required this.courtName,
    required this.duration,
    required this.session,
    required this.ptsCtrl,
    required this.t3Ctrl,
    required this.t2Ctrl,
    required this.tlCtrl,
  });

  @override
  State<_MatchStatsSheet> createState() => _MatchStatsSheetState();
}

class _MatchStatsSheetState extends State<_MatchStatsSheet> {
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    // Input numérico compacto (plano: filled sin borde, foco en acento).
    InputDecoration numDecoration(double size) => InputDecoration(
          hintText: '0',
          hintStyle: AppText.archivo(
              size: size, weight: FontWeight.w800, color: AppColors.white(0.2)),
          filled: true,
          fillColor: AppColors.white(0.05),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
        );

    Widget field(String label, TextEditingController ctrl) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: AppText.grotesk(
                    size: 9.5,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.4),
                    letterSpacing: 0.08)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppText.archivo(size: 16, weight: FontWeight.w800),
              cursorColor: AppColors.accent,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: numDecoration(16),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElev,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tus estadísticas',
                            style: AppText.archivo(
                                size: 18, weight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                            '${widget.courtName.isEmpty ? 'Cancha' : widget.courtName} · ${widget.duration}',
                            style: AppText.grotesk(
                                size: 12, color: AppColors.white(0.45))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.white(0.5), size: 22),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Por qué cargar esto (tono relajado: es para promedios).
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(20),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: AppColors.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sirve para llevar el registro de tu progreso. Si no te acordás los números exactos, no pasa nada: se usan para sacar un promedio, así que con que te acerques alcanza.',
                              style: AppText.grotesk(
                                  size: 12,
                                  color: AppColors.white(0.7),
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Puntos totales (ancho completo).
                    Text('PUNTOS ANOTADOS',
                        style: AppText.grotesk(
                            size: 10,
                            weight: FontWeight.w700,
                            color: AppColors.white(0.4),
                            letterSpacing: 0.08)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: widget.ptsCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: AppText.archivo(size: 20, weight: FontWeight.w800),
                      cursorColor: AppColors.accent,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: numDecoration(20),
                    ),
                    const SizedBox(height: 16),
                    // Desglose: 3PT / 2PT / TL en una sola fila.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        field('3PT', widget.t3Ctrl),
                        const SizedBox(width: 10),
                        field('2PT', widget.t2Ctrl),
                        const SizedBox(width: 10),
                        field('TL', widget.tlCtrl),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // Botones de acción
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.line, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        final pts = int.tryParse(widget.ptsCtrl.text);
                        final t3 = int.tryParse(widget.t3Ctrl.text);
                        final t2 = int.tryParse(widget.t2Ctrl.text);
                        final tl = int.tryParse(widget.tlCtrl.text);
                        Navigator.pop(context, {
                          'pts': pts,
                          't3': t3,
                          't2': t2,
                          'tl': tl,
                          'viewDetail': false,
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppShape.rChip),
                          side: BorderSide(
                              color: AppColors.white(0.12), width: 1),
                        ),
                      ),
                      child: Text('Listo',
                          style: AppText.grotesk(
                              size: 14,
                              weight: FontWeight.w700,
                              color: AppColors.white(0.8))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextButton(
                      onPressed: () {
                        final pts = int.tryParse(widget.ptsCtrl.text);
                        final t3 = int.tryParse(widget.t3Ctrl.text);
                        final t2 = int.tryParse(widget.t2Ctrl.text);
                        final tl = int.tryParse(widget.tlCtrl.text);
                        Navigator.pop(context, {
                          'pts': pts,
                          't3': t3,
                          't2': t2,
                          'tl': tl,
                          'viewDetail': true,
                        });
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppShape.rChip),
                        ),
                      ),
                      child: Text('Ver resultado',
                          style: AppText.grotesk(
                              size: 14,
                              weight: FontWeight.w700,
                              color: Colors.white)),
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
