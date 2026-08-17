import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

/// Sheet para elegir qué se muestra de un partido — en el detalle Y en la imagen
/// que se comparte en redes.
///
/// Resuelve los DOS niveles de configuración en una sola pantalla: por defecto
/// edita el override de este partido, y con el check del pie guarda lo elegido
/// como default para todos. Tener una sola entrada evita una segunda pantalla de
/// ajustes en el perfil que diría exactamente lo mismo.
///
/// Es escritura local (SharedPreferences), así que va sin loader.
Future<void> showMatchVisibilitySheet(
  BuildContext context,
  PlaySession session,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MatchVisibilitySheet(session: session),
  );
}

class _MatchVisibilitySheet extends StatefulWidget {
  final PlaySession session;
  const _MatchVisibilitySheet({required this.session});

  @override
  State<_MatchVisibilitySheet> createState() => _MatchVisibilitySheetState();
}

class _MatchVisibilitySheetState extends State<_MatchVisibilitySheet> {
  /// Se edita en local y se persiste al confirmar: así "Cancelar" (cerrar el
  /// sheet) no deja cambios a medias.
  late Set<MatchSection> _hidden;
  late bool _hadOverride;
  bool _asDefault = false;

  @override
  void initState() {
    super.initState();
    final play = context.read<PlaySessionService>();
    _hidden = {...play.effectiveHiddenFor(widget.session)};
    _hadOverride = play.hasVisibilityOverride(widget.session);
  }

  /// Si este partido tiene datos para la sección. Las que no, se muestran igual
  /// (con un aviso) porque el mismo sheet puede guardar el default global, donde
  /// sí importan.
  bool _hasData(MatchSection s) => switch (s) {
        MatchSection.stats => widget.session.hasUserStats,
        MatchSection.salud => widget.session.hasHealth,
        MatchSection.desglose => widget.session.isMultiGame,
        _ => true,
      };

  Future<void> _save() async {
    final play = context.read<PlaySessionService>();
    final nav = Navigator.of(context);
    if (_asDefault) {
      await play.setDefaultHiddenSections(_hidden);
      // Se limpia el override: si quedara, este partido dejaría de reflejar los
      // cambios futuros del default que el usuario acaba de pedir.
      await play.setMatchHiddenSections(widget.session, null);
    } else {
      await play.setMatchHiddenSections(widget.session, _hidden);
    }
    nav.pop();
  }

  Future<void> _backToDefault() async {
    final play = context.read<PlaySessionService>();
    final nav = Navigator.of(context);
    await play.setMatchHiddenSections(widget.session, null);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      decoration: const BoxDecoration(
        color: AppColors.bgElev,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Qué se muestra',
                            style: AppText.archivo(
                                size: 18, weight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'Lo que apagues acá no se ve en este resumen ni en la imagen que compartís.',
                          style: AppText.grotesk(
                              size: 12,
                              color: AppColors.white(0.5),
                              height: 1.35),
                        ),
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
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in MatchSection.values) _row(s),
                    const SizedBox(height: 8),
                    // El EXP no es ocultable: siempre queda algo en la tarjeta.
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.white(0.04),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: AppColors.white(0.4)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Los puntos que ganaste siempre se muestran.',
                              style: AppText.grotesk(
                                  size: 12,
                                  color: AppColors.white(0.55),
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _defaultToggle(),
                    if (_hadOverride && !_asDefault) ...[
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: _backToDefault,
                          child: Text(
                            'Volver a mi configuración por defecto',
                            style: AppText.grotesk(
                                size: 12,
                                weight: FontWeight.w600,
                                color: AppColors.accent),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line, width: 1)),
              ),
              child: PressableWidget(
                onTap: _save,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                  ),
                  child: Text('GUARDAR',
                      style: AppText.archivo(
                          size: 14,
                          weight: FontWeight.w800,
                          letterSpacing: 0.04,
                          color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fila de una sección: el switch prendido = visible (más intuitivo que
  /// "oculto", aunque internamente el set guarde lo escondido).
  Widget _row(MatchSection s) {
    final visible = !_hidden.contains(s);
    final sinDatos = !_hasData(s);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label,
                    style: AppText.grotesk(
                        size: 14,
                        weight: FontWeight.w700,
                        color: visible ? Colors.white : AppColors.white(0.45))),
                const SizedBox(height: 1),
                Text(
                  sinDatos ? 'Sin datos en este partido' : s.hint,
                  style: AppText.grotesk(
                    size: 11,
                    color: sinDatos
                        ? AppColors.white(0.3)
                        : AppColors.white(0.45),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: visible,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
            onChanged: (v) => setState(() {
              if (v) {
                _hidden.remove(s);
              } else {
                _hidden.add(s);
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _defaultToggle() {
    return PressableWidget(
      onTap: () => setState(() => _asDefault = !_asDefault),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _asDefault
              ? AppColors.accent.withAlpha(20)
              : AppColors.white(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _asDefault ? AppColors.accent : AppColors.white(0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _asDefault
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: _asDefault ? AppColors.accent : AppColors.white(0.4),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Usar en todos mis partidos',
                      style: AppText.grotesk(
                          size: 13, weight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(
                    'También en los próximos. Los que configuraste aparte no cambian.',
                    style: AppText.grotesk(
                        size: 11, color: AppColors.white(0.45), height: 1.3),
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
