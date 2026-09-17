import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/models.dart';
import '../services/cache/api_cache.dart';
import '../services/news_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/pressable_widget.dart';

/// Feed de noticias de básquet, filtrable por liga. Sin props: vive dentro de
/// `SocialScreen` como segundo segmento (Crew/Noticias).
///
/// [topPadding] es el mismo mecanismo que `CrewScreen.topPadding`: dentro de
/// `SocialScreen` el selector de segmentos ya ocupa el espacio de arriba.
class NewsScreen extends StatefulWidget {
  final double topPadding;

  const NewsScreen({super.key, this.topPadding = 8});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  String _league = NewsService.nba;
  bool _loading = false;

  String get _cacheKey => 'news::$_league';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Patrón (a) de docs/cache.md: peek síncrono antes del primer build, fetch
  // + put + setState si no está fresco. Sin invalidación por mutación (nadie
  // crea noticias desde el cliente) — es TTL puro.
  Future<void> _load({bool force = false}) async {
    if (!force && ApiCache.isFresh(_cacheKey, ApiCache.ttlNews)) return;
    setState(() => _loading = true);
    final fresh = await NewsService.forLeague(_league);
    ApiCache.put(_cacheKey, fresh);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _selectLeague(String league) {
    if (league == _league) return;
    setState(() => _league = league);
    _load();
  }

  Future<void> _openArticle(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* sin browser disponible: no hacer nada */}
  }

  @override
  Widget build(BuildContext context) {
    final cached = ApiCache.peek<List<NewsArticle>>(_cacheKey) ?? const [];
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      color: AppColors.accent,
      backgroundColor: AppColors.bgElev,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, widget.topPadding, 20, 160),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppChip(
                label: 'NBA',
                active: _league == NewsService.nba,
                onTap: () => _selectLeague(NewsService.nba),
              ),
              AppChip(
                label: 'WNBA',
                active: _league == NewsService.wnba,
                onTap: () => _selectLeague(NewsService.wnba),
              ),
              AppChip(
                label: 'Liga Nacional',
                active: _league == NewsService.lnb,
                onTap: () => _selectLeague(NewsService.lnb),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading && cached.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white(0.4),
                ),
              ),
            )
          else if (cached.isEmpty)
            _emptyState()
          else
            for (final a in cached) _articleCard(a),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Icon(Icons.article_outlined, size: 44, color: AppColors.white(0.25)),
          const SizedBox(height: 12),
          Text(
            'Sin noticias por ahora',
            style: AppText.grotesk(
                size: 14, weight: FontWeight.w700, color: AppColors.white(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _articleCard(NewsArticle a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableWidget(
        onTap: () => _openArticle(a.url),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppShape.rCard),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.imageUrl.isNotEmpty)
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Image.network(
                    a.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.bgElev,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: AppColors.white(0.2)),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.grotesk(
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppColors.ink),
                      ),
                      if (a.source.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          a.source,
                          style: AppText.grotesk(
                              size: 11,
                              weight: FontWeight.w600,
                              color: AppColors.white(0.5)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
