import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import '../services/app_loading_state.dart';
import '../services/app_permissions.dart' as app_perms;
import '../services/court_rating_service.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/notifications_service.dart';
import '../services/notion_service.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../services/session_alarms.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/court_marker_icon.dart';
import '../widgets/permissions_modal.dart';
import '../widgets/rating_badge.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/status_dot.dart';
import 'pickup_create_screen.dart';

const _kApiKey = String.fromEnvironment('MAPS_API_KEY');

/// Cámara inicial del mapa (CABA). Es también el valor de arranque de
/// `_lastCam`, la cámara vigente con la que se proyecta el punto de ubicación.
const CameraPosition _kInitialCam = CameraPosition(
  target: LatLng(-34.6037, -58.3816),
  zoom: 12,
);

// Mapa DARK: geometría oscura, calles grises, agua azul oscuro,
// POIs/transit ocultos.
const _kMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#888888"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2a2a2a"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#cccccc"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill","stylers":[{"color":"#888888"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2a2a2a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#666666"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#333333"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3a3a3a"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#2a2a2a"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#777777"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d2137"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4a6fa5"}]}
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

  // Marca de ruta (waypoint estilo GTA): cancha destino, modo elegido y la
  // ruta calculada. La polyline violeta se dibuja de _userPos a la cancha.
  Court? _waypointCourt;
  String _waypointMode = 'walking';
  RouteResult? _route;
  // Posición desde la que se calculó la última ruta: si el usuario se aleja
  // lo suficiente de ese punto, se recalcula (throttle por distancia).
  Position? _routeOrigin;
  bool _routeLoading = false;
  static const Color _kWaypointColor = Color(0xFFB16CEA);

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

  // Íconos custom de los marcadores (disco con pelota, dibujados con Canvas).
  // Hasta que terminan de rasterizar se usa el pin default como fallback.
  BitmapDescriptor? _markerIcon;
  BitmapDescriptor? _markerIconSel;

  // Reseñas de la cancha seleccionada (máx. 2, rating ≥ 4). Se cargan al
  // cambiar de cancha y se muestran como burbujas sobre el punto GPS.
  final NotionService _notion = NotionService();
  List<Review> _courtReviews = [];
  bool _reviewsLoading = false;
  int _reviewRequestId = 0;

  // Toggle para mostrar/ocultar reseñas en el mapa (persistido en local).
  bool _showMapReviews = true;
  // Estado de expansión de las burbujas de reseñas (tap para colapsar).
  bool _reviewsExpanded = true;

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
      context.read<LocationService>().update(pos);
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
      context.read<LocationService>().update(pos);
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
    // Cargar preferencia de visibilidad de reseñas en mapa.
    SharedPreferences.getInstance().then((sp) {
      final saved = sp.getBool('map_reviews_toggle');
      if (saved != null && mounted) setState(() => _showMapReviews = saved);
    });
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
    // Rasterizar los íconos custom de marcador (necesitan el dpr del device,
    // por eso post-frame). Mientras tanto se ve el pin default.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMarkerIcons());
  }

  Future<void> _loadMarkerIcons() async {
    if (!mounted) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final normal = await buildCourtMarker(selected: false, dpr: dpr);
    final sel = await buildCourtMarker(selected: true, dpr: dpr);
    if (!mounted) return;
    setState(() {
      _markerIcon = normal;
      _markerIconSel = sel;
      _rebuildMarkers();
    });
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
            context.read<LocationService>().update(pos);
            _updateUserScreenPos();
            _onPositionForWaypoint(pos);
            _autoSelectNearCourt(pos);
            if (firstFix) {
              // Primer fix: centrar el mapa en la ubicación del usuario.
              _mapCtrl?.animateCamera(
                CameraUpdate.newLatLngZoom(
                  LatLng(pos.latitude, pos.longitude),
                  14,
                ),
              );
              // Aplicar el orden "Cerca" una única vez.
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
          // Ícono propio (disco con pelota); pin default solo mientras
          // termina de rasterizar en el arranque.
          icon: (i == _index ? _markerIconSel : _markerIcon) ??
              BitmapDescriptor.defaultMarkerWithHue(
                i == _index ? 22.0 : BitmapDescriptor.hueAzure,
              ),
          // La puntita del disco apunta al punto exacto de la cancha.
          anchor: const Offset(0.5, 1.0),
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
      _courtReviews = [];
      _reviewsLoading = true;
      _rebuildMarkers();
    });
    _loadCourtReviews();
    if (_skipNextPageCamera) {
      _skipNextPageCamera = false;
      return;
    }
    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLng(LatLng(_filtered[i].lat, _filtered[i].lng)),
    );
  }

  /// Carga las mejores reseñas de la cancha seleccionada.
  Future<void> _loadCourtReviews() async {
    final court = _court;
    if (court == null || !_notion.isConfigured) {
      setState(() { _courtReviews = []; _reviewsLoading = false; });
      return;
    }
    // Guard: incrementar requestId para descartar respuestas stale.
    final myRequestId = ++_reviewRequestId;
    // Resetear expansión al cambiar de cancha.
    _reviewsExpanded = true;
    try {
      final rows = await _notion.queryDatabase(
        NotionConfig.dbReviews,
        filter: NotionService.filterText('CourtId', court.id),
      );
      // Si cambió la cancha mientras cargaba, descartar este resultado.
      if (myRequestId != _reviewRequestId) return;
      final all = rows.map(Review.fromNotion).toList();
      // Solo 4-5 estrellas, ordenadas por rating desc, máximo 2.
      final best = all
          .where((r) => r.rating >= 4.0)
          .toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
      if (mounted) setState(() { _courtReviews = best.take(2).toList(); _reviewsLoading = false; });
    } catch (_) {
      if (myRequestId != _reviewRequestId) return;
      if (mounted) setState(() { _courtReviews = []; _reviewsLoading = false; });
    }
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
                // Ruta de la marca activa (waypoint): violeta estilo GTA. Si
                // Directions no está disponible cae a línea recta punteada.
                polylines: {
                  if (_waypointCourt != null && _route != null)
                    Polyline(
                      polylineId: const PolylineId('waypoint'),
                      points: _route!.points,
                      color: _kWaypointColor,
                      width: 5,
                      startCap: Cap.roundCap,
                      endCap: Cap.roundCap,
                      jointType: JointType.round,
                      patterns: _route!.straightLine
                          ? [PatternItem.dash(18), PatternItem.gap(10)]
                          : const [],
                    ),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
                tiltGesturesEnabled: false,
              ),
               _userLocationDot(),
               _courtReviewBubbles(),
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
                      // Estado actual del banner, para que AnimatedSwitcher
                      // detecte el cambio y haga el cross-fade entre estados.
                      final bannerKey = ps.isPlaying
                          ? 'playing'
                          : ps.isDwelling
                              ? 'dwell'
                              : ps.manualStartCourt != null
                                  ? 'manual'
                                  : 'idle';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // El cronómetro se muestra SIEMPRE. Estar dentro del radio
                          // solo lo "activa" (arranca la cuenta regresiva y el
                          // partido); fuera del radio queda inactivo pero visible.
                          // El cambio de estado (empieza → jugando → reposo) se
                          // funde progresivamente en vez de saltar de golpe.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 380),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: KeyedSubtree(
                              key: ValueKey(bannerKey),
                              child: ps.isPlaying
                                  ? _playingBanner(context)
                                  : ps.isDwelling
                                      ? _dwellBanner(context)
                                      : ps.manualStartCourt != null
                                          ? _manualStartBanner(context)
                                          : _idleTimer(context),
                            ),
                          ),
                          if (!active) ...[
                            const SizedBox(height: 10),
                            _quickChips(),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              // Siempre presente (vacío sin marca): insertar/quitar un hijo en
              // el medio del Stack re-crea los siguientes — el carrusel perdía
              // su página y volvía a la primera cancha.
              Positioned(
                left: 16,
                bottom: 312,
                child: _waypointCourt != null
                    ? _routeChip()
                    : const SizedBox.shrink(),
              ),
              Positioned(
                right: 16,
                bottom: 312,
                child: Column(
                  children: [
                    _reviewToggleBtn(),
                    const SizedBox(height: 10),
                    if (context.read<Session>().isAdmin) ...[
                      _devControls(),
                      const SizedBox(height: 10),
                    ],
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
                            Border.all(color: AppColors.accent, width: 1),
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
                  PressableWidget(
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
        PressableWidget(
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
    // El color de estado (verde jugando / gris pausado) transiciona suave en
    // vez de saltar de golpe al pausar/reanudar.
    final targetAccent = paused ? AppColors.white(0.7) : AppColors.open;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: targetAccent),
      duration: const Duration(milliseconds: 450),
      builder: (context, animated, _) {
        final accent = animated ?? targetAccent;
        return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        // Plano: fill sólido sin borde ni sombra; el color de estado vive en
        // el dot y el cronómetro (con transición suave).
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
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
                          // Tinte plano, sin borde (lenguaje editorial).
                          decoration: BoxDecoration(
                            color: AppColors.accent.withAlpha(38),
                            borderRadius:
                                BorderRadius.circular(AppShape.rChip),
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
            PressableWidget(
              onTap: () => context.read<PlaySessionService>().togglePause(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.white(0.08),
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                ),
                child: Icon(
                  paused ? Icons.play_arrow : Icons.pause,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 6),
            PressableWidget(
              onTap: () => context.read<PlaySessionService>().stopNow(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
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
      },
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
        // Plano: fill sólido sin borde (estado inactivo = todo atenuado).
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
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
        // Plano: sin borde; el naranja vive en el ícono y la cuenta regresiva.
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
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
                  const SizedBox(height: 2),
                  Text(
                    'Entrá en calor tranquilo: arrancamos y registramos '
                    'el partido por vos.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(
                      size: 9.5,
                      color: AppColors.white(0.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // "No juego": cancela la cuenta y silencia esta cancha por 1 h
            // (mientras sigas adentro queda el arranque manual).
            PressableWidget(
              onTap: () =>
                  context.read<PlaySessionService>().declineDwell(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white(0.08),
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                ),
                child: Text(
                  'NO JUEGO',
                  style: AppText.archivo(
                    size: 10,
                    weight: FontWeight.w800,
                    letterSpacing: 0.04,
                    color: AppColors.white(0.7),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PressableWidget(
              onTap: () => context.read<PlaySessionService>().startNow(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
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

  /// Banner tras "No juego": la detección de esta cancha queda silenciada 1 h,
  /// con el arranque manual a un tap por si el usuario cambia de opinión.
  Widget _manualStartBanner(BuildContext context) {
    final ps = context.watch<PlaySessionService>();
    final court = ps.manualStartCourt;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_basketball,
                size: 15, color: AppColors.white(0.55)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detección pausada',
                    style: AppText.archivo(
                      size: 13,
                      weight: FontWeight.w800,
                      color: AppColors.white(0.85),
                    ),
                  ),
                  Text(
                    court?.name ?? 'En una cancha',
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
            PressableWidget(
              onTap: () =>
                  context.read<PlaySessionService>().startManualNow(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                ),
                child: Text(
                  'INICIAR PARTIDO',
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
      var permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        // Pedido EN CONTEXTO: el usuario tocó "mi ubicación", este es el
        // momento natural para el diálogo del sistema (si quedó denegado
        // permanente, requestLocation abre los ajustes de la app).
        await app_perms.requestLocation();
        permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.always &&
            permission != LocationPermission.whileInUse) {
          return;
        }
        // Recién concedido: el stream en vivo del arranque se había salteado
        // por falta de permiso — lo levantamos ahora.
        if (_posStream == null) unawaited(_startLocationUpdates());
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
      context.read<LocationService>().update(pos);
      await _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
      );
      _updateUserScreenPos();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // Última cancha auto-seleccionada por entrar a su radio: dispara UNA vez
  // por entrada (el usuario puede swipear a otra sin que se lo pelee).
  String? _autoSelectedCourtId;

  /// Al entrar al radio de una cancha, el carrusel salta solo a su miniatura.
  void _autoSelectNearCourt(Position pos) {
    var idx = -1;
    var best = PlaySessionService.radiusMeters + 1;
    for (var i = 0; i < _filtered.length; i++) {
      final c = _filtered[i];
      if (c.lat == 0 && c.lng == 0) continue;
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, c.lat, c.lng);
      if (d <= PlaySessionService.radiusMeters && d < best) {
        best = d;
        idx = i;
      }
    }
    if (idx < 0) {
      _autoSelectedCourtId = null; // fuera de todo radio: re-arma el disparo
      return;
    }
    final id = _filtered[idx].id;
    if (id == _autoSelectedCourtId) return; // ya disparado en esta entrada
    _autoSelectedCourtId = id;
    if (_index != idx) _selectIndex(idx);
  }

  // ── Marca de ruta (waypoint estilo GTA) ──────────────────────────────────

  /// Coloca la marca hacia [court] y calcula la ruta desde la posición actual.
  Future<void> _setWaypoint(Court court, String mode) async {
    final pos = _userPos;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Todavía no hay señal de GPS para trazar la ruta'),
      ));
      return;
    }
    setState(() {
      _waypointCourt = court;
      _waypointMode = mode;
      _route = null;
    });
    await _refreshRoute(pos);
    // Encuadrar la ruta completa (usuario + cancha) en el mapa.
    final r = _route;
    if (r != null && _mapCtrl != null && _waypointCourt?.id == court.id) {
      var minLat = double.infinity, maxLat = -double.infinity;
      var minLng = double.infinity, maxLng = -double.infinity;
      for (final p in r.points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ));
    }
  }

  void _clearWaypoint() {
    if (_waypointCourt == null) return;
    setState(() {
      _waypointCourt = null;
      _route = null;
      _routeOrigin = null;
    });
  }

  /// Pide la ruta a Directions (o línea recta de fallback) desde [pos].
  Future<void> _refreshRoute(Position pos) async {
    final court = _waypointCourt;
    if (court == null || _routeLoading) return;
    _routeLoading = true;
    _routeOrigin = pos;
    final r = await RouteService.fetchRoute(
      origin: LatLng(pos.latitude, pos.longitude),
      dest: LatLng(court.lat, court.lng),
      mode: _waypointMode,
    );
    _routeLoading = false;
    // Puede haberse quitado/cambiado la marca mientras esperábamos la red.
    if (!mounted || _waypointCourt?.id != court.id) return;
    setState(() => _route = r);
  }

  /// Cada fix de GPS con marca activa: recalcular si nos movimos bastante del
  /// origen de la última ruta, y auto-quitar la marca al llegar a la cancha.
  void _onPositionForWaypoint(Position pos) {
    final court = _waypointCourt;
    if (court == null) return;
    final toCourt = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, court.lat, court.lng);
    if (toCourt <= PlaySessionService.radiusMeters) {
      _clearWaypoint();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Llegaste a ${court.name} 🏀'),
      ));
      return;
    }
    final origin = _routeOrigin;
    final moved = origin == null
        ? double.infinity
        : Geolocator.distanceBetween(
            origin.latitude, origin.longitude, pos.latitude, pos.longitude);
    // ~un tercio de cuadra: la ruta se siente "viva" sin abusar de la API.
    if (moved > 35) _refreshRoute(pos);
  }

  /// Sheet para elegir el modo de la marca (caminando / en auto), con la
  /// opción de quitarla si ya está puesta en esta cancha.
  void _onWaypointTap(Court court) {
    if (_waypointCourt?.id == court.id) {
      _clearWaypoint();
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
      ),
      builder: (sheetCtx) {
        Widget option(IconData icon, String label, String mode) {
          return PressableWidget(
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _setWaypoint(court, mode);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: _kWaypointColor),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label,
                        style:
                            AppText.grotesk(size: 14, weight: FontWeight.w700)),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: AppColors.white(0.35)),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.flag_rounded, size: 16, color: _kWaypointColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'COLOCAR MARCA · ${court.name.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.archivo(
                            size: 12,
                            weight: FontWeight.w800,
                            letterSpacing: 0.06),
                      ),
                    ),
                  ],
                ),
              ),
              option(Icons.directions_walk, 'Caminando', 'walking'),
              Container(height: 1, color: AppColors.white(0.06)),
              option(
                  Icons.directions_car_filled_outlined, 'Vehículo', 'driving'),
              if (_waypointCourt != null) ...[
                Container(height: 1, color: AppColors.white(0.06)),
                PressableWidget(
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _clearWaypoint();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 20, color: AppColors.busy),
                        const SizedBox(width: 14),
                        Text('Quitar marca actual',
                            style: AppText.grotesk(
                                size: 14,
                                weight: FontWeight.w700,
                                color: AppColors.busy)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
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
                      border: Border.all(color: AppColors.line, width: 3),
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

  /// Burbujas con las 2 mejores reseñas de la cancha seleccionada,
  /// posicionadas justo arriba del marcador de la cancha en el mapa.
  Widget _courtReviewBubbles() {
    if (!_showMapReviews) return const SizedBox.shrink();
    final court = _court;
    if (court == null) return const SizedBox.shrink();
    // Mostrar loader mientras se cargan reseñas.
    if (_reviewsLoading && _courtReviews.isEmpty) {
      return ValueListenableBuilder<Offset?>(
        valueListenable: _userScreen,
        builder: (context, _, _) {
          final pos = _projectToScreen(court.lat, court.lng);
          if (pos == null) return const SizedBox.shrink();
          return Positioned(
            left: (pos.dx - 20).clamp(8.0, 9999.0),
            top: pos.dy - 72,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bgElev,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.line, width: 1),
                ),
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    if (_courtReviews.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<Offset?>(
      key: ValueKey('reviews:${court.id}'),
      valueListenable: _userScreen,
      builder: (context, _, _) {
        final pos = _projectToScreen(court.lat, court.lng);
        if (pos == null) return const SizedBox.shrink();
        return Positioned(
          left: (pos.dx - 100).clamp(8.0, 9999.0),
          top: pos.dy - 72 - (_reviewsExpanded ? _courtReviews.length * 64.0 : 40),
          width: 200,
          child: GestureDetector(
            onTap: () => setState(() => _reviewsExpanded = !_reviewsExpanded),
            child: IgnorePointer(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _courtReviews.length; i++)
                      if (_reviewsExpanded)
                        _reviewBubble(_courtReviews[i], i)
                      else
                        _reviewBubbleMini(_courtReviews[i]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _reviewBubble(Review r, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var s = 0; s < 5; s++)
                  Icon(
                    s < r.rating.round()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 12,
                    color: AppColors.accent,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.userHandle.isNotEmpty
                        ? r.userHandle
                        : r.userEmail.split('@').first,
                    style: AppText.grotesk(
                      size: 11,
                      color: AppColors.ink.withAlpha(180),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (r.comment.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                r.comment,
                style: AppText.grotesk(
                  size: 11,
                  color: AppColors.ink.withAlpha(200),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reviewBubbleMini(Review r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var s = 0; s < 5; s++)
              Icon(
                s < r.rating.round()
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 10,
                color: AppColors.accent,
              ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                r.userHandle.isNotEmpty
                    ? r.userHandle
                    : r.userEmail.split('@').first,
                style: AppText.grotesk(
                  size: 10,
                  color: AppColors.ink.withAlpha(180),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Botón flotante para activar/desactivar reseñas en el mapa.
  Widget _reviewToggleBtn() {
    return PressableWidget(
      onTap: () async {
        setState(() => _showMapReviews = !_showMapReviews);
        final sp = await SharedPreferences.getInstance();
        await sp.setBool('map_reviews_toggle', _showMapReviews);
      },
      child: _glassContainer(
        width: 48,
        height: 48,
        radius: AppShape.rBtn,
        child: Icon(
          _showMapReviews ? Icons.rate_review_rounded : Icons.rate_review_outlined,
          color: _showMapReviews ? AppColors.accent : AppColors.ink.withAlpha(140),
          size: 22,
        ),
      ),
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
    context.read<LocationService>().update(_userPos!);
    _updateUserScreenPos();
    _onPositionForWaypoint(_userPos!);
    _autoSelectNearCourt(_userPos!);
  }

  void _toggleMockMode() {
    final play = context.read<PlaySessionService>();
    setState(() => _mockMode = !_mockMode);
    if (!_mockMode) {
      play.clearMock();
      _loadInitialPosition(); // volvemos al GPS real
    }
  }

  /// DEV: estado de la detección en background — permiso real y momento del
  /// último fix de GPS recibido con la app minimizada (radar o stream). Permite
  /// verificar en la calle que el background funciona, sin conectar el USB.
  Future<void> _showBgDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final last = prefs.getInt(kLastBgFixKey);
    final perm = await Geolocator.checkPermission();
    if (!mounted) return;
    final fix = last == null
        ? 'sin fixes aún'
        : 'último fix hace '
            '${DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)).inMinutes} min';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Background · permiso: ${perm.name} · $fix',
          style: AppText.grotesk(size: 13)),
    ));
  }

  Widget _devControls() {
    return Column(
      children: [
        _devBtn(Icons.gps_fixed, AppColors.white(0.7), _showBgDiagnostics),
        const SizedBox(height: 10),
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
    return PressableWidget(
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
    return PressableWidget(
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

  /// Chip flotante de la marca activa: modo + ETA/distancia de Google y ✕
  /// para quitarla. Si la ruta es de fallback (línea recta) muestra la
  /// distancia geodésica calculada localmente.
  Widget _routeChip() {
    final court = _waypointCourt!;
    final r = _route;
    final meters = metersTo(_userPos, court.lat, court.lng);
    final dist = (r != null && r.distText.isNotEmpty)
        ? r.distText
        : (meters != null ? formatDist(meters) : '');
    final eta = r?.durationText ?? '';
    return _glassContainer(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      radius: AppShape.rBtn,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _waypointMode == 'driving'
                ? Icons.directions_car_filled_outlined
                : Icons.directions_walk,
            size: 16,
            color: _kWaypointColor,
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r == null ? 'TRAZANDO RUTA…' : [
                    if (eta.isNotEmpty) eta.toUpperCase(),
                    if (dist.isNotEmpty) dist.toUpperCase(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.archivo(
                      size: 11, weight: FontWeight.w800, color: _kWaypointColor),
                ),
                Text(
                  court.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.grotesk(size: 9, color: AppColors.white(0.55)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          PressableWidget(
            onTap: _clearWaypoint,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 16, color: AppColors.white(0.6)),
            ),
          ),
        ],
      ),
    );
  }

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
            itemBuilder: (context, i) {
              final court = _filtered[i];
              // Distancia REAL al usuario; sin GPS aún, cae al texto de Notion.
              final meters = metersTo(_userPos, court.lat, court.lng);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _CourtSwipeCard(
                  court: court,
                  distLabel: meters != null ? formatDist(meters) : court.dist,
                  isWaypoint: _waypointCourt?.id == court.id,
                  waypointColor: _kWaypointColor,
                  onWaypoint: () => _onWaypointTap(court),
                  onSelect: () => widget.onSelectCourt?.call(court.id),
                ),
              );
            },
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
    // Overlay plano sobre el mapa (lenguaje editorial): fill sólido oscuro,
    // sin borde ni sombra dura; el contraste con el mapa ya lo da el fill.
    return Container(
      width: width,
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class _CourtSwipeCard extends StatelessWidget {
  final Court court;
  final VoidCallback onSelect;
  // Distancia ya formateada (real si hay GPS; texto de Notion si no).
  final String distLabel;
  // Marca de ruta: si esta cancha es el waypoint activo y el tap del botón.
  final bool isWaypoint;
  final Color waypointColor;
  final VoidCallback onWaypoint;

  const _CourtSwipeCard({
    required this.court,
    required this.onSelect,
    required this.distLabel,
    required this.isWaypoint,
    required this.waypointColor,
    required this.onWaypoint,
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
    // Tarjeta plana sobre el mapa (lenguaje editorial): fill sólido sin borde
    // ni sombra dura; la foto y la tipografía llevan el protagonismo.
    return Container(
      padding: const EdgeInsets.all(14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppShape.rCard),
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
                // Distancia a la cancha: chip de legibilidad plano sobre la
                // foto (fondo oscuro, sin borde). Se oculta si no hay dato.
                if (distLabel.isNotEmpty)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.black(0.55),
                      borderRadius: BorderRadius.circular(AppShape.rChip),
                    ),
                    child: Text(
                      distLabel.toUpperCase(),
                      style: AppText.grotesk(
                        size: 9,
                        weight: FontWeight.w800,
                        color: Colors.white,
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
                    Builder(builder: (context) {
                      final rs = context.read<CourtRatingService>();
                      return FutureBuilder<CourtRating>(
                        future: rs.ratingFor(court.id),
                        builder: (context, snap) {
                          final cr = snap.data;
                          return RatingBadge(
                            value: cr?.average,
                            size: 11,
                          );
                        },
                      );
                    }),
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
                // Acciones: dos botones parejos, radio fijo (rBtn es pill y los
                // deformaba). El carrusel se navega deslizando (hay puntitos).
                Row(
                  children: [
                    Expanded(
                      child: _cardBtn(
                        label: 'VER DETALLE',
                        filled: true,
                        onTap: onSelect,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _cardBtn(
                        label: 'PICKUP',
                        icon: Icons.add,
                        filled: false,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PickupCreateScreen(initialCourt: court),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Marca de ruta (waypoint estilo GTA): elegir modo y trazar
                    // el camino hasta la cancha; re-tap con marca puesta la quita.
                    PressableWidget(
                      onTap: onWaypoint,
                      child: Container(
                        width: 34,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isWaypoint
                              ? waypointColor
                              : AppColors.white(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isWaypoint ? Icons.flag : Icons.flag_outlined,
                          size: 15,
                          color: isWaypoint ? AppColors.ink : waypointColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Botón de acción de la card (radio fijo, una sola línea). [filled] = acento
  /// pleno con texto oscuro; si no, contorno de acento sobre card.
  Widget _cardBtn({
    required String label,
    required bool filled,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final fg = filled ? AppColors.ink : AppColors.accent;
    return PressableWidget(
      onTap: onTap,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        // Botones planos: primario = acento pleno; secundario = fill sutil con
        // texto de acento (sin bordes).
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : AppColors.white(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.archivo(
                  size: 10.5,
                  weight: FontWeight.w800,
                  letterSpacing: 0.02,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
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
