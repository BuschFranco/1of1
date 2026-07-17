import 'package:flutter/material.dart';

import '../services/api/api_client.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/season_banner.dart';

/// Ranking GLOBAL de la app. Dos pestañas: **Global** (Jugadores/Clanes con
/// filtro Semana/Mes) y **Temporada** (aparte, con su banner de fechas +
/// Jugadores/Clanes de la temporada en curso). Muestra tu posición y la de tu
/// clan abajo aunque quedes fuera del top 50. Se abre desde el botón de trofeo
/// del mapa; el ranking del perfil queda scopeado a amigos.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

enum _Period { week, month, season }

class _RankingScreenState extends State<RankingScreen> {
  // Swipe lineal de 6 páginas:
  //  0 Global·Jug·Semana · 1 Global·Jug·Mes · 2 Global·Clan·Semana
  //  3 Global·Clan·Mes  · 4 Temp·Jugadores  · 5 Temp·Clanes
  static const int _pages = 6;
  static const _pageIsClans = [false, false, true, true, false, true];
  static const _pagePeriod = [
    _Period.week, _Period.month, _Period.week, _Period.month, //
    _Period.season, _Period.season,
  ];

  final PageController _pageCtrl = PageController();
  int _page = 0;
  // Respuesta cruda del backend cacheada por período (cubre ambos scopes, así
  // Jugadores↔Clanes no vuelve a la red).
  final Map<_Period, Map<String, dynamic>> _cache = {};

  bool get _isSeason => _page >= 4;
  bool get _isClans => _pageIsClans[_page];
  _Period get _period => _pagePeriod[_page];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Corte del período (semana = lunes 00:00, mes = día 1, temporada = semestre).
  DateTime _cutoff(_Period p) {
    final now = DateTime.now();
    switch (p) {
      case _Period.week:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case _Period.month:
        return DateTime(now.year, now.month, 1);
      case _Period.season:
        return PlaySessionService.seasonStart(now);
    }
  }

  Future<void> _load() async {
    final p = _period;
    if (_cache.containsKey(p)) return;
    setState(() {}); // muestra el spinner de la página nueva
    try {
      final data =
          await ApiClient().globalRanking(_cutoff(p).toIso8601String());
      _cache[p] = data;
    } catch (_) {
      // Sin conexión: queda la vista vacía con su mensaje.
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _rows(_Period p, bool clans) => [
        for (final r in (_cache[p]?[clans ? 'clans' : 'players'] as List? ??
            const []))
          if (r is Map) r.cast<String, dynamic>(),
      ];

  @override
  Widget build(BuildContext context) {
    // Sin swipe-right-to-pop acá: el drag horizontal navega las 6 páginas del
    // ranking (queda el botón de volver).
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            // Header: volver + título centrado.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  PressableWidget(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.chevron_left,
                          size: 28, color: AppColors.ink),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Ranking global',
                      textAlign: TextAlign.center,
                      style: AppText.archivo(size: 20, weight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 44), // balancea el botón de volver
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Los mejores de toda la app',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.4)),
            ),
            const SizedBox(height: 16),
            // Fila 1: pestaña principal (Global vs Temporada, separadas).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _tabChip('Global', season: false),
                const SizedBox(width: 8),
                _tabChip('Temporada', season: true),
              ],
            ),
            const SizedBox(height: 10),
            // Fila 2: scope (Jugadores/Clanes), en ambas pestañas.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _scopeChip('Jugadores', clans: false),
                const SizedBox(width: 8),
                _scopeChip('Clanes', clans: true),
              ],
            ),
            // Fila 3: filtro de tiempo, solo en Global (Temporada es fija).
            if (!_isSeason) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _periodChip('Semana', _Period.week),
                  const SizedBox(width: 8),
                  _periodChip('Mes', _Period.month),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _load();
                },
                itemBuilder: (_, i) => _pageBody(i),
              ),
            ),
            _myPosition(),
          ],
        ),
      ),
    );
  }

  /// Contenido de la página [i]: en Temporada, banner arriba + lista.
  Widget _pageBody(int i) {
    final list = _list(_pageIsClans[i], _pagePeriod[i]);
    if (_pagePeriod[i] != _Period.season) return list;
    return Column(
      children: [
        const SeasonBanner(),
        Expanded(child: list),
      ],
    );
  }

  /// Anima el carrusel a una página objetivo.
  void _goTo(int target) {
    if (target == _page) return;
    _pageCtrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Widget _tabChip(String label, {required bool season}) => AppChip(
        label: label,
        active: _isSeason == season,
        // Al cambiar de pestaña conserva el scope (jugadores/clanes) actual.
        // Global vuelve a Semana; Temporada no tiene sub-período.
        onTap: () => _goTo(
          season ? (_isClans ? 5 : 4) : (_isClans ? 2 : 0),
        ),
      );

  Widget _scopeChip(String label, {required bool clans}) => AppChip(
        label: label,
        active: _isClans == clans,
        onTap: () => _goTo(
          _isSeason
              ? (clans ? 5 : 4)
              // Global: preserva el período (semana=+0, mes=+1).
              : (clans ? 2 : 0) + (_period == _Period.month ? 1 : 0),
        ),
      );

  Widget _periodChip(String label, _Period p) => AppChip(
        label: label,
        active: _period == p,
        onTap: () => _goTo((_isClans ? 2 : 0) + (p == _Period.month ? 1 : 0)),
      );

  Widget _list(bool clans, _Period period) {
    if (!_cache.containsKey(period)) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.accent),
        ),
      );
    }
    final rows = _rows(period, clans);
    if (rows.isEmpty) {
      return Center(
        child: Text(
          clans
              ? 'Sin clanes con puntos en este período'
              : 'Sin partidos en este período',
          style: AppText.grotesk(size: 13, color: AppColors.white(0.4)),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: AppColors.white(0.06)),
              clans
                  ? _clanRow(i, rows[i], _cache[period])
                  : _playerRow(i, rows[i], _cache[period]),
            ],
          ],
        ),
      ),
    );
  }

  String _medal(int i) => i == 0
      ? '\u{1F947}'
      : i == 1
          ? '\u{1F948}'
          : i == 2
              ? '\u{1F949}'
              : '';

  Widget _rankBadge(int i) => SizedBox(
        width: 28,
        child: Text(
          _medal(i).isNotEmpty ? _medal(i) : '${i + 1}',
          style: AppText.grotesk(
              size: 13, weight: FontWeight.w800, color: AppColors.white(0.5)),
          textAlign: TextAlign.center,
        ),
      );

  Widget _pts(int points, {required bool highlight}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$points',
              style: AppText.archivo(
                  size: 15,
                  weight: FontWeight.w800,
                  color: highlight ? AppColors.accent : AppColors.ink)),
          const SizedBox(width: 4),
          Text('pts',
              style: AppText.grotesk(size: 10, color: AppColors.white(0.35))),
        ],
      );

  Widget _playerRow(int i, Map<String, dynamic> r, Map<String, dynamic>? data) {
    // Mi fila se identifica por posición (el server no expone emails).
    final me = (data?['me'] as Map?)?.cast<String, dynamic>() ?? const {};
    final isMe = (me['playerRank'] as num?)?.toInt() == i + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: isMe ? AppColors.accent.withAlpha(18) : Colors.transparent,
      child: Row(
        children: [
          _rankBadge(i),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (r['name'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w700,
                    color: isMe ? AppColors.accent : AppColors.ink,
                  ),
                ),
                if ((r['handle'] ?? '').toString().isNotEmpty)
                  Text(
                    (r['handle'] ?? '').toString(),
                    style:
                        AppText.grotesk(size: 10, color: AppColors.white(0.4)),
                  ),
              ],
            ),
          ),
          _pts((r['points'] as num?)?.round() ?? 0, highlight: isMe),
        ],
      ),
    );
  }

  Widget _clanRow(int i, Map<String, dynamic> r, Map<String, dynamic>? data) {
    final me = (data?['me'] as Map?)?.cast<String, dynamic>() ?? const {};
    final isMine = (me['clanRank'] as num?)?.toInt() == i + 1;
    final members = (r['members'] as num?)?.round() ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: isMine ? AppColors.accent.withAlpha(18) : Colors.transparent,
      child: Row(
        children: [
          _rankBadge(i),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (r['clan'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.archivo(
                    size: 14,
                    weight: FontWeight.w900,
                    color: isMine ? AppColors.accent : AppColors.ink,
                  ),
                ),
                Text(
                  '$members ${members == 1 ? 'miembro' : 'miembros'}',
                  style: AppText.grotesk(size: 10, color: AppColors.white(0.4)),
                ),
              ],
            ),
          ),
          _pts((r['points'] as num?)?.round() ?? 0, highlight: isMine),
        ],
      ),
    );
  }

  /// Sección fija de abajo: tu puesto como jugador y el de tu clan en el
  /// período elegido (aunque estén fuera del top 50).
  Widget _myPosition() {
    final data = _cache[_period];
    if (data == null) return const SizedBox.shrink();
    final me = (data['me'] as Map?)?.cast<String, dynamic>() ?? const {};
    final playerRank = (me['playerRank'] as num?)?.toInt();
    final playerPoints = (me['playerPoints'] as num?)?.round() ?? 0;
    final clan = (me['clan'] ?? '').toString();
    final clanRank = (me['clanRank'] as num?)?.toInt();
    final clanPoints = (me['clanPoints'] as num?)?.round() ?? 0;

    Widget cell(String label, String value, String detail) => Expanded(
          child: Column(
            children: [
              Text(label.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.grotesk(
                      size: 10,
                      weight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: AppColors.white(0.45))),
              const SizedBox(height: 4),
              Text(value,
                  style: AppText.archivo(
                      size: 18,
                      weight: FontWeight.w900,
                      color: AppColors.accent)),
              const SizedBox(height: 2),
              Text(detail,
                  style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgElev,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            cell(
              'Tu posición',
              playerRank != null ? '#$playerRank' : '—',
              playerRank != null ? '$playerPoints pts' : 'Sin partidos',
            ),
            Container(width: 1, color: AppColors.white(0.06)),
            cell(
              clan.isNotEmpty ? 'Clan $clan' : 'Tu clan',
              clanRank != null ? '#$clanRank' : '—',
              clan.isEmpty
                  ? 'Sin clan'
                  : clanRank != null
                      ? '$clanPoints pts'
                      : 'Sin puntos',
            ),
          ],
        ),
      ),
    );
  }
}
