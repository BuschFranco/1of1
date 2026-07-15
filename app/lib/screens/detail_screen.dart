import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../data/legal_content.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import '../services/blocked_provider.dart';
import '../services/court_rating_service.dart';
import '../services/favorites_provider.dart';
import '../services/location_service.dart';
import '../services/notion_service.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/report_service.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/player_avatar.dart';
import '../widgets/pop_button.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/section_title.dart';
import '../widgets/status_dot.dart';
import 'pickup_create_screen.dart';

// Rojo destructivo (eliminar cancha/reseña). Local: AppColors no tiene token
// de peligro y este es el único lugar que lo usa.
const Color _danger = Color(0xFFEF4444);

class DetailScreen extends StatelessWidget {
  final String courtId;
  final List<Court> courts;
  final VoidCallback? onBack;
  final ValueChanged<String>? onShowOnMap;

  const DetailScreen({
    super.key,
    required this.courtId,
    required this.courts,
    this.onBack,
    this.onShowOnMap,
  });

  @override
  Widget build(BuildContext context) {
    if (courts.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sports_basketball_outlined,
                  size: 48, color: AppColors.ink.withAlpha(100)),
              const SizedBox(height: 16),
              Text('Cancha no disponible',
                  style: AppText.archivo(
                      size: 18, weight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 8),
              Text('No se pudo cargar la información',
                  style: AppText.grotesk(size: 14, color: AppColors.ink.withAlpha(160))),
              const SizedBox(height: 24),
              PopButton(
                label: 'Volver',
                onPressed: () => onBack?.call(),
              ),
            ],
          ),
        ),
      );
    }
    final court = courts.firstWhere((c) => c.id == courtId,
        orElse: () => courts.first);

    return GestureDetector(
      // Deslizar a la derecha cierra el detalle y vuelve a la pestaña previa
      // (mapa o canchas, según por dónde entró: al cerrar el overlay queda a la
      // vista el tab que estaba debajo). No choca con el scroll vertical.
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 0) onBack?.call();
      },
      child: Container(
      color: AppColors.bg,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 180),
            children: [
              _hero(court),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (context) {
                      final ratingService = context.read<CourtRatingService>();
                      return FutureBuilder<CourtRating>(
                        future: ratingService.ratingFor(court.id),
                        builder: (context, snap) {
                          final cr = snap.data;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ratingStrip(court, courtRating: cr),
                              if (cr == null || !cr.hasRating)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Necesita más reseñas para estimar el rating',
                                    style: AppText.grotesk(
                                      size: 12,
                                      color: AppColors.ink.withAlpha(140),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    }),
                    Builder(builder: (context) {
                      final secs = context
                          .watch<PlaySessionService>()
                          .secondsForCourt(court.id);
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          // Card plana: fill sin borde (lenguaje editorial).
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius:
                                BorderRadius.circular(AppShape.rBtn),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 18, color: AppColors.accent),
                              const SizedBox(width: 10),
                              Text('Jugaste acá',
                                  style: AppText.grotesk(
                                      size: 13, color: AppColors.white(0.7))),
                              const Spacer(),
                              Text(
                                PlaySessionService.fmt(secs),
                                style: AppText.archivo(
                                    size: 15,
                                    weight: FontWeight.w800,
                                    color: AppColors.accent),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    _playingNow(court),
                    const SizedBox(height: 22),
                    const SectionTitle(title: 'Amenities'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final b in court.badges)
                          AppChip(label: b),
                        AppChip(label: court.surface),
                        AppChip(label: court.type),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle(title: 'Sobre la cancha'),
                    Text(
                      court.desc,
                      style: AppText.grotesk(
                        size: 14,
                        color: AppColors.white(0.75),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _ReviewsSection(courtId: court.id),
                    const SizedBox(height: 24),
                    const SectionTitle(
                        title: 'Actividad semanal', right: 'Hoy'),
                    _activityChart(),
                    if (context.read<Session>().isAdmin) ...[
                      const SizedBox(height: 24),
                      _adminDeleteCourt(context, court),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 56,
            left: 16,
            child: _iconBtn(Icons.chevron_left, onTap: onBack),
          ),
          Positioned(
            bottom: 110,
            left: 16,
            right: 16,
            child: _bottomCta(court),
          ),
        ],
      ),
      ),
    );
  }

  /// Jugadores jugando AHORA en esta cancha, con presencia REAL:
  ///  - YO primero, desde el estado LOCAL del partido (PlaySessionService):
  ///    instantáneo, sin depender del round-trip a Notion ni de shareCourt
  ///    (verte a vos mismo no es un problema de privacidad).
  ///  - Los demás, desde los perfiles de Notion, solo si comparten cancha
  ///    (shareCourt) — excluyendo mi email para no duplicarme cuando Notion
  ///    ya refleje mi presencia.
  List<({Profile profile, bool isMe})> _livePlayers(
      BuildContext context, Court court) {
    final session = context.watch<Session>();
    final play = context.watch<PlaySessionService>();
    final myEmail = (session.email ?? '').trim().toLowerCase();
    final out = <({Profile profile, bool isMe})>[];
    final me = session.profile;
    if (me != null && play.courtId == court.id) {
      out.add((profile: me, isMe: true));
    }
    for (final p in context.watch<ProfilesProvider>().all) {
      if (!p.playing || !p.shareCourt || p.playingCourtId != court.id) {
        continue;
      }
      if (p.userEmail.trim().toLowerCase() == myEmail) continue;
      out.add((profile: p, isMe: false));
    }
    return out;
  }

  Widget _hero(Court court) {
    return SizedBox(
      height: 360,
      child: Stack(
        children: [
          Positioned.fill(child: CourtImage(url: court.img)),
          // Scrim plano de 2 stops (lenguaje editorial, como la lista): funde
          // la foto con el fondo sin el degradado triple viejo.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.bg],
                  stops: const [0.35, 1],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusDot(status: court.status),
                    // Conteo REAL de presencia (incluyéndome): oculto si nadie
                    // está jugando. `court.players` (campo estático de Notion)
                    // ya no se usa como "jugando ahora".
                    Builder(builder: (context) {
                      final n = _livePlayers(context, court).length;
                      if (n == 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '· $n JUGANDO AHORA',
                          style: AppText.grotesk(
                            size: 10.5,
                            color: AppColors.white(0.6),
                            letterSpacing: 0.1,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  court.name,
                  style: AppText.archivo(
                    size: 38,
                    weight: FontWeight.w900,
                    letterSpacing: -0.01,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                // Distancia REAL al usuario (fallback: texto de Notion).
                Builder(builder: (context) {
                  final m = metersTo(
                    context.watch<LocationService>().last,
                    court.lat,
                    court.lng,
                  );
                  final dist = m != null ? formatDist(m) : court.dist;
                  return Text(
                    [court.area, if (dist.isNotEmpty) dist, court.hoursLabel]
                        .join(' · '),
                    style: AppText.grotesk(
                      size: 13,
                      color: AppColors.white(0.6),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                // Crear un pickup con esta cancha ya seleccionada.
                Builder(
                  builder: (context) => PressableWidget(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PickupCreateScreen(initialCourt: court),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppShape.rBtn),
                        border: Border.all(color: AppColors.ink, width: 2),
                        boxShadow: AppFx.hardShadow(offset: const Offset(2, 2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, size: 16, color: AppColors.ink),
                          const SizedBox(width: 6),
                          Text(
                            'CREAR PICKUP',
                            style: AppText.archivo(
                              size: 12,
                              weight: FontWeight.w900,
                              letterSpacing: 0.04,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Jugadores jugando ahora en esta cancha (presencia REAL, ver
  /// [_livePlayers]): mazo horizontal de insignias superpuestas (yo primero)
  /// + el total al lado, aclarando que la actividad es de usuarios de la app.
  Widget _playingNow(Court court) {
    return Builder(builder: (context) {
      final players = _livePlayers(context, court);
      if (players.isEmpty) return const SizedBox.shrink();
      const maxShown = 5;
      const double avatarSize = 36;
      const double overlap = 26; // corrimiento entre insignias (mazo)
      final shown = players.take(maxShown).toList();
      final extra = players.length - shown.length;
      final bubbles = shown.length + (extra > 0 ? 1 : 0);
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'Jugando ahora'),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: avatarSize + (bubbles - 1) * overlap,
                  height: avatarSize,
                  child: Stack(
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        Positioned(
                          left: i * overlap,
                          child: PlayerAvatar(
                            profile: shown[i].profile,
                            size: avatarSize,
                          ),
                        ),
                      if (extra > 0)
                        Positioned(
                          left: shown.length * overlap,
                          child: Container(
                            width: avatarSize,
                            height: avatarSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.bgElev,
                              border:
                                  Border.all(color: AppColors.line, width: 1),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '+$extra',
                              style: AppText.grotesk(
                                size: 11,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        players.length == 1
                            ? '1 jugando ahora'
                            : '${players.length} jugando ahora',
                        style:
                            AppText.archivo(size: 14, weight: FontWeight.w700),
                      ),
                      Text(
                        'Actividad de usuarios registrados en 1of1',
                        style: AppText.grotesk(
                            size: 11, color: AppColors.white(0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _ratingStrip(Court court, {CourtRating? courtRating}) {
    final displayRating = courtRating?.hasRating == true
        ? courtRating!.average!.toStringAsFixed(1)
        : '—';
    final reviewCount = courtRating?.count ?? court.reviews;
    // Panel plano: fill sin borde (antes PopPanel con borde 1px).
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: Row(
        children: [
          _statCell(
            icon: Icons.star_rounded,
            value: displayRating,
            label: '$reviewCount reseñas',
          ),
          _strokeDivider(),
          _statCell(value: court.hoops.toString(), label: 'Aros disp.'),
          _strokeDivider(),
          _statCell(value: court.vibe, label: 'Vibe'),
        ],
      ),
    );
  }

  Widget _statCell({IconData? icon, required String value, required String label}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  value,
                  style: AppText.archivo(size: 22, weight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: AppText.grotesk(
              size: 10,
              color: AppColors.white(0.5),
              letterSpacing: 0.08,
            ),
          ),
        ],
      ),
    );
  }

  Widget _strokeDivider() => Container(
        width: 1,
        height: 40,
        color: AppColors.white(0.08),
        margin: const EdgeInsets.symmetric(horizontal: 12),
      );

  Widget _activityChart() {
    const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    const vals = [30, 55, 70, 85, 90, 100, 75];
    return Container(
      padding: const EdgeInsets.all(18),
      height: 160,
      // Card plana: fill sin borde (lenguaje editorial).
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 14,
                    height: vals[i].toDouble(),
                    decoration: BoxDecoration(
                      // Barra destacada en acento plano, sin glow.
                      color: i == 3 ? AppColors.accent : AppColors.white(0.12),
                      borderRadius: BorderRadius.circular(AppShape.rChip),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    days[i],
                    style: AppText.grotesk(
                      size: 11,
                      weight: FontWeight.w600,
                      color: i == 3 ? AppColors.accent : AppColors.white(0.45),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon,
      {VoidCallback? onTap, Color color = AppColors.ink}) {
    return PressableWidget(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.line, width: 1),
          boxShadow: AppFx.hardShadow(offset: const Offset(2, 2)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _adminDeleteCourt(BuildContext context, Court court) {
    return PressableWidget(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('Eliminar cancha',
                style: AppText.archivo(size: 18, weight: FontWeight.w800)),
            content: Text(
              '¿Eliminar "${court.name}" y todas sus reseñas? Esta acción no se puede deshacer.',
              style: AppText.grotesk(size: 14, color: AppColors.white(0.7)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancelar',
                    style: AppText.grotesk(
                        size: 13, color: AppColors.white(0.5))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Eliminar',
                    style: AppText.grotesk(
                        size: 13,
                        color: _danger,
                        weight: FontWeight.w700)),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        try {
          await NotionService().deleteCourt(
            court.id,
            reviewsDbId: NotionConfig.dbReviews,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cancha eliminada',
                  style: AppText.grotesk(size: 13)),
              backgroundColor: AppColors.accent,
            ),
          );
          onBack?.call();
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo eliminar',
                  style: AppText.grotesk(size: 13)),
              backgroundColor: AppColors.bg,
            ),
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _danger.withAlpha(20),
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(
              color: _danger.withAlpha(60), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline,
                size: 18, color: _danger),
            const SizedBox(width: 8),
            Text('ELIMINAR CANCHA',
                style: AppText.archivo(
                    size: 13,
                    weight: FontWeight.w800,
                    color: _danger)),
          ],
        ),
      ),
    );
  }

  Widget _bottomCta(Court court) {
    return Row(
      // Anclados a la esquina inferior derecha: favoritos a la izquierda del
      // botón de localización.
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Builder(builder: (context) {
          final isFav = context.watch<FavoritesProvider>().isFavorite(court.id);
          return _squareBtn(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? AppColors.accent : AppColors.ink,
            onTap: () => context.read<FavoritesProvider>().toggle(court.id),
          );
        }),
        const SizedBox(width: 10),
        _squareBtn(
          Icons.location_on_outlined,
          onTap: () => onShowOnMap?.call(court.id),
        ),
      ],
    );
  }

  /// Botón cuadrado de acción (favoritos / ubicar en el mapa) al pie del detalle.
  Widget _squareBtn(IconData icon,
      {VoidCallback? onTap, Color color = AppColors.ink}) {
    return PressableWidget(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.glass,
          border: Border.all(color: AppColors.line, width: 1),
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

/// Sección de reseñas: lista las reseñas de la cancha desde Notion y permite
/// agregar una nueva (rating + comentario).
class _ReviewsSection extends StatefulWidget {
  final String courtId;
  const _ReviewsSection({required this.courtId});

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  final _notion = NotionService();
  late Future<List<Review>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Review>> _fetch() async {
    if (!_notion.isConfigured) return [];
    try {
      final rows = await _notion.queryDatabase(
        NotionConfig.dbReviews,
        filter: NotionService.filterText('CourtId', widget.courtId),
      );
      return rows.map(Review.fromNotion).toList();
    } catch (_) {
      return [];
    }
  }

  void _refresh() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Reseñas',
          right: 'Escribir',
          onRight: () => _openReviewDialog(context),
        ),
        FutureBuilder<List<Review>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white(0.4)),
                  ),
                ),
              );
            }
            // Ocultamos reseñas de usuarios bloqueados en este dispositivo.
            final blocked = context.watch<BlockedProvider>();
            final reviews = (snap.data ?? [])
                .where((r) => !blocked.isBlocked(r.userEmail))
                .toList();
            if (reviews.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                // Card plana: fill sin borde (lenguaje editorial).
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppShape.rCard),
                ),
                child: Text(
                  'Todavía no hay reseñas. ¡Sé el primero!',
                  style: AppText.grotesk(size: 13, color: AppColors.white(0.5)),
                ),
              );
            }
            return Column(
              children: [for (final r in reviews) _reviewCard(r)],
            );
          },
        ),
      ],
    );
  }

  Widget _reviewCard(Review r) {
    final session = context.read<Session>();
    final isAdmin = session.isAdmin;
    final myEmail = (session.email ?? '').trim().toLowerCase();
    final isMine = r.userEmail.trim().toLowerCase() == myEmail;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      // Card plana: fill sin borde (lenguaje editorial).
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Icon(
                  i < r.rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 16,
                  color: AppColors.accent,
                ),
              const Spacer(),
              // Reportar/bloquear la reseña de otro usuario (UGC). Con `child`
              // (no `icon`) el botón mide lo que mide el ícono: el IconButton
              // interno de `icon:` impone 48px y deformaba la card.
              if (!isMine && r.userEmail.isNotEmpty) ...[
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  color: AppColors.bgElev,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.more_horiz,
                        size: 16, color: AppColors.white(0.4)),
                  ),
                  onSelected: (v) {
                    if (v == 'report') _reportReview(r);
                    if (v == 'block') _blockReviewer(r);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'report',
                      child: Row(children: [
                        Icon(Icons.flag_outlined, size: 16, color: AppColors.white(0.7)),
                        const SizedBox(width: 10),
                        Text('Reportar', style: AppText.grotesk(size: 13)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Row(children: [
                        Icon(Icons.block, size: 16, color: AppColors.white(0.7)),
                        const SizedBox(width: 10),
                        Text('Bloquear usuario', style: AppText.grotesk(size: 13)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
              if (isAdmin)
                GestureDetector(
                  onTap: () => _deleteReview(r),
                  child: Icon(Icons.close, size: 16, color: AppColors.white(0.4)),
                ),
              if (isAdmin) const SizedBox(width: 8),
              Text(
                r.userHandle.isNotEmpty ? r.userHandle : r.userEmail.split('@').first,
                style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
              ),
            ],
          ),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.comment, style: AppText.grotesk(size: 13, color: AppColors.white(0.8), height: 1.4)),
          ],
        ],
      ),
    );
  }

  Future<void> _reportReview(Review r) async {
    final me = (context.read<Session>().email ?? '').trim().toLowerCase();
    final ok = await ReportService.report(
      tipo: 'reseña',
      referencia: 'Autor: ${r.userHandle.isNotEmpty ? r.userHandle : r.userEmail} · "${r.comment}"',
      reportadoPor: me,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Gracias, revisaremos el reporte.'
              : 'No se pudo abrir el mail. Escribinos a $kSupportEmail.',
          style: AppText.grotesk(size: 13),
        ),
        backgroundColor: AppColors.bgElev,
      ),
    );
  }

  Future<void> _blockReviewer(Review r) async {
    await context.read<BlockedProvider>().block(r.userEmail);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bloqueaste a ${r.userHandle.isNotEmpty ? r.userHandle : r.userEmail}. No verás más su contenido.',
            style: AppText.grotesk(size: 13)),
        backgroundColor: AppColors.bgElev,
      ),
    );
  }

  Future<void> _deleteReview(Review r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Eliminar reseña',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: Text(
          '¿Eliminar la reseña de ${r.userHandle.isNotEmpty ? r.userHandle : r.userEmail.split('@').first}?',
          style: AppText.grotesk(size: 14, color: AppColors.white(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: AppText.grotesk(size: 13, color: AppColors.white(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: AppText.grotesk(size: 13, color: _danger, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await NotionService().archivePage(r.pageId);
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reseña eliminada', style: AppText.grotesk(size: 13)),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _openReviewDialog(BuildContext context) async {
    final session = context.read<Session>();
    if (session.email == null) return;
    // Solo puede reseñar quien jugó al menos una vez en la cancha (evita
    // reseñas de gente que nunca pisó el lugar).
    final played =
        context.read<PlaySessionService>().secondsForCourt(widget.courtId) > 0;
    if (!played) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Jugá al menos una vez en esta cancha para dejar una reseña.',
            style: AppText.grotesk(size: 13),
          ),
          backgroundColor: AppColors.bgElev,
        ),
      );
      return;
    }
    int rating = 5;
    final commentCtrl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // El fondo/forma los pone el dialogTheme global (neobrutalista).
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Tu reseña', style: AppText.archivo(size: 18, weight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    PressableWidget(
                      onTap: () => setLocal(() => rating = i),
                      child: Icon(
                        i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: AppColors.accent,
                        size: 30,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                style: AppText.grotesk(size: 14),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: 'Contá tu experiencia...',
                  hintStyle: AppText.grotesk(size: 13, color: AppColors.white(0.35)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                    borderSide:
                        BorderSide(color: AppColors.white(0.25), width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                    borderSide:
                        const BorderSide(color: AppColors.accent, width: 1),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar', style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      setLocal(() => saving = true);
                      try {
                        await _notion.createPage(
                          NotionConfig.dbReviews,
                          Review(
                            courtId: widget.courtId,
                            userEmail: session.email!,
                            userHandle: session.profile?.handle ?? '',
                            rating: rating.toDouble(),
                            comment: commentCtrl.text.trim(),
                            createdAt: DateTime.now().toIso8601String(),
                          ).toNotionProperties(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _refresh();
                      } catch (_) {
                        setLocal(() => saving = false);
                      }
                    },
              child: Text('Publicar',
                  style: AppText.grotesk(size: 13, weight: FontWeight.w700, color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}
