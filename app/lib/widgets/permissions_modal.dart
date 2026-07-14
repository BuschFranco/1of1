import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_permissions.dart';
import '../services/notifications_service.dart';
import '../services/play_session_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

/// Modal que aparece sobre el mapa cuando faltan permisos clave (ubicación,
/// notificaciones, alarmas exactas). Explica para qué sirve cada uno y ofrece
/// un botón para activarlo. Incluye además el toggle opcional de Salud (Health
/// Connect). Se auto-refresca al volver de los ajustes y, cuando se abre por
/// falta de permisos, se cierra solo al concederse todos los obligatorios.
class PermissionsModal extends StatefulWidget {
  /// Si es true, el modal se cierra solo cuando están todos los permisos
  /// obligatorios (uso automático sobre el mapa). Si es false (abierto a mano
  /// desde el perfil), queda abierto hasta que el usuario lo cierre.
  final bool autoClose;
  const PermissionsModal({super.key, this.autoClose = true});

  /// Muestra el modal si falta algún permiso (incluida la batería recomendada).
  static Future<void> showIfNeeded(BuildContext context) async {
    final state = await checkPermissions();
    if (state.missing.isEmpty || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const PermissionsModal(),
    );
  }

  /// Muestra el modal UNA sola vez por usuario (tras login/registro): un flag
  /// persistido namespaced por usuario evita re-mostrarlo en cada apertura o
  /// resume de la app. Después, el usuario lo abre a mano desde el perfil
  /// (tuerquita → Permisos y salud). El flag se marca ANTES de mostrar: si el
  /// usuario lo descarta con "Listo", no volvemos a insistir.
  static Future<void> showOnceIfNeeded(BuildContext context) async {
    final email = context.read<Session>().email ?? '';
    final userKey = email.trim().toLowerCase();
    final flagKey =
        userKey.isEmpty ? 'perms_prompted' : 'perms_prompted::$userKey';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) ?? false) return;
    await prefs.setBool(flagKey, true);
    // Notificaciones: diálogo directo del sistema, sin pasar por el modal
    // (fricción mínima). Si acepta, la fila ni aparece en el modal; si
    // rechaza, queda ahí como recordatorio.
    await NotificationsService.instance.requestPermission();
    if (!context.mounted) return;
    await showIfNeeded(context);
  }

  /// Abre el modal siempre (acceso manual desde el perfil), sin auto-cerrarse.
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const PermissionsModal(autoClose: false),
    );
  }

  @override
  State<PermissionsModal> createState() => _PermissionsModalState();
}

class _PermissionsModalState extends State<PermissionsModal>
    with WidgetsBindingObserver {
  PermState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Al volver de los ajustes del sistema, re-chequeamos.
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final st = await checkPermissions();
    if (!mounted) return;
    setState(() => _state = st);
    // "Permitir siempre" concedido: sincronizamos la preferencia de background
    // (idempotente) para que el coordinador registre geofences + radar ya mismo,
    // sin esperar a reiniciar la app.
    if (st.background) {
      unawaited(context.read<PlaySessionService>().setBackground(true));
    }
    // Se cierra solo cuando no falta NADA (batería incluida): si cerráramos con
    // la batería pendiente, el modal se abriría y cerraría al instante.
    if (st.missing.isEmpty && widget.autoClose) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _activate(AppPerm p) async {
    if (_busy) return;
    // Background exige la divulgación destacada de Google Play ANTES de pedir
    // el permiso del sistema (misma que usa el switch del perfil).
    if (p == AppPerm.background && !await _backgroundDisclosure()) return;
    setState(() => _busy = true);
    await requestPerm(p);
    await _refresh();
    if (mounted) setState(() => _busy = false);
    // Encadenado: al conceder la ubicación base seguimos de una con "Permitir
    // todo el tiempo" (Android lo obliga en dos pasos: el diálogo del sistema
    // no ofrece "Siempre"; hay que pasar por los ajustes). Así el usuario no
    // tiene que descubrir el segundo switch.
    if (p == AppPerm.location && mounted) {
      final st = _state;
      if (st != null && st.location && !st.background) {
        await _activate(AppPerm.background);
      }
    }
  }

  /// Divulgación destacada previa al permiso "Permitir siempre". Devuelve true
  /// si el usuario acepta continuar hacia los ajustes del sistema.
  Future<bool> _backgroundDisclosure() async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElev,
        title: Text('Ubicación en segundo plano',
            style: AppText.archivo(size: 17, weight: FontWeight.w800)),
        content: Text(
          '1of1 recolecta tu ubicación para detectar y registrar tus partidos, '
          'incluso cuando la app está cerrada o no la estás usando. '
          'Solo guardamos en qué cancha jugaste, no tus coordenadas. '
          'En la pantalla que sigue, elegí "Permitir todo el tiempo". '
          'Podés desactivarlo cuando quieras desde el perfil o los ajustes del '
          'sistema.',
          style: AppText.grotesk(size: 13, color: AppColors.white(0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Ahora no',
                style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Permitir',
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.accent)),
          ),
        ],
      ),
    );
    return accept == true;
  }

  // Copy orientado al beneficio: qué ganás con cada permiso y qué perdés sin
  // él, sin jerga técnica ("alarmas exactas", "batería sin restricciones"
  // sonaban agresivos y espantaban en vez de invitar).
  static const _meta = {
    AppPerm.location: (
      Icons.location_on_outlined,
      'Ubicación',
      'Encuentra canchas cerca tuyo y detecta cuándo estás jugando.',
    ),
    AppPerm.background: (
      Icons.share_location,
      'Detección automática',
      'Tus partidos arrancan y se guardan solos al llegar a la cancha, aunque '
          'la app esté cerrada. Sin esto, solo cuentan con la app abierta.',
    ),
    AppPerm.notifications: (
      Icons.notifications_active_outlined,
      'Avisos de partido',
      'Te avisa cuándo arranca y cuándo termina tu partido. Sin esto todo '
          'funciona igual, pero sin avisos.',
    ),
    AppPerm.alarm: (
      Icons.alarm,
      'Arranque puntual',
      'El partido arranca y se cierra justo a tiempo, incluso con el celu '
          'bloqueado. Sin esto puede demorar unos minutos.',
    ),
    AppPerm.battery: (
      Icons.battery_charging_full,
      'Detección estable',
      'Evita que el sistema pause la app en pleno partido. No gasta batería '
          'extra (odiaríamos eso): solo se usa cuando estás en una cancha. '
          'Sin esto, el cronómetro puede congelarse en algunos celus.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final st = _state;
    // SIEMPRE solo lo que falta (también abierto desde el perfil): lo ya
    // concedido desaparece en vez de quedar como fila en verde. La fila de
    // background recién aparece con la ubicación base concedida (sin ella,
    // "Permitir siempre" no existe; además el switch de Ubicación ya encadena
    // hacia "todo el tiempo").
    final pending = st == null
        ? const <AppPerm>[]
        : st.missing
            .where((p) => p != AppPerm.background || st.location)
            .toList();
    return AlertDialog(
      backgroundColor: AppColors.bgElev,
      scrollable: true,
      title: Text('Que todo funcione solo',
          style: AppText.archivo(size: 18, weight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (st == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              ),
            )
          else ...[
            // Con todo concedido, el modal queda como panel de Salud a secas
            // (sin intro de permisos ni cartel de "todo listo").
            if (pending.isNotEmpty) ...[
              Text(
                'Con esto 1of1 arranca, cuenta y guarda tus partidos sin que '
                'toques nada. Activá todo para la mejor experiencia:',
                style: AppText.grotesk(size: 12, color: AppColors.white(0.6)),
              ),
              const SizedBox(height: 12),
              for (final p in pending) _row(p, false),
              Divider(color: AppColors.white(0.08), height: 24),
            ],
            _healthRow(),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('Listo',
              style: AppText.grotesk(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.accent)),
        ),
      ],
    );
  }

  /// Conectar / desconectar Salud (Health Connect). Opcional: no cuenta para
  /// [PermState.allGranted], así que no bloquea el cierre del modal. Solo pide
  /// el permiso al activar (nunca solo). Si ya se concedió antes (incluso a mano
  /// desde Health Connect), al activar no vuelve a preguntar: pasa a Conectado.
  Future<void> _toggleHealth() async {
    if (_busy) return;
    final ps = context.read<PlaySessionService>();
    if (ps.healthEnabled) {
      await ps.disableHealth();
      return;
    }
    setState(() => _busy = true);
    final ok = await ps.enableHealth();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No encontramos Health Connect. Instalalo desde Play Store y '
            'sincronizá tu reloj o anillo para medir tu desempeño.',
            style: AppText.grotesk(size: 13),
          ),
        ),
      );
    }
  }

  /// Corre una lectura de prueba y muestra el resultado, para entender por qué
  /// un partido no trae datos (permiso, sin muestras, o error).
  Future<void> _testHealth() async {
    if (_busy) return;
    setState(() => _busy = true);
    final report = await context.read<PlaySessionService>().diagnoseHealth();
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElev,
        title: Text('Lectura de salud',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(report,
              style: AppText.grotesk(size: 13, color: AppColors.white(0.8))),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cerrar',
                style: AppText.grotesk(size: 13, color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _healthRow() {
    final enabled = context.watch<PlaySessionService>().healthEnabled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.favorite_border,
              size: 22, color: enabled ? AppColors.open : AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Salud',
                        style:
                            AppText.grotesk(size: 13, weight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.white(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('OPCIONAL',
                          style: AppText.grotesk(
                              size: 8,
                              weight: FontWeight.w800,
                              color: AppColors.white(0.5),
                              letterSpacing: 0.2)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Registra calorías, pulso y pasos de tus partidos desde tu '
                  'reloj o anillo. Superar tu récord de calorías suma puntos.',
                  style:
                      AppText.grotesk(size: 11, color: AppColors.white(0.5)),
                ),
                if (enabled) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      PressableWidget(
                        onTap: _busy ? null : _testHealth,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.science_outlined,
                                size: 13, color: AppColors.accent),
                            const SizedBox(width: 4),
                            Text('Probar lectura',
                                style: AppText.grotesk(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: AppColors.accent)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Fallback manual: gestionar los permisos directamente en
                      // Health Connect (por si el diálogo in-app no aparece).
                      PressableWidget(
                        onTap: _busy ? null : openHealthConnect,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new,
                                size: 13, color: AppColors.accent),
                            const SizedBox(width: 4),
                            Text('Health Connect',
                                style: AppText.grotesk(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: AppColors.accent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: enabled,
            onChanged: _busy ? null : (_) => _toggleHealth(),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _row(AppPerm p, bool granted) {
    final (icon, title, why) = _meta[p]!;
    // Batería y background son recomendados, no obligatorios: no bloquean el
    // cierre del modal (ver PermState.allGranted) y lo aclaramos con un badge.
    final recommended = p == AppPerm.battery || p == AppPerm.background;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 22,
              color: granted ? AppColors.open : AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: AppText.grotesk(
                              size: 13, weight: FontWeight.w700)),
                    ),
                    if (recommended) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('RECOMENDADO',
                            style: AppText.grotesk(
                                size: 8,
                                weight: FontWeight.w800,
                                color: AppColors.accent,
                                letterSpacing: 0.2)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(why,
                    style: AppText.grotesk(
                        size: 11, color: AppColors.white(0.5))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // ON solo si el permiso está concedido. Si está OFF, activarlo dispara
          // la solicitud del permiso; ya concedido, queda fijo en ON.
          Switch(
            value: granted,
            onChanged: (granted || _busy) ? null : (_) => _activate(p),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
