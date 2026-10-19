import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/achievements.dart';
import '../data/courts.dart';
import '../services/analytics_service.dart';
import '../services/cache/court_image_cache.dart';
import '../services/courts_provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/court_image.dart';
import '../widgets/form_style.dart';
import '../widgets/match_visibility_sheet.dart';
import '../widgets/pressable_widget.dart';

class MatchDetailScreen extends StatefulWidget {
  final PlaySession session;
  final ValueChanged<String>? onSelectCourt;
  const MatchDetailScreen({super.key, required this.session, this.onSelectCourt});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  ValueChanged<String>? get onSelectCourt => widget.onSelectCourt;

  /// Mientras se arma la imagen para compartir (precarga de la foto + captura),
  /// el botón muestra un loader y no acepta otro toque: tarda un par de segundos
  /// y sin feedback se tocaba dos veces y salían dos share sheets.
  bool _sharing = false;

  /// Versión más fresca del partido: si la re-lectura de salud actualizó el
  /// historial (los datos del reloj llegan tarde a Health Connect), usamos esa
  /// entrada; si no, el snapshot recibido.
  PlaySession get session {
    for (final e in context.read<PlaySessionService>().log) {
      if (e.endedAtMillis == widget.session.endedAtMillis &&
          e.courtId == widget.session.courtId) {
        return e;
      }
    }
    return widget.session;
  }

  @override
  void initState() {
    super.initState();
    // Partido sin datos de salud: reintentar la lectura ahora (Health Connect
    // puede haber sincronizado el reloj después de resolverse el resultado).
    unawaited(
        context.read<PlaySessionService>().refreshHealthFor(widget.session));
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild cuando la re-lectura de salud actualiza el historial.
    context.watch<PlaySessionService>();
    final s = session;
    final courts = context.read<CourtsProvider>().courts;
    Court? court;
    for (final c in courts) {
      if (c.id == s.courtId) {
        court = c;
        break;
      }
    }
    final (color, label) = _resultStyle(s.displayResult);
    final ended = DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis);
    // Qué ocultó el usuario (el override de este partido, o su default). La
    // precedencia la resuelve el servicio: acá solo se consulta.
    final hidden = context.read<PlaySessionService>().effectiveHiddenFor(s);
    // Null si ocultó duración Y horario: sin items la franja quedaría como una
    // caja vacía con bordes.
    final statStrip = _statStrip(s, ended, hidden);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient sutil de fondo.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bg, Color(0xFF0D0D0D), AppColors.bg],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // AppBar custom.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      PressableWidget(
                        onTap: () => Navigator.pop(context),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.arrow_back_ios_new, size: 20),
                        ),
                      ),
                      const Spacer(),
                      Text('Resumen',
                          style: AppText.grotesk(
                              size: 14, weight: FontWeight.w600, color: AppColors.white(0.6))),
                      const Spacer(),
                      // Qué se muestra de este partido (y de la imagen que se
                      // comparte). Ocupa el hueco que balanceaba el título.
                      PressableWidget(
                        onTap: () => showMatchVisibilitySheet(context, s),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.tune_rounded,
                              size: 20, color: AppColors.white(0.7)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Contenido scrollable.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        // Hero: imagen de la cancha con el resultado y el nombre.
                        // Si ocultó la cancha pero no el resultado, este último
                        // necesita su propia fila (vive DENTRO del hero, que es
                        // la foto de la cancha).
                        if (!hidden.contains(MatchSection.ubicacion))
                          _heroBanner(court, s, color, label,
                              showResult:
                                  !hidden.contains(MatchSection.resultado))
                        else if (!hidden.contains(MatchSection.resultado))
                          _resultOnlyBanner(color, label, s),
                        if (!hidden.contains(MatchSection.ubicacion) ||
                            !hidden.contains(MatchSection.resultado))
                          const SizedBox(height: 22),
                        // Puntos protagonista. Nunca se oculta: es lo que
                        // garantiza que el resumen no quede vacío.
                        _pointsHero(s),
                        // Franja de stats (duración · fecha · hora).
                        if (statStrip != null) ...[
                          const SizedBox(height: 22),
                          statStrip,
                        ],
                        if (s.hasFormats &&
                            !hidden.contains(MatchSection.duracion)) ...[
                          const SizedBox(height: 22),
                          _formatRow(s),
                        ],
                        // Desglose de la sesión (varios partidos).
                        if (s.isMultiGame &&
                            !hidden.contains(MatchSection.desglose)) ...[
                          const SizedBox(height: 22),
                          _sessionBreakdown(s),
                        ],
                        // Lo que anotó el usuario (total + desglose 3PT/2PT/TL).
                        if (s.hasUserStats &&
                            !(hidden.contains(MatchSection.puntuacion) &&
                                hidden.contains(
                                    MatchSection.desglosePuntos))) ...[
                          const SizedBox(height: 22),
                          _userStatsSection(
                            s,
                            verTotal:
                                !hidden.contains(MatchSection.puntuacion),
                            verDesglose:
                                !hidden.contains(MatchSection.desglosePuntos),
                          ),
                        ],
                        // Salud (todas las métricas disponibles). Mientras
                        // se procesa NO se muestra nada: media franja de datos
                        // junto al cartel de "procesando" se lee como un bug.
                        if (s.hasHealth &&
                            !s.healthPending &&
                            !hidden.contains(MatchSection.salud)) ...[
                          const SizedBox(height: 22),
                          _healthStrip(s),
                        ],
                        // Estado de la sincronización: "procesando" mientras el
                        // reloj todavía puede volcar los datos, y el aviso de
                        // que no llegaron cuando esa ventana venció.
                        if (!hidden.contains(MatchSection.salud) &&
                            s.healthPending) ...[
                          const SizedBox(height: 14),
                          _healthPendingNotice(s),
                        ],
                        // El diagnóstico aparece aunque HAYA datos: el caso
                        // más común es tenerlos incompletos (pasos del teléfono
                        // y nada del reloj), y ahí es cuando más falta hace saber
                        // de dónde vino cada número. Pero no mientras se procesa:
                        // preguntar "¿por qué no aparecen?" debajo de un cartel
                        // que dice que están llegando es contradictorio.
                        if (!hidden.contains(MatchSection.salud) &&
                            !s.healthPending) ...[
                          const SizedBox(height: 14),
                          _healthDiagnoseLink(s),
                        ],
                        const SizedBox(height: 24),
                        _brandFooter(),
                      ],
                    ),
                  ),
                ),
                // Botones inferiores.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      24, 0, 24, 16 + MediaQuery.of(context).viewPadding.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _shareButton(context),
                      const SizedBox(height: 10),
                      if (court != null) _courtButton(context, court),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hero: imagen de la cancha a ancho completo con degradado; el resultado como
  /// chip arriba-izquierda y el nombre/zona sobre la imagen abajo.
  Widget _heroBanner(Court? court, PlaySession s, Color color, String label,
      {bool showResult = true}) {
    final name = court?.name ?? (s.courtName.isEmpty ? 'Cancha' : s.courtName);
    final sub = court == null
        ? ''
        : dotJoin([court.area, court.type]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppShape.rCard),
      child: Stack(
        children: [
          CourtImage(
            url: court?.img ?? '',
            width: double.infinity,
            height: 250,
            borderRadius: BorderRadius.zero,
          ),
          // Misma receta que la imagen para compartir: máscara pareja para que
          // el texto se lea y degradé a negro desde ~40% de la altura.
          Positioned.fill(
              child: ColoredBox(color: Colors.black.withAlpha(110))),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(0),
                    Colors.black.withAlpha(215),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),
          // Resultado: plano y editorial, barrita de acento a la izquierda.
          if (showResult)
            Positioned(
              top: 18,
              left: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(width: 5, height: 26, color: color),
                  const SizedBox(width: 10),
                  Text(label,
                      style: AppText.display(
                          size: 26,
                          weight: FontWeight.w900,
                          color: color,
                          letterSpacing: 0.2,
                          shadows: _kSoftShadow)),
                  if (_scoreLabel(s).isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(_scoreLabel(s),
                        style: AppText.archivo(
                            size: 18,
                            weight: FontWeight.w800,
                            color: Colors.white.withAlpha(220),
                            shadows: _kSoftShadow)),
                  ],
                ],
              ),
            ),
          // Nombre + zona.
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(
                        size: 40,
                        weight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.05,
                        shadows: _kSoftShadow)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(sub,
                      style: AppText.grotesk(
                          size: 16,
                          weight: FontWeight.w600,
                          color: Colors.white.withAlpha(225),
                          shadows: _kSoftShadow)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Resultado sin la foto de la cancha, para cuando ocultó la ubicación pero no
  /// el resultado (que normalmente vive dentro del hero).
  Widget _resultOnlyBanner(Color color, String label, PlaySession s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 14, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: AppText.archivo(
                  size: 12,
                  weight: FontWeight.w900,
                  color: color,
                  letterSpacing: 0.2)),
          if (_scoreLabel(s).isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(_scoreLabel(s),
                style: AppText.archivo(
                    size: 12,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.55))),
          ],
        ],
      ),
    );
  }

  /// Acceso al diagnóstico de salud de ESTE partido. Aparece solo cuando no hubo
  /// datos: es la diferencia entre "el reloj no sincronizó" y "la app no leyó".
  /// "Procesando datos de salud…": el reloj vuelca a Health Connect con retraso,
  /// así que un partido recién terminado casi siempre llega incompleto. El
  /// spinner aparece solo mientras hay una lectura EN VUELO, para no dejar una
  /// animación eterna girando sobre algo que no está pasando.
  Widget _healthPendingNotice(PlaySession s) {
    final leyendo = context.watch<PlaySessionService>().isRefreshingHealth(s);
    // Sin caja tintada: barra de acento a la izquierda (el mismo recurso que las
    // opciones de resultado), titular en Anton y una linea fina que se convierte
    // en barra de progreso solo mientras se esta leyendo de verdad.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hairline(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 3, height: 36, color: AppColors.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ESPERANDO AL RELOJ',
                        style: AppText.display(
                          size: 21,
                          color: AppColors.accent,
                          letterSpacing: -0.01,
                          height: 1.0,
                          shadows: AppFx.accentGlow(),
                        )),
                    const SizedBox(height: 7),
                    Text(
                      'Sincroniza sus datos después de la sesión. '
                      'Volvé a entrar y van a estar acá.',
                      style: AppText.grotesk(
                          size: 11.5,
                          color: AppColors.white(0.45),
                          height: 1.4),
                    ),
                    const SizedBox(height: 5),
                    // Expectativa explícita: sin esto, el usuario vuelve a los
                    // dos minutos, no ve nada y cree que está roto. Cuándo llega
                    // depende del reloj (muchos vuelcan recién al cargarlos o al
                    // abrir su app), así que no prometemos un número.
                    Text(
                      'Puede tardar un rato: algunos relojes vuelcan los datos '
                      'recién al cargarlos o al abrir su app.',
                      style: AppText.grotesk(
                          size: 11,
                          color: AppColors.white(0.32),
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: leyendo
              ? LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: AppColors.white(0.06),
                  color: AppColors.accent,
                )
              : hairline(),
        ),
      ],
    );
  }

  Widget _healthDiagnoseLink(PlaySession s) {
    // El texto describe el problema real de cada caso: sin nada, con datos que
    // no vinieron del reloj, o todo en orden (ahí es solo curiosidad).
    final label = s.healthMissing && !s.hasHealth
        ? 'No llegaron datos del reloj · ver por qué'
        : (!s.hasHealth
            ? '¿Por qué no hay datos de salud?'
            : (!s.fromWearable
                ? '¿Por qué no aparecen los datos del reloj?'
                : 'Ver de dónde vienen estos datos'));
    return PressableWidget(
      onTap: () => _showHealthDiagnose(s),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white(0.04),
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        child: Row(
          children: [
            Icon(Icons.help_outline, size: 16, color: AppColors.white(0.4)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: AppText.grotesk(
                      size: 12.5, color: AppColors.white(0.6))),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.3)),
          ],
        ),
      ),
    );
  }

  Future<void> _showHealthDiagnose(PlaySession s) async {
    final play = context.read<PlaySessionService>();
    final report = await runBusy(
      context,
      () => play.diagnoseHealthForSession(s),
    );
    if (report == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElev,
        title: Text('Lectura de salud',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(report,
              style: AppText.grotesk(size: 12, color: AppColors.white(0.8))),
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

  /// Desglose de una sesión con varios partidos: cuántos se jugaron, cuántos se
  /// ganaron y cuántos entrenamientos hubo, más los puntos de cada partido si se
  /// cargaron.
  Widget _sessionBreakdown(PlaySession s) {
    // El entrenamiento NO va en la misma fila que partidos/victorias: parecía
    // uno más de los partidos y la puntuación se leía como si lo incluyera.
    final items = <(String, String)>[
      if (s.gamesPlayed > 0) ('PARTIDOS', '${s.gamesPlayed}'),
      if (s.gamesPlayed > 0) ('VICTORIAS', '${s.winsCount}'),
    ];
    final trainings = s.trainingsDone;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Column(
        children: [
          if (items.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) _vDivider(),
                  Expanded(child: _inlineStat(items[i].$1, items[i].$2)),
                ],
              ],
            ),
          // Puntos partido por partido (solo si los cargó).
          if (s.hasGamePoints) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.white(0.08)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                for (var i = 0; i < s.gamePoints!.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.white(0.05),
                      borderRadius: BorderRadius.circular(AppShape.rChip),
                    ),
                    child: Text(
                      'P${i + 1}  ${s.gamePoints![i]}'
                      '${(s.gameFormats?.length ?? 0) > i ? '  ·  ${s.gameFormats![i]}v${s.gameFormats![i]}' : ''}',
                      style: AppText.grotesk(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.white(0.75)),
                    ),
                  ),
              ],
            ),
          ],
          // Entrenamientos: debajo de los partidos, aclarando que no suman.
          if (trainings > 0) ...[
            if (items.isNotEmpty) const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.white(0.05),
                borderRadius: BorderRadius.circular(AppShape.rChip),
                border: Border.all(color: AppColors.white(0.12)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fitness_center,
                      size: 14, color: AppColors.white(0.6)),
                  const SizedBox(width: 8),
                  Text(
                      '+ $trainings ${trainings == 1 ? 'entrenamiento' : 'entrenamientos'}',
                      style: AppText.grotesk(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: AppColors.white(0.85))),
                  Text(
                      '  ·  no ${trainings == 1 ? 'suma' : 'suman'} puntos',
                      style: AppText.grotesk(
                          size: 12.5, color: AppColors.white(0.5))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Puntos protagonista del partido.
  Widget _pointsHero(PlaySession s) {
    final has = s.points > 0;
    return Column(
      children: [
        Text(has ? '+${s.points}' : '—',
            style: AppText.display(
                size: 64,
                weight: FontWeight.w900,
                height: 1.0,
                color: has ? AppColors.accent : AppColors.white(0.4))),
        const SizedBox(height: 4),
        Text('EXP GANADA',
            style: AppText.archivo(
                size: 12,
                weight: FontWeight.w800,
                color: AppColors.white(0.6),
                letterSpacing: 0.14)),
      ],
    );
  }

  /// Franja única con duración · fecha · hora, separadas por líneas finas.
  ///
  /// Los items se arman según lo que el usuario dejó visible (duración y horario
  /// son toggles distintos) y los divisores se intercalan después, así no queda
  /// una línea colgando de un borde. Devuelve **null** si no sobrevivió ningún
  /// item: la franja vacía sería una caja con bordes y nada adentro.
  Widget? _statStrip(PlaySession s, DateTime ended, Set<MatchSection> hidden) {
    final items = <Widget>[
      if (!hidden.contains(MatchSection.duracion))
        _inlineStat('DURACIÓN', PlaySessionService.fmt(s.seconds)),
      if (!hidden.contains(MatchSection.horario)) ...[
        _inlineStat('FECHA', _fmtDate(ended)),
        _inlineStat('HORA',
            '${ended.hour.toString().padLeft(2, '0')}:${ended.minute.toString().padLeft(2, '0')}'),
      ],
    ];
    if (items.isEmpty) return null;

    final row = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) row.add(_vDivider());
      row.add(Expanded(child: items[i]));
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Row(children: row),
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 30, color: AppColors.white(0.1));

  /// Lo que anotó el usuario en "¿Cómo te fue?": total de puntos + desglose por
  /// valor de tiro. Distinto de los "PUNTOS GANADOS" que otorga la app.
  ///
  /// [verTotal] y [verDesglose] son toggles independientes (el usuario puede
  /// querer publicar cuánto metió sin abrir de dónde vino).
  Widget _userStatsSection(PlaySession s,
      {bool verTotal = true, bool verDesglose = true}) {
    final pts = verTotal ? (s.userPoints ?? 0) : 0;
    // Métricas desde la fuente única (compartida con la imagen, no se desincroniza).
    final items = verDesglose ? _userStatItems(s) : const [];

    // Filas de "planilla": etiqueta a la izquierda, valor a la derecha, con una
    // línea fina entre cada una. Texto plano, sin cajas ni divisores verticales.
    final lines = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        lines.add(Divider(height: 1, thickness: 1, color: AppColors.white(0.05)));
      }
      lines.add(_statLine(items[i].label, items[i].value));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_basketball, size: 13, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('PUNTUACIÓN EN PARTIDOS',
                  style: AppText.archivo(
                      size: 12,
                      weight: FontWeight.w800,
                      color: AppColors.white(0.65),
                      letterSpacing: 0.1)),
              if (pts > 0) ...[
                const Spacer(),
                Text('$pts',
                    style: AppText.display(
                        size: 40,
                        weight: FontWeight.w900,
                        height: 1.0,
                        color: AppColors.accent)),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('PTS',
                      style: AppText.grotesk(
                          size: 10,
                          weight: FontWeight.w700,
                          color: AppColors.white(0.4))),
                ),
              ],
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...lines,
          ],
        ],
      ),
    );
  }

  /// Fila de planilla: nombre de la métrica a la izquierda (tenue), valor a la
  /// derecha (blanco, destacado). Lectura tipo lista, no columnas apretadas.
  Widget _statLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.white(0.6))),
          ),
          Text(value,
              style: AppText.archivo(size: 17, weight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _inlineStat(String label, String value) {
    return Column(
      children: [
        // scaleDown: antes la fecha se cortaba con "…" ("13/10/20...").
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              maxLines: 1,
              style: AppText.display(size: 24, weight: FontWeight.w900)),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: AppText.archivo(
                size: 11,
                weight: FontWeight.w800,
                color: AppColors.white(0.55),
                letterSpacing: 0.1)),
      ],
    );
  }

  /// Formato jugado: una pastilla "4 VS 4" por formato (sin comas), igual que
  /// en la imagen para compartir pero a menor escala.
  Widget _formatRow(PlaySession s) {
    return Column(
      children: [
        Text('FORMATO',
            style: AppText.archivo(
                size: 11,
                weight: FontWeight.w800,
                color: AppColors.white(0.55),
                letterSpacing: 0.1)),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final n in s.formatList) _vsPill(n, scale: 0.62),
          ],
        ),
      ],
    );
  }

  /// "Tu estado": todas las métricas de salud disponibles, como chips.
  Widget _healthStrip(PlaySession s) {
    // Métricas planas con color por tipo (sin cajas grises). Solo las que tienen
    // dato: lo que esté en 0/null no aparece.
    final metrics = <Widget>[
      // El "~" y el sufijo "est." marcan lo que calculamos nosotros a partir de
      // los pasos (con un peso fijo), no lo que midió el reloj. Sin eso, un
      // récord de calorías podía ser de un número inventado.
      if (s.calories > 0)
        _healthMetric(
            Icons.local_fire_department,
            const Color(0xFFFF6B1A),
            '${s.caloriesEstimated ? '~' : ''}${s.calories.round()}',
            s.caloriesEstimated ? 'kcal est.' : 'kcal'),
      if (s.steps > 0)
        _healthMetric(Icons.directions_walk, const Color(0xFF22C55E),
            '${s.steps}', 'pasos'),
      // Minutos en zona alta (≥70% del pulso máximo): refleja cuánto jugaste
      // fuerte, que el promedio de la sesión no muestra (lo diluyen las esperas).
      if (intenseMinutes(s) != null)
        _healthMetric(Icons.local_fire_department_outlined,
            const Color(0xFFF97316), '${intenseMinutes(s)}', 'min intensos'),
      if (s.maxHr != null && s.maxHr! > 0)
        _healthMetric(
            Icons.monitor_heart, const Color(0xFFF43F5E), '${s.maxHr}', 'bpm máx'),
      if (s.avgHr != null)
        _healthMetric(
            Icons.favorite, const Color(0xFFEF4444), '${s.avgHr}', 'bpm prom.'),
      if (s.distance > 0)
        _healthMetric(
            Icons.straighten,
            const Color(0xFF3B82F6),
            '${s.distanceEstimated ? '~' : ''}'
                '${s.distance >= 1000 ? (s.distance / 1000).toStringAsFixed(2) : s.distance.round()}',
            '${s.distance >= 1000 ? 'km' : 'm'}${s.distanceEstimated ? ' est.' : ''}'),
      // Oxígeno, pulso en reposo, HRV, respiración y velocidad ya no se
      // muestran: las primeras son mediciones diarias o esporádicas del reloj
      // (no de la sesión) y la velocidad promediaba caminar entre partidos con
      // correr. Se siguen guardando, por si un día se les da contexto.
    ];
    final hasZones = s.hrZones != null &&
        s.hrZones!.any((z) => z > 0);
    final calorieRecord = context.read<PlaySessionService>().calorieRecord;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 13, color: AppColors.accent),
            const SizedBox(width: 6),
            Text('ESTADO',
                style: AppText.grotesk(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.5),
                    letterSpacing: 0.12)),
            // Sin señal de reloj (no hay pulso ni sesión), estos números salen
            // del teléfono: decirlo evita que un dato bajo se lea como propio.
            if (!s.fromWearable) ...[
              const SizedBox(width: 6),
              Text('· del teléfono',
                  style: AppText.grotesk(
                      size: 10, color: AppColors.white(0.35))),
            ],
            if (s.calorieRecord) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kGold.withAlpha(38),
                  borderRadius: BorderRadius.circular(AppShape.rChip),
                  border: Border.all(color: kGold),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 11, color: kGold),
                    const SizedBox(width: 3),
                    Text('RÉCORD',
                        style: AppText.grotesk(
                            size: 8.5, weight: FontWeight.w800, color: kGold)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // Donut de zonas cardíacas + gauge de calorías (si hay datos).
        if (hasZones || s.calories > 0) ...[
          Row(
            children: [
              if (hasZones) Expanded(child: _hrZoneDonut(s.hrZones!)),
              if (hasZones && s.calories > 0) const SizedBox(width: 16),
              if (s.calories > 0)
                Expanded(
                    child: _calorieGauge(s.calories, calorieRecord)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // Centradas. El SizedBox de ancho infinito es imprescindible: la Column
        // usa crossAxisAlignment.start, así que sin él el Wrap se encoge al
        // ancho de su contenido y `WrapAlignment.center` no centra nada.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 22,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: metrics,
          ),
        ),
      ],
    );
  }

  /// Donut chart de zonas cardíacas: muestra distribución de intensidad.
  static const _zoneColors = [
    Color(0xFF22C55E), // Calentamiento (verde)
    Color(0xFFEAB308), // Quema de grasa (amarillo)
    Color(0xFFF97316), // Cardio (naranja)
    Color(0xFFEF4444), // Pico (rojo)
    Color(0xFF991B1B), // Máximo (rojo oscuro)
  ];
  static const _zoneLabels = ['Calentamiento', 'Quema', 'Cardio', 'Pico', 'Máximo'];

  Widget _hrZoneDonut(List<int> zones) {
    final total = zones.fold(0, (s, z) => s + z);
    if (total == 0) return const SizedBox.shrink();

    final sections = List.generate(5, (i) {
      final pct = zones[i] / total * 100;
      return PieChartSectionData(
        value: zones[i].toDouble(),
        color: _zoneColors[i],
        radius: 14,
        title: pct >= 8 ? '${pct.round()}%' : '',
        titleStyle: AppText.grotesk(
            size: 9, weight: FontWeight.w700, color: Colors.white),
        titlePositionPercentageOffset: 0.55,
      );
    });

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 28,
              sectionsSpace: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Leyenda compacta
        Wrap(
          spacing: 8,
          runSpacing: 2,
          children: List.generate(5, (i) {
            if (zones[i] == 0) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: _zoneColors[i], shape: BoxShape.circle)),
                const SizedBox(width: 3),
                Text(_zoneLabels[i],
                    style: AppText.grotesk(
                        size: 8, color: AppColors.white(0.5))),
              ],
            );
          }),
        ),
      ],
    );
  }

  /// Gauge de calorías: arco que muestra calorías vs récord personal.
  Widget _calorieGauge(double calories, double record) {
    final pct = record > 0 ? (calories / record).clamp(0.0, 1.0) : 0.0;
    final color = pct >= 1.0
        ? kGold
        : (pct >= 0.7
            ? AppColors.accent
            : AppColors.white(0.4));

    return Column(
      children: [
        SizedBox(
          height: 100,
          width: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 80,
                width: 80,
                child: CircularProgressIndicator(
                  value: pct > 0 ? pct : 0.001,
                  strokeWidth: 8,
                  backgroundColor: AppColors.white(0.08),
                  valueColor: AlwaysStoppedAnimation(color),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${calories.round()}',
                      style: AppText.archivo(
                          size: 22,
                          weight: FontWeight.w900,
                          color: color)),
                  Text('kcal',
                      style: AppText.grotesk(
                          size: 9, color: AppColors.white(0.4))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(record > 0 ? 'Récord: ${record.round()}' : 'Sin récord',
            style: AppText.grotesk(size: 8, color: AppColors.white(0.4))),
      ],
    );
  }

  /// Métrica de salud plana (sin caja): ícono a color + valor + unidad chica.
  Widget _healthMetric(IconData icon, Color color, String value, String unit) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(value,
            style: AppText.archivo(
                size: 17, weight: FontWeight.w900, color: AppColors.ink)),
        const SizedBox(width: 3),
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Text(unit,
              style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
        ),
      ],
    );
  }

  Widget _brandFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.white(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(width: 10),
              const AppLogo(height: 22),
              const SizedBox(width: 10),
              Container(
                width: 24,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.white(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Estadísticas provistas por 1of1',
              style: AppText.grotesk(
                  size: 9.5,
                  weight: FontWeight.w500,
                  color: AppColors.white(0.3),
                  letterSpacing: 0.06)),
        ],
      ),
    );
  }

  Widget _shareButton(BuildContext context) {
    return PressableWidget(
      onTap: _sharing ? null : () => _captureAndShare(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_sharing)
              const BusySpinner(size: 16, color: AppColors.ink)
            else
              const Icon(Icons.camera_alt_outlined,
                  size: 16, color: AppColors.ink),
            const SizedBox(width: 8),
            Text(_sharing ? 'GENERANDO IMAGEN…' : 'COMPARTIR RESULTADO',
                style: AppText.archivo(
                    size: 12,
                    weight: FontWeight.w800,
                    letterSpacing: 0.04,
                    color: AppColors.ink)),
          ],
        ),
      ),
    );
  }

  Widget _courtButton(BuildContext context, Court court) {
    return PressableWidget(
      onTap: () {
        Navigator.pop(context);
        onSelectCourt?.call(court.id);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.line, width: 1),
        ),
        child: Text('Ver cancha',
            textAlign: TextAlign.center,
            style: AppText.grotesk(
                size: 12.5, weight: FontWeight.w600, color: AppColors.white(0.7))),
      ),
    );
  }

  Future<void> _captureAndShare(BuildContext context) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await _generateAndShare(context);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _generateAndShare(BuildContext context) async {
    // Crear un widget replicable para captura.
    final key = GlobalKey();
    final s = session;
    final courts = context.read<CourtsProvider>().courts;
    Court? court;
    for (final c in courts) {
      if (c.id == s.courtId) {
        court = c;
        break;
      }
    }
    // Mismo criterio que la pantalla y el historial: con varios partidos
    // cargados manda el marcador (ver PlaySession.displayResult).
    final (color, label) = _resultStyle(s.displayResult);
    final ended = DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis);
    // La tarjeta respeta lo mismo que la pantalla: lo que el usuario ve es
    // exactamente lo que publica.
    final hidden = context.read<PlaySessionService>().effectiveHiddenFor(s);

    // Foto de fondo: se precarga ANTES de capturar. Con la espera fija de más
    // abajo, en red lenta el PNG saldría con el placeholder de carga. Si la
    // oculta el usuario (la foto delata el lugar, así que "Cancha y zona" también
    // la saca), no tiene URL o no llega a tiempo, la tarjeta queda con el fondo
    // oscuro de siempre: compartir nunca falla por esto.
    ImageProvider? background;
    final photoUrl = court?.img ?? '';
    if (photoUrl.isNotEmpty &&
        !hidden.contains(MatchSection.fondo) &&
        !hidden.contains(MatchSection.ubicacion)) {
      try {
        // Mismo caché en disco que CourtImage: si la foto ya se vio, sale del
        // celu sin volver a bajarla.
        final provider = CachedNetworkImageProvider(photoUrl,
            cacheManager: courtImageCache);
        await precacheImage(provider, context)
            .timeout(const Duration(seconds: 6));
        background = provider;
      } catch (_) {
        background = null;
      }
    }
    if (!context.mounted) return;

    // Overlay temporal FUERA de pantalla (left: -3000) para renderizar la
    // tarjeta 1080×1920 sin que el usuario la vea. El RepaintBoundary con [key]
    // es lo que se captura (antes faltaba y el cast a RenderRepaintBoundary
    // tiraba, con lo que el compartir fallaba en silencio).
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -3000,
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(
            key: key,
            child: _ShareCard(
              session: s,
              court: court,
              color: color,
              label: label,
              ended: ended,
              hidden: hidden,
              background: background,
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    // Esperar a que se renderice (dos frames para asegurar el layout).
    await Future.delayed(const Duration(milliseconds: 250));

    try {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // La tarjeta ya es 1080×1920: pixelRatio 1 alcanza para una story nítida.
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      // Un archivo por partido: con un nombre fijo, compartir dos partidos
      // seguidos mandaba la imagen del anterior (varias apps del share sheet
      // leen el archivo DESPUÉS de que el sheet volvió).
      final file = File('${dir.path}/match_${s.endedAtMillis}.png');
      await file.writeAsBytes(buffer);

      entry.remove();
      if (mounted) setState(() => _sharing = false);

      final shared = await Share.shareXFiles(
        [XFile(file.path)],
        text: '¡Resultado en 1of1! 🏀',
      );
      AnalyticsService.share('session_result', {
        'status': shared.status.name, // success / dismissed / unavailable
        'has_photo': background != null,
        'result': s.displayResult?.name,
        'games': s.gamesPlayed,
      });
    } catch (e) {
      entry.remove();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar la imagen para compartir.',
                style: AppText.grotesk(size: 13)),
            backgroundColor: AppColors.bgElev,
          ),
        );
      }
    }
  }

  static (Color, String) _resultStyle(PlayResult? r) {
    switch (r) {
      case PlayResult.win:
        return (AppColors.open, 'VICTORIA');
      case PlayResult.loss:
        return (AppColors.accentDark, 'DERROTA');
      case PlayResult.tie:
        return (AppColors.white(0.7), 'EMPATE');
      case PlayResult.training:
        return (AppColors.accent, 'ENTRENAMIENTO');
      case PlayResult.notCounted:
      case null:
        return (AppColors.white(0.4), 'SIN INFO');
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Marcador de la sesión ("2-1") cuando tuvo más de un partido; vacío si no.
///
/// Acompaña SIEMPRE al resultado: con varios partidos, un "VICTORIA" solo no
/// dice de dónde salió. Las perdidas se infieren como `partidos - ganadas`, por
/// la misma razón que en [PlaySession.displayResult]: el desglose no registra
/// empates por partido.
String _scoreLabel(PlaySession s) =>
    (s.isMultiGame && s.gamesPlayed >= 2)
        ? '${s.winsCount}-${s.gamesPlayed - s.winsCount}'
        : '';

/// Métricas derivadas de lo que anotó el usuario. FUENTE ÚNICA: la usan tanto el
/// registro en pantalla como la imagen de compartir, así las dos SIEMPRE muestran
/// lo mismo.
///
/// El desglose se cuenta por VALOR del tiro (puntos de 1, de 2 y de 3) y no por
/// "tiro libre / doble / triple", porque los tiros valen distinto según la
/// modalidad: en 3x3 un tiro de larga distancia vale 2, no 3.
///
/// Por eso ya no existe "Canastas" (canastas de campo = todo menos tiros libres):
/// con esta semántica un tiro de 1 punto puede ser perfectamente una canasta de
/// campo, así que la distinción era falsa.
List<({String label, String value})> _userStatItems(PlaySession s) {
  final pts = s.userPoints ?? 0;
  final p3 = s.userPts3 ?? 0;
  final p2 = s.userPts2 ?? 0;
  final p1 = s.userPts1 ?? 0;
  final madeShots = p3 + p2 + p1;
  // Puntos por tiro anotado (eficiencia) y qué parte del puntaje salió de los
  // tiros de 3. Ninguna de las dos depende del TIEMPO, que es lo que las hace
  // válidas para una sesión.
  final perShot = (pts > 0 && madeShots > 0) ? pts / madeShots : null;
  final threeShare = (pts > 0 && p3 > 0) ? (p3 * 3 / pts * 100).round() : null;

  // ── Métricas que SOLO tienen sentido con varios partidos ──────────────────
  // Una sesión es una estadía en la cancha, con esperas y descansos entre
  // partidos: por eso NO hay "puntos por minuto" (4 puntos en 3 horas de estadía
  // daba 0.0, un número que no dice nada de cómo se jugó). Lo que sí se puede
  // comparar es PARTIDO contra partido, y eso no se diluye con el tiempo muerto.
  final games = s.gamesPlayed;
  final multi = s.isMultiGame && games >= 2;
  final perGame = (pts > 0 && multi) ? pts / games : null;
  final best = (multi && s.hasGamePoints && s.gamePoints!.length >= 2)
      ? s.gamePoints!.reduce((a, b) => a > b ? a : b)
      : null;
  // Va en esta tarjeta y no en la fila PARTIDOS/VICTORIAS/ENTRENAM.: en la
  // imagen para compartir esa fila no se ajusta y una cuarta etiqueta de 30 px
  // se desbordaría. Solo si hay puntuación cargada, para no dejar la tarjeta
  // "PUNTUACIÓN" mostrando únicamente victorias.
  final winRate = (multi && (pts > 0 || madeShots > 0))
      ? (s.winsCount / games * 100).round()
      : null;

  return [
    if (p3 > 0) (label: 'Puntos de 3', value: '$p3'),
    if (p2 > 0) (label: 'Puntos de 2', value: '$p2'),
    if (p1 > 0) (label: 'Puntos de 1', value: '$p1'),
    if (madeShots > 0) (label: 'Tiros anotados', value: '$madeShots'),
    if (perGame != null)
      (label: 'Puntos por partido', value: perGame.toStringAsFixed(1)),
    if (best != null) (label: 'Mejor partido', value: '$best'),
    if (perShot != null)
      (label: 'Puntos por tiro', value: perShot.toStringAsFixed(1)),
    if (threeShare != null)
      (label: '% de puntos de 3', value: '$threeShare%'),
    if (winRate != null)
      (label: 'Efectividad de victorias', value: '$winRate%'),
  ];
}

/// Minutos de la sesión en zona alta (Cardio, Pico y Máximo: ≥70% del pulso
/// máximo). null si no hay zonas o no llega a un minuto.
int? intenseMinutes(PlaySession s) {
  final z = s.hrZones;
  if (z == null || z.length < 5) return null;
  final m = (z[2] + z[3] + z[4]) ~/ 60;
  return m > 0 ? m : null;
}

/// Sombra suave para texto sobre foto (hero del resumen). Más leve que la de la
/// imagen para compartir porque en pantalla el scrim ya hace casi todo.
const _kSoftShadow = [
  Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 1)),
];

/// "4 VS 4" como pastilla: el VS en el acento, los números en blanco. La usan
/// la imagen para compartir (escala 1) y el resumen en pantalla (escala menor).
Widget _vsPill(int n, {double scale = 1}) {
  final num = AppText.display(size: 46 * scale, weight: FontWeight.w900);
  return Container(
    padding:
        EdgeInsets.symmetric(horizontal: 34 * scale, vertical: 16 * scale),
    decoration: BoxDecoration(
      color: AppColors.accent.withAlpha(40),
      borderRadius: BorderRadius.circular(AppShape.rChip),
      border: Border.all(color: AppColors.accent, width: 3 * scale),
    ),
    child: Text.rich(
      TextSpan(
        style: num.copyWith(color: Colors.white),
        children: [
          TextSpan(text: '$n'),
          TextSpan(
            text: '  VS  ',
            style: num.copyWith(color: AppColors.accent, fontSize: 34 * scale),
          ),
          TextSpan(text: '$n'),
        ],
      ),
    ),
  );
}

/// Widget optimizado para captura como imagen (9:16, Instagram Stories).
///
/// Sus títulos van SIN halo de color (glow) a propósito: esto se renderiza
/// offscreen a un PNG de 1080x1920, así que el glow quedaría horneado en la
/// imagen que el usuario comparte. Lo único que llevan es una sombra negra
/// suave para que se lean sobre la foto de fondo.
class _ShareCard extends StatelessWidget {
  final PlaySession session;
  final Court? court;
  final Color color;
  final String label;
  final DateTime ended;

  /// Secciones que el usuario ocultó (ya resueltas por
  /// `PlaySessionService.effectiveHiddenFor`). El logo y el EXP
  /// no son ocultables, así que la tarjeta nunca queda sin contenido.
  final Set<MatchSection> hidden;

  /// Foto de la cancha ya precargada (null = fondo oscuro de siempre).
  final ImageProvider? background;

  const _ShareCard({
    required this.session,
    required this.court,
    required this.color,
    required this.label,
    required this.ended,
    required this.hidden,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    final bg = background;
    return Stack(
      children: [
        SizedBox(width: 1080, height: 1920),
        // Fondo: la foto de la cancha con dos máscaras (una pareja para que el
        // texto blanco se lea sobre cualquier foto y un degradé a negro desde
        // ~40% de la altura) o, sin foto, el degradé oscuro de siempre.
        if (bg != null) ...[
          Positioned.fill(child: Image(image: bg, fit: BoxFit.cover)),
          Positioned.fill(
              child: ColoredBox(color: Colors.black.withAlpha(160))),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xFF000000)],
                  stops: [0.4, 1.0],
                ),
              ),
            ),
          ),
        ] else
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0A0A0A),
                    Color(0xFF111111),
                    Color(0xFF0A0A0A)
                  ],
                ),
              ),
            ),
          ),
        Positioned.fill(
          // Sombra suave para TODOS los textos: sobre una foto el blanco solo no
          // alcanza. Los estilos de AppText heredan `shadows` de acá.
          child: DefaultTextStyle.merge(
            style: const TextStyle(shadows: [
              Shadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 1)),
            ]),
            child: Padding(
      padding: const EdgeInsets.all(80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          _shareLogo(),
          // Todo el contenido va centrado en el alto que queda y, si no entra
          // (p. ej. con salud + desglose + puntos a la vez), se achica
          // proporcionalmente en vez de cortarse contra el borde de la imagen.
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 920,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
          const SizedBox(height: 40),
          // Resultado: plano y editorial (sin globo), barrita de acento arriba.
          if (!hidden.contains(MatchSection.resultado)) ...[
            Container(width: 76, height: 7, color: color),
            const SizedBox(height: 28),
            Text(label,
                style: AppText.display(
                    size: 56,
                    weight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.25)),
            if (_scoreLabel(s).isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('${_scoreLabel(s)} EN LA SESIÓN',
                  style: AppText.archivo(
                      size: 36,
                      weight: FontWeight.w700,
                      letterSpacing: 0.1,
                      color: Colors.white.withAlpha(200))),
            ],
            const SizedBox(height: 52),
          ],
          // Cancha: nombre, zona y el chip de tipo se van juntos. La foto de
          // fondo (si la hay) se oculta con "Cancha y zona" o con "Foto de fondo".
          if (!hidden.contains(MatchSection.ubicacion)) ...[
            Text(
              court?.name ?? (s.courtName.isEmpty ? 'Cancha' : s.courtName),
              textAlign: TextAlign.center,
              style: AppText.display(
                  size: 92, weight: FontWeight.w900, height: 1.05),
            ),
            if (court != null && court!.area.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(court!.area,
                  style: AppText.grotesk(
                      size: 46,
                      weight: FontWeight.w600,
                      color: AppColors.white(0.85))),
            ],
            // Exterior/Interior: mismo dato que ya se muestra en el detalle de
            // cancha (court.type), acá como chip con ícono para la imagen.
            if (court != null && court!.type.isNotEmpty) ...[
              const SizedBox(height: 22),
              _shareTypeBadge(court!.type),
            ],
            const SizedBox(height: 30),
          ],
          if (!hidden.contains(MatchSection.horario))
            Text(
              '${_fmtDate(ended)} · ${ended.hour.toString().padLeft(2, '0')}:${ended.minute.toString().padLeft(2, '0')}',
              style: AppText.grotesk(
                  size: 42,
                  weight: FontWeight.w600,
                  color: AppColors.white(0.8)),
            ),
          const SizedBox(height: 64),
          // Stats principales. El EXP va siempre, así que el divisor nunca queda
          // colgado de un borde.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!hidden.contains(MatchSection.duracion)) ...[
                _shareStat('DURACIÓN', PlaySessionService.fmt(s.seconds)),
                _shareDivider(),
              ],
              _shareStat('EXP', s.points > 0 ? '+${s.points}' : '—',
                  color: s.points > 0 ? AppColors.accent : null),
            ],
          ),
          // Formato en su propia fila: una pastilla por formato jugado. Unidos
          // con comas ("1v1, 4v4") no entraban en la fila de arriba.
          if (s.hasFormats && !hidden.contains(MatchSection.duracion)) ...[
            const SizedBox(height: 44),
            Text('FORMATO',
                style: AppText.archivo(
                    size: 30,
                    weight: FontWeight.w900,
                    color: AppColors.white(0.78),
                    letterSpacing: 0.08)),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 16,
              children: [
                for (final n in s.formatList) _shareFormatPill(n),
              ],
            ),
          ],
          // Stats del usuario: total anotado (número grande) + el desglose como
          // planilla de texto plano (mismas métricas y valores que el registro).
          // Desglose de la sesión (varios partidos).
          // Partidos y victorias, SIN el entrenamiento: puesto en la misma fila
          // parecía uno más de los partidos, y la puntuación de abajo ("en 5
          // partidos") se leía como si lo incluyera. El entrenamiento va aparte,
          // después de los puntos, aclarando que no suma.
          if (s.isMultiGame &&
              !hidden.contains(MatchSection.desglose) &&
              s.gamesPlayed > 0) ...[
            const SizedBox(height: 56),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _shareStat('PARTIDOS', '${s.gamesPlayed}'),
                  _shareDivider(),
                  _shareStat('VICTORIAS', '${s.winsCount}'),
                ],
              ),
            ),
          ],
          if (s.isMultiGame &&
              !hidden.contains(MatchSection.desglose) &&
              s.gamesPlayed > 0) ...[
            if (s.hasGamePoints) ...[
              const SizedBox(height: 32),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 20,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < s.gamePoints!.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.white(0.06),
                          borderRadius: BorderRadius.circular(AppShape.rChip),
                          border: Border.all(color: AppColors.white(0.14)),
                        ),
                        child: Text(
                          'P${i + 1}  ${s.gamePoints![i]}',
                          style: AppText.grotesk(
                              size: 26,
                              weight: FontWeight.w700,
                              color: AppColors.white(0.8)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
          // Entrenamientos: debajo de partidos/victorias (y de los puntos por
          // partido, que son de esos partidos), como pastilla aparte que aclara
          // que no suman.
          if (s.isMultiGame &&
              !hidden.contains(MatchSection.desglose) &&
              s.trainingsDone > 0) ...[
            SizedBox(height: s.gamesPlayed > 0 ? 28 : 56),
            _shareTrainingNote(s.trainingsDone),
          ],
          // Total y desglose son toggles independientes, igual que en pantalla.
          if (s.hasUserStats &&
              !(hidden.contains(MatchSection.puntuacion) &&
                  hidden.contains(MatchSection.desglosePuntos))) ...[
            const SizedBox(height: 56),
            if ((s.userPoints ?? 0) > 0 &&
                !hidden.contains(MatchSection.puntuacion)) ...[
              Text('${s.userPoints}',
                  style: AppText.display(
                      size: 112,
                      weight: FontWeight.w900,
                      color: AppColors.accent,
                      height: 0.95)),
              const SizedBox(height: 16),
              // Los entrenamientos no suman puntos: el rótulo lo deja explícito
              // (con la cantidad cuando hubo varios partidos).
              Text(
                  s.gamesPlayed > 1
                      ? 'PUNTOS EN ${s.gamesPlayed} PARTIDOS'
                      : 'PUNTOS EN PARTIDOS',
                  style: AppText.archivo(
                      size: 32,
                      weight: FontWeight.w900,
                      color: AppColors.white(0.78),
                      letterSpacing: 0.1)),
              const SizedBox(height: 40),
            ],
            if (!hidden.contains(MatchSection.desglosePuntos))
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  children: [
                    for (final it in _userStatItems(s))
                      _shareStatLine(it.label, it.value),
                  ],
                ),
              ),
          ],
          // Salud: todas las métricas disponibles.
          if (s.hasHealth &&
              !s.healthPending &&
              !hidden.contains(MatchSection.salud)) ...[
            const SizedBox(height: 60),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 52,
              runSpacing: 36,
              children: [
                // Las estimadas van marcadas también acá: publicar un número
                // calculado como si lo hubiera medido el reloj es peor todavía.
                if (s.calories > 0)
                  _shareMiniStat(Icons.local_fire_department,
                      '${s.caloriesEstimated ? '~' : ''}${s.calories.round()} kcal'),
                if (s.steps > 0)
                  _shareMiniStat(Icons.directions_walk, '${s.steps} pasos'),
                if (intenseMinutes(s) != null)
                  _shareMiniStat(Icons.local_fire_department_outlined,
                      '${intenseMinutes(s)} min intensos'),
                if (s.maxHr != null && s.maxHr! > 0)
                  _shareMiniStat(Icons.monitor_heart, '${s.maxHr} bpm máx'),
                if (s.distance > 0)
                  _shareMiniStat(
                    Icons.straighten,
                    '${s.distanceEstimated ? '~' : ''}'
                        '${s.distance >= 1000 ? '${(s.distance / 1000).toStringAsFixed(1)} km' : '${s.distance.round()} m'}',
                  ),
                // Igual que en pantalla: sin oxígeno, reposo, HRV, respiración
                // ni velocidad (no son de la sesión o no dicen nada en ella), y
                // sin el pulso promedio, que en una sesión diluyen las esperas.
              ],
            ),
            // Mini barra de zonas cardíacas.
            if (s.hrZones != null && s.hrZones!.any((z) => z > 0)) ...[
              const SizedBox(height: 48),
              _shareZoneBar(s.hrZones!),
            ],
          ],
          const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
          ),
          ),
        ),
      ],
    );
  }

  /// Chip con el tipo de cancha (Exterior/Interior/lo que sea que traiga el
  /// backend) para la imagen de compartir. Ícono de sol para exterior, techo
  /// para cualquier otro valor (interior u otros que se agreguen a futuro).
  Widget _shareTypeBadge(String type) {
    final isOutdoor = type.toLowerCase() == 'exterior';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white(0.08),
        borderRadius: BorderRadius.circular(AppShape.rChip),
        border: Border.all(color: AppColors.white(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOutdoor ? Icons.wb_sunny_outlined : Icons.home_outlined,
              size: 38, color: AppColors.white(0.85)),
          const SizedBox(width: 14),
          Text(type.toUpperCase(),
              style: AppText.grotesk(
                  size: 34,
                  weight: FontWeight.w700,
                  color: AppColors.white(0.85),
                  letterSpacing: 0.08)),
        ],
      ),
    );
  }

  /// Logo con una sombra suave detrás (copia negra desenfocada): al ser una
  /// imagen no le llega el `shadows` de los textos.
  Widget _shareLogo() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.4,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
              child: const AppLogo(height: 150),
            ),
          ),
        ),
        const AppLogo(height: 150),
      ],
    );
  }

  Widget _shareFormatPill(int n) => _vsPill(n);

  Widget _shareDivider() => Container(
        width: 2,
        height: 90,
        margin: const EdgeInsets.symmetric(horizontal: 52),
        color: AppColors.white(0.15),
      );

  /// Número + etiqueta para la imagen de compartir. La etiqueta va en
  /// `archivo` (Anybody, el rol de la tipografía para etiquetas — ver
  /// app/CLAUDE.md §5.1) y no en `grotesk`: a tamaño de miniatura (la imagen
  /// se comparte a WhatsApp/Instagram, que la reducen antes de mostrarla) el
  /// trazo más fino de Archivo Narrow con 40% de opacidad se volvía ilegible,
  /// mientras el número al lado quedaba desproporcionadamente grande.
  Widget _shareStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(value,
            style: AppText.display(
                size: 68, weight: FontWeight.w900, color: color ?? Colors.white)),
        const SizedBox(height: 14),
        Text(label,
            style: AppText.archivo(
                size: 30,
                weight: FontWeight.w900,
                color: AppColors.white(0.78),
                letterSpacing: 0.08)),
      ],
    );
  }

  /// Fila de planilla para la imagen: métrica a la izquierda, valor a la
  /// derecha, con una línea fina debajo. Mismo estilo que el registro en app.
  Widget _shareStatLine(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.white(0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppText.grotesk(
                    size: 35,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.85))),
          ),
          Text(value,
              style: AppText.display(
                  size: 44, weight: FontWeight.w900, color: Colors.white)),
        ],
      ),
    );
  }

  /// "+ 1 ENTRENAMIENTO · NO SUMA PUNTOS": separado de los partidos a propósito.
  Widget _shareTrainingNote(int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white(0.06),
        borderRadius: BorderRadius.circular(AppShape.rChip),
        border: Border.all(color: AppColors.white(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fitness_center, size: 34, color: AppColors.white(0.8)),
          const SizedBox(width: 16),
          Text(
            '+ $n ${n == 1 ? 'ENTRENAMIENTO' : 'ENTRENAMIENTOS'}',
            style: AppText.archivo(
                size: 30, weight: FontWeight.w900, color: Colors.white),
          ),
          Text(
            '  ·  NO ${n == 1 ? 'SUMA' : 'SUMAN'} PUNTOS',
            style: AppText.archivo(
                size: 26, weight: FontWeight.w700, color: AppColors.white(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _shareMiniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: AppColors.accent),
        const SizedBox(width: 14),
        Text(text,
            style: AppText.display(
                size: 39, weight: FontWeight.w800, color: Colors.white)),
      ],
    );
  }

  /// Mini barra horizontal de zonas cardíacas para la share card.
  static const _zoneColors = [
    Color(0xFF22C55E),
    Color(0xFFEAB308),
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFF991B1B),
  ];

  Widget _shareZoneBar(List<int> zones) {
    final total = zones.fold(0, (s, z) => s + z);
    if (total == 0) return const SizedBox.shrink();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 20,
            child: Row(
              children: List.generate(5, (i) {
                final pct = zones[i] / total;
                if (pct <= 0) return const SizedBox.shrink();
                return Expanded(
                  flex: (pct * 1000).round(),
                  child: Container(color: _zoneColors[i]),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            if (zones[i] == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: _zoneColors[i], shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(_zoneLabels[i],
                      style: AppText.grotesk(
                          size: 16, color: AppColors.white(0.5))),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  static const _zoneLabels = ['Calentamiento', 'Quema', 'Cardio', 'Pico', 'Máximo'];

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
