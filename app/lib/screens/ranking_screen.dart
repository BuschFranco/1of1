import 'package:flutter/material.dart';

import '../services/api/api_client.dart';
import '../services/cache/api_cache.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/season_banner.dart';

/// Ranking GLOBAL de la app. Dos pestañas REALES arriba: **Global** (con
/// filtros Jugadores/Clanes y Semana/Mes) y **Temporada** (con su banner de
/// fechas + Jugadores/Clanes de la temporada en curso). El swipe alterna solo
/// entre esas dos pestañas; los filtros de adentro cambian al tocar. Muestra tu
/// posición y la de tu clan abajo aunque quedes fuera del top 50. Se abre desde
/// el botón de trofeo del mapa; el ranking del perfil queda scopeado a amigos.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

enum _Period { week, month, season, custom }

class _RankingScreenState extends State<RankingScreen> {
  final PageController _pageCtrl = PageController();
  int _tab = 0; // 0 = Global, 1 = Temporada

  // Filtros de la pestaña Global (tap, instantáneos).
  bool _globalClans = false;
  _Period _globalPeriod = _Period.week;
  // Filtro de la pestaña Temporada.
  bool _seasonClans = false;

  // Rango personalizado.
  DateTime? _customFrom;
  DateTime? _customTo;

  // Respuesta cruda del backend cacheada por período (cubre ambos scopes, así
  // Jugadores↔Clanes cambia sin volver a la red).
  final Map<String, Map<String, dynamic>> _cache = {};

  @override
  void initState() {
    super.initState();
    _load(_Period.week);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _cacheKey(_Period p) => p == _Period.custom
      ? 'custom_${_customFrom?.toIso8601String()}_${_customTo?.toIso8601String()}'
      : p.name;

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
      case _Period.custom:
        return _customFrom ?? DateTime(now.year, now.month, 1);
    }
  }

  Future<void> _load(_Period p) async {
    final key = _cacheKey(p);
    if (_cache.containsKey(key)) return;
    // Reusar entre aperturas de la pantalla vía ApiCache (períodos fijos): si
    // está fresco, se pinta sin pegar a la red. El custom no se cachea global.
    final apiKey = p == _Period.custom ? null : 'globalranking::${p.name}';
    if (apiKey != null && ApiCache.isFresh(apiKey, ApiCache.ttlRanking)) {
      final cached = ApiCache.peek<Map<String, dynamic>>(apiKey);
      if (cached != null) {
        _cache[key] = cached;
        if (mounted) setState(() {});
        return;
      }
    }
    setState(() {}); // muestra el spinner de esa página
    try {
      final data =
          await ApiClient().globalRanking(_cutoff(p).toIso8601String());
      _cache[key] = data;
      if (apiKey != null) ApiCache.put(apiKey, data);
    } catch (_) {
      // Sin conexión: queda la vista vacía con su mensaje.
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: now,
            ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: AppColors.bg,
          colorScheme: ColorScheme.dark(
            primary: AppColors.accent,
            onPrimary: Colors.black,
            surface: AppColors.bgElev,
            onSurface: AppColors.ink,
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: AppColors.bgElev,
            rangePickerBackgroundColor: AppColors.bg,
            rangePickerHeaderBackgroundColor: AppColors.bgElev,
            rangePickerHeaderForegroundColor: AppColors.ink,
            headerBackgroundColor: AppColors.bgElev,
            headerForegroundColor: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customFrom = picked.start;
        _customTo = picked.end;
        _globalPeriod = _Period.custom;
        _cache.removeWhere((k, _) => k.startsWith('custom_'));
      });
      _load(_Period.custom);
    }
  }

  List<Map<String, dynamic>> _rows(_Period p, bool clans) => [
        for (final r in (_cache[_cacheKey(p)]?[clans ? 'clans' : 'players']
                as List? ??
            const []))
          if (r is Map) r.cast<String, dynamic>(),
      ];

  void _selectTab(int i) {
    if (i == _tab) return;
    // Páginas adyacentes: el swipe/animación NO atraviesa filtros.
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 12),
            // Tabs REALES (subrayado), distintas de los chips de filtro.
            _tabBar(),
            const SizedBox(height: 14),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) {
                  setState(() => _tab = i);
                  _load(i == 0 ? _globalPeriod : _Period.season);
                },
                children: [
                  _globalPage(),
                  _seasonPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header de tabs ─────────────────────────────────────────────────────────

  Widget _tabBar() {
    return Column(
      children: [
        Row(
          children: [
            _tabItem('Global', 0),
            _tabItem('Temporada', 1),
          ],
        ),
        Container(height: 1, color: AppColors.line),
      ],
    );
  }

  Widget _tabItem(String label, int i) {
    final active = _tab == i;
    return Expanded(
      child: PressableWidget(
        onTap: () => _selectTab(i),
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppText.archivo(
                  size: 15,
                  weight: FontWeight.w900,
                  color: active ? AppColors.accent : AppColors.white(0.45),
                ),
              ),
              const SizedBox(height: 8),
              // Subrayado indicador (3px) solo bajo la pestaña activa.
              Container(
                height: 3,
                width: 60,
                decoration: BoxDecoration(
                  color: active ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Página Global ────────────────────────────────────────────────────────

  Widget _globalPage() {
    return Column(
      children: [
        const SizedBox(height: 4),
        // Filtro scope.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppChip(
                label: 'Jugadores',
                active: !_globalClans,
                onTap: () => setState(() => _globalClans = false)),
            const SizedBox(width: 8),
            AppChip(
                label: 'Clanes',
                active: _globalClans,
                onTap: () => setState(() => _globalClans = true)),
          ],
        ),
        const SizedBox(height: 10),
        // Filtro período.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppChip(
                label: 'Semana',
                active: _globalPeriod == _Period.week,
                onTap: () {
                  setState(() => _globalPeriod = _Period.week);
                  _load(_Period.week);
                }),
            const SizedBox(width: 8),
            AppChip(
                label: 'Mes',
                active: _globalPeriod == _Period.month,
                onTap: () {
                  setState(() => _globalPeriod = _Period.month);
                  _load(_Period.month);
                }),
            const SizedBox(width: 8),
            // Filtro secundario (avanzado): rango de fechas personalizado. No es
            // un chip más al mismo nivel — es un botón de ícono que se expande a
            // mostrar el rango cuando está activo.
            _customRangeButton(),
          ],
        ),
        if (_globalPeriod == _Period.custom && _customFrom != null) ...[
          const SizedBox(height: 6),
          Text(
            '${_fmt(_customFrom!)} — ${_fmt(_customTo!)}',
            style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
          ),
        ],
        const SizedBox(height: 14),
        Expanded(child: _list(_globalPeriod, _globalClans)),
        _myPosition(_globalPeriod),
      ],
    );
  }

  /// Botón del filtro de rango personalizado. Inactivo: solo un ícono de
  /// calendario (secundario, no compite con Semana/Mes). Activo: se expande y
  /// muestra el rango elegido, tintado con el acento.
  Widget _customRangeButton() {
    final active = _globalPeriod == _Period.custom &&
        _customFrom != null &&
        _customTo != null;
    return PressableWidget(
      onTap: _pickCustomRange,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: active ? 12 : 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppShape.rChip),
          border: Border.all(
              color: active ? AppColors.accent : AppColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 16,
                color: active ? AppColors.accent : AppColors.white(0.55)),
            if (active) ...[
              const SizedBox(width: 6),
              Text('${_fmtShort(_customFrom!)} — ${_fmtShort(_customTo!)}',
                  style: AppText.grotesk(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.accent)),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  // ── Página Temporada ───────────────────────────────────────────────────────

  Widget _seasonPage() {
    return Column(
      children: [
        const SizedBox(height: 4),
        const SeasonBanner(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppChip(
                label: 'Jugadores',
                active: !_seasonClans,
                onTap: () => setState(() => _seasonClans = false)),
            const SizedBox(width: 8),
            AppChip(
                label: 'Clanes',
                active: _seasonClans,
                onTap: () => setState(() => _seasonClans = true)),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(child: _list(_Period.season, _seasonClans)),
        _myPosition(_Period.season),
      ],
    );
  }

  // ── Lista y filas ──────────────────────────────────────────────────────────

  Widget _list(_Period period, bool clans) {
    if (!_cache.containsKey(_cacheKey(period))) {
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
              ? 'Sin clanes con EXP en este período'
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
                  ? _clanRow(i, rows[i], _cache[_cacheKey(period)])
                  : _playerRow(i, rows[i], _cache[_cacheKey(period)]),
            ],
          ],
        ),
      ),
    );
  }

  // Top 3 con número tintado oro/plata/bronce (sin emojis).
  static const Color _gold = Color(0xFFFFD54A);
  static const Color _silver = Color(0xFFCFD8DC);
  static const Color _bronze = Color(0xFFCD7F32);

  Widget _rankBadge(int i) {
    final Color? medal = i == 0
        ? _gold
        : i == 1
            ? _silver
            : i == 2
                ? _bronze
                : null;
    return SizedBox(
      width: 28,
      child: Text(
        '${i + 1}',
        textAlign: TextAlign.center,
        style: AppText.archivo(
          size: medal != null ? 16 : 13,
          weight: FontWeight.w900,
          color: medal ?? AppColors.white(0.5),
        ),
      ),
    );
  }

  Widget _pts(int points, {required bool highlight}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$points',
              style: AppText.archivo(
                  size: 15,
                  weight: FontWeight.w800,
                  color: highlight ? AppColors.accent : AppColors.ink)),
          const SizedBox(width: 4),
          Text('EXP',
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
  /// período visible (aunque estén fuera del top 50).
  Widget _myPosition(_Period period) {
    final data = _cache[_cacheKey(period)];
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
              playerRank != null ? '$playerPoints EXP' : 'Sin partidos',
            ),
            Container(width: 1, color: AppColors.white(0.06)),
            cell(
              clan.isNotEmpty ? 'Clan $clan' : 'Tu clan',
              clanRank != null ? '#$clanRank' : '—',
              clan.isEmpty
                  ? 'Sin clan'
                  : clanRank != null
                      ? '$clanPoints EXP'
                      : 'Sin EXP',
            ),
          ],
        ),
      ),
    );
  }
}
