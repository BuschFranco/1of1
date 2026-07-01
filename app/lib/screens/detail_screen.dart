import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import '../services/favorites_provider.dart';
import '../services/notion_service.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/pop_panel.dart';
import '../widgets/section_title.dart';
import '../widgets/status_dot.dart';

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
    final pool = courts.isNotEmpty ? courts : kCourts;
    final court = pool.firstWhere((c) => c.id == courtId,
        orElse: () => pool.first);

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
                    _ratingStrip(court),
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
                            color: const Color(0x801A2430),
                            border: Border.all(color: AppColors.white(0.06)),
                            borderRadius: BorderRadius.circular(14),
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x260A0F14),
                    Color(0x990A0F14),
                    AppColors.bg,
                  ],
                  stops: [0, 0.65, 1],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++) ...[
                  Container(
                    width: i == 0 ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == 0 ? Colors.white : AppColors.white(0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (i < 3) const SizedBox(width: 5),
                ],
              ],
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
                    letterSpacing: -0.03,
                    height: 0.95,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${court.area} · ${court.dist} · ${court.hours}',
                  style: AppText.grotesk(
                    size: 13,
                    color: AppColors.white(0.6),
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
                    color: const Color(0x801A2430),
                    border: Border.all(color: AppColors.white(0.06)),
                    borderRadius: BorderRadius.circular(14),
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

  Widget _ratingStrip(Court court) {
    return PopPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _statCell(
            icon: Icons.star_rounded,
            value: court.rating.toString(),
            label: '${court.reviews} reseñas',
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
        color: const Color(0x991A2430),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.white(0.08)),
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
                      color: i == 3 ? AppColors.accent : AppColors.white(0.12),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: i == 3
                          ? [
                              BoxShadow(
                                color: AppColors.accent.withAlpha(136),
                                blurRadius: 16,
                              ),
                            ]
                          : null,
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
                      border: Border.all(color: AppColors.bg, width: 2),
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
                    color: AppColors.white(0.08),
                    border: Border.all(color: AppColors.bg, width: 2),
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

  Widget _iconBtn(IconData icon, {VoidCallback? onTap, Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xB311181F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.white(0.1)),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _bottomCta(Court court) {
    return Row(
      children: [
        Builder(builder: (context) {
          final isFav = context.watch<FavoritesProvider>().isFavorite(court.id);
          return _squareBtn(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? AppColors.accent : Colors.white,
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
      {VoidCallback? onTap, Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.white(0.08),
          border: Border.all(color: AppColors.white(0.12)),
          borderRadius: BorderRadius.circular(16),
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
            final reviews = snap.data ?? [];
            if (reviews.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0x801A2430),
                  border: Border.all(color: AppColors.white(0.06)),
                  borderRadius: BorderRadius.circular(14),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x801A2430),
        border: Border.all(color: AppColors.white(0.06)),
        borderRadius: BorderRadius.circular(14),
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
              Text(
                r.userEmail.split('@').first,
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

  Future<void> _openReviewDialog(BuildContext context) async {
    final session = context.read<Session>();
    if (session.email == null) return;
    int rating = 5;
    final commentCtrl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.bgElev,
          title: Text('Tu reseña', style: AppText.archivo(size: 18, weight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
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
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.white(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent),
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
