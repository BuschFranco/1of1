import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../data/legal_content.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import '../services/blocked_provider.dart';
import '../services/court_rating_service.dart';
import '../services/favorites_provider.dart';
import '../services/notion_service.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/report_service.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/pop_button.dart';
import '../widgets/pop_panel.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/section_title.dart';
import '../widgets/status_dot.dart';
import 'pickup_create_screen.dart';

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
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(
                                color: AppColors.white(0.25), width: 1.5),
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
                    const SizedBox(height: 24),
                    const SectionTitle(
                        title: 'Jugando ahora', right: 'Ver todos'),
                    _playersRow(court),
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

  Widget _hero(Court court) {
    return SizedBox(
      height: 360,
      child: Stack(
        children: [
          Positioned.fill(child: CourtImage(url: court.img)),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.black(0.15),
                    AppColors.black(0.6),
                    AppColors.bg,
                  ],
                  stops: [0, 0.65, 1],
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
                    const SizedBox(width: 8),
                    Text(
                      '· ${court.players} JUGANDO AHORA',
                      style: AppText.grotesk(
                        size: 10.5,
                        color: AppColors.white(0.6),
                        letterSpacing: 0.1,
                      ),
                    ),
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
                Text(
                  '${court.area} · ${court.dist} · ${court.hoursLabel}',
                  style: AppText.grotesk(
                    size: 13,
                    color: AppColors.white(0.6),
                  ),
                ),
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

  /// Lista de jugadores que están jugando ahora en esta cancha (solo los que
  /// lo permiten: shareCourt; el tiempo se muestra si además shareTime).
  Widget _playingNow(Court court) {
    return Builder(builder: (context) {
      final players = context
          .watch<ProfilesProvider>()
          .all
          .where((p) =>
              p.playing && p.shareCourt && p.playingCourtId == court.id)
          .toList();
      if (players.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'Jugando ahora'),
            for (final p in players)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border:
                        Border.all(color: AppColors.white(0.25), width: 1.5),
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.open,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.handle.isNotEmpty
                              ? p.handle
                              : (p.name.isEmpty ? 'Jugador' : p.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.grotesk(
                              size: 13, weight: FontWeight.w600),
                        ),
                      ),
                      if (p.shareTime && p.playingSince.isNotEmpty)
                        Builder(builder: (_) {
                          final since = DateTime.tryParse(p.playingSince);
                          if (since == null) return const SizedBox.shrink();
                          return Text(
                            PlaySessionService.fmt(
                                DateTime.now().difference(since).inSeconds),
                            style: AppText.grotesk(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.accent),
                          );
                        }),
                    ],
                  ),
                ),
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
    return PopPanel(
      radius: AppShape.rCard,
      padding: const EdgeInsets.all(14),
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
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.white(0.25), width: 1.5),
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

  Widget _playersRow(Court court) {
    const avatars = [
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&q=80',
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&q=80',
      'https://images.unsplash.com/photo-1531427186611-ecfd6d936c79?w=100&q=80',
      'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100&q=80',
    ];
    return Row(
      children: [
        SizedBox(
          width: 36 + (avatars.length + 1) * 26,
          height: 36,
          child: Stack(
            children: [
              for (var i = 0; i < avatars.length; i++)
                Positioned(
                  left: i * 26,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 1),
                      image: DecorationImage(
                        image: NetworkImage(avatars[i]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: avatars.length * 26,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgElev,
                    border: Border.all(color: AppColors.bg, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+${court.players - 4}',
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
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${court.players} jugadores',
              style: AppText.archivo(size: 14, weight: FontWeight.w700),
            ),
            Text(
              'Pickup game · 5v5',
              style: AppText.grotesk(size: 11, color: AppColors.white(0.5)),
            ),
          ],
        ),
      ],
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
                        color: const Color(0xFFEF4444),
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
          color: const Color(0xFFEF4444).withAlpha(20),
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(
              color: const Color(0xFFEF4444).withAlpha(60), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline,
                size: 18, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Text('ELIMINAR CANCHA',
                style: AppText.archivo(
                    size: 13,
                    weight: FontWeight.w800,
                    color: const Color(0xFFEF4444))),
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
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border:
                      Border.all(color: AppColors.white(0.25), width: 1.5),
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
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.white(0.25), width: 1.5),
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
              // Reportar/bloquear la reseña de otro usuario (UGC).
              if (!isMine && r.userEmail.isNotEmpty) ...[
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, size: 16, color: AppColors.white(0.4)),
                  color: AppColors.bgElev,
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
                style: AppText.grotesk(size: 13, color: const Color(0xFFEF4444), weight: FontWeight.w700)),
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
