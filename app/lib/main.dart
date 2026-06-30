import 'dart:async';
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
import 'notion/notion_config.dart';
import 'services/app_loading_state.dart';
import 'services/courts_provider.dart';
import 'services/favorites_provider.dart';
import 'services/geofence_service.dart';
import 'services/notifications_service.dart';
import 'services/notion_service.dart';
import 'services/play_session_service.dart';
import 'services/profiles_provider.dart';
import 'services/session.dart';
import 'services/sync_coordinator.dart';
import 'theme/app_theme.dart';
import 'widgets/bball_glyph.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final mapsImpl = GoogleMapsFlutterPlatform.instance;
  if (mapsImpl is GoogleMapsFlutterAndroid) {
    mapsImpl.useAndroidViewSurface = true;
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
  ));

  // Notificaciones locales (recompensas). No bloquea el arranque si falla.
  unawaited(NotificationsService.instance.init());
  // Geofencing (detecta llegada a una cancha sin notificación persistente).
  unawaited(GeofenceService.instance.init());

  // Crea (si faltan) las columnas que usan las features nuevas. Idempotente y
  // sin bloquear el arranque: si falla por permisos, la app sigue funcionando.
  unawaited(_ensureNotionSchema());

  runApp(const OneOfOneApp());
}

/// Garantiza el schema de Notion necesario para clan/color y autor de cancha.
Future<void> _ensureNotionSchema() async {
  if (!NotionConfig.isConfigured) return;
  final notion = NotionService();
  try {
    await notion.ensureProperties(
      NotionConfig.dbProfiles,
      const {
        'Clan': 'rich_text',
        'AvatarColor': 'rich_text',
        'ClanTextColor': 'rich_text',
        'ClanFont': 'rich_text',
        'AvatarFrame': 'rich_text',
        'EquippedTitle': 'rich_text',
        'Level': 'rich_text',
        'ShareStatus': 'checkbox',
        'ShareCourt': 'checkbox',
        'ShareTime': 'checkbox',
        'Playing': 'checkbox',
        'PlayingCourtId': 'rich_text',
        'PlayingSince': 'date',
        'LastPlayedCourtId': 'rich_text',
        'LastPlayedAt': 'date',
        'ShowLastPlayed': 'checkbox',
      },
    );
    await notion.ensureProperties(
      NotionConfig.dbCourts,
      const {'CreatedByClan': 'rich_text', 'CreatedByEmail': 'rich_text'},
    );
  } catch (_) {
    // Permisos insuficientes u otro error: se puede crear a mano en Notion.
  }
}

class OneOfOneApp extends StatelessWidget {
  const OneOfOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Session()..restore()),
        ChangeNotifierProvider(create: (_) => CourtsProvider()..load()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()..load()),
        ChangeNotifierProvider(create: (_) => ProfilesProvider()..load()),
        ChangeNotifierProvider(create: (_) => PlaySessionService()),
        ChangeNotifierProvider(create: (_) => AppLoadingState()),
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
          ),
          dispose: (_, c) => c.dispose(),
        ),
      ],
      child: MaterialApp(
        title: '1of1',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.accent, AppColors.accentDark],
                ),
              ),
              child: const Center(child: BBallGlyph(size: 34)),
            ),
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
