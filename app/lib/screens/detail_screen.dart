import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../data/legal_content.dart';
import '../data/models.dart';
import '../services/api/api_client.dart';
import '../services/api/api_config.dart';
import '../services/blocked_provider.dart';
import '../services/cache/api_cache.dart';
import '../services/court_owner_cache.dart';
import '../services/court_rating_service.dart';
import '../services/courts_provider.dart';
import '../services/favorites_provider.dart';
import '../services/location_service.dart';
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
                    _CourtOwnerCard(courtId: court.id),
                    _CourtKingCard(courtId: court.id),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _MyCourtStats(courtId: court.id),
                    ),
                    _playingNow(court),
                    _MyCourtHistory(courtId: court.id),
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
                    _PostsSection(courtId: court.id),
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
        // Capturado antes del await (lint use_build_context_synchronously).
        final courtsProvider = context.read<CourtsProvider>();
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
          // El server archiva la cancha y sus reseñas (solo admin).
          await courtsProvider.deleteCourt(court.id);
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

/// Decoración compartida de los inputs de texto de los diálogos (reseña,
/// publicación, comentario). Rectángulo redondeado (no píldora), fondo hundido
/// más oscuro que el diálogo para dar profundidad, borde sutil que se acenta al
/// enfocar. Se centraliza acá para que los tres se vean igual.
InputDecoration _dialogFieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AppText.grotesk(size: 13, color: AppColors.white(0.35)),
    filled: true,
    fillColor: AppColors.bg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppShape.rField),
      borderSide: BorderSide(color: AppColors.white(0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppShape.rField),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
    ),
  );
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
  late Future<List<Review>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Review>> _fetch() async {
    try {
      return await context
          .read<CourtRatingService>()
          .listReviews(widget.courtId);
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
          // Semilla del cache: si ya se cargaron antes, se ven al instante
          // (sin spinner) mientras se revalida en segundo plano.
          initialData: ApiCache.peek<List<Review>>(
              CourtRatingService.reviewsKey(widget.courtId)),
          builder: (context, snap) {
            if (!snap.hasData &&
                snap.connectionState == ConnectionState.waiting) {
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
      // El server valida: dueño de la reseña o admin.
      await context
          .read<CourtRatingService>()
          .deleteReview(r.pageId, courtId: widget.courtId);
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
                decoration: _dialogFieldDecoration('Contá tu experiencia...'),
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
                        // Email y handle salen del token en el server.
                        await context.read<CourtRatingService>().createReview(
                              widget.courtId,
                              rating: rating,
                              comment: commentCtrl.text.trim(),
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

// ── Clan que conquistó la cancha ────────────────────────────────────────────

/// Card con el clan "dueño" de la cancha: el de más puntos históricos
/// acumulados acá (agregado server-side desde la DB Partidos, agrupando por la
/// insignia de clan de cada jugador). Sin dueño no se muestra nada; si el
/// dueño es MI clan, la card se tinta con el acento.
class _CourtOwnerCard extends StatefulWidget {
  final String courtId;
  const _CourtOwnerCard({required this.courtId});

  @override
  State<_CourtOwnerCard> createState() => _CourtOwnerCardState();
}

class _CourtOwnerCardState extends State<_CourtOwnerCard> {
  String? _clan;
  int _points = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic>? owner) {
    _clan = (owner?['clan'] ?? '').toString();
    _points = (owner?['points'] as num?)?.round() ?? 0;
  }

  Future<void> _load() async {
    if (!ApiConfig.isConfigured || !context.read<Session>().isLoggedIn) return;
    // Pintar al instante lo cacheado (aunque esté viejo), sin spinner.
    final cached = ApiCache.peek<Map<String, dynamic>?>(
        CourtOwnerCache.ownerKey(widget.courtId));
    if (cached != null) _apply(cached);
    // Fresco → no toca la red; viejo/ausente → refresca en segundo plano.
    final data = await CourtOwnerCache.ownerDataFor(widget.courtId);
    if (!mounted) return;
    setState(() => _apply(data));
  }

  @override
  Widget build(BuildContext context) {
    final clan = _clan;
    if (clan == null || clan.isEmpty) return const SizedBox.shrink();
    final myClan =
        (context.watch<Session>().profile?.clan ?? '').trim().toUpperCase();
    final isMine = myClan.isNotEmpty && clan == myClan;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isMine ? AppColors.accent.withAlpha(18) : AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Conquistada esta temporada por',
                  style:
                      AppText.grotesk(size: 13, color: AppColors.white(0.7))),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(clan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.archivo(
                      size: 15,
                      weight: FontWeight.w900,
                      color: AppColors.accent)),
            ),
            const SizedBox(width: 8),
            Text('$_points EXP',
                style:
                    AppText.grotesk(size: 10, color: AppColors.white(0.35))),
          ],
        ),
      ),
    );
  }
}

// ── Rey de la cancha (jugador con más puntos esta temporada) ─────────────────

/// Card con el jugador que más puntos hizo en esta cancha EN LA TEMPORADA
/// actual. Se reinicia cada temporada, igual que la conquista de clan. Sin
/// nadie con puntos, no se muestra.
class _CourtKingCard extends StatefulWidget {
  final String courtId;
  const _CourtKingCard({required this.courtId});

  @override
  State<_CourtKingCard> createState() => _CourtKingCardState();
}

class _CourtKingCardState extends State<_CourtKingCard> {
  String? _name;
  String _handle = '';
  int _points = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic>? king) {
    _name = (king?['name'] ?? '').toString();
    _handle = (king?['handle'] ?? '').toString();
    _points = (king?['points'] as num?)?.round() ?? 0;
  }

  Future<void> _load() async {
    if (!ApiConfig.isConfigured || !context.read<Session>().isLoggedIn) return;
    final cached = ApiCache.peek<Map<String, dynamic>?>(
        CourtOwnerCache.kingKey(widget.courtId));
    if (cached != null) _apply(cached);
    final data = await CourtOwnerCache.kingDataFor(widget.courtId);
    if (!mounted) return;
    setState(() => _apply(data));
  }

  @override
  Widget build(BuildContext context) {
    final name = _name;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rey de la cancha esta temporada',
                      style: AppText.grotesk(
                          size: 13, color: AppColors.white(0.7))),
                  if (_handle.isNotEmpty)
                    Text(_handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.grotesk(
                            size: 10, color: AppColors.white(0.4))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.archivo(
                      size: 15,
                      weight: FontWeight.w900,
                      color: AppColors.accent)),
            ),
            const SizedBox(width: 8),
            Text('$_points EXP',
                style:
                    AppText.grotesk(size: 10, color: AppColors.white(0.35))),
          ],
        ),
      ),
    );
  }
}

// ── Mis stats en esta cancha ────────────────────────────────────────────────

/// Card con el tiempo jugado y los puntos acumulados en ESTA cancha. El tiempo
/// es local (en vivo, incluye la sesión en curso); los puntos vienen de la DB
/// Partidos del backend (sobreviven reinstalaciones y no están capados a los
/// últimos 100 partidos del log). Se muestran DOS totales: el de la temporada
/// actual (lo que compite) y el histórico de por vida. Mientras la DB no
/// respondió —o si lo local supera lo subido (partidos pendientes de sync)— se
/// usa la suma local.
class _MyCourtStats extends StatefulWidget {
  final String courtId;
  const _MyCourtStats({required this.courtId});

  @override
  State<_MyCourtStats> createState() => _MyCourtStatsState();
}

class _MyCourtStatsState extends State<_MyCourtStats> {
  int? _dbPoints;
  int? _dbSeasonPoints;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic> r) {
    _dbPoints = (r['points'] as num?)?.toInt() ?? 0;
    _dbSeasonPoints = (r['seasonPoints'] as num?)?.toInt() ?? 0;
  }

  Future<void> _load() async {
    if (!ApiConfig.isConfigured || !context.read<Session>().isLoggedIn) return;
    final key = 'mypoints::${widget.courtId}';
    final cached = ApiCache.peek<Map<String, dynamic>>(key);
    // Aplicar lo cacheado ANTES del primer build (sin setState: estamos en el
    // flujo de initState). Si está fresco, no se toca la red.
    if (cached != null) _apply(cached);
    if (cached != null && ApiCache.isFresh(key, ApiCache.ttlMyPoints)) {
      return;
    }
    try {
      final r = await ApiClient().courtPoints(widget.courtId);
      final data = <String, dynamic>{
        'points': (r['points'] as num?)?.toInt() ?? 0,
        'seasonPoints': (r['seasonPoints'] as num?)?.toInt() ?? 0,
      };
      ApiCache.put(key, data);
      if (!mounted) return;
      setState(() => _apply(data));
    } catch (_) {/* sin red: queda el estimado local o lo cacheado */}
  }

  @override
  Widget build(BuildContext context) {
    final play = context.watch<PlaySessionService>();
    final secs = play.secondsForCourt(widget.courtId);
    final mine = play.log.where((e) => e.courtId == widget.courtId);
    final localPts = mine.fold(0, (a, e) => a + e.points);
    // Suma local de la temporada actual (fallback si la DB no respondió).
    final seasonStartMs =
        PlaySessionService.seasonStart().millisecondsSinceEpoch;
    final localSeasonPts = mine
        .where((e) => e.endedAtMillis >= seasonStartMs)
        .fold(0, (a, e) => a + e.points);
    final pts =
        _dbPoints == null || localPts > _dbPoints! ? localPts : _dbPoints!;
    final seasonPts = _dbSeasonPoints == null || localSeasonPts > _dbSeasonPoints!
        ? localSeasonPts
        : _dbSeasonPoints!;

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Text(label,
                  style:
                      AppText.grotesk(size: 13, color: AppColors.white(0.7))),
              const Spacer(),
              Text(value,
                  style: AppText.archivo(
                      size: 15,
                      weight: FontWeight.w800,
                      color: AppColors.accent)),
            ],
          ),
        );

    Widget divider() => Container(height: 1, color: AppColors.white(0.06));

    return Container(
      clipBehavior: Clip.antiAlias,
      // Card plana: fill sin borde (lenguaje editorial).
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: Column(
        children: [
          row(Icons.timer_outlined, 'Jugaste acá',
              PlaySessionService.fmt(secs)),
          divider(),
          row(Icons.military_tech, 'EXP esta temporada', '$seasonPts EXP'),
          divider(),
          row(Icons.star_rounded, 'EXP histórica', '$pts EXP'),
        ],
      ),
    );
  }
}

// ── Historial de partidos en esta cancha ────────────────────────────────────

/// Últimos partidos jugados en ESTA cancha, desde el log local del dispositivo
/// (mismo lenguaje que el historial del perfil). Sin partidos acá no se
/// muestra nada.
class _MyCourtHistory extends StatelessWidget {
  final String courtId;
  const _MyCourtHistory({required this.courtId});

  static const int _maxRows = 10;

  (Color, String) _resultStyle(PlayResult? r) {
    switch (r) {
      case PlayResult.win:
        return (AppColors.open, 'VICTORIA');
      case PlayResult.loss:
        return (AppColors.accentDark, 'DERROTA');
      case PlayResult.tie:
        return (AppColors.white(0.7), 'EMPATE');
      case PlayResult.training:
        return (AppColors.accent, 'ENTREN.');
      case PlayResult.notCounted:
      case null:
        return (AppColors.white(0.45), 'S/INFO');
    }
  }

  String _fmtDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final matches = context
        .watch<PlaySessionService>()
        .log
        .where((e) => e.courtId == courtId)
        .toList();
    if (matches.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < matches.length && i < _maxRows; i++) {
      if (i > 0) rows.add(Container(height: 1, color: AppColors.white(0.06)));
      rows.add(_row(matches[i]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        const SectionTitle(title: 'Tus partidos acá'),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppShape.rCard),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _row(PlaySession s) {
    final (color, label) = _resultStyle(s.result);
    // Fila plana: dot+etiqueta de color, duración · fecha y puntos a la
    // derecha (sin nombre de cancha: ya estamos en su detalle).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: AppText.grotesk(
                  size: 10,
                  weight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.06)),
          Expanded(
            child: Text(
              '  ·  ${PlaySessionService.fmt(s.seconds)}  ·  ${_fmtDate(s.endedAtMillis)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
            ),
          ),
          const SizedBox(width: 8),
          if (s.points > 0) ...[
            Text('+${s.points}',
                style: AppText.archivo(
                    size: 14,
                    weight: FontWeight.w900,
                    color: AppColors.accent)),
            const SizedBox(width: 1),
            Text('EXP',
                style:
                    AppText.grotesk(size: 10, color: AppColors.white(0.45))),
          ],
        ],
      ),
    );
  }
}

// ── Publicaciones de la cancha ──────────────────────────────────────────────

class _PostsSection extends StatefulWidget {
  final String courtId;
  const _PostsSection({required this.courtId});

  @override
  State<_PostsSection> createState() => _PostsSectionState();
}

class _PostsSectionState extends State<_PostsSection> {
  late Future<List<CourtPost>> _future;
  List<CourtPost> posts = [];

  String get _cacheKey => 'posts::${widget.courtId}';

  @override
  void initState() {
    super.initState();
    // Semilla del cache para que los likes/comentarios tengan datos al toque.
    final cached = ApiCache.peek<List<CourtPost>>(_cacheKey);
    if (cached != null) posts = cached;
    _future = _fetch();
  }

  Future<List<CourtPost>> _fetch({bool force = false}) async {
    final cached = ApiCache.peek<List<CourtPost>>(_cacheKey);
    if (!force && cached != null && ApiCache.isFresh(_cacheKey, ApiCache.ttlPosts)) {
      posts = cached;
      return cached;
    }
    try {
      final data = await ApiClient().courtPosts(widget.courtId);
      final List rows = (data['items'] as List?) ?? [];
      final list = rows.map<CourtPost>((r) => CourtPost.fromApi(r)).toList();
      ApiCache.put(_cacheKey, list);
      if (mounted) setState(() => posts = list);
      return list;
    } catch (e) {
      debugPrint('courtPosts fetch error: $e');
      // Si hay algo cacheado (aunque viejo), mostrarlo en vez del error.
      if (cached != null) {
        posts = cached;
        return cached;
      }
      // Nada que mostrar: relanzar para la tarjeta de error con "Reintentar".
      rethrow;
    }
  }

  // Tras crear/borrar/comentar: invalidar el cache y traer fresco.
  void _refresh() {
    ApiCache.invalidate(_cacheKey);
    setState(() => _future = _fetch(force: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Publicaciones',
          right: 'Publicar',
          onRight: () => _openPostDialog(context),
        ),
        FutureBuilder<List<CourtPost>>(
          future: _future,
          // Semilla del cache: reentrar a la cancha muestra los posts al toque.
          initialData: ApiCache.peek<List<CourtPost>>(_cacheKey),
          builder: (context, snap) {
            if (!snap.hasData &&
                snap.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white(0.4)),
                  ),
                ),
              );
            }
            if (snap.hasError) {
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppShape.rCard),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No se pudieron cargar las publicaciones.',
                      style: AppText.grotesk(
                          size: 13, color: AppColors.white(0.7)),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _refresh,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 16, color: AppColors.accent),
                          const SizedBox(width: 6),
                          Text(
                            'Reintentar',
                            style: AppText.grotesk(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            final blocked = context.watch<BlockedProvider>();
            final posts = (snap.data ?? [])
                .where((p) => !blocked.isBlocked(p.userEmail))
                .toList();
            if (posts.isEmpty) {
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppShape.rCard),
                ),
                child: Text(
                  'Todavía no hay publicaciones. ¡Sé el primero!',
                  style:
                      AppText.grotesk(size: 13, color: AppColors.white(0.5)),
                ),
              );
            }
            return Column(
              children: [for (final p in posts) _postCard(p)],
            );
          },
        ),
      ],
    );
  }

  Widget _postCard(CourtPost p) {
    final session = context.read<Session>();
    final isAdmin = session.isAdmin;
    final myEmail = (session.email ?? '').trim().toLowerCase();
    final isMine = p.userEmail.trim().toLowerCase() == myEmail;
    final date = p.createdAt != null ? _fmtDate(p.createdAt!) : '';
    // Estado local del like: se captura por el StatefulBuilder y persiste entre
    // rebuilds. Antes se actualizaba `posts[idx]` pero se renderizaba desde `p`
    // (variable vieja), así que el ícono nunca cambiaba al dar like.
    bool liked = p.likedByMe;
    int likeCount = p.likeCount;
    bool liking = false;
    return StatefulBuilder(
      builder: (context, setLocal) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openPostDetail(p),
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: autor + fecha + menú.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.userHandle.isNotEmpty ? p.userHandle : 'Anon',
                        style: AppText.grotesk(
                            size: 13, weight: FontWeight.w700),
                      ),
                      if (date.isNotEmpty)
                        Text(date,
                            style: AppText.grotesk(
                                size: 10, color: AppColors.white(0.4))),
                    ],
                  ),
                ),
                if (!isMine && p.userEmail.isNotEmpty)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    color: AppColors.bgElev,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.more_horiz,
                          size: 16, color: AppColors.white(0.4)),
                    ),
                    onSelected: (v) async {
                      if (v == 'report') {
                        await ReportService.report(
                          tipo: 'publicación',
                          referencia: '${p.userHandle} — ${p.pageId}',
                          detalle: 'Publicación reportada desde detalle de cancha',
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Publicación reportada',
                                  style: AppText.grotesk(size: 13)),
                              backgroundColor: AppColors.bgElev,
                            ),
                          );
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'report',
                        child: Text('Reportar',
                            style: AppText.grotesk(size: 13)),
                      ),
                    ],
                  )
                else if (isMine || isAdmin)
                  PressableWidget(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text('Eliminar publicación',
                              style: AppText.archivo(
                                  size: 16, weight: FontWeight.w800)),
                          content: Text('¿Seguro que querés eliminar esta publicación?',
                              style: AppText.grotesk(size: 13)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text('Cancelar',
                                  style: AppText.grotesk(
                                      size: 13, color: AppColors.white(0.6))),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text('Eliminar',
                                  style: AppText.grotesk(
                                      size: 13, color: _danger)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await ApiClient().deletePost(p.pageId);
                          _refresh();
                        } catch (_) {}
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 16, color: _danger),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Contenido (truncado; el detalle muestra todo).
            Text(
              p.content,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppText.grotesk(
                  size: 13, color: AppColors.white(0.85), height: 1.5),
            ),
            // Like + comentarios (abre el detalle).
            const SizedBox(height: 4),
            Row(
              children: [
                PressableWidget(
                  onTap: () async {
                    if (liking) return;
                    liking = true;
                    // Optimista: reflejar el toque al instante.
                    setLocal(() {
                      liked = !liked;
                      likeCount += liked ? 1 : -1;
                      if (likeCount < 0) likeCount = 0;
                    });
                    try {
                      final res = await ApiClient().togglePostLike(p.pageId);
                      final serverCount = (res['likeCount'] as num?)?.toInt();
                      final serverLiked = res['likedByMe'] as bool?;
                      setLocal(() {
                        if (serverCount != null) likeCount = serverCount;
                        if (serverLiked != null) liked = serverLiked;
                      });
                      // Mirror al listado para que un rebuild externo no revierta.
                      final idx =
                          posts.indexWhere((x) => x.pageId == p.pageId);
                      if (idx >= 0) {
                        final old = posts[idx];
                        posts[idx] = CourtPost(
                          pageId: old.pageId,
                          courtId: old.courtId,
                          userEmail: old.userEmail,
                          userHandle: old.userHandle,
                          content: old.content,
                          createdAt: old.createdAt,
                          likeCount: likeCount,
                          likedByMe: liked,
                          comments: old.comments,
                        );
                      }
                    } catch (_) {
                      // Revertir el optimismo si falló.
                      setLocal(() {
                        liked = !liked;
                        likeCount += liked ? 1 : -1;
                        if (likeCount < 0) likeCount = 0;
                      });
                    } finally {
                      liking = false;
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          size: 20,
                          color: liked
                              ? AppColors.accent
                              : AppColors.white(0.5),
                        ),
                        if (likeCount > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            '$likeCount',
                            style: AppText.grotesk(
                                size: 12,
                                weight: FontWeight.w600,
                                color: liked
                                    ? AppColors.accent
                                    : AppColors.white(0.5)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PressableWidget(
                  onTap: () => _openPostDetail(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mode_comment_outlined,
                            size: 18, color: AppColors.white(0.5)),
                        const SizedBox(width: 5),
                        Text(
                          p.comments.isEmpty
                              ? 'Comentar'
                              : '${p.comments.length} comentario${p.comments.length == 1 ? '' : 's'}',
                          style: AppText.grotesk(
                              size: 12,
                              weight: FontWeight.w600,
                              color: AppColors.white(0.5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// Abre el detalle de una publicación (fecha completa + lista de comentarios +
  /// input) en una hoja modal. Los cambios (like, nuevo comentario) vuelven por
  /// [onChanged] para mantener el listado en sync sin recargar todo.
  Future<void> _openPostDetail(CourtPost p) async {
    final session = context.read<Session>();
    final isAdmin = session.isAdmin;
    final myEmail = (session.email ?? '').trim().toLowerCase();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostDetailSheet(
        post: p,
        isAdmin: isAdmin,
        myEmail: myEmail,
        onChanged: _applyPostUpdate,
        onDeleted: _refresh,
      ),
    );
  }

  /// Reemplaza una publicación en el listado (y en el cache) tras un cambio en
  /// el detalle, y repinta.
  void _applyPostUpdate(CourtPost updated) {
    final idx = posts.indexWhere((x) => x.pageId == updated.pageId);
    if (idx < 0) return;
    posts[idx] = updated;
    ApiCache.put(_cacheKey, posts);
    if (mounted) setState(() {});
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  // ── Dialog: nueva publicación ────────────────────────────────────────────

  Future<void> _openPostDialog(BuildContext context) async {
    final session = context.read<Session>();
    if (session.email == null) return;
    // Solo puede publicar quien jugó al menos una vez en la cancha.
    final played =
        context.read<PlaySessionService>().secondsForCourt(widget.courtId) > 0;
    if (!played) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Jugá al menos una vez en esta cancha para publicar.',
            style: AppText.grotesk(size: 13),
          ),
          backgroundColor: AppColors.bgElev,
        ),
      );
      return;
    }
    final ctrl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Nueva publicación',
              style: AppText.archivo(size: 18, weight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Una publicación por día en esta cancha.',
                style: AppText.grotesk(size: 12, color: AppColors.white(0.45)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                maxLength: 300,
                style: AppText.grotesk(size: 14),
                cursorColor: AppColors.accent,
                decoration: _dialogFieldDecoration('¿Qué pasó en la cancha?'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: AppText.grotesk(
                      size: 13, color: AppColors.white(0.6))),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final text = ctrl.text.trim();
                      if (text.isEmpty) return;
                      setLocal(() => saving = true);
                      try {
                        await ApiClient().createPost(widget.courtId,
                            content: text);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _refresh();
                      } catch (e) {
                        setLocal(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().contains('Ya publicaste hoy')
                                    ? 'Ya publicaste hoy en esta cancha.'
                                    : 'Error al publicar.',
                                style: AppText.grotesk(size: 13),
                              ),
                              backgroundColor: AppColors.bgElev,
                            ),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent))
                  : Text('Publicar',
                      style: AppText.grotesk(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }

}

/// Fecha corta dd/mm de una publicación/comentario.
String _fmtPostShortDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Fecha + hora completas (dd/mm/aaaa · hh:mm) para el detalle.
String _fmtPostDateTime(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year} · $hh:$min';
}

/// Hoja de detalle de una publicación: fecha completa, contenido, like y la
/// lista completa de comentarios con su input. Comentar es optimista (aparece
/// al instante). Los cambios vuelven al listado por [onChanged].
class _PostDetailSheet extends StatefulWidget {
  final CourtPost post;
  final bool isAdmin;
  final String myEmail;
  final void Function(CourtPost updated) onChanged;
  final VoidCallback onDeleted;
  const _PostDetailSheet({
    required this.post,
    required this.isAdmin,
    required this.myEmail,
    required this.onChanged,
    required this.onDeleted,
  });

  @override
  State<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends State<_PostDetailSheet> {
  late List<PostComment> _comments;
  late bool _liked;
  late int _likeCount;
  bool _liking = false;
  bool _sending = false;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _comments = List.of(widget.post.comments);
    _liked = widget.post.likedByMe;
    _likeCount = widget.post.likeCount;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  CourtPost get _current => CourtPost(
        pageId: widget.post.pageId,
        courtId: widget.post.courtId,
        userEmail: widget.post.userEmail,
        userHandle: widget.post.userHandle,
        content: widget.post.content,
        createdAt: widget.post.createdAt,
        likeCount: _likeCount,
        likedByMe: _liked,
        comments: _comments,
      );

  Future<void> _toggleLike() async {
    if (_liking) return;
    _liking = true;
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
      if (_likeCount < 0) _likeCount = 0;
    });
    try {
      final res = await ApiClient().togglePostLike(widget.post.pageId);
      final c = (res['likeCount'] as num?)?.toInt();
      final l = res['likedByMe'] as bool?;
      setState(() {
        if (c != null) _likeCount = c;
        if (l != null) _liked = l;
      });
      widget.onChanged(_current);
    } catch (_) {
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
        if (_likeCount < 0) _likeCount = 0;
      });
    } finally {
      _liking = false;
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final json =
          await ApiClient().addPostComment(widget.post.pageId, content: text);
      final c = PostComment.fromApi(json);
      setState(() {
        _comments = [..._comments, c];
        _ctrl.clear();
        _sending = false;
      });
      widget.onChanged(_current);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    } catch (_) {
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al comentar.',
                style: AppText.grotesk(size: 13)),
            backgroundColor: AppColors.bgElev,
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Eliminar publicación',
            style: AppText.archivo(size: 16, weight: FontWeight.w800)),
        content: Text('¿Seguro que querés eliminar esta publicación?',
            style: AppText.grotesk(size: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar',
                style:
                    AppText.grotesk(size: 13, color: AppColors.white(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar',
                style: AppText.grotesk(size: 13, color: _danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiClient().deletePost(widget.post.pageId);
        if (mounted) Navigator.pop(context);
        widget.onDeleted();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.post.userEmail.trim().toLowerCase() == widget.myEmail;
    final dt =
        widget.post.createdAt != null ? _fmtPostDateTime(widget.post.createdAt!) : '';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Manija.
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.white(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header: autor + fecha completa + eliminar.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post.userHandle.isNotEmpty
                              ? widget.post.userHandle
                              : 'Anon',
                          style: AppText.grotesk(
                              size: 15, weight: FontWeight.w800),
                        ),
                        if (dt.isNotEmpty)
                          Text(dt,
                              style: AppText.grotesk(
                                  size: 11, color: AppColors.white(0.4))),
                      ],
                    ),
                  ),
                  if (isMine || widget.isAdmin)
                    PressableWidget(
                      onTap: _delete,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline,
                            size: 18, color: _danger),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Contenido completo.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.post.content,
                  style: AppText.grotesk(
                      size: 14, color: AppColors.white(0.9), height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Like.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  PressableWidget(
                    onTap: _toggleLike,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _liked ? Icons.favorite : Icons.favorite_border,
                            size: 20,
                            color: _liked
                                ? AppColors.accent
                                : AppColors.white(0.5),
                          ),
                          if (_likeCount > 0) ...[
                            const SizedBox(width: 5),
                            Text('$_likeCount',
                                style: AppText.grotesk(
                                    size: 12,
                                    weight: FontWeight.w600,
                                    color: _liked
                                        ? AppColors.accent
                                        : AppColors.white(0.5))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.white(0.06),
            ),
            // Título comentarios.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Comentarios (${_comments.length})',
                    style: AppText.grotesk(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.white(0.5))),
              ),
            ),
            // Lista.
            Flexible(
              child: _comments.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 24),
                      child: Text('Todavía no hay comentarios. ¡Sé el primero!',
                          style: AppText.grotesk(
                              size: 13, color: AppColors.white(0.4))),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      itemCount: _comments.length,
                      itemBuilder: (_, i) => _CommentTile(_comments[i]),
                    ),
            ),
            // Input.
            Padding(
              padding: EdgeInsets.fromLTRB(
                  12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      maxLength: 300,
                      minLines: 1,
                      maxLines: 4,
                      style: AppText.grotesk(size: 14),
                      cursorColor: AppColors.accent,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: _dialogFieldDecoration('Escribí un comentario...')
                          .copyWith(counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressableWidget(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppShape.rField),
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.send_rounded,
                              size: 20, color: Colors.black),
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
}

/// Un comentario en el detalle de la publicación, con su propio estado de like.
class _CommentTile extends StatefulWidget {
  final PostComment comment;
  const _CommentTile(this.comment);

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  late bool _liked;
  late int _likeCount;
  bool _liking = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.comment.likedByMe;
    _likeCount = widget.comment.likeCount;
  }

  Future<void> _toggle() async {
    if (_liking) return;
    _liking = true;
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
      if (_likeCount < 0) _likeCount = 0;
    });
    try {
      final res = await ApiClient().toggleCommentLike(widget.comment.pageId);
      final c = (res['likeCount'] as num?)?.toInt();
      final l = res['likedByMe'] as bool?;
      setState(() {
        if (c != null) _likeCount = c;
        if (l != null) _liked = l;
      });
    } catch (_) {
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
        if (_likeCount < 0) _likeCount = 0;
      });
    } finally {
      _liking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final date = c.createdAt != null ? _fmtPostShortDate(c.createdAt!) : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.userHandle.isNotEmpty ? c.userHandle : 'Anon',
                  style: AppText.grotesk(size: 11, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  c.content,
                  style: AppText.grotesk(
                      size: 12, color: AppColors.white(0.7), height: 1.4),
                ),
                const SizedBox(height: 4),
                PressableWidget(
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _liked ? Icons.favorite : Icons.favorite_border,
                          size: 14,
                          color:
                              _liked ? AppColors.accent : AppColors.white(0.4),
                        ),
                        if (_likeCount > 0) ...[
                          const SizedBox(width: 4),
                          Text('$_likeCount',
                              style: AppText.grotesk(
                                  size: 10,
                                  color: _liked
                                      ? AppColors.accent
                                      : AppColors.white(0.4))),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(date,
                  style:
                      AppText.grotesk(size: 9, color: AppColors.white(0.3))),
            ),
        ],
      ),
    );
  }
}
