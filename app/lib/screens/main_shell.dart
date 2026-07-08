import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_loading_state.dart';
import '../services/courts_provider.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_loader.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/reward_banner.dart';
import 'crew_screen.dart';
import 'create_screen.dart';
import 'detail_screen.dart';
import 'filters_screen.dart';
import 'home_screen.dart';
import 'list_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppTab _tab = AppTab.home;

  // Subpestaña del Perfil (0 = Perfil, 1 = Amigos). Vive acá para que el swipe
  // del shell pueda alternarla antes de saltar a otra pestaña principal.
  int _profileTab = 0;

  // Tope de seguridad del loader: si las señales (mapa/GPS/canchas) no llegan,
  // igual lo ocultamos a los 6s para no dejar la app tapada.
  bool _loaderTimedOut = false;
  Timer? _loaderTimer;

  @override
  void initState() {
    super.initState();
    _loaderTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _loaderTimedOut = true);
    });
    // Los permisos (ubicación, notificaciones, alarmas) NO se piden solos al
    // abrir la app: los pide el modal de permisos sobre el mapa cuando el
    // usuario activa cada switch.
  }

  @override
  void dispose() {
    _loaderTimer?.cancel();
    super.dispose();
  }


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
      _tab = t;
    });
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
        _tab = prev;
      });
      return true;
    }
    if (_tab != AppTab.home) {
      setState(() {
        _slideDir = -1;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.white(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.white(0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(r.label,
                  style: AppText.grotesk(size: 14, weight: FontWeight.w600)),
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
    await play.resolvePending(chosen ?? PlayResult.notCounted);
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

    // Si hay un partido terminado sin resultado, preguntamos cómo le fue.
    final pending = context.watch<PlaySessionService>().pending;
    if (pending != null && !_resultPromptOpen) {
      _resultPromptOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askResult(pending);
      });
    }
    final bottomInset = MediaQuery.of(context).padding.bottom;

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
              left: 16,
              right: 16,
              bottom: 16 + bottomInset,
              child: AppTabBar(active: _tab, onChange: _selectTab),
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
