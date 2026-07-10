import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_permissions.dart';
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
    setState(() => _busy = true);
    await requestPerm(p);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  static const _meta = {
    AppPerm.location: (
      Icons.location_on_outlined,
      'Ubicación',
      'Detecta las canchas cercanas, te ubica en el mapa y cuenta tu partido.',
    ),
    AppPerm.notifications: (
      Icons.notifications_active_outlined,
      'Notificaciones',
      'Te avisa cuándo arranca y cuándo termina tu partido.',
    ),
    AppPerm.alarm: (
      Icons.alarm,
      'Alarmas exactas',
      'Arranca y cierra tu partido solo, aunque tengas la app cerrada.',
    ),
    AppPerm.battery: (
      Icons.battery_charging_full,
      'Batería sin restricciones',
      'Evita que el sistema congele la app en pleno partido. Sin esto tu '
          'partido no se pierde, pero el cronómetro puede dejar de verse en vivo.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final st = _state;
    return AlertDialog(
      backgroundColor: AppColors.bgElev,
      scrollable: true,
      title: Text('Permisos necesarios',
          style: AppText.archivo(size: 18, weight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Para que 1of1 detecte y registre tus partidos correctamente, '
            'necesita estos permisos:',
            style: AppText.grotesk(size: 12, color: AppColors.white(0.6)),
          ),
          const SizedBox(height: 12),
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
            for (final p in AppPerm.values) _row(p, !st.missing.contains(p)),
            Divider(color: AppColors.white(0.08), height: 24),
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
    // La batería es recomendada, no obligatoria: no bloquea el cierre del modal
    // (ver PermState.allGranted) y lo aclaramos con un badge.
    final recommended = p == AppPerm.battery;
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
