import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/achievements.dart';
import '../data/cosmetics.dart';
import '../data/courts.dart';
import '../data/legal_content.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import '../services/app_permissions.dart';
import '../services/blocked_provider.dart';
import '../services/court_rating_service.dart';
import '../services/courts_provider.dart';
import '../services/favorites_provider.dart';
import '../services/friends_service.dart';
import '../services/notion_service.dart';
import '../services/pickups_provider.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/report_service.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import 'legal_screen.dart';
import 'notifications_screen.dart';
import 'match_detail_screen.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/permissions_modal.dart';
import '../widgets/pop_background.dart';
import '../widgets/pop_panel.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/rating_badge.dart';
import '../widgets/reveal_on_scroll.dart';
import '../widgets/section_title.dart';

class ProfileScreen extends StatefulWidget {
  /// Abre el detalle de una cancha (al tocar un favorito).
  final ValueChanged<String>? onSelectCourt;

  /// Subpestaña activa (0 = Perfil, 1 = Amigos). Si viene dada, el estado lo
  /// controla el padre (para poder cambiarla con swipe desde el shell); si es
  /// null, la pantalla la maneja internamente.
  final int? activeTab;
  final ValueChanged<int>? onTabChange;

  const ProfileScreen({
    super.key,
    this.onSelectCourt,
    this.activeTab,
    this.onTabChange,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _localTab = 0; // 0 = Perfil, 1 = Amigos (fallback si no lo controla el padre)

  int get _tab => widget.activeTab ?? _localTab;

  /// True si el fondo elegido del perfil es saturado oscuro (lila/oliva/rojo):
  /// los textos que apoyan directo sobre el fondo van en blanco con la sombra
  /// dura clásica del brand.
  bool get _onDarkBg {
    final key = context.watch<Session>().profileBg;
    return key == 'lilac' || key == 'olive' || key == 'red';
  }

  void _setTab(int idx) {
    if (widget.onTabChange != null) {
      widget.onTabChange!(idx);
    } else {
      setState(() => _localTab = idx);
    }
  }

  // Ancla de la sección "Últimos partidos" para hacer scroll hacia ella al
  // tocar el mazo de puntos que va debajo del nivel.
  final GlobalKey _historyKey = GlobalKey();

  void _scrollToHistory() {
    final ctx = _historyKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final profile = session.profile ?? const Profile(name: 'Invitado');

    // Fondo elegido por el usuario (tuerquita → Fondo del perfil); default oliva.
    final bg = AppColors.profileBg(session.profileBg);
    return Container(
      color: bg,
      child: Stack(
        children: [
          Positioned.fill(child: PopBackground(color: bg)),
          _tab == 0
              ? _profileView(profile)
              : Column(
                  children: [
                    const SizedBox(height: 56),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Perfil',
                            style: AppText.archivo(
                              size: 30,
                              weight: FontWeight.w900,
                              color: _onDarkBg ? Colors.white : AppColors.ink,
                              letterSpacing: -0.01,
                            ).copyWith(
                              shadows: _onDarkBg
                                  ? const [
                                      Shadow(
                                          color: Colors.black,
                                          offset: Offset(3, 3)),
                                    ]
                                  : null,
                            ),
                          ),
                          Row(
                            children: [
                              _notifButton(context),
                              const SizedBox(width: 8),
                                if (context.read<Session>().isLoggedIn)
                                PressableWidget(
                                  onTap: () => _openSettings(context, profile),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.bgElev,
                                      borderRadius:
                                          BorderRadius.circular(AppShape.rBtn),
                                      border: Border.all(
                                          color: AppColors.white(0.25), width: 1.5),
                                    ),
                                    child: const Icon(Icons.settings_outlined,
                                        color: AppColors.ink, size: 18),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              PressableWidget(
                                onTap: () => _confirmLogout(context),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.bgElev,
                                    borderRadius:
                                        BorderRadius.circular(AppShape.rBtn),
                                    border: Border.all(
                                        color: AppColors.white(0.25), width: 1.5),
                                  ),
                                  child: const Icon(Icons.logout,
                                      color: AppColors.ink, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _tabs(),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _FriendsTab(profile: profile),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  /// Botón de campana con badge de notificaciones sin leer + invitaciones
  /// pendientes a pickup. Abre el listado.
  Widget _notifButton(BuildContext context) {
    final myEmail = (context.read<Session>().email ?? '').trim().toLowerCase();
    final invites =
        context.watch<PickupsProvider>().pendingInvitesFor(myEmail).length;
    final unread = context.watch<PlaySessionService>().unreadCount + invites;
    return PressableWidget(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.bgElev,
              borderRadius: BorderRadius.circular(AppShape.rBtn),
              border: Border.all(color: AppColors.white(0.25), width: 1.5),
            ),
            child: const Icon(Icons.notifications_outlined,
                color: AppColors.ink, size: 18),
          ),
          if (unread > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rChip),
                  border: Border.all(color: AppColors.bg, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: AppText.grotesk(
                    size: 9,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabs() {
    // Selector pill retro-pop: papel + borde negro + sombra dura.
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(color: AppColors.line, width: 1),
        boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
      ),
      child: Row(
        children: [
          _tabBtn('Perfil', 0),
          _tabBtn('Amigos', 1),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int idx) {
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setTab(idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            // Radio chip por estar anidado dentro del selector rBtn.
            borderRadius: BorderRadius.circular(AppShape.rChip),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.grotesk(
              size: 13,
              weight: FontWeight.w700,
              color: active ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileView(Profile profile) {
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 180),
      clipBehavior: Clip.none,
      children: [
        const SizedBox(height: 56),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Perfil',
                style: AppText.archivo(
                  size: 30,
                  weight: FontWeight.w900,
                  color: _onDarkBg ? Colors.white : AppColors.ink,
                  letterSpacing: -0.01,
                ).copyWith(
                  shadows: _onDarkBg
                      ? const [
                          Shadow(
                              color: Colors.black,
                              offset: Offset(3, 3)),
                        ]
                      : null,
                ),
              ),
              Row(
                children: [
                  _notifButton(context),
                  const SizedBox(width: 8),
                    if (context.read<Session>().isLoggedIn)
                    PressableWidget(
                      onTap: () => _openSettings(context, profile),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.bgElev,
                          borderRadius:
                              BorderRadius.circular(AppShape.rBtn),
                          border: Border.all(
                              color: AppColors.white(0.25), width: 1.5),
                        ),
                        child: const Icon(Icons.settings_outlined,
                            color: AppColors.ink, size: 18),
                      ),
                    ),
                  const SizedBox(width: 8),
                  PressableWidget(
                    onTap: () => _confirmLogout(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.bgElev,
                        borderRadius:
                            BorderRadius.circular(AppShape.rBtn),
                        border: Border.all(
                            color: AppColors.white(0.25), width: 1.5),
                      ),
                      child: const Icon(Icons.logout,
                          color: AppColors.ink, size: 18),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _tabs(),
        ),
        const SizedBox(height: 16),
        RevealOnScroll(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _avatar(profile),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isEmpty ? 'Jugador' : profile.name,
                        style: AppText.archivo(
                          size: 24,
                          weight: FontWeight.w900,
                          color: _onDarkBg ? Colors.white : AppColors.ink,
                        ).copyWith(
                          shadows: _onDarkBg
                              ? const [
                                  Shadow(
                                      color: Colors.black,
                                      offset: Offset(2, 2)),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              [
                                if (profile.handle.isNotEmpty) profile.handle,
                                if (profile.city.isNotEmpty) profile.city,
                              ].join(' · '),
                              style: AppText.grotesk(size: 12, color: AppColors.white(0.5)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (context.read<Session>().isLoggedIn) ...[
                            const SizedBox(width: 6),
                            PressableWidget(
                              onTap: () => _editHandle(context, profile.handle),
                              child: Icon(Icons.edit, size: 13, color: AppColors.accent),
                            ),
                          ],
                        ],
                      ),
                      _identityBadges(profile),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (context.read<Session>().isLoggedIn)
          RevealOnScroll(
            child: Column(
              children: [
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: PressableWidget(
                    onTap: () => _editClanBadge(context, profile),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      // Fila plana estilo settings: solo fill sutil, sin borde
                      // ni sombra dura (menos "caja").
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppShape.rCard),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: AppColors.accent),
                          const SizedBox(width: 12),
                          Text('Insignia de Clan',
                              style: AppText.grotesk(size: 14, weight: FontWeight.w600)),
                          const Spacer(),
                          Text(
                            profile.clan.isEmpty ? 'Definir' : profile.clan,
                            style: AppText.grotesk(size: 13, color: AppColors.white(0.5)),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.4)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        const SizedBox(height: 24),
        RevealOnScroll(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _levelWithHistory(),
          ),
        ),
        const SizedBox(height: 10),
        RevealOnScroll(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _statsGrid(),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RevealOnScroll(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(title: 'Canchas más jugadas', onDark: _onDarkBg),
                    _topCourtsSection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              RevealOnScroll(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(title: 'Favoritos', onDark: _onDarkBg),
                    _favoritesSection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              RevealOnScroll(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(title: 'Títulos', onDark: _onDarkBg),
                    _titlesSection(profile),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              RevealOnScroll(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(title: 'Logros', onDark: _onDarkBg),
                    _achievementsSection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              RevealOnScroll(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                        key: _historyKey,
                        title: 'Últimos partidos',
                        onDark: _onDarkBg),
                    _historySection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatar(Profile profile) {
    final color = clanColor(profile.avatarColor);
    final textColor = clanTextColor(profile.clanTextColor);
    final hasClan = profile.clan.trim().isNotEmpty;
    // La insignia de clan tiene prioridad como "imagen de perfil"; si no hay
    // clan caemos a la foto subida y, en último caso, a la inicial del nombre.
    final useImage = !hasClan && profile.avatar.isNotEmpty;
    final label = hasClan
        ? profile.clan.trim().toUpperCase()
        : (profile.name.isNotEmpty ? profile.name[0] : '?').toUpperCase();
    final inner = Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Avatar neobrutalista: relleno plano del color del clan, borde negro
        // puro y sombra dura chica (sin degradado ni glow).
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
        color: useImage ? null : color,
        image: useImage
            ? DecorationImage(image: NetworkImage(profile.avatar), fit: BoxFit.cover)
            : null,
        boxShadow: AppFx.hardShadow(offset: const Offset(2, 2)),
      ),
      child: useImage
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: hasClan
                      ? clanFontStyle(profile.clanFont,
                          size: 30, color: textColor)
                      : AppText.archivo(
                          size: 36, weight: FontWeight.w900, color: textColor),
                ),
              ),
            ),
    );
    return framedAvatar(frameById(profile.avatarFrame), AppShape.rCard, inner);
  }

  Widget _levelCard() {
    final pts = context.watch<PlaySessionService>().points;
    final lvl = levelForPoints(pts);
    final start = pointsForLevel(lvl);
    final next = pointsForLevel(lvl + 1);
    final progress = ((pts - start) / (next - start)).clamp(0.0, 1.0);
    // Fondo SÓLIDO claro (el mazo de partidos va detrás y no debe transparentarse).
    const solid = AppColors.paper;
    return PopPanel(
      radius: AppShape.rCard,
      fill: solid,
      glow: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              Text('Nivel $lvl',
                  style: AppText.archivo(size: 16, weight: FontWeight.w800)),
              const Spacer(),
              Text('$pts pts',
                  style: AppText.grotesk(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.accent)),
            ],
          ),
          const SizedBox(height: 12),
          // Barra de progreso plana: acento sólido, sin glow ni píldora.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShape.rChip),
            child: Container(
              height: 7,
              color: AppColors.white(0.08),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress == 0 ? 0.001 : progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppShape.rChip),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Faltan ${next - pts} pts para el nivel ${lvl + 1}',
            style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
          ),
        ],
      ),
    );
  }

  /// Nivel + mini historial de los últimos 3 partidos. El historial se
  /// renderiza como un mazo de cartas que sale de DETRÁS del nivel: pegado y
  /// solapado, cada partido detrás del anterior, más angosto y más transparente
  /// a medida que se aleja (el 3ro casi no se ve). El nivel queda siempre por
  /// encima.
  Widget _levelWithHistory() {
    final log = context.watch<PlaySessionService>().log;
    final recent = log.where((e) => e.result != null).take(3).toList();
    final levelCard = _levelCard();
    if (recent.isEmpty) return levelCard;

    const cardH = 48.0; // alto de cada carta
    const peek = 34.0; // cuánto asoma cada carta por debajo de la anterior
    const overlap = 14.0; // cuánto se mete la 1ra carta debajo del nivel
    // Más angostas y más transparentes hacia el final (pero el último todavía
    // legible: asoma lo suficiente para ver su info).
    const widths = [0.94, 0.85, 0.76];
    const opacities = [1.0, 0.62, 0.34];

    final n = recent.length;
    final stackH = cardH + peek * (n - 1);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Mazo, anclado al fondo del Stack para que su parte superior quede
        // tapada por el nivel (que se pinta después, encima).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: PressableWidget(
            onTap: _scrollToHistory,
            child: SizedBox(
              height: stackH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // De atrás (último, transparente) hacia adelante (más reciente).
                  for (var i = n - 1; i >= 0; i--)
                    Positioned(
                      top: peek * i,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: FractionallySizedBox(
                          widthFactor: widths[i],
                          child: Opacity(
                            opacity: opacities[i],
                            child: _recentPointsRow(recent[i], cardH),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Nivel encima + espacio reservado para la parte visible del mazo.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            levelCard,
            SizedBox(height: stackH - overlap),
          ],
        ),
      ],
    );
  }

  /// Fondo de una carta/fila según el resultado: rojo si perdió, verde si ganó,
  /// gris si empató; el resto (entrenamiento / sin info) queda azulado.
  Color _resultBg(PlayResult? r) {
    // Fondo SÓLIDO claro con un tinte suave del color de resultado sobre papel.
    const base = AppColors.paper;
    switch (r) {
      case PlayResult.win:
        return Color.alphaBlend(AppColors.open.withAlpha(30), base);
      case PlayResult.loss:
        return Color.alphaBlend(AppColors.accent.withAlpha(30), base);
      case PlayResult.tie:
        return Color.alphaBlend(AppColors.black(0.06), base);
      default:
        return base;
    }
  }

  Widget _recentPointsRow(PlaySession s, double height) {
    final (color, label) = _resultStyle(s.result);
    // Carta plana del mazo: tinte de resultado + hairline sutil para definir el
    // solape; el resultado es un dot+etiqueta, sin chip con borde.
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _resultBg(s.result),
        border: Border.all(color: AppColors.white(0.08), width: 1),
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: Row(
        children: [
          _flatChip(color, label),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.courtName.isEmpty ? 'Cancha' : s.courtName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.grotesk(size: 13, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${s.points}',
            style: AppText.archivo(
                size: 14, weight: FontWeight.w900, color: AppColors.accent),
          ),
          const SizedBox(width: 1),
          Text('pts',
              style: AppText.grotesk(size: 10, color: AppColors.white(0.45))),
        ],
      ),
    );
  }

  /// Ranking de las 3 canchas más jugadas (por tiempo) + el tiempo total como
  /// dato aislado y pequeño debajo.
  Widget _topCourtsSection() {
    final ps = context.watch<PlaySessionService>();
    // breakdown viene ordenado de mayor a menor tiempo: tomamos el top 3.
    final top = ps.breakdown.where((e) => e.seconds > 0).take(3).toList();
    if (top.isEmpty) {
      return _emptyCard('Todavía no jugaste en ninguna cancha.');
    }
    return Column(
      children: [
        _sectionCard([
          for (var i = 0; i < top.length; i++) _topCourtRow(i + 1, top[i]),
        ]),
        const SizedBox(height: 12),
        _totalTimeInline(ps.totalSeconds),
      ],
    );
  }

  /// Colores de podio para el puesto (1º oro, 2º plata, 3º bronce).
  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD24A); // oro
      case 2:
        return const Color(0xFFC9D1D9); // plata
      default:
        return const Color(0xFFCD8B5B); // bronce
    }
  }

  Widget _topCourtRow(int rank, ({String courtId, String name, int seconds}) e) {
    final color = _rankColor(rank);
    // Fila plana: el puesto es tipografía en color de podio, sin medalla-box.
    return GestureDetector(
      onTap: () => widget.onSelectCourt?.call(e.courtId),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text('$rank',
                  style: AppText.archivo(
                      size: 14, weight: FontWeight.w900, color: color)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                e.name.isEmpty ? 'Cancha' : e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.grotesk(size: 13, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              PlaySessionService.fmt(e.seconds),
              style: AppText.grotesk(
                  size: 13, weight: FontWeight.w700, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  /// Tiempo total jugado como dato chico y aislado (debajo del ranking).
  Widget _totalTimeInline(int total) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 13, color: AppColors.white(0.4)),
          const SizedBox(width: 6),
          Text(
            'Tiempo total jugado · ${PlaySessionService.fmt(total)}',
            style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
          ),
        ],
      ),
    );
  }

  /// Stats 2×2 en UNA sola card con hairlines internas (antes eran 4 boxes
  /// bordeados con tile de ícono cada uno). Lo destacado es el VALOR, no el box.
  Widget _statsGrid() {
    final ps = context.watch<PlaySessionService>();

    Widget cell(String label, String value, IconData icon,
        {bool accent = false, VoidCallback? onTap}) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 13,
                    color: accent ? AppColors.accent : AppColors.white(0.4)),
                const SizedBox(width: 6),
                Text(label.toUpperCase(),
                    style: AppText.grotesk(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: AppColors.white(0.45),
                        letterSpacing: 0.1)),
                if (onTap != null) ...[
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: 14, color: AppColors.white(0.3)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: AppText.archivo(
                    size: 22,
                    weight: FontWeight.w900,
                    height: 1.0,
                    color: accent ? AppColors.accent : AppColors.ink)),
          ],
        ),
      );
      if (onTap == null) return content;
      return GestureDetector(
          onTap: onTap, behavior: HitTestBehavior.opaque, child: content);
    }

    Widget vDiv() => Container(width: 1, color: AppColors.white(0.06));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                    child: cell('Partidos', '${ps.totalPlays}',
                        Icons.sports_basketball)),
                vDiv(),
                Expanded(
                    child: cell('Canchas', '${ps.uniqueCourtsCount}',
                        Icons.place_outlined)),
              ],
            ),
          ),
          _hairline(),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                    child: cell(
                        'Racha', '${ps.streak}', Icons.local_fire_department,
                        accent: true, onTap: () => _showStreaks(context))),
                vDiv(),
                Expanded(
                    child: cell('Rating', '${ps.points}', Icons.star_rounded,
                        onTap: () => _showRanking(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PlayStats _statsOf(PlaySessionService ps) => PlayStats(
        partidos: ps.totalPlays,
        canchas: ps.uniqueCourtsCount,
        victorias: ps.wins,
        maxRacha: ps.bestStreak,
        segundos: ps.totalSeconds,
        entrenamientos: ps.trainings,
        victoriasAnio: ps.winsLastYear,
        nivel: ps.level,
      );

  PlayStats _stats() => _statsOf(context.watch<PlaySessionService>());

  /// "Ver más" plano: texto de acción sin box (abre el modal con la lista).
  Widget _seeMore(String label, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppText.grotesk(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: AppColors.accent)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }

  /// Modal de pantalla casi completa con una lista de items.
  void _showSheet(String title, List<Widget> Function(BuildContext) children) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgElev,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: AppText.archivo(size: 18, weight: FontWeight.w800)),
                    const Spacer(),
                    PressableWidget(
                      onTap: () => Navigator.pop(ctx),
                      child: Icon(Icons.close, color: AppColors.white(0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(children: children(ctx)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Posiciones de básquet seleccionables (local, cosmético).
  /// Chips de identidad bajo el nombre: título equipado (color de rareza).
  Widget _identityBadges(Profile profile) {
    final hasTitle = profile.title.isNotEmpty;
    if (!hasTitle) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (hasTitle)
            AppChip(
              label: profile.title,
              color: titleByName(profile.title)?.color,
              onTap: _showUnlockedTitles,
            ),
        ],
      ),
    );
  }

  /// Bottom sheet con los títulos ya desbloqueados, para equipar uno rápido
  /// desde el chip bajo el nombre (sin scrollear hasta la sección Títulos).
  void _showUnlockedTitles() {
    _showSheet('Elegí tu título', (ctx) {
      final profile = ctx.watch<Session>().profile ?? const Profile(name: '');
      final ps = ctx.watch<PlaySessionService>();
      final s = _statsOf(ps);
      final badges = ps.unlockedBadges;
      final unlockedTitles = kTitles
          .where((t) => t.requires.every((id) =>
              badges.contains(id) ||
              (achievementById(id)?.unlocked(s) ?? false)))
          .toList();
      if (unlockedTitles.isEmpty) {
        return [
          _emptyCard('Todavía no desbloqueaste títulos. '
              'Completá logros para conseguirlos.'),
        ];
      }
      return [
        _sectionCard([for (final t in unlockedTitles) _titleRow(t, profile)]),
      ];
    });
  }



  Widget _achievementsSection() {
    final s = _stats();
    const preview = 5;
    final extra = kAchievements.length - preview;
    return Column(
      children: [
        _sectionCard([
          for (var i = 0; i < kAchievements.length && i < preview; i++)
            _achievementRow(kAchievements[i], s),
        ]),
        if (extra > 0) ...[
          const SizedBox(height: 6),
          _seeMore('Ver los $extra logros restantes', _showAllAchievements),
        ],
      ],
    );
  }

  void _showAllAchievements() {
    _showSheet('Logros', (ctx) {
      final s = _statsOf(ctx.read<PlaySessionService>());
      return [
        _sectionCard([for (final a in kAchievements) _achievementRow(a, s)]),
      ];
    });
  }

  Widget _achievementRow(Achievement a, PlayStats s) {
    // Desbloqueado si las stats actuales lo cumplen O si ya quedó registrado en
    // el set permanente (sobrevive al reinstalar, sembrado desde Notion).
    final badges = context.watch<PlaySessionService>().unlockedBadges;
    final unlocked = badges.contains(a.id) || a.unlocked(s);
    final color = unlocked ? kGold : AppColors.white(0.35);
    // Fila plana: el dorado vive en el ícono y el check, sin tile ni borde.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(a.icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(a.name,
                    style: AppText.grotesk(
                        size: 13,
                        weight: FontWeight.w700,
                        color:
                            unlocked ? AppColors.ink : AppColors.white(0.4))),
                const SizedBox(height: 1),
                Text(
                  a.desc,
                  style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          unlocked
              ? Icon(Icons.verified, size: 18, color: kGold)
              : Text('${a.progress(s)}/${a.goal}',
                  style: AppText.grotesk(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.white(0.45))),
        ],
      ),
    );
  }

  Widget _titlesSection(Profile profile) {
    const preview = 5;
    final extra = kTitles.length - preview;
    return Column(
      children: [
        _sectionCard([
          for (var i = 0; i < kTitles.length && i < preview; i++)
            _titleRow(kTitles[i], profile),
        ]),
        if (extra > 0) ...[
          const SizedBox(height: 6),
          _seeMore('Ver los $extra títulos restantes', _showAllTitles),
        ],
      ],
    );
  }

  void _showAllTitles() {
    _showSheet('Títulos', (ctx) {
      final profile =
          ctx.watch<Session>().profile ?? const Profile(name: '');
      return [
        _sectionCard([for (final t in kTitles) _titleRow(t, profile)]),
      ];
    });
  }

  Widget _titleRow(GameTitle t, Profile profile) {
    final ps = context.watch<PlaySessionService>();
    final s = _statsOf(ps);
    final badges = ps.unlockedBadges;
    // El título se desbloquea si TODOS sus logros requeridos están conseguidos
    // (por stats actuales o por el set permanente).
    final unlocked = t.requires
        .every((id) => badges.contains(id) || (achievementById(id)?.unlocked(s) ?? false));
    final equipped = profile.title == t.name;
    final loggedIn = context.read<Session>().isLoggedIn;
    // Card retro-pop: papel + borde negro; la rareza vive en el tile del ícono
    // y en su etiqueta, no en el borde. Equipado se destaca con tinte + sombra.
    final rarity = t.color;
    final iconColor = unlocked ? rarity : AppColors.white(0.35);
    // Fila plana: la rareza vive en el ícono y la etiqueta; equipado se marca
    // con una barrita de acento a la izquierda (nada de card tintada + sombra).
    return GestureDetector(
      onTap: (unlocked && loggedIn) ? () => _toggleTitle(t.name, equipped) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 32,
              color: equipped ? rarity : Colors.transparent,
            ),
            const SizedBox(width: 13),
            Icon(unlocked ? Icons.workspace_premium : Icons.lock_outline,
                size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.name,
                      style: AppText.grotesk(
                          size: 13,
                          weight: FontWeight.w700,
                          color: unlocked
                              ? AppColors.ink
                              : AppColors.white(0.4))),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        t.rarity.label.toUpperCase(),
                        style: AppText.grotesk(
                            size: 10,
                            weight: FontWeight.w800,
                            color: iconColor,
                            letterSpacing: 0.06),
                      ),
                      Flexible(
                        child: Text(
                          ' · ${t.unlockDesc}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.grotesk(
                              size: 11, color: AppColors.white(0.45)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (equipped)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, size: 16, color: rarity),
                const SizedBox(width: 4),
                Text('Equipado',
                    style: AppText.grotesk(
                        size: 11, weight: FontWeight.w700, color: rarity)),
              ])
            else if (unlocked && loggedIn)
              Text(
                'Equipar',
                style: AppText.grotesk(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.accent,
                ).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTitle(String title, bool equipped) async {
    final session = context.read<Session>();
    final err = await session.setTitle(equipped ? '' : title);
    if (!mounted || err == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err, style: AppText.grotesk(size: 13))),
    );
  }

  Widget _historySection() {
    final log = context.watch<PlaySessionService>().log;
    if (log.isEmpty) {
      return _emptyCard('Todavía no jugaste partidos.');
    }
    return _sectionCard([
      for (var i = 0; i < log.length && i < 20; i++) _historyRow(log[i]),
    ]);
  }

  Widget _historyRow(PlaySession s) {
    final (color, label) = _resultStyle(s.result);
    // Fila plana: el resultado es un dot+etiqueta de color, sin card tintada
    // ni chip con borde.
    return GestureDetector(
      onTap: () => _showMatchDetail(s),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.courtName.isEmpty ? 'Cancha' : s.courtName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(size: 13, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _flatChip(color, label),
                      Text(
                        '  ·  ${PlaySessionService.fmt(s.seconds)}  ·  ${_fmtDate(s.endedAtMillis)}',
                        style: AppText.grotesk(
                            size: 11, color: AppColors.white(0.45)),
                      ),
                    ],
                  ),
                ],
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
              Text('pts',
                  style:
                      AppText.grotesk(size: 10, color: AppColors.white(0.45))),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.35)),
          ],
        ),
      ),
    );
  }

  /// Modal con el detalle de un partido: cancha (imagen + rating), resultado,
  /// fecha, hora, duración y puntos. Usa solo datos ya disponibles (el
  /// [PlaySession] guardado + el catálogo de canchas en memoria), sin queries.
  Future<void> _showMatchDetail(PlaySession s) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(
          session: s,
          onSelectCourt: widget.onSelectCourt,
        ),
      ),
    );
  }

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

  Widget _favoritesSection() {
    final favIds = context.watch<FavoritesProvider>().ids;
    final courts = context.watch<CourtsProvider>().courts;
    final favs = courts.where((c) => favIds.contains(c.id)).toList();
    if (favs.isEmpty) {
      return _emptyCard(
          'Todavía no agregaste canchas a favoritos. Tocá el corazón en una cancha.');
    }
    return _sectionCard([for (final c in favs) _favoriteCard(c)]);
  }

  Widget _favoriteCard(Court c) {
    // Fila plana dentro de la card de sección (la imagen conserva su clip).
    return PressableWidget(
      onTap: () => widget.onSelectCourt?.call(c.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CourtImage(
              url: c.img,
              width: 52,
              height: 52,
              borderRadius: BorderRadius.circular(AppShape.rBtn),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.archivo(size: 14, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.area.isEmpty ? c.type : '${c.area} · ${c.type}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(size: 11, color: AppColors.white(0.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Builder(builder: (context) {
              final rs = context.read<CourtRatingService>();
              return FutureBuilder<CourtRating>(
                future: rs.ratingFor(c.id),
                builder: (context, snap) {
                  final cr = snap.data;
                  return RatingBadge(value: cr?.average, size: 11);
                },
              );
            }),
            const SizedBox(width: 10),
            PressableWidget(
              onTap: () => context.read<FavoritesProvider>().toggle(c.id),
              child: Icon(Icons.favorite, size: 18, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  /// Estado vacío plano: solo texto atenuado, sin box (regla anti-cajas).
  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Text(
        text,
        style: AppText.grotesk(size: 12.5, color: AppColors.white(0.35)),
      ),
    );
  }

  /// Divider fino entre filas de una sección (reemplaza el borde por item).
  Widget _hairline() => Container(height: 1, color: AppColors.white(0.06));

  /// Contenedor único por sección: fill sutil, sin borde ni sombra dura. Las
  /// filas van adentro separadas por hairlines — un solo nivel de "caja" por
  /// sección en vez de N cards bordeadas.
  Widget _sectionCard(List<Widget> children) {
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) kids.add(_hairline());
      kids.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: kids),
    );
  }

  /// Estado plano: puntito de color + etiqueta en color, sin fondo ni borde
  /// (mismo lenguaje que el detalle de partido).
  Widget _flatChip(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
      ],
    );
  }

  Future<void> _editHandle(BuildContext context, String current) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditHandleDialog(current: current),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Handle actualizado', style: AppText.grotesk(size: 13)),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  Future<void> _editClanBadge(BuildContext context, Profile profile) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ClanBadgeDialog(
        currentClan: profile.clan,
        currentColor: profile.avatarColor,
        currentTextColor: profile.clanTextColor,
        currentFont: profile.clanFont,
        currentFrame: profile.avatarFrame,
        level: context.read<PlaySessionService>().level,
      ),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insignia actualizada', style: AppText.grotesk(size: 13)),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  Future<void> _showStreaks(BuildContext context) async {
    final ps = context.read<PlaySessionService>();
    final history = ps.streakHistory;
    await showDialog<void>(
      context: context,
      // El fondo/forma los pone el dialogTheme global (neobrutalista).
      builder: (_) => AlertDialog(
        scrollable: true,
        title: Text('Tus rachas',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  'Racha actual: ${ps.streak} ${ps.streak == 1 ? 'victoria' : 'victorias'}',
                  style: AppText.grotesk(size: 13, weight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (history.isEmpty)
              Text('Todavía no cerraste ninguna racha.',
                  style: AppText.grotesk(size: 12, color: AppColors.white(0.5)))
            else
              for (final s in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.local_fire_department,
                          size: 14, color: AppColors.open),
                      const SizedBox(width: 6),
                      Text(
                        'Racha de ${s.wins}',
                        style: AppText.grotesk(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.open),
                      ),
                      const Spacer(),
                      Text(
                        'Hasta: ${_fmtDate(s.endedAtMillis)}',
                        style: AppText.grotesk(
                            size: 12, color: AppColors.white(0.6)),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar',
                style: AppText.grotesk(size: 13, color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  String _fmtDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _showRanking(BuildContext context) async {
    final session = context.read<Session>();
    final ps = context.read<PlaySessionService>();
    final friendsService = FriendsService();
    final profiles = context.read<ProfilesProvider>();

    // Cargar amigos.
    List<Friend> friends = [];
    if (session.email != null && friendsService.isConfigured) {
      try {
        friends = await friendsService.listFriends(session.email!);
      } catch (_) {}
    }

    // Datos de amigos (nombre/handle/email + total de perfil para el modo Total).
    final friendData = <_RankFriend>[
      for (final f in friends)
        _RankFriend(
          name: f.friendName.isNotEmpty ? f.friendName : f.friendHandle,
          handle: f.friendHandle,
          email: f.friendEmail.trim().toLowerCase(),
          totalPoints: profiles.byEmail(f.friendEmail)?.points ?? 0,
        ),
    ];

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RankingSheet(
        myName: session.profile?.name.isNotEmpty == true
            ? session.profile!.name
            : 'Invitado',
        myHandle: session.profile?.handle ?? '',
        myTotalPoints: ps.points,
        play: ps,
        friends: friendData,
      ),
    );
  }

  Future<void> _editPrivacy(BuildContext context, Profile profile) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PrivacyDialog(profile: profile),
    );
  }

  /// Menú de la tuerquita: privacidad + permisos y salud + fondo del perfil.
  void _openSettings(BuildContext context, Profile profile) {
    _showSheet('Ajustes', (ctx) {
      final health = ctx.watch<PlaySessionService>().healthEnabled;
      return [
        _sectionCard([
        _settingsRow(
          ctx,
          Icons.visibility_outlined,
          'Privacidad',
          'Qué ven los demás de vos',
          () {
            Navigator.pop(ctx);
            _editPrivacy(context, profile);
          },
        ),
        _settingsRow(
          ctx,
          Icons.tune,
          'Permisos y salud',
          health
              ? 'Salud conectada · midiendo tu desempeño'
              : 'Ubicación, notificaciones y salud',
          () {
            Navigator.pop(ctx);
            PermissionsModal.show(context);
          },
          trailingOn: health,
        ),
        _settingsRow(
          ctx,
          Icons.format_paint_outlined,
          'Personalización',
          'Fondo del perfil y pantalla de inicio',
          () {
            Navigator.pop(ctx);
            _openPersonalization(context);
          },
        ),
        ]),
        const SizedBox(height: 16),
        Text('LEGAL',
            style: AppText.grotesk(
                size: 11,
                weight: FontWeight.w700,
                color: AppColors.white(0.4),
                letterSpacing: 0.1)),
        const SizedBox(height: 8),
        _sectionCard([
          _settingsRow(
            ctx,
            Icons.privacy_tip_outlined,
            'Política de Privacidad',
            'Qué datos usamos y por qué',
            () {
              Navigator.pop(ctx);
              LegalScreen.open(context, LegalScreen.privacy());
            },
          ),
          _settingsRow(
            ctx,
            Icons.description_outlined,
            'Términos y Condiciones',
            'Reglas de uso de la app',
            () {
              Navigator.pop(ctx);
              LegalScreen.open(context, LegalScreen.terms());
            },
          ),
          _settingsRow(
            ctx,
            Icons.mail_outline,
            'Contacto y soporte',
            // Sin mostrar la casilla: el botón abre el mail directamente.
            'Escribinos ante cualquier problema',
            () => launchUrl(
              Uri(scheme: 'mailto', path: kSupportEmail),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // Eliminar cuenta: fila destructiva, aislada del resto.
        PressableWidget(
          onTap: () {
            Navigator.pop(ctx);
            _confirmDeleteAccount(context);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppShape.rCard),
            ),
            child: Row(
              children: [
                Icon(Icons.delete_forever_outlined,
                    size: 18, color: AppColors.accentDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Eliminar cuenta',
                      style: AppText.grotesk(
                          size: 14,
                          weight: FontWeight.w600,
                          color: AppColors.accentDark)),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.4)),
              ],
            ),
          ),
        ),
      ];
    });
  }

  /// Confirmación fuerte + borrado real de la cuenta y sus datos en Notion.
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElev,
        title: Text('Eliminar cuenta',
            style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: Text(
          'Esto borra tu perfil, tu historial de partidos, tus reseñas y tus '
          'amigos de forma permanente. No se puede deshacer.',
          style: AppText.grotesk(size: 13, color: AppColors.white(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.accentDark)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // Capturamos navigator y messenger ANTES del await: al borrar la cuenta la
    // sesión pasa a null y _Root reemplaza este árbol por la pantalla de auth,
    // dejando `context` desmontado. Estas referencias sí siguen vivas.
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final session = context.read<Session>();

    // Loader modal mientras se archivan las páginas en Notion.
    nav.push(
      DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.accent),
          ),
        ),
      ),
    );
    final err = await session.deleteAccount();
    nav.pop(); // cierra el loader (aunque el árbol de abajo haya cambiado)
    if (err != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Se cerró tu sesión, pero algunos datos podrían no haberse '
            'borrado. Escribinos a $kSupportEmail.',
            style: AppText.grotesk(size: 13),
          ),
        ),
      );
    }
    // Al quedar sin sesión, _Root vuelve solo a la pantalla de auth.
  }

  /// Pantalla de personalización: fondo del perfil + pantalla de inicio.
  void _openPersonalization(BuildContext context) {
    _showSheet('Personalización', (ctx) {
      final currentBg = ctx.watch<Session>().profileBg;
      final currentTab = ctx.watch<Session>().defaultTab;

      final tabOptions = [
        ('home', 'Mapa', Icons.map_outlined),
        ('list', 'Canchas', Icons.stadium_outlined),
        ('profile', 'Perfil', Icons.person_outline),
        ('plus', 'Nuevo', Icons.add_circle_outline),
        ('chat', 'Crew', Icons.group_outlined),
      ];

      return [
        // Sección: Fondo del perfil.
        Text('Fondo del perfil',
            style: AppText.grotesk(
                size: 13, weight: FontWeight.w700, color: AppColors.white(0.6))),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in AppColors.profileBgs.entries)
                PressableWidget(
                  onTap: () {
                    ctx.read<Session>().setProfileBg(e.key);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.ink,
                        width: (currentBg.isEmpty ? 'cream' : currentBg) == e.key
                            ? 3
                            : 1.5,
                      ),
                    ),
                    child: (currentBg.isEmpty ? 'cream' : currentBg) == e.key
                        ? Icon(Icons.check,
                            size: 18,
                            color: e.value.computeLuminance() > 0.6
                                ? AppColors.ink
                                : Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Sección: Pantalla de inicio.
        Text('Pantalla de inicio',
            style: AppText.grotesk(
                size: 13, weight: FontWeight.w700, color: AppColors.white(0.6))),
        const SizedBox(height: 4),
        Text('Qué pestaña se abre al iniciar la app',
            style: AppText.grotesk(size: 11, color: AppColors.white(0.4))),
        const SizedBox(height: 10),
        // Opciones planas dentro de una sola card con hairlines; la elegida se
        // marca con tinte + acento (sin borde por opción).
        _sectionCard([
          for (final opt in tabOptions)
            GestureDetector(
              onTap: () => ctx.read<Session>().setDefaultTab(opt.$1),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                color: currentTab == opt.$1
                    ? AppColors.accent.withAlpha(18)
                    : Colors.transparent,
                child: Row(
                  children: [
                    Icon(opt.$3,
                        size: 18,
                        color: currentTab == opt.$1
                            ? AppColors.accent
                            : AppColors.white(0.5)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(opt.$2,
                          style: AppText.grotesk(
                              size: 14,
                              weight: FontWeight.w600,
                              color: currentTab == opt.$1
                                  ? AppColors.accent
                                  : AppColors.ink)),
                    ),
                    if (currentTab == opt.$1)
                      Icon(Icons.check_circle, size: 18, color: AppColors.accent),
                  ],
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
      ];
    });
  }

  Widget _settingsRow(BuildContext ctx, IconData icon, String title,
      String subtitle, VoidCallback onTap,
      {bool trailingOn = false}) {
    // Fila plana (va dentro de una _sectionCard con hairlines).
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style:
                          AppText.grotesk(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppText.grotesk(
                          size: 11,
                          color: trailingOn
                              ? AppColors.open
                              : AppColors.white(0.5))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.4)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      // El fondo/forma los pone el dialogTheme global (neobrutalista).
      builder: (ctx) => AlertDialog(
        title: Text('Cerrar sesión', style: AppText.archivo(size: 18, weight: FontWeight.w800)),
        content: Text('¿Querés salir de tu cuenta?',
            style: AppText.grotesk(size: 14, color: AppColors.white(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Salir',
                style: AppText.grotesk(size: 13, weight: FontWeight.w700, color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<Session>().logout();
    }
  }
}

/// Un amigo para el ranking: identidad + su total acumulado (para el modo Total).
class _RankFriend {
  final String name;
  final String handle;
  final String email; // normalizado (minúsculas), clave en la DB de partidos
  final int totalPoints;
  const _RankFriend({
    required this.name,
    required this.handle,
    required this.email,
    required this.totalPoints,
  });
}

/// Períodos del ranking. `total` usa el acumulado del perfil; el resto suma los
/// puntos de los partidos con fecha en el rango.
enum _RankPeriod { week, month, season, total }

/// Fila ya resuelta del ranking (identidad + puntos del período elegido).
class _RankEntry {
  final String name;
  final String handle;
  final int points;
  final bool isMe;
  const _RankEntry(this.name, this.handle, this.points, this.isMe);
}

/// Hoja del ranking con selector de período (semana/mes/temporada/total).
///
/// - Mis puntos del período salen de los getters locales del [PlaySessionService]
///   (frescos, incluyen partidos aún no subidos → evita doble conteo con Notion).
/// - Los de amigos se consultan a la DB "Partidos" de Notion filtrando por fecha
///   y por la lista de emails.
/// - Si Notion no está configurado, solo se ofrece "Total".
class _RankingSheet extends StatefulWidget {
  final String myName;
  final String myHandle;
  final int myTotalPoints;
  final PlaySessionService play;
  final List<_RankFriend> friends;

  const _RankingSheet({
    required this.myName,
    required this.myHandle,
    required this.myTotalPoints,
    required this.play,
    required this.friends,
  });

  @override
  State<_RankingSheet> createState() => _RankingSheetState();
}

class _RankingSheetState extends State<_RankingSheet> {
  _RankPeriod _period = _RankPeriod.total;
  bool _loading = false;
  List<_RankEntry> _entries = const [];

  // El ranking por período necesita el historial con fecha en Notion.
  bool get _periodsAvailable =>
      NotionConfig.isConfigured && NotionConfig.dbMatches.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  /// Inicio del rango para el período elegido (espejo de los getters locales del
  /// servicio: semana = lunes 00:00, mes = día 1 00:00, temporada = −180 días).
  DateTime _cutoff(_RankPeriod p) {
    final now = DateTime.now();
    switch (p) {
      case _RankPeriod.week:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case _RankPeriod.month:
        return DateTime(now.year, now.month, 1);
      case _RankPeriod.season:
        // Temporada = semestre de calendario (1 ene–30 jun / 1 jul–31 dic).
        return PlaySessionService.seasonStart(now);
      case _RankPeriod.total:
        return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  int _myPeriodPoints(_RankPeriod p) => switch (p) {
        _RankPeriod.week => widget.play.pointsThisWeek,
        _RankPeriod.month => widget.play.pointsThisMonth,
        _RankPeriod.season => widget.play.pointsSeason,
        _RankPeriod.total => widget.myTotalPoints,
      };

  Future<void> _rebuild() async {
    final p = _period;

    // Modo Total: todo sale de los acumulados, sin red.
    if (p == _RankPeriod.total) {
      final list = <_RankEntry>[
        _RankEntry(widget.myName, widget.myHandle, widget.myTotalPoints, true),
        for (final f in widget.friends)
          _RankEntry(f.name, f.handle, f.totalPoints, false),
      ];
      list.sort((a, b) => b.points.compareTo(a.points));
      setState(() {
        _entries = list;
        _loading = false;
      });
      return;
    }

    // Modo período: mis puntos de local, los de amigos de Notion.
    setState(() => _loading = true);
    final byEmail = <String, int>{};
    final emails = widget.friends
        .map((f) => f.email)
        .where((e) => e.isNotEmpty)
        .toList();
    if (emails.isNotEmpty) {
      try {
        final cutoffIso = _cutoff(p).toIso8601String();
        final rows = await NotionService().queryDatabaseAll(
          NotionConfig.dbMatches,
          filter: NotionService.filterAnd([
            NotionService.filterDateOnOrAfter('EndedAt', cutoffIso),
            NotionService.filterOr(
              [for (final e in emails) NotionService.filterTitle('Email', e)],
            ),
          ]),
        );
        for (final row in rows) {
          final props = row['properties'] as Map<String, dynamic>?;
          if (props == null) continue;
          final email = NotionService.readTitle(props, 'Email').toLowerCase();
          final pts = NotionService.readNumber(props, 'Points').round();
          byEmail[email] = (byEmail[email] ?? 0) + pts;
        }
      } catch (_) {
        // Sin conexión / error: los amigos quedan en 0 para el período.
      }
    }

    if (!mounted) return;
    final list = <_RankEntry>[
      _RankEntry(widget.myName, widget.myHandle, _myPeriodPoints(p), true),
      for (final f in widget.friends)
        _RankEntry(f.name, f.handle, byEmail[f.email] ?? 0, false),
    ];
    list.sort((a, b) => b.points.compareTo(a.points));
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  void _select(_RankPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _rebuild();
  }

  String _subtitle(_RankPeriod p) => switch (p) {
        _RankPeriod.week => 'Puntos de esta semana',
        _RankPeriod.month => 'Puntos de este mes',
        _RankPeriod.season => 'Puntos de la temporada (semestre)',
        _RankPeriod.total => 'Puntos totales',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: AppColors.bgElev,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Handle.
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.white(0.2),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 16),
            Text('Ranking',
                style: AppText.archivo(size: 20, weight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(_subtitle(_period),
                style: AppText.grotesk(size: 12, color: AppColors.white(0.4))),
            const SizedBox(height: 14),
            // Selector de período (solo si hay historial en Notion).
            if (_periodsAvailable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _periodChip('Semana', _RankPeriod.week),
                    const SizedBox(width: 8),
                    _periodChip('Mes', _RankPeriod.month),
                    const SizedBox(width: 8),
                    _periodChip('Temporada', _RankPeriod.season),
                    const SizedBox(width: 8),
                    _periodChip('Total', _RankPeriod.total),
                  ],
                ),
              ),
            if (_periodsAvailable) const SizedBox(height: 14),
            // Lista de ranking.
            Expanded(
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent),
                      ),
                    )
                  // Una sola card con filas planas separadas por hairlines
                  // (antes cada puesto era un box bordeado).
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(AppShape.rCard),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _entries.length,
                            separatorBuilder: (_, _) => Container(
                                height: 1, color: AppColors.white(0.06)),
                            itemBuilder: (_, i) => _rankRow(i, _entries[i]),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodChip(String label, _RankPeriod p) => AppChip(
        label: label,
        active: _period == p,
        onTap: () => _select(p),
      );

  Widget _rankRow(int i, _RankEntry e) {
    final medal = i == 0
        ? '\u{1F947}'
        : i == 1
            ? '\u{1F948}'
            : i == 2
                ? '\u{1F949}'
                : '';
    // Fila plana: "vos" se marca solo con tinte de acento, sin borde.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: e.isMe ? AppColors.accent.withAlpha(18) : Colors.transparent,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              medal.isNotEmpty ? medal : '${i + 1}',
              style: AppText.grotesk(
                size: 13,
                weight: FontWeight.w800,
                color: AppColors.white(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w700,
                    color: e.isMe ? AppColors.accent : AppColors.ink,
                  ),
                ),
                if (e.handle.isNotEmpty)
                  Text(
                    e.handle,
                    style: AppText.grotesk(
                      size: 10,
                      color: AppColors.white(0.4),
                    ),
                  ),
              ],
            ),
          ),
          Text('${e.points}',
              style: AppText.archivo(
                  size: 15,
                  weight: FontWeight.w800,
                  color: e.isMe ? AppColors.accent : AppColors.ink)),
          const SizedBox(width: 4),
          Text('pts',
              style:
                  AppText.grotesk(size: 10, color: AppColors.white(0.35))),
        ],
      ),
    );
  }
}

/// Pestaña de amigos: buscar por handle, agregar (sin aceptación) y listar.
class _FriendsTab extends StatefulWidget {
  final Profile profile;
  const _FriendsTab({required this.profile});

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  final _service = FriendsService();
  final _searchCtrl = TextEditingController();
  late Future<List<Friend>> _future;
  bool _adding = false;

  String get _ownerEmail => widget.profile.userEmail;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Refresca la presencia de los perfiles (estado "Jugando" de los amigos).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProfilesProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Friend>> _load() async {
    if (!_service.isConfigured || _ownerEmail.isEmpty) return [];
    try {
      return await _service.listFriends(_ownerEmail);
    } catch (_) {
      return [];
    }
  }

  void _refresh() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final input = _searchCtrl.text.trim();
    if (input.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _adding = true);
    try {
      final found = await _service.searchByHandle(input);
      if (!mounted) return;
      if (found == null) {
        _snack('No existe ningún jugador con ese handle');
      } else if (FriendsService.normalizeHandle(input) == widget.profile.handle) {
        _snack('No te podés agregar a vos mismo');
      } else {
        final current = await _future;
        final already = current.any((f) => f.friendHandle == found.handle);
        if (already) {
          _snack('${found.handle} ya está en tus amigos');
        } else {
          await _service.addFriend(_ownerEmail, found);
          _searchCtrl.clear();
          _snack('¡Agregaste a ${found.name}!');
          _refresh();
        }
      }
    } catch (_) {
      _snack('No se pudo agregar. Revisá la conexión.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(Friend f) async {
    try {
      await _service.removeFriend(f.pageId);
      _refresh();
    } catch (_) {
      _snack('No se pudo eliminar.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppText.grotesk(size: 13)),
        backgroundColor: AppColors.bgElev,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    // Search bar protagonista: sólida y con borde claro franco.
                    color: AppColors.glass,
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                    border: Border.all(color: AppColors.line, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.alternate_email, size: 16, color: AppColors.white(0.4)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: AppText.grotesk(size: 14),
                          cursorColor: AppColors.accent,
                          onSubmitted: (_) => _add(),
                          decoration: InputDecoration(
                            hintText: 'Buscar por handle (ej. mateo.r)',
                            hintStyle: AppText.grotesk(size: 13.5, color: AppColors.white(0.35)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PressableWidget(
                onTap: _adding ? null : _add,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    // Acento plano + borde negro (sin degradado).
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppShape.rBtn),
                    border: Border.all(color: AppColors.line, width: 1),
                  ),
                  child: _adding
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<List<Friend>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white(0.4)),
                  ),
                );
              }
              // Ocultamos a los usuarios bloqueados de este dispositivo.
              final blocked = context.watch<BlockedProvider>();
              final friends = (snap.data ?? [])
                  .where((f) => !blocked.isBlocked(f.friendEmail))
                  .toList();
              if (friends.isEmpty) {
                // Estado vacío plano: solo texto, sin box.
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      'Todavía no agregaste amigos. Buscá su handle arriba y agregalos',
                      style: AppText.grotesk(
                          size: 12.5, color: AppColors.white(0.35)),
                    ),
                  ),
                );
              }
              // Una sola card con filas planas separadas por hairlines.
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppShape.rCard),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < friends.length; i++) ...[
                          if (i > 0)
                            Container(
                                height: 1, color: AppColors.white(0.06)),
                          _friendCard(friends[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Línea "Jugando en X · 1h 20m" si el amigo lo permite. null si no aplica.
  Widget? _presenceLine(Friend f) {
    final prof = context.watch<ProfilesProvider>().byEmail(f.friendEmail);
    if (prof == null || !prof.playing || !prof.shareStatus) return null;

    var label = 'Jugando';
    if (prof.shareCourt && prof.playingCourtId.isNotEmpty) {
      final courts = context.watch<CourtsProvider>().courts;
      final match = courts.where((c) => c.id == prof.playingCourtId);
      if (match.isNotEmpty) label = 'Jugando en ${match.first.name}';
    }
    // El tiempo corre en vivo (contador local cada 1s) usando PlayingSince como
    // base estática: cero peticiones a la base por segundo.
    DateTime? since;
    if (prof.shareTime && prof.playingSince.isNotEmpty) {
      since = DateTime.tryParse(prof.playingSince);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.open,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: since == null
                ? Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppColors.open),
                  )
                : _LiveElapsed(since: since, prefix: '$label · '),
          ),
        ],
      ),
    );
  }

  /// "Jugó en X · 12/5 14:30" si el amigo lo comparte y no está jugando ahora.
  /// null si no aplica.
  Widget? _lastPlayedLine(Friend f) {
    final prof = context.watch<ProfilesProvider>().byEmail(f.friendEmail);
    if (prof == null ||
        prof.playing ||
        !prof.showLastPlayed ||
        prof.lastPlayedAt.isEmpty) {
      return null;
    }
    final at = DateTime.tryParse(prof.lastPlayedAt);
    if (at == null) return null;

    var label = 'Jugó';
    if (prof.lastPlayedCourtId.isNotEmpty) {
      final courts = context.watch<CourtsProvider>().courts;
      final match = courts.where((c) => c.id == prof.lastPlayedCourtId);
      if (match.isNotEmpty) label = 'Jugó en ${match.first.name}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.history, size: 12, color: AppColors.white(0.4)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label · ${_fmtDateTime(at)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
            ),
          ),
        ],
      ),
    );
  }

  /// Fecha + hora corta, ej. "12/5 · 14:30".
  String _fmtDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month} · $hh:$mm';
  }

  /// Avatar del amigo: muestra su insignia de clan (con su color/tipografía),
  /// o su foto, o la inicial como fallback.
  Widget _friendAvatar(String initial, Profile? fp) {
    final hasClan = (fp?.clan ?? '').trim().isNotEmpty;
    final color = clanColor(fp?.avatarColor ?? '');
    final textColor = clanTextColor(fp?.clanTextColor ?? '');
    final useImage = !hasClan && (fp?.avatar ?? '').isNotEmpty;
    final label = hasClan ? fp!.clan.trim().toUpperCase() : initial;
    final inner = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Avatar de amigo: plano, borde negro y sombra dura chica.
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(color: AppColors.line, width: 1),
        color: useImage ? null : color,
        image: useImage
            ? DecorationImage(image: NetworkImage(fp!.avatar), fit: BoxFit.cover)
            : null,
        boxShadow: AppFx.hardShadow(offset: const Offset(2, 2)),
      ),
      child: useImage
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: clanFontStyle(fp?.clanFont ?? '',
                      size: hasClan ? 16 : 20, color: textColor),
                ),
              ),
            ),
    );
    return framedAvatar(frameById(fp?.avatarFrame ?? ''), AppShape.rBtn, inner);
  }

  Widget _friendCard(Friend f) {
    final initial = (f.friendName.isNotEmpty ? f.friendName[0] : '?').toUpperCase();
    final presence = _presenceLine(f);
    // Si no está jugando, mostramos cuándo jugó por última vez (si lo comparte).
    final lastPlayed = presence == null ? _lastPlayedLine(f) : null;
    final fp = context.watch<ProfilesProvider>().byEmail(f.friendEmail);
    final friendTitle = fp?.title ?? '';
    final friendClan = fp?.clan ?? '';
    final friendLevel = (fp?.level ?? '').isEmpty ? '1' : fp!.level;
    // Fila plana (va dentro de la card única con hairlines).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _friendAvatar(initial, fp),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        f.friendName.isEmpty ? f.friendHandle : f.friendName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.archivo(size: 15, weight: FontWeight.w700),
                      ),
                    ),
                    if (friendClan.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('[$friendClan]',
                          style: AppText.grotesk(
                              size: 11,
                              weight: FontWeight.w800,
                              color: AppColors.accent)),
                    ],
                    const SizedBox(width: 6),
                    // Nivel plano pegado al nombre (sin chip bordeado).
                    Text('NV $friendLevel',
                        style: AppText.grotesk(
                            size: 10,
                            weight: FontWeight.w800,
                            color: AppColors.accent,
                            letterSpacing: 0.06)),
                  ],
                ),
                Text(
                  f.friendHandle,
                  style: AppText.grotesk(size: 12, color: AppColors.white(0.5)),
                ),
                if (friendTitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      friendTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.grotesk(
                          size: 11,
                          weight: FontWeight.w700,
                          color: titleByName(friendTitle)?.color ?? kGold),
                    ),
                  ),
                ?presence,
                ?lastPlayed,
              ],
            ),
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            color: AppColors.bgElev,
            // `child` en vez de `icon` para no heredar los 48px del IconButton.
            child: Padding(
              padding: const EdgeInsets.all(6),
              child:
                  Icon(Icons.more_vert, size: 20, color: AppColors.white(0.4)),
            ),
            onSelected: (v) {
              switch (v) {
                case 'remove':
                  _remove(f);
                  break;
                case 'block':
                  _blockFriend(f);
                  break;
                case 'report':
                  _reportFriend(f);
                  break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('remove', Icons.person_remove_outlined, 'Quitar amigo'),
              _menuItem('block', Icons.block, 'Bloquear'),
              _menuItem('report', Icons.flag_outlined, 'Reportar'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.white(0.7)),
          const SizedBox(width: 10),
          Text(label, style: AppText.grotesk(size: 13)),
        ],
      ),
    );
  }

  /// Bloquea a un usuario (local): oculta su contenido y lo quita de amigos.
  Future<void> _blockFriend(Friend f) async {
    await context.read<BlockedProvider>().block(f.friendEmail);
    await _service.removeFriend(f.pageId).catchError((_) {});
    if (!mounted) return;
    _refresh();
    _snack('Bloqueaste a ${f.friendName.isEmpty ? f.friendHandle : f.friendName}');
  }

  Future<void> _reportFriend(Friend f) async {
    final ok = await ReportService.report(
      tipo: 'usuario',
      referencia: '${f.friendHandle} (${f.friendEmail})',
      reportadoPor: _ownerEmail,
    );
    if (!mounted) return;
    if (!ok) _snack('No se pudo abrir el mail. Escribinos a $kSupportEmail.');
  }
}

/// Diálogo para editar el handle. Valida formato y unicidad vía Session.
class _EditHandleDialog extends StatefulWidget {
  final String current;
  const _EditHandleDialog({required this.current});

  @override
  State<_EditHandleDialog> createState() => _EditHandleDialogState();
}

class _EditHandleDialogState extends State<_EditHandleDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current.replaceFirst('@', ''));
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<Session>().setHandle(_ctrl.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _loading = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // El fondo/forma los pone el dialogTheme global (neobrutalista).
    return AlertDialog(
      title: Text('Editar handle',
          style: AppText.archivo(size: 18, weight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.bgElev,
              borderRadius: BorderRadius.circular(AppShape.rBtn),
              border: Border.all(color: AppColors.white(0.25), width: 1.5),
            ),
            child: Row(
              children: [
                Text('@',
                    style: AppText.archivo(
                        size: 16, weight: FontWeight.w800, color: AppColors.accent)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    style: AppText.grotesk(size: 14),
                    cursorColor: AppColors.accent,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    decoration: InputDecoration(
                      hintText: 'tu.handle',
                      hintStyle: AppText.grotesk(size: 14, color: AppColors.white(0.35)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: AppText.grotesk(size: 12, color: AppColors.accentDark)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: Text('Cancelar',
              style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
        ),
        TextButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                )
              : Text('Guardar',
                  style: AppText.grotesk(
                      size: 13, weight: FontWeight.w700, color: AppColors.accent)),
        ),
      ],
    );
  }
}

/// Construye el TextStyle del clan para una familia de Google Fonts. Si el
/// nombre no existe, cae a Archivo.
/// Fuerza el texto a mayúsculas mientras se escribe (insignia de clan).
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// Diálogo para definir la insignia de clan (hasta 4 caracteres), el color de
/// fondo y el color de las letras. Guarda todo en la base Perfiles vía Session.
class _ClanBadgeDialog extends StatefulWidget {
  final String currentClan;
  final String currentColor;
  final String currentTextColor;
  final String currentFont;
  final String currentFrame;
  final int level;
  const _ClanBadgeDialog({
    required this.currentClan,
    required this.currentColor,
    required this.currentTextColor,
    required this.currentFont,
    required this.currentFrame,
    required this.level,
  });

  @override
  State<_ClanBadgeDialog> createState() => _ClanBadgeDialogState();
}

class _ClanBadgeDialogState extends State<_ClanBadgeDialog> {
  late final TextEditingController _ctrl;
  late String _color;
  late String _textColor;
  late String _font;
  late String _frame;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentClan);
    _color = widget.currentColor.trim().isEmpty
        ? kBgColors.first.hex
        : widget.currentColor.trim().toUpperCase();
    _textColor = widget.currentTextColor.trim().isEmpty
        ? kTextColors.first.hex
        : widget.currentTextColor.trim().toUpperCase();
    _font = widget.currentFont.trim().isEmpty
        ? kFonts.first.family
        : widget.currentFont.trim();
    _frame = widget.currentFrame.trim().isEmpty ? 'none' : widget.currentFrame.trim();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<Session>().setClanBadge(
          clan: _ctrl.text,
          color: _color,
          textColor: _textColor,
          font: _font,
          frame: _frame,
        );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _loading = false;
        _error = err;
      });
    }
  }

  /// Chip seleccionable de cosmético. Si está bloqueado (nivel insuficiente) se
  /// atenúa, no responde al tap y muestra el candado con el nivel requerido.
  Widget _lockableChip({
    required bool unlocked,
    required bool selected,
    required int unlockLevel,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return PressableWidget(
      onTap: unlocked ? onTap : null,
      child: Opacity(
        opacity: unlocked ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // Chip plano (lenguaje editorial): fill sutil sin borde; el elegido
          // se marca solo con el tinte de acento.
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withAlpha(45)
                : AppColors.white(0.06),
            borderRadius: BorderRadius.circular(AppShape.rChip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              if (!unlocked) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock, size: 12, color: AppColors.white(0.55)),
                const SizedBox(width: 1),
                Text('Nv $unlockLevel',
                    style:
                        AppText.grotesk(size: 10, color: AppColors.white(0.55))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = clanColor(_color);
    final fg = clanTextColor(_textColor);
    final preview = _ctrl.text.trim().isEmpty ? 'CLAN' : _ctrl.text.trim();
    // El fondo/forma los pone el dialogTheme global (neobrutalista).
    return AlertDialog(
      title: Text('Insignia de Clan',
          style: AppText.archivo(size: 18, weight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview en vivo del avatar (con el marco equipado). Queda FIJA
            // arriba: no entra en el scroll de las opciones, así siempre se ve.
            Center(
              child: framedAvatar(
                frameById(_frame),
                AppShape.rCard,
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  // Preview coherente con el avatar real: plano + borde negro.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppShape.rCard),
                    border: Border.all(color: AppColors.line, width: 1),
                    color: bg,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(preview,
                          style: clanFontStyle(_font, size: 22, color: fg)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Opciones scrolleables (el preview de arriba permanece visible).
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
          Text('Hasta 4 caracteres',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.5))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // Input plano: fill sutil sin borde (mismo lenguaje que el auth).
            decoration: BoxDecoration(
              color: AppColors.white(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _ctrl,
              // Sin autofocus: que el teclado no tape las opciones al abrir.
              textAlign: TextAlign.center,
              style: AppText.archivo(size: 18, weight: FontWeight.w800),
              cursorColor: AppColors.accent,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(4),
                _UpperCaseFormatter(),
              ],
              decoration: InputDecoration(
                hintText: 'TRPL',
                hintStyle: AppText.archivo(
                    size: 18, weight: FontWeight.w800, color: AppColors.white(0.25)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Marco',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.5))),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final fr in kFrames)
                _lockableChip(
                  unlocked: fr.unlockedAt(widget.level),
                  selected: _frame == fr.id,
                  unlockLevel: fr.unlockLevel,
                  onTap: () => setState(() => _frame = fr.id),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: fr.isNone
                              ? null
                              : LinearGradient(colors: fr.ring),
                          color: fr.isNone ? AppColors.white(0.12) : null,
                          border: fr.isNone
                              ? Border.all(color: AppColors.white(0.3))
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(fr.name,
                          style: AppText.grotesk(
                              size: 12, weight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Tipografía',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.5))),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in kFonts)
                _lockableChip(
                  unlocked: f.unlockedAt(widget.level),
                  selected: _font == f.family,
                  unlockLevel: f.unlockLevel,
                  onTap: () => setState(() => _font = f.family),
                  // Tinta negra: el default blanco era invisible sobre el chip
                  // claro del branding actual.
                  child: Text(preview,
                      style: clanFontStyle(f.family,
                          size: 18, color: AppColors.ink)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _ColorPicker(
            label: 'Color del fondo',
            colors: kBgColors,
            level: widget.level,
            value: _color,
            onChanged: (hex) => setState(() => _color = hex),
          ),
          const SizedBox(height: 18),
          _ColorPicker(
            label: 'Color de las letras',
            colors: kTextColors,
            level: widget.level,
            value: _textColor,
            onChanged: (hex) => setState(() => _textColor = hex),
          ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: AppText.grotesk(
                              size: 12, color: AppColors.accentDark)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: Text('Cancelar',
              style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
        ),
        TextButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                )
              : Text('Aplicar',
                  style: AppText.grotesk(
                      size: 13, weight: FontWeight.w700, color: AppColors.accent)),
        ),
      ],
    );
  }
}

/// Selector de color reutilizable: paleta de muestras. Notifica el hex elegido
/// (6 dígitos) vía [onChanged].
class _ColorPicker extends StatefulWidget {
  final String label;
  final List<CosmeticColor> colors;
  final int level;
  final String value;
  final ValueChanged<String> onChanged;
  const _ColorPicker({
    required this.label,
    required this.colors,
    required this.level,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  void _select(String hex) {
    setState(() => _value = hex);
    widget.onChanged(hex);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: AppText.grotesk(size: 12, color: AppColors.white(0.5))),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in widget.colors)
              () {
                final unlocked = c.unlockedAt(widget.level);
                final selected = _value == c.hex;
                final contrast = clanColor(c.hex).computeLuminance() > 0.6
                    ? Colors.black
                    : Colors.white;
                return PressableWidget(
                  onTap: unlocked ? () => _select(c.hex) : null,
                  child: Opacity(
                    opacity: unlocked ? 1 : 0.4,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: clanColor(c.hex),
                        shape: BoxShape.circle,
                        // Plano: aro blanco solo en el seleccionado; un aro
                        // sutil en el resto para que los oscuros no se fundan
                        // con el fondo del diálogo.
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : AppColors.white(0.12),
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      child: !unlocked
                          ? Icon(Icons.lock, size: 13, color: contrast)
                          : (selected
                              ? Icon(Icons.check, size: 16, color: contrast)
                              : null),
                    ),
                  ),
                );
              }(),
          ],
        ),
      ],
    );
  }
}

/// Ajustes de privacidad de presencia: qué comparte el usuario mientras juega.
class _PrivacyDialog extends StatefulWidget {
  final Profile profile;
  const _PrivacyDialog({required this.profile});

  @override
  State<_PrivacyDialog> createState() => _PrivacyDialogState();
}

class _PrivacyDialogState extends State<_PrivacyDialog> {
  late bool _status = widget.profile.shareStatus;
  late bool _court = widget.profile.shareCourt;
  late bool _time = widget.profile.shareTime;
  late bool _showLast = widget.profile.showLastPlayed;
  late bool _background = context.read<PlaySessionService>().backgroundEnabled;
  bool _saving = false;

  Future<void> _save() async {
    final play = context.read<PlaySessionService>();
    final session = context.read<Session>();
    setState(() => _saving = true);
    // Background es local (por dispositivo); se aplica siempre.
    await play.setBackground(_background);
    final err = await session.setSharePrefs(
          shareStatus: _status,
          shareCourt: _court,
          shareTime: _time,
          showLastPlayed: _showLast,
        );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err, style: AppText.grotesk(size: 13))),
      );
    }
  }

  /// Al ACTIVAR la detección en segundo plano mostramos primero la divulgación
  /// destacada que exige Google Play (qué se recolecta, para qué y que ocurre
  /// con la app cerrada) ANTES de disparar el permiso del sistema. Al desactivar
  /// no hay disclosure. El permiso "Siempre" se pide solo tras aceptar.
  Future<void> _toggleBackground(bool v) async {
    if (!v) {
      setState(() => _background = false);
      return;
    }
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElev,
        title: Text('Ubicación en segundo plano',
            style: AppText.archivo(size: 17, weight: FontWeight.w800)),
        content: Text(
          '1of1 recolecta tu ubicación para detectar y registrar tus partidos, '
          'incluso cuando la app está cerrada o no la estás usando. '
          'Solo guardamos en qué cancha jugaste, no tus coordenadas. '
          'Podés desactivarlo cuando quieras desde acá o desde los ajustes del '
          'sistema.',
          style: AppText.grotesk(size: 13, color: AppColors.white(0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Ahora no',
                style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Permitir',
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (accept != true) return;
    await requestBackgroundLocation();
    if (mounted) setState(() => _background = true);
  }

  Widget _switchRow(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.grotesk(size: 13, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppText.grotesk(size: 11, color: AppColors.white(0.45))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // El fondo/forma los pone el dialogTheme global (neobrutalista).
    return AlertDialog(
      scrollable: true,
      title: Text('Privacidad',
          style: AppText.archivo(size: 18, weight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cuando estés jugando en una cancha:',
            style: AppText.grotesk(size: 12, color: AppColors.white(0.55)),
          ),
          const SizedBox(height: 8),
          _switchRow(
            'Estado visible para amigos',
            'Tus amigos ven que estás "Jugando".',
            _status,
            (v) => setState(() => _status = v),
          ),
          _switchRow(
            'Mostrar la cancha',
            'Aparecés en la cancha donde estás jugando.',
            _court,
            (v) => setState(() => _court = v),
          ),
          _switchRow(
            'Mostrar el tiempo',
            'Se ve cuánto tiempo llevás jugando.',
            _time,
            (v) => setState(() => _time = v),
          ),
          _switchRow(
            'Mostrar último partido',
            'Cuando no estés jugando, tus amigos ven cuándo y dónde jugaste por última vez.',
            _showLast,
            (v) => setState(() => _showLast = v),
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.white(0.08), height: 1),
          const SizedBox(height: 8),
          _switchRow(
            'Detectar en segundo plano',
            'Detecta y guarda tus partidos aunque no tengas la app abierta. Requiere permiso de ubicación "Siempre".',
            _background,
            _toggleBackground,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('Cancelar',
              style: AppText.grotesk(size: 13, color: AppColors.white(0.6))),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                )
              : Text('Guardar',
                  style: AppText.grotesk(
                      size: 13, weight: FontWeight.w700, color: AppColors.accent)),
        ),
      ],
    );
  }
}

/// Tiempo transcurrido que corre en vivo (tick local cada 1s) desde [since].
/// Usa el timestamp estático del amigo como base, sin pegarle a la red.
class _LiveElapsed extends StatefulWidget {
  final DateTime since;
  final String prefix;
  const _LiveElapsed({required this.since, this.prefix = ''});

  @override
  State<_LiveElapsed> createState() => _LiveElapsedState();
}

class _LiveElapsedState extends State<_LiveElapsed> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = DateTime.now().difference(widget.since).inSeconds;
    return Text(
      '${widget.prefix}${PlaySessionService.fmt(secs < 0 ? 0 : secs)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.grotesk(
          size: 11, weight: FontWeight.w600, color: AppColors.open),
    );
  }
}
