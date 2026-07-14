import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../services/court_rating_service.dart';
import '../services/location_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/rating_badge.dart';
import '../widgets/reveal_on_scroll.dart';
import '../widgets/status_dot.dart';

class ListScreen extends StatefulWidget {
  final List<Court> courts;
  final ValueChanged<String>? onSelectCourt;

  /// Dirección por la que entra la pestaña (+1 desde la derecha, -1 desde la
  /// izquierda — el mismo `_slideDir` del shell): las cards entran deslizando
  /// desde el lado contrario a la pestaña de la que venís.
  final int enterDir;

  const ListScreen({
    super.key,
    required this.courts,
    this.onSelectCourt,
    this.enterDir = 1,
  });

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  String _sort = 'near';

  // La animación de entrada corre UNA sola vez por visita a la pestaña: al
  // cambiar el filtro/orden se apaga (re-animar el reorden dejaba cards a
  // mitad de camino).
  bool _introPlayed = false;

  Offset get _revealBegin => Offset(widget.enterDir * 0.15, 0);

  /// Distancia real en metros al usuario si hay posición; si no, cae al texto
  /// de Notion parseado (legado) para no romper el orden "cerca".
  double _distMeters(Court c) {
    final m = metersTo(context.read<LocationService>().last, c.lat, c.lng);
    if (m != null) return m;
    final parsed =
        double.tryParse(c.dist.replaceAll(RegExp(r'[^0-9.]'), ''));
    return parsed != null ? parsed * 1000 : 1e12;
  }

  List<Court> get _sortedCourts {
    final list = [...widget.courts];
    switch (_sort) {
      case 'rate':
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case 'busy':
        list.sort((a, b) => b.players.compareTo(a.players));
      case 'near':
        list.sort((a, b) => _distMeters(a).compareTo(_distMeters(b)));
      case 'new':
        break; // orden original (más nuevas primero según Notion)
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    // Reconstruye (y re-ordena "cerca") cuando cambia la posición del usuario.
    context.watch<LocationService>();
    return Container(
      color: AppColors.lilac,
      child: ListView(
        padding: const EdgeInsets.only(top: 56, bottom: 160),
        children: [
          RevealOnScroll(
            begin: _revealBegin,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '340 CANCHAS · BUENOS AIRES',
                    style: AppText.grotesk(
                      size: 11,
                      weight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: 0.16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Canchas\ncerca tuyo.',
                    style: AppText.archivo(
                      size: 38,
                      weight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.01,
                      height: 1.05,
                    ).copyWith(
                      shadows: const [
                        Shadow(color: Colors.black, offset: Offset(3, 3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          RevealOnScroll(
            begin: _revealBegin,
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final c in const [
                    ('near', 'Más cerca'),
                    ('rate', 'Mejor rating'),
                    ('busy', 'Más activas'),
                    ('new', 'Nuevas'),
                  ]) ...[
                    AppChip(
                      label: c.$2,
                      active: _sort == c.$1,
                      onTap: () => setState(() {
                        _sort = c.$1;
                        // El reorden no se re-anima (dejaba cards trabadas).
                        _introPlayed = true;
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _sortedCourts.length; i++)
            if (_introPlayed)
              Padding(
                key: ValueKey(_sortedCourts[i].id),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _CourtListItem(
                  court: _sortedCourts[i],
                  rank: i + 1,
                  onTap: () => widget.onSelectCourt?.call(_sortedCourts[i].id),
                ),
              )
            else
              RevealOnScroll(
                key: ValueKey(_sortedCourts[i].id),
                begin: _revealBegin,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: _CourtListItem(
                    court: _sortedCourts[i],
                    rank: i + 1,
                    onTap: () =>
                        widget.onSelectCourt?.call(_sortedCourts[i].id),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CourtListItem extends StatelessWidget {
  final Court court;
  final int rank;
  final VoidCallback onTap;

  const _CourtListItem({
    required this.court,
    required this.rank,
    required this.onTap,
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
    return PressableWidget(
      onTap: onTap,
      child: Container(
        // Card plana: fill sutil sin borde ni sombra (lenguaje editorial del
        // perfil); la foto y la tipografía llevan el protagonismo.
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Stack(
              children: [
                CourtImage(
                  url: court.img,
                  height: 140,
                  width: double.infinity,
                  // El contenedor (clipBehavior) ya recorta las esquinas.
                  borderRadius: BorderRadius.zero,
                ),
                // Scrim de LEGIBILIDAD sobre la foto: se conserva (no es
                // decoración, da contraste a los badges y al ranking).
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, AppColors.black(0.85)],
                      stops: const [0.4, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Text(
                    rank.toString().padLeft(2, '0'),
                    style: AppText.archivo(
                      size: 24,
                      weight: FontWeight.w900,
                      letterSpacing: -0.05,
                      color: AppColors.accent,
                    ).copyWith(
                      // Solo la sombra negra de legibilidad sobre la foto
                      // (el glow de acento se quitó con el neobrutalismo).
                      shadows: [
                        const Shadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: StatusDot(status: court.status),
                ),
                Positioned(
                  bottom: 12,
                  left: 14,
                  right: 14,
                  child: Row(
                    children: [
                      for (final b in court.badges.take(3)) ...[
                        _miniBadge(b),
                        const SizedBox(width: 5),
                      ],
                      const Spacer(),
                      if (proposer.handle.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          // Autor sobre la foto: fondo oscuro plano, el acento
                          // vive en el texto (sin borde).
                          decoration: BoxDecoration(
                            color: AppColors.black(0.55),
                            borderRadius:
                                BorderRadius.circular(AppShape.rChip),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_location_alt_outlined,
                                  size: 10, color: AppColors.accent),
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
                              Text(
                                proposer.handle,
                                style: AppText.grotesk(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              court.name,
                              style: AppText.archivo(
                                size: 19,
                                weight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            // Distancia REAL al usuario (fallback: Notion).
                            Builder(builder: (context) {
                              final m = metersTo(
                                context.watch<LocationService>().last,
                                court.lat,
                                court.lng,
                              );
                              final dist =
                                  m != null ? formatDist(m) : court.dist;
                              return Text(
                                dist.isEmpty
                                    ? court.area
                                    : '${court.area} · $dist',
                                style: AppText.grotesk(
                                  size: 12,
                                  color: AppColors.white(0.6),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      Builder(builder: (context) {
                        final rs = context.read<CourtRatingService>();
                        return FutureBuilder<CourtRating>(
                          future: rs.ratingFor(court.id),
                          builder: (context, snap) {
                            final cr = snap.data;
                            return RatingBadge(
                              value: cr?.average,
                              size: 13,
                            );
                          },
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.white(0.06)),
                      ),
                    ),
                    child: Row(
                      children: [
                        _stat('Tipo', court.type),
                        _divider(),
                        _stat('Superficie', court.surface),
                        _divider(),
                        _stat('Jugando', '${court.players}', highlight: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String label) {
    // Chip de legibilidad sobre la foto: fondo oscuro plano, sin borde.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.black(0.55),
        borderRadius: BorderRadius.circular(AppShape.rChip),
      ),
      // Chip oscuro sobre la foto: texto blanco.
      child: Text(
        label.toUpperCase(),
        style: AppText.grotesk(
          size: 9.5,
          weight: FontWeight.w600,
          letterSpacing: 0.04,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {bool highlight = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.grotesk(
              size: 9.5,
              weight: FontWeight.w600,
              color: AppColors.white(0.4),
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppText.archivo(
              size: 14,
              weight: FontWeight.w700,
              color: highlight ? AppColors.accent : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 28,
        color: AppColors.white(0.06),
        margin: const EdgeInsets.symmetric(horizontal: 12),
      );
}
