import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'app_tab_bar.dart';
import 'pressable_widget.dart';

/// Un paso del tour: el elemento a resaltar y qué decir de él.
class TourStep {
  final GlobalKey target;
  final String title;
  final String body;

  /// Lista que contiene al elemento, si puede estar fuera de pantalla (p. ej.
  /// los Logros, abajo de todo en el Perfil). El tour scrollea hasta que el
  /// elemento aparece. Es una función porque el controller existe recién
  /// cuando la pantalla está montada.
  final ScrollController? Function()? scroll;

  const TourStep(this.target, this.title, this.body, {this.scroll});
}

/// Keys de los elementos que recorre el tour. Estáticas para que la pantalla
/// del mapa y la barra de pestañas las cuelguen de sus widgets sin cablear
/// parámetros por el árbol. Cada una se usa en UN solo lugar (una GlobalKey
/// repetida en el árbol rompe el build).
class TourKeys {
  TourKeys._();
  static final timer = GlobalKey(debugLabel: 'tour_timer');
  static final courtCard = GlobalKey(debugLabel: 'tour_court_card');
  static final search = GlobalKey(debugLabel: 'tour_search');
  static final ranking = GlobalKey(debugLabel: 'tour_ranking');
  // Social
  static final socialTabs = GlobalKey(debugLabel: 'tour_social_tabs');
  static final crewList = GlobalKey(debugLabel: 'tour_crew_list');
  // Crear (pestaña del botón central)
  static final createPickup = GlobalKey(debugLabel: 'tour_create_pickup');
  static final joinPickup = GlobalKey(debugLabel: 'tour_join_pickup');
  static final addCourt = GlobalKey(debugLabel: 'tour_add_court');
  // Perfil
  static final profileLevel = GlobalKey(debugLabel: 'tour_profile_level');
  static final profileStats = GlobalKey(debugLabel: 'tour_profile_stats');
  static final profileNotif = GlobalKey(debugLabel: 'tour_profile_notif');
  static final profileTabs = GlobalKey(debugLabel: 'tour_profile_tabs');
  static final profileSettings =
      GlobalKey(debugLabel: 'tour_profile_settings');
  static final profileClan = GlobalKey(debugLabel: 'tour_profile_clan');
  static final profileTitles = GlobalKey(debugLabel: 'tour_profile_titles');
  static final profileAchievements =
      GlobalKey(debugLabel: 'tour_profile_achievements');

  /// Scroll del Perfil (lo registra la pantalla mientras está montada).
  static ScrollController? profileScroll;
  static final _tabs = {
    for (final t in AppTab.values)
      t: GlobalKey(debugLabel: 'tour_tab_${t.name}'),
  };
  static GlobalKey tab(AppTab t) => _tabs[t]!;
}

/// Pedido de volver a mostrar el tour (fila "Ver tutorial" del perfil). Lo
/// escucha `MainShell`, que vuelve al mapa y lo corre. Mismo patrón que
/// `crewActivityNotifier`.
final ValueNotifier<int> appTourRequest = ValueNotifier<int>(0);

/// Muestra el tour encima de todo (overlay raíz) y termina cuando el usuario
/// lo completa o lo salta. Los pasos cuyo elemento no está en pantalla (p. ej.
/// el ranking en modo offline) se saltean solos.
Future<void> runAppTour(BuildContext context, List<TourStep> steps) async {
  // Un paso entra si su elemento está montado, o si se puede scrollear hasta él.
  final visible = [
    for (final s in steps)
      if (_rectOf(s.target) != null || s.scroll != null) s,
  ];
  if (visible.isEmpty) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TourOverlay(
      steps: visible,
      onClose: () {
        // Saltar y el back pueden llegar juntos: cerrar una sola vez.
        if (done.isCompleted) return;
        entry.remove();
        done.complete();
      },
    ),
  );
  overlay.insert(entry);
  await done.future;
}

/// Rect del elemento en coordenadas de pantalla, o null si no está montado o
/// no tiene tamaño (fuera de pantalla, oculto).
Rect? _rectOf(GlobalKey key) {
  final ctx = key.currentContext;
  final box = ctx?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  if (box.size.isEmpty) return null;
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final VoidCallback onClose;
  const _TourOverlay({required this.steps, required this.onClose});

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay>
    with SingleTickerProviderStateMixin {
  // -1 hasta ubicar el primer paso (puede requerir scrollear).
  int _i = -1;
  // Mientras se scrollea hacia el próximo elemento no se aceptan toques.
  bool _busy = false;
  // El hueco se anima de la posición del paso anterior a la del actual.
  late Rect _from;
  late Rect _to;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  static const _pad = 8.0;

  @override
  void initState() {
    super.initState();
    _from = _to = Rect.zero;
    _ctrl.value = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_busy) return;
    _goTo(_i + 1);
  }

  /// Va al paso [n] o al siguiente que se pueda mostrar. Un elemento pudo
  /// desaparecer entre pasos (p. ej. se cortó la red): se saltea en vez de
  /// resaltar un hueco vacío.
  Future<void> _goTo(int n) async {
    _busy = true;
    try {
      while (n < widget.steps.length) {
        final r = await _bringIntoView(widget.steps[n]);
        if (!mounted) return;
        if (r != null) {
          final hole = r.inflate(_pad);
          setState(() {
            // El primero aparece en su lugar; los demás se deslizan.
            _from = _i < 0 ? hole : Rect.lerp(_from, _to, _ctrl.value)!;
            _i = n;
            _to = hole;
          });
          _ctrl.forward(from: 0);
          return;
        }
        n++;
      }
      widget.onClose();
    } finally {
      _busy = false;
    }
  }

  /// Rect del elemento ya visible en pantalla, scrolleando si hace falta.
  /// Null si no hay forma de mostrarlo.
  Future<Rect?> _bringIntoView(TourStep step) async {
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final bottom = media.size.height;
    for (var tries = 0; tries < 30; tries++) {
      final r = _rectOf(step.target);
      if (r != null && r.top >= top && r.bottom <= bottom) return r;
      final ctx = step.target.currentContext;
      if (r != null && ctx != null && ctx.mounted) {
        // Construido pero fuera de pantalla: centrarlo un poco arriba (la
        // tarjeta del tour va abajo) y esperar el fade de RevealOnScroll.
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        await Future<void>.delayed(const Duration(milliseconds: 550));
        return _rectOf(step.target);
      }
      // Todavía no construido (la lista es perezosa): bajar de a pedazos
      // hasta que aparezca.
      final sc = step.scroll?.call();
      if (sc == null || !sc.hasClients) return null;
      final p = sc.position;
      if (p.pixels >= p.maxScrollExtent - 1) return null;
      await sc.animateTo(
        math.min(p.pixels + p.viewportDimension * 0.7, p.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Hasta ubicar el primer paso: solo el velo, sin tarjeta.
    if (_i < 0) {
      return const IgnorePointer(child: ColoredBox(color: Color(0x80000000)));
    }
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    final screen = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;

    return PopScope(
      canPop: false,
      // Back de Android = saltar el tour.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            // Recortado a la pantalla con un margen: los elementos de ancho
            // completo (tarjeta, filtros) y la pestaña del borde quedaban con
            // el borde naranja cortado.
            final hole = Rect.lerp(
              _from,
              _to,
              Curves.easeInOut.transform(_ctrl.value),
            )!.intersect(
              Rect.fromLTRB(6, pad.top, screen.width - 6, screen.height - 6),
            );
            // La tarjeta va del lado donde hay más lugar.
            final below = hole.center.dy < screen.height / 2;
            return Stack(
              children: [
                // Tocar fuera de la tarjeta avanza.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _next,
                    child: CustomPaint(painter: _HolePainter(hole)),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: below ? hole.bottom + 14 : null,
                  bottom: below
                      ? null
                      : (screen.height - hole.top + 14).clamp(
                          pad.bottom + 16,
                          screen.height,
                        ),
                  child: _card(step, last),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card(TourStep step, bool last) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: AppColors.bgElev,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_i + 1} DE ${widget.steps.length}',
            style: AppText.archivo(
              size: 10.5,
              weight: FontWeight.w800,
              letterSpacing: 0.12,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.title,
            style: AppText.archivo(size: 17, weight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text.rich(_richBody(step.body)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!last)
                PressableWidget(
                  onTap: widget.onClose,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'SALTAR',
                      style: AppText.archivo(
                        size: 12,
                        weight: FontWeight.w800,
                        letterSpacing: 0.06,
                        color: AppColors.white(0.5),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              PressableWidget(
                onTap: _next,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                  ),
                  child: Text(
                    last ? '¡A JUGAR!' : 'SIGUIENTE',
                    style: AppText.archivo(
                      size: 12,
                      weight: FontWeight.w900,
                      letterSpacing: 0.06,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Texto del paso con la marca destacada: "1of1" se reemplaza por el logo en
/// miniatura y "EXP" va en acento (como en el resto de la app).
TextSpan _richBody(String body) {
  final base = AppText.grotesk(
    size: 13.5,
    color: AppColors.white(0.75),
    height: 1.45,
  );
  final spans = <InlineSpan>[];
  final re = RegExp(r'1of1|\bexp\b', caseSensitive: false);
  var at = 0;
  for (final m in re.allMatches(body)) {
    if (m.start > at) spans.add(TextSpan(text: body.substring(at, m.start)));
    if (m.group(0)!.toLowerCase() == '1of1') {
      spans.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 1),
          child: AppLogo(height: 17),
        ),
      ));
    } else {
      spans.add(TextSpan(
        text: 'EXP',
        // Helper y no copyWith: la fuente es variable y el peso necesita el
        // eje wght que manda AppText.
        style: AppText.grotesk(
          size: 13.5,
          weight: FontWeight.w800,
          color: AppColors.accent,
          height: 1.45,
        ),
      ));
    }
    at = m.end;
  }
  if (at < body.length) spans.add(TextSpan(text: body.substring(at)));
  return TextSpan(style: base, children: spans);
}

/// Fondo oscuro con un hueco redondeado sobre el elemento resaltado, y un
/// borde de acento alrededor del hueco.
class _HolePainter extends CustomPainter {
  final Rect hole;
  _HolePainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      hole,
      Radius.circular(hole.shortestSide < 70 ? hole.shortestSide / 2 : 18),
    );
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(r),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black.withAlpha(195));
    canvas.drawRRect(
      r,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole;
}
