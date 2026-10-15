import 'dart:async';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'widgets/offline_pill.dart';
import 'widgets/permissions_modal.dart';

/// Navegador raíz: permite navegar desde fuera del árbol de widgets (p.ej. al
/// tocar una notificación de pickup para ir a su chat).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final mapsImpl = GoogleMapsFlutterPlatform.instance;
  if (mapsImpl is GoogleMapsFlutterAndroid) {
    mapsImpl.useAndroidViewSurface = true;
  }

  // Solo vertical, aunque el usuario tenga la rotación automática activada: la
  // app no tiene layouts horizontales. El manifest (screenOrientation) cubre
  // el splash nativo; esto, a Flutter.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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
        // Restauración de estado: cuando Android mata el proceso con la app en
        // segundo plano (pasa seguido en Samsung al abrir otras apps), al volver
        // se recupera la pestaña en la que estabas. Solo aplica a ESE caso: si
        // el usuario cierra la app a mano, arranca en su pestaña de inicio.
        restorationScopeId: 'app',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildAppTheme(),
        // Localización: sin esto el date range picker de Material abre en blanco.
        locale: const Locale('es'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es'), Locale('en')],
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
  bool _splashTimeout = false;
  // Login y no registro: acá se llega con el onboarding YA visto, o sea que el
  // usuario abrió la app antes. Lo mas probable es que ya tenga cuenta y venga
  // a entrar, no a crearse otra. Los dos botones del onboarding siguen mandando
  // el modo explicito, asi que "Empezar" sigue abriendo el registro.
  AuthMode _authMode = AuthMode.login;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // Si después de 5 s la sesión no se restauró, ir al login.
    _splashTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_splashTimeout) setState(() => _splashTimeout = true);
    });
    // Enrutar al chat del pickup al tocar su notificación (o el botón "Ir al
    // chat"). Al asignarlo se drena un pickup pendiente si la app se abrió
    // desde la notificación con el proceso muerto.
    NotificationsService.instance.onOpenPickupChat = (pickupId) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && !requireOnline(ctx)) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => PickupChatScreen(pickupId: pickupId),
        ),
      );
    };
    // Aviso de ahorro de energía: abre el panel de permisos, que es donde se
    // explica qué desactivar. Mismo drenaje que el chat si la app se abrió desde
    // la notificación.
    NotificationsService.instance.onOpenPermissions = () {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) PermissionsModal.show(ctx);
    };
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
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

    // Splash: solo mientras se lee lo LOCAL (prefs, perfil cacheado). La
    // verificación contra el backend (`GET /me`) ya no se espera acá: con Render
    // dormido eran 4 s de splash antes de que el mapa empezara siquiera a
    // crearse. Se entra con el perfil cacheado y, si `/me` devuelve 401, la
    // sesión se cierra y este build manda al login con el aviso.
    if ((_bootstrapping || session.restoring) && !_splashTimeout) {
      return const _Splash();
    }

    if (session.isLoggedIn) {
      // Recién registrado sin handle → forzar la elección antes de entrar.
      return session.needsHandle ? const HandleSetupScreen() : const MainShell();
    }

    // La sesión cacheada venció (401): al login con el mensaje. La falta de red
    // ya no llega acá: entra en modo offline (ver Session.offline).
    final startupError = session.startupError;
    if (startupError != null) {
      return AuthScreen(
          initialMode: AuthMode.login, initialError: startupError);
    }

    // Si no se pudo establecer sesión (timeout o sin cache/token), ir al login.
    if (!_onboardingSeen && !_goAuth) {
      // El CTA principal abre el LOGIN y el link secundario el registro, no al
      // revés. Es a propósito: decisión de producto, aunque el onboarding se
      // muestre solo la primera vez. Los dos caminos siguen existiendo — si
      // ambos fueran al login, no habría forma de crearse una cuenta.
      return OnboardingScreen(
        onStart: () => _leaveOnboarding(AuthMode.login),
        onLogin: () => _leaveOnboarding(AuthMode.signup),
      );
    }
    return AuthScreen(initialMode: _authMode);
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    // Mismo fondo, logo y spinner que AppLoader: se suceden al arrancar y antes
    // se notaba el cambio de color entre una y otra.
    return Scaffold(
      backgroundColor: AppColors.splash,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Marca plana (neobrutalismo): el logo va limpio, sin caja ni glow.
            const AppLogo(height: 120),
            const SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent.withAlpha(180)),
            ),
          ],
        ),
      ),
    );
  }
}
