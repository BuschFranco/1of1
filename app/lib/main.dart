import 'dart:async';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/auth_screen.dart';
import 'screens/handle_setup_screen.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pickup_chat_screen.dart';
import 'services/api/api_client.dart';
import 'services/app_loading_state.dart';
import 'services/blocked_provider.dart';
import 'services/court_rating_service.dart';
import 'services/courts_provider.dart';
import 'services/favorites_provider.dart';
import 'services/geofence_service.dart';
import 'services/location_service.dart';
import 'services/notifications_service.dart';
import 'services/pickups_provider.dart';
import 'services/play_session_service.dart';
import 'services/profiles_provider.dart';
import 'services/session.dart';
import 'services/sync_coordinator.dart';
import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';

/// Navegador raíz: permite navegar desde fuera del árbol de widgets (p.ej. al
/// tocar una notificación de pickup para ir a su chat).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final mapsImpl = GoogleMapsFlutterPlatform.instance;
  if (mapsImpl is GoogleMapsFlutterAndroid) {
    mapsImpl.useAndroidViewSurface = true;
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Notificaciones locales (recompensas). No bloquea el arranque si falla.
  unawaited(NotificationsService.instance.init());
  // Geofencing (detecta llegada a una cancha sin notificación persistente).
  unawaited(GeofenceService.instance.init());
  // Alarmas del sistema: arranque/cierre automático del partido en segundo
  // plano (a los 6 min), aunque la app esté minimizada o cerrada. Solo Android.
  if (defaultTargetPlatform == TargetPlatform.android) {
    unawaited(AndroidAlarmManager.initialize());
  }

  // El schema de la BD lo asegura el BACKEND al arrancar (ProfilesService.
  // onModuleInit): la app ya no toca Notion ni conoce su token.

  // Cargar el JWT persistido ANTES de crear los providers: los load() del
  // arranque (canchas, perfiles) necesitan el token para hablar con la API.
  await ApiClient().loadToken();

  runApp(const OneOfOneApp());
}

class OneOfOneApp extends StatelessWidget {
  const OneOfOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Cliente único del backend, compartido por todos los providers (el JWT
    // igualmente es estático a nivel proceso).
    final api = ApiClient();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Session(api: api)..restore()),
        ChangeNotifierProvider(create: (_) => CourtsProvider(api: api)..load()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()..load()),
        ChangeNotifierProvider(create: (_) => ProfilesProvider(api: api)..load()),
        ChangeNotifierProvider(create: (_) => PlaySessionService()),
        ChangeNotifierProvider(create: (_) => PickupsProvider(api: api)),
        ChangeNotifierProvider(create: (_) => BlockedProvider()),
        // Última posición conocida compartida: la alimenta el mapa y la leen
        // canchas/detalle para mostrar distancias reales.
        ChangeNotifierProvider(create: (_) => LocationService()..warmUp()),
        ChangeNotifierProvider(create: (_) => AppLoadingState()),
        Provider(create: (_) => CourtRatingService(api: api)),
        // Pegamento de sincronización (presencia, batch, sembrado). Se crea de
        // forma temprana (lazy: false) para cablear los callbacks ni bien
        // arranca la app, sin depender de que se monte ninguna pantalla.
        Provider<SyncCoordinator>(
          lazy: false,
          create: (ctx) => SyncCoordinator(
            session: ctx.read<Session>(),
            play: ctx.read<PlaySessionService>(),
            courts: ctx.read<CourtsProvider>(),
            favorites: ctx.read<FavoritesProvider>(),
            pickups: ctx.read<PickupsProvider>(),
            blocked: ctx.read<BlockedProvider>(),
          ),
          dispose: (_, c) => c.dispose(),
        ),
      ],
      child: MaterialApp(
        title: '1of1',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildAppTheme(),
        // Blindaje: íconos de la barra de estado SIEMPRE claros (tema dark).
        // Sin esto, cualquier pantalla que pise el estilo lo deja pegado.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: AppColors.bg,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: child!,
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _bootstrapping = true;
  bool _onboardingSeen = false;
  bool _goAuth = false;
  AuthMode _authMode = AuthMode.signup;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // Enrutar al chat del pickup al tocar su notificación (o el botón "Ir al
    // chat"). Al asignarlo se drena un pickup pendiente si la app se abrió
    // desde la notificación con el proceso muerto.
    NotificationsService.instance.onOpenPickupChat = (pickupId) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => PickupChatScreen(pickupId: pickupId),
        ),
      );
    };
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    if (mounted) setState(() => _bootstrapping = false);
  }

  Future<void> _leaveOnboarding(AuthMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    setState(() {
      _onboardingSeen = true;
      _goAuth = true;
      _authMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    if (_bootstrapping || session.restoring) return const _Splash();
    if (session.isLoggedIn) {
      // Recién registrado sin handle → forzar la elección antes de entrar.
      return session.needsHandle ? const HandleSetupScreen() : const MainShell();
    }

    if (!_onboardingSeen && !_goAuth) {
      return OnboardingScreen(
        onStart: () => _leaveOnboarding(AuthMode.signup),
        onLogin: () => _leaveOnboarding(AuthMode.login),
      );
    }
    return AuthScreen(initialMode: _authMode);
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Marca plana (neobrutalismo): el logo va limpio, sin caja ni glow.
            const AppLogo(height: 96),
            const SizedBox(height: 20),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white(0.4)),
            ),
          ],
        ),
      ),
    );
  }
}
