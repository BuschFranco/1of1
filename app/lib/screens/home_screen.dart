import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../services/app_loading_state.dart';
import '../services/notifications_service.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/permissions_modal.dart';
import '../widgets/rating_badge.dart';
import '../widgets/status_dot.dart';

const _kApiKey = String.fromEnvironment('MAPS_API_KEY');

/// Cámara inicial del mapa (CABA). Es también el valor de arranque de
/// `_lastCam`, la cámara vigente con la que se proyecta el punto de ubicación.
const CameraPosition _kInitialCam = CameraPosition(
  target: LatLng(-34.6037, -58.3816),
  zoom: 12,
);

// Mapa CLARO retro-pop: geometría crema, calles blancas/crema, agua lila
// (guiño a la paleta), POIs/transit ocultos. Solo cambia el string de estilo,
// sin overlays sobre el GoogleMap.
const _kMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#f2e8d5"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#6b6459"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f4ebdd"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#e5dac2"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#3d3833"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill","stylers":[{"color":"#6b6459"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#e0d5bd"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8275"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#fdf6e8"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#f5c98a"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#d9a55e"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#7a6f5c"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#b7aeee"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#5d539e"}]}
]
''';

class _Prediction {
  final String placeId;
  final String mainText;
  final String secondaryText;
  const _Prediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });
}

class HomeScreen extends StatefulWidget {
  final List<Court> courts;
  final String? focusCourtId;
  final VoidCallback? onFocusConsumed;
  final ValueChanged<String>? onSelectCourt;
  final VoidCallback? onOpenFilters;

  const HomeScreen({
    super.key,
    required this.courts,
    this.focusCourtId,
    this.onFocusConsumed,
    this.onSelectCourt,
    this.onOpenFilters,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _index = 0;
  GoogleMapController? _mapCtrl;
  // Evita apilar el modal de permisos.
  bool _permOpen = false;
  // Estado de carga inicial (loader del shell). Se captura en initState para no
  // depender del context tras awaits.
  late final AppLoadingState _loading = context.read<AppLoadingState>();
  final TextEditingController _searchCtrl = TextEditingController();
  List<_Prediction> _predictions = [];
  bool _showSearch = false;
  bool _locating = false;

  // DEV: modo prueba de ubicación. Con esto activo, tocar el mapa mueve tu
  // ubicación simulada a ese punto para probar el radio y las canchas.
  bool _mockMode = false;

  // Stream de ubicación para mover el punto azul en vivo (como otras apps).
  StreamSubscription<Position>? _posStream;

  // Filtros rápidos activos (chips debajo del buscador). "Cerca" ordena por
  // cercanía a la ubicación del usuario; el resto filtra la lista.
  final Set<String> _activeFilters = {'Cerca'};
  Position? _userPos;

  // Punto de "mi ubicación" con animación de pulso. _userScreen es la posición
  // en pantalla (px lógicos) de _userPos, recalculada al mover la cámara.
  // Es un ValueNotifier para que reposicionar el punto en cada frame del
  // arrastre no reconstruya todo el Stack (y sus BackdropFilter), que es lo
  // que tiraba los FPS al deslizar el mapa.
  late final AnimationController _pulseCtrl;
  final ValueNotifier<Offset?> _userScreen = ValueNotifier(null);
  // Cámara vigente y tamaño del mapa: permiten proyectar _userPos a pantalla de
  // forma SÍNCRONA (Web Mercator) en cada frame del arrastre. Antes esto se
  // resolvía con getScreenCoordinate (async, platform channel) en cada
  // onCameraMove: la respuesta llegaba tarde y se descartaban llamadas en
  // vuelo, así que el punto quedaba congelado y "saltaba" detrás del mapa.
  CameraPosition _lastCam = _kInitialCam;
  Size? _mapSize;

  // Canchas visibles tras aplicar los filtros activos. Alimenta tanto los
  // marcadores del mapa como la tarjeta inferior.
  List<Court> _filtered = [];

  // Carrusel de tarjetas: el PageView permite arrastrar con el dedo y hace
  // snap. _skipNextPageCamera evita que un cambio de página programático
  // (foco desde el detalle, sync por filtros) pise una cámara ya animada.
  late final PageController _pageCtrl;
  bool _skipNextPageCamera = false;

  Court? get _court => _filtered.isEmpty
      ? null
      : _filtered[_index.clamp(0, _filtered.length - 1)];

  // Markers cacheados: solo se recalculan cuando cambian las canchas o el
  // índice seleccionado, no en cada setState (buscar, spinner, etc.).
  Set<Marker> _markers = {};

  // Círculos del radio de detección de "jugando" (110m) alrededor de cada cancha.
  Set<Circle> _circles = {};

  void _applyFilters() {
    final list = widget.courts.where((c) {
      if (_activeFilters.contains('Abierto ahora') &&
          c.status != CourtStatus.open) {
        return false;
      }
      if (_activeFilters.contains('Iluminada') && !c.lit) return false;
      if (_activeFilters.contains('Gratis') && !c.free) return false;
      if (_activeFilters.contains('Interior') && c.type != 'Interior') {
        return false;
      }
      return true;
    }).toList();

    if (_activeFilters.contains('Cerca') && _userPos != null) {
      final p = _userPos!;
      list.sort(
        (a, b) =>
            Geolocator.distanceBetween(
              p.latitude,
              p.longitude,
              a.lat,
              a.lng,
            ).compareTo(
              Geolocator.distanceBetween(p.latitude, p.longitude, b.lat, b.lng),
            ),
      );
    }

    _filtered = list;
    if (_index >= _filtered.length) _index = 0;
    _rebuildMarkers();
  }

  Future<void> _toggleFilter(String label) async {
    setState(() {
      if (_activeFilters.contains(label)) {
        _activeFilters.remove(label);
      } else {
        _activeFilters.add(label);
      }
    });
    // Al activar "Cerca" sin ubicación todavía, la pedimos para poder ordenar.
    if (label == 'Cerca' &&
        _activeFilters.contains('Cerca') &&
        _userPos == null) {
      await _ensureUserPosition();
    }
    setState(_applyFilters);
    _syncPageToIndex();
  }

  /// Reposiciona el carrusel al índice actual tras cambios en la lista
  /// (filtros, orden por cercanía). Se hace post-frame para que el PageView ya
  /// tenga el nuevo itemCount.
  void _syncPageToIndex() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageCtrl.hasClients || _filtered.isEmpty) return;
      final target = _index.clamp(0, _filtered.length - 1);
      if (_pageCtrl.page?.round() != target) {
        _skipNextPageCamera = true;
        _pageCtrl.jumpToPage(target);
      }
    });
  }

  Future<void> _ensureUserPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        // Sin permiso: no lo pedimos acá, abrimos el modal de permisos.
        await _maybeShowPerms();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      _userPos = pos;
      _updateUserScreenPos();
    } catch (_) {}
  }

  Future<void> _loadInitialPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userPos = pos;
        _applyFilters();
      });
      _syncPageToIndex();
      _updateUserScreenPos();
    } catch (_) {
      // Ignoramos el error: el loader no debe quedarse esperando el GPS.
    } finally {
      // Listo (con o sin punto): liberamos el loader del primer GPS.
      _loading.markGpsReady();
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    // Si venimos desde el detalle con una cancha en foco, seleccionarla.
    _applyFilters();
    final fid = widget.focusCourtId;
    if (fid != null) {
      final idx = _filtered.indexWhere((c) => c.id == fid);
      if (idx >= 0) _index = idx;
    }
    _pageCtrl = PageController(initialPage: _index);
    _rebuildMarkers();
    _loadInitialPosition();
    _startLocationUpdates();
    // La detección de partidos (presencia, batch, sembrado y canchas) la cablea
    // SyncCoordinator al arrancar la app; HomeScreen ya no orquesta nada de eso.
    WidgetsBinding.instance.addObserver(this);
    // DEV: si el servicio restauró una ubicación simulada tras un reinicio del
    // proceso, retomamos el modo prueba en la UI (el pin sigue gobernando).
    _syncMockMode();
    // Modal de permisos sobre el mapa: UNA sola vez por usuario (tras el primer
    // login/registro). Después se abre a mano desde el perfil.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPerms());
  }

  /// DEV: alinea el flag de UI del modo prueba con el estado del servicio (el
  /// mock puede haberse restaurado tras morir el proceso, y el servicio arranca
  /// async: re-chequeamos también al volver al frente).
  void _syncMockMode() {
    if (!_mockMode && context.read<PlaySessionService>().mockActive) {
      setState(() => _mockMode = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncMockMode();
      // OJO: acá NO se re-muestra el modal de permisos (molestaba en cada
      // minimizar/maximizar). Solo se muestra una vez, en initState.
    }
  }

  /// Muestra el modal de permisos una única vez por usuario. Evita apilarlo.
  Future<void> _maybeShowPerms() async {
    if (_permOpen || !mounted) return;
    _permOpen = true;
    await PermissionsModal.showOnceIfNeeded(context);
    if (mounted) _permOpen = false;
  }

  /// Sigue la ubicación en vivo para mover el punto azul a medida que el usuario
  /// se desplaza (no solo al tocar "mi ubicación"). En modo prueba se ignora el
  /// GPS real: la ubicación la fija el tap en el mapa.
  Future<void> _startLocationUpdates() async {
    try {
      // NO pedimos permiso acá: lo pide el modal de permisos cuando el usuario
      // activa el switch. Solo arrancamos el stream si ya está concedido.
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      _posStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((pos) {
            if (!mounted || _mockMode) return;
            // Solo movemos el punto (ValueNotifier): reconstruir todo el árbol por
            // cada update de GPS producía jank sobre el mapa.
            final firstFix = _userPos == null;
            _userPos = pos;
            _updateUserScreenPos();
            if (firstFix) {
              // Primer fix: aplicar el orden "Cerca" una única vez.
              setState(_applyFilters);
              _syncPageToIndex();
            }
          }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.courts, widget.courts) ||
        old.courts.length != widget.courts.length) {
      _applyFilters();
      _syncPageToIndex();
    }
    final fid = widget.focusCourtId;
    if (fid != null && fid != old.focusCourtId) {
      _focusOnCourt(fid);
    }
  }

  void _rebuildMarkers() {
    _markers = {
      for (var i = 0; i < _filtered.length; i++)
        Marker(
          markerId: MarkerId(_filtered[i].id),
          position: LatLng(_filtered[i].lat, _filtered[i].lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == _index ? 22.0 : BitmapDescriptor.hueAzure,
          ),
          onTap: () => _selectIndex(i),
        ),
    };
    _circles = {
      for (var i = 0; i < _filtered.length; i++)
        Circle(
          circleId: CircleId('radius_${_filtered[i].id}'),
          center: LatLng(_filtered[i].lat, _filtered[i].lng),
          radius: PlaySessionService.radiusMeters,
          fillColor: AppColors.accent.withAlpha(i == _index ? 46 : 18),
          strokeColor: AppColors.accent.withAlpha(i == _index ? 170 : 80),
          strokeWidth: 1,
        ),
    };
  }

  void _focusOnCourt(String courtId) {
    final idx = _filtered.indexWhere((c) => c.id == courtId);
    if (idx >= 0) {
      // Movemos el carrusel sin que su cámara (zoom default) pise el zoom 16
      // que queremos al enfocar desde el detalle.
      if (idx != _index && _pageCtrl.hasClients) {
        _skipNextPageCamera = true;
        _pageCtrl.jumpToPage(idx);
      } else {
        setState(() {
          _index = idx;
          _rebuildMarkers();
        });
      }
      final c = _filtered[idx];
      _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(c.lat, c.lng), 16),
      );
    }
    widget.onFocusConsumed?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posStream?.cancel();
    _pulseCtrl.dispose();
    _mapCtrl?.dispose();
    _searchCtrl.dispose();
    _userScreen.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // Reproyecta _userPos a coordenadas de pantalla y mueve el punto (vía el
  // ValueNotifier, sin rebuild del Stack). Es SÍNCRONO y barato (unas pocas
  // operaciones trigonométricas), así que se puede llamar en cada frame de
  // onCameraMove y el punto queda pegado al mapa, sin el lag/salto que tenía
  // el round-trip async por platform channel.
  void _updateUserScreenPos() {
    final pos = _userPos;
    if (pos == null) {
      _userScreen.value = null;
      return;
    }
    _userScreen.value = _projectToScreen(pos.latitude, pos.longitude);
  }

  /// Proyección Web Mercator de un lat/lng a píxeles lógicos de pantalla, según
  /// la cámara vigente ([_lastCam]) y el tamaño del mapa. El target de la cámara
  /// cae en el centro de la vista (no usamos padding de cámara) y el tilt está
  /// deshabilitado, así que la proyección plana es exacta. Soporta la rotación
  /// del mapa (bearing) y el cruce del antimeridiano.
  Offset? _projectToScreen(double lat, double lng) {
    final size = _mapSize;
    if (size == null || size.isEmpty) return null;
    final cam = _lastCam;

    // Mundo Web Mercator normalizado [0,1) con tile base de 256 px lógicos.
    double worldX(double lng) => (lng + 180.0) / 360.0;
    double worldY(double lat) {
      final s = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
      return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    }

    final scale = 256.0 * math.pow(2.0, cam.zoom);
    var dx = worldX(lng) - worldX(cam.target.longitude);
    // Antimeridiano: elegimos el delta más corto (el mundo se repite cada 1.0).
    if (dx > 0.5) {
      dx -= 1.0;
    } else if (dx < -0.5) {
      dx += 1.0;
    }
    final dy = worldY(lat) - worldY(cam.target.latitude);
    var px = dx * scale;
    var py = dy * scale;

    // Rotación del mapa (bearing, horaria): rotamos el delta al marco de pantalla.
    if (cam.bearing != 0) {
      final b = cam.bearing * math.pi / 180.0;
      final cosB = math.cos(b);
      final sinB = math.sin(b);
      final rx = px * cosB + py * sinB;
      final ry = -px * sinB + py * cosB;
      px = rx;
      py = ry;
    }
    return Offset(size.width / 2 + px, size.height / 2 + py);
  }

  /// Selección externa (tap en marker, flechas): anima el carrusel a la página
  /// i; el resto (índice, markers, cámara) lo resuelve _onPageChanged.
  void _selectIndex(int i) {
    if (!_pageCtrl.hasClients) {
      _onPageChanged(i);
      return;
    }
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Se dispara cuando el PageView asienta una página (arrastre con el dedo o
  /// animación programática). Actualiza índice, markers y centra la cámara.
  void _onPageChanged(int i) {
    setState(() {
      _index = i;
      _rebuildMarkers();
    });
    if (_skipNextPageCamera) {
      _skipNextPageCamera = false;
      return;
    }
    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLng(LatLng(_filtered[i].lat, _filtered[i].lng)),
    );
  }

  Future<void> _onSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': query,
          'types': '(regions)',
          'components': 'country:ar',
          'language': 'es',
          'key': _kApiKey,
        },
      );
      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = data['predictions'] as List<dynamic>;
      final predictions = raw.map((p) {
        final fmt = p['structured_formatting'] as Map<String, dynamic>;
        return _Prediction(
          placeId: p['place_id'] as String,
          mainText: fmt['main_text'] as String,
          secondaryText: (fmt['secondary_text'] ?? '') as String,
        );
      }).toList();
      setState(() => _predictions = predictions);
    } catch (_) {}
  }

  Future<void> _onSelectPrediction(_Prediction pred) async {
    setState(() {
      _showSearch = false;
      _predictions = [];
      _searchCtrl.text = pred.mainText;
    });
    FocusScope.of(context).unfocus();
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {'place_id': pred.placeId, 'fields': 'geometry', 'key': _kApiKey},
      );
      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final loc =
          (data['result'] as Map)['geometry']['location']
              as Map<String, dynamic>;
      _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          ),
          14,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tamaño real del área del mapa (el Stack lo llena): lo necesita la
          // proyección síncrona del punto de ubicación.
          _mapSize = constraints.biggest;
          return Stack(
            children: [
              GoogleMap(
                style: _kMapStyle,
                onMapCreated: (ctrl) {
                  _mapCtrl = ctrl;
                  final c = _court;
                  if (widget.focusCourtId != null && c != null) {
                    ctrl.animateCamera(
                      CameraUpdate.newLatLngZoom(LatLng(c.lat, c.lng), 16),
                    );
                    widget.onFocusConsumed?.call();
                  }
                  _updateUserScreenPos();
                  _loading.markMapReady();
                },
                // Cada frame de arrastre/animación: guardamos la cámara y
                // reproyectamos el punto en forma síncrona (sin platform channel).
                onCameraMove: (cam) {
                  _lastCam = cam;
                  _updateUserScreenPos();
                },
                onTap: _mockMode ? _onMockTap : null,
                initialCameraPosition: _kInitialCam,
                markers: _markers,
                circles: _circles,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
                tiltGesturesEnabled: false,
              ),
              _userLocationDot(),
              Positioned(top: 54, left: 16, right: 16, child: _searchBar()),
              if (_showSearch && _predictions.isNotEmpty)
                Positioned(
                  top: 112,
                  left: 16,
                  right: 16,
                  child: _predictionsOverlay(),
                ),
              if (!_showSearch)
                Positioned(
                  top: 112,
                  left: 0,
                  right: 0,
                  child: Builder(
                    builder: (context) {
                      final ps = context.watch<PlaySessionService>();
                      final active = ps.isPlaying || ps.isDwelling;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // El cronómetro se muestra SIEMPRE. Estar dentro del radio
                          // solo lo "activa" (arranca la cuenta regresiva y el
                          // partido); fuera del radio queda inactivo pero visible.
                          if (ps.isPlaying)
                            _playingBanner(context)
                          else if (ps.isDwelling)
                            _dwellBanner(context)
                          else
                            _idleTimer(context),
                          if (!active) ...[
                            const SizedBox(height: 10),
                            _quickChips(),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              Positioned(
                right: 16,
                bottom: 312,
                child: Column(
                  children: [
                    _devControls(),
                    const SizedBox(height: 10),
                    _locateBtn(),
                  ],
                ),
              ),
              if (_mockMode)
                Positioned(
                  bottom: 296,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        border:
                            Border.all(color: AppColors.accent, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app,
                            size: 14,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Modo prueba · tocá el mapa para moverte',
                            style: AppText.grotesk(
                              size: 11,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 148,
                left: 0,
                right: 0,
                child: _filtered.isEmpty ? _emptyFilterCard() : _bottomSwipe(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchBar() {
    return Row(
      children: [
        Expanded(
          child: _glassContainer(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            radius: AppShape.rBtn,
            child: Row(
              children: [
                Icon(Icons.search, size: 16, color: AppColors.white(0.5)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onTap: () => setState(() => _showSearch = true),
                    onChanged: _onSearch,
                    style: AppText.grotesk(size: 14),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      hintText: 'Buscar barrio',
                      hintStyle: AppText.grotesk(
                        size: 14,
                        color: AppColors.white(0.55),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_showSearch)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showSearch = false;
                        _predictions = [];
                        _searchCtrl.clear();
                      });
                      FocusScope.of(context).unfocus();
                    },
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.white(0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: widget.onOpenFilters,
          child: _glassContainer(
            width: 44,
            height: 44,
            radius: AppShape.rBtn,
            child: const Center(
              child: Icon(Icons.tune, color: AppColors.ink, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _predictionsOverlay() {
    return _glassContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final pred in _predictions.take(5))
            InkWell(
              onTap: () => _onSelectPrediction(pred),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: AppColors.white(0.5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pred.mainText, style: AppText.grotesk(size: 14)),
                          if (pred.secondaryText.isNotEmpty)
                            Text(
                              pred.secondaryText,
                              style: AppText.grotesk(
                                size: 11,
                                color: AppColors.white(0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _playingBanner(BuildContext context) {
    final ps = context.watch<PlaySessionService>();
    // El banner NO cambia de color al salir del radio: sigue siendo el mismo
    // verde de "Jugando" (gris si está pausado), y el tiempo del partido sigue
    // corriendo. La salida de la cancha se muestra como una línea ámbar DENTRO
    // del mismo banner (sin swaps bruscos de color/layout).
    final ending = ps.isEndingSoon;
    final paused = ps.isPaused;
    final secs = ps.elapsedSeconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    // Cuenta regresiva de salida (solo cuando estás fuera del radio).
    final exit = ps.endRemainingSeconds;
    final emm = (exit ~/ 60).toString().padLeft(2, '0');
    final ess = (exit % 60).toString().padLeft(2, '0');
    const amber = AppColors.busy;
    final accent = paused ? AppColors.white(0.7) : AppColors.open;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.glass,
          // Neobrutalismo: rectángulo franco con borde pleno del color de
          // estado (verde / gris) y sombra dura, sin glow.
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: accent, width: 2),
          boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$mm:$ss',
                        style: AppText.archivo(
                          size: 13,
                          weight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                      // Multiplicador por duración, creciendo en vivo.
                      if (!paused) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withAlpha(38),
                            borderRadius:
                                BorderRadius.circular(AppShape.rChip),
                            border: Border.all(color: AppColors.accent),
                          ),
                          child: Text(
                            'x${ps.currentMultiplier.toStringAsFixed(2)}',
                            style: AppText.grotesk(
                              size: 10,
                              weight: FontWeight.w800,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        // Puntos por tiempo acumulándose en vivo, con animación.
                        const SizedBox(width: 8),
                        _LivePoints(ps.currentTimePoints),
                      ],
                    ],
                  ),
                  // Segunda línea: si estás saliendo, la cuenta regresiva de
                  // salida en ámbar (dentro del mismo banner verde); si no, el
                  // estado normal.
                  if (ending && !paused)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_run, size: 11, color: amber),
                        const SizedBox(width: 3),
                        Text('Sale de la cancha en $emm:$ess',
                            style: AppText.grotesk(
                                size: 10,
                                weight: FontWeight.w700,
                                color: amber)),
                      ],
                    )
                  else
                    Text(
                      paused ? 'Pausado' : 'Jugando en ${ps.courtName ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.grotesk(size: 10, color: AppColors.white(0.6)),
                    ),
                  // Con Salud conectada dejamos claro que estamos midiendo el
                  // desempeño físico (calorías/pulso) durante el partido.
                  if (ps.healthEnabled) ...[
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.monitor_heart_outlined,
                          size: 10,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Midiendo tu desempeño',
                          style: AppText.grotesk(
                            size: 9,
                            weight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Botón pausa/reanudar (siempre visible: el banner es el mismo, jugues
            // o estés saliendo del radio).
            GestureDetector(
              onTap: () => context.read<PlaySessionService>().togglePause(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.blush,
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                  border: Border.all(color: AppColors.ink, width: 1.5),
                ),
                child: Icon(
                  paused ? Icons.play_arrow : Icons.pause,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => context.read<PlaySessionService>().stopNow(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                  border: Border.all(color: AppColors.ink, width: 1.5),
                ),
                child: Text(
                  'DETENER',
                  style: AppText.archivo(
                    size: 10,
                    weight: FontWeight.w800,
                    letterSpacing: 0.04,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cronómetro en reposo: visible siempre que no haya partido ni cuenta
  /// regresiva en curso (incluso fuera del radio de cualquier cancha). Muestra
  /// 00:00 e indica que hay que acercarse a una cancha; el partido (y el botón
  /// para arrancarlo manualmente) recién se habilitan al entrar al radio.
  Widget _idleTimer(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.glass,
          // Estado "inactivo": borde gris franco (se mantiene el gris de
          // estado, solo cambia el lenguaje de forma).
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.white(0.25), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 15, color: AppColors.white(0.55)),
            const SizedBox(width: 8),
            Text(
              '00:00',
              style: AppText.archivo(
                size: 13,
                weight: FontWeight.w800,
                color: AppColors.white(0.85),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Acercate a una cancha para jugar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.grotesk(size: 11, color: AppColors.white(0.55)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner de cuenta regresiva: aparece al llegar a una cancha, antes de que el
  /// partido arranque solo. Muestra cuánto falta y un botón para empezar ya.
  Widget _dwellBanner(BuildContext context) {
    final ps = context.watch<PlaySessionService>();
    final s = ps.dwellRemainingSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_basketball, size: 15, color: AppColors.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Empieza en $mm:$ss',
                    style: AppText.archivo(
                      size: 13,
                      weight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                  Text(
                    ps.dwellCourtName ?? 'En una cancha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(
                      size: 10,
                      color: AppColors.white(0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => context.read<PlaySessionService>().startNow(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                  // Acento pleno → borde negro puro (contraste neobrutalista).
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
                child: Text(
                  'EMPEZAR YA',
                  style: AppText.archivo(
                    size: 10,
                    weight: FontWeight.w800,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChips() {
    const labels = [
      'Cerca',
      'Abierto ahora',
      'Iluminada',
      'Gratis',
      'Interior',
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) => AppChip(
          label: labels[i],
          active: _activeFilters.contains(labels[i]),
          onTap: () => _toggleFilter(labels[i]),
        ),
      ),
    );
  }

  Widget _emptyFilterCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _glassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Row(
          children: [
            Icon(Icons.search_off, color: AppColors.white(0.5), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ninguna cancha coincide con los filtros',
                style: AppText.grotesk(size: 13, color: AppColors.white(0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        // Sin permiso: no lo pedimos acá, abrimos el modal de permisos.
        await _maybeShowPerms();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      // Sin esto el indicador de ubicación nunca se dibuja: el punto se ancla a
      // _userPos y se reposiciona vía _updateUserScreenPos.
      _userPos = pos;
      await _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
      );
      _updateUserScreenPos();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Widget _userLocationDot() {
    return ValueListenableBuilder<Offset?>(
      valueListenable: _userScreen,
      builder: (context, p, _) {
        if (p == null) return const SizedBox.shrink();
        const box = 96.0;
        return Positioned(
          left: p.dx - box / 2,
          top: p.dy - box / 2,
          width: box,
          height: box,
          child: IgnorePointer(
            // El pulso anima a 60 fps: el RepaintBoundary aísla su repaint en su
            // propia capa para no invalidar el resto del Stack en cada frame.
            child: RepaintBoundary(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, child) {
                    final t = _pulseCtrl.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Anillo de pulso que crece y se desvanece.
                        Container(
                          width: 20 + t * 56,
                          height: 20 + t * 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accent.withAlpha(
                              ((1 - t) * 90).round(),
                            ),
                          ),
                        ),
                        child!,
                      ],
                    );
                  },
                  // Punto central fijo.
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent,
                      border: Border.all(color: AppColors.ink, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withAlpha(140),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── DEV: prueba de ubicación ──────────────────────────────────────────────

  /// Tocar el mapa en modo prueba: mueve la ubicación simulada (y el punto azul)
  /// a ese punto y dispara la detección de cercanía.
  void _onMockTap(LatLng p) {
    context.read<PlaySessionService>().setMock(p.latitude, p.longitude);
    // Solo el punto se mueve (ValueNotifier): sin setState, sin rebuild global.
    _userPos = Position(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _updateUserScreenPos();
  }

  void _toggleMockMode() {
    final play = context.read<PlaySessionService>();
    setState(() => _mockMode = !_mockMode);
    if (!_mockMode) {
      play.clearMock();
      _loadInitialPosition(); // volvemos al GPS real
    }
  }

  Widget _devControls() {
    return Column(
      children: [
        if (_mockMode) ...[
          // Botón de prueba de notificación: si aparece la notificación,
          // el permiso está concedido y el canal funciona.
          _devBtn(
            Icons.notifications_active,
            AppColors.open,
            () => NotificationsService.instance.show(
              'Prueba',
              'Las notificaciones funcionan ✅',
            ),
          ),
          const SizedBox(height: 10),
        ],
        _devBtn(
          _mockMode ? Icons.wrong_location : Icons.bug_report,
          _mockMode ? AppColors.accent : AppColors.white(0.7),
          _toggleMockMode,
        ),
      ],
    );
  }

  Widget _devBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: _glassContainer(
        width: 48,
        height: 48,
        radius: AppShape.rBtn,
        child: Center(child: Icon(icon, color: color, size: 22)),
      ),
    );
  }

  Widget _locateBtn() {
    return GestureDetector(
      onTap: _goToMyLocation,
      child: _glassContainer(
        width: 48,
        height: 48,
        radius: AppShape.rBtn,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _locating
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                )
              : Icon(
                  key: const ValueKey('icon'),
                  Icons.my_location,
                  color: AppColors.accent,
                  size: 22,
                ),
        ),
      ),
    );
  }

  void _goPrev() =>
      _selectIndex((_index - 1 + _filtered.length) % _filtered.length);
  void _goNext() => _selectIndex((_index + 1) % _filtered.length);

  Widget _bottomSwipe() {
    return Column(
      children: [
        // Carrusel: se arrastra con el dedo y hace snap. clipBehavior.none deja
        // ver la sombra del card (queda fuera del alto fijo del PageView).
        SizedBox(
          height: 138,
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: _onPageChanged,
            clipBehavior: Clip.none,
            itemCount: _filtered.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _CourtSwipeCard(
                court: _filtered[i],
                onSelect: () => widget.onSelectCourt?.call(_filtered[i].id),
                onPrev: _goPrev,
                onNext: _goNext,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _filtered.length; i++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: i == _index ? 18 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: i == _index ? AppColors.accent : AppColors.white(0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (i < _filtered.length - 1) const SizedBox(width: 5),
            ],
          ],
        ),
      ],
    );
  }

  Widget _glassContainer({
    required Widget child,
    double? width,
    double? height,
    double radius = AppShape.rCard,
    EdgeInsetsGeometry? padding,
  }) {
    // Neobrutalismo: overlay SÓLIDO sobre el mapa con borde franco y sombra
    // dura desplazada (nada de blur ni glow, que además tiraban los FPS).
    return Container(
      width: width,
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.line, width: 2),
        boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
      ),
      child: child,
    );
  }
}

class _CourtSwipeCard extends StatelessWidget {
  final Court court;
  final VoidCallback onSelect;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _CourtSwipeCard({
    required this.court,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    // Handle + clan vigentes del proponente (en vivo desde Perfiles).
    final session = context.watch<Session>();
    final proposer = context.watch<ProfilesProvider>().resolveProposer(
      court,
      sessionProfile: session.profile,
      sessionEmail: session.email,
    );
    // Tarjeta protagonista del mapa: sólida, borde claro franco y sombra dura
    // desplazada (lenguaje neobrutalista, sin blur sobre el mapa).
    return Container(
      padding: const EdgeInsets.all(14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 2),
        boxShadow: AppFx.hardShadow(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CourtImage(
                  url: court.img,
                  // Radio fijo chico: rBtn ahora es pill (100) y deformaría la
                  // miniatura.
                  borderRadius: BorderRadius.circular(12),
                ),
                // Distancia a la cancha: chip retro-pop (papel + borde negro).
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(AppShape.rChip),
                      border: Border.all(color: AppColors.ink, width: 1.5),
                    ),
                    child: Text(
                      court.dist.toUpperCase(),
                      style: AppText.grotesk(
                        size: 9,
                        weight: FontWeight.w800,
                        color: AppColors.ink,
                        letterSpacing: 0.06,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusDot(status: court.status),
                    RatingBadge(value: court.rating, size: 11),
                  ],
                ),
                Text(
                  court.name,
                  style: AppText.archivo(size: 18, weight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${court.area} · ${court.type} · ${court.hoops} aros',
                  style: AppText.grotesk(
                    size: 11,
                    color: AppColors.white(0.55),
                  ),
                ),
                // Quién propuso la cancha: handle completo (clan opcional).
                if (proposer.handle.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        Icons.add_location_alt_outlined,
                        size: 11,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      if (proposer.clan.isNotEmpty) ...[
                        Text(
                          '[${proposer.clan}]',
                          style: AppText.grotesk(
                            size: 10,
                            weight: FontWeight.w800,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          proposer.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.grotesk(
                            size: 10,
                            weight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onSelect,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius:
                                BorderRadius.circular(AppShape.rBtn),
                            // Acento pleno → borde negro puro.
                            border:
                                Border.all(color: AppColors.ink, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'VER DETALLE',
                            style: AppText.archivo(
                              size: 11,
                              weight: FontWeight.w800,
                              letterSpacing: 0.04,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _arrowBtn(Icons.chevron_left, onPrev),
                    const SizedBox(width: 6),
                    _arrowBtn(Icons.chevron_right, onNext),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrowBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.ink, width: 1.5),
        ),
        child: Icon(icon, color: AppColors.ink, size: 16),
      ),
    );
  }
}

/// Puntos por tiempo acumulándose en vivo: cuenta suavemente hasta el valor
/// nuevo y da un pequeño "pop" cada vez que incrementa.
class _LivePoints extends StatefulWidget {
  final int points;
  const _LivePoints(this.points);

  @override
  State<_LivePoints> createState() => _LivePointsState();
}

class _LivePointsState extends State<_LivePoints>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.25,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.25,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 1,
    ),
  ]).animate(_pop);

  @override
  void didUpdateWidget(_LivePoints old) {
    super.didUpdateWidget(old);
    if (old.points != widget.points) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: widget.points.toDouble()),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (_, v, _) => Text(
          '+${v.round()} pts',
          style: AppText.archivo(
            size: 12,
            weight: FontWeight.w900,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
