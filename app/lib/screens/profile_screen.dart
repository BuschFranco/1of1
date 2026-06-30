import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../data/achievements.dart';
import '../data/cosmetics.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../services/courts_provider.dart';
import '../services/favorites_provider.dart';
import '../services/friends_service.dart';
import '../services/play_session_service.dart';
import '../services/profiles_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import 'notifications_screen.dart';
import '../widgets/app_chip.dart';
import '../widgets/court_image.dart';
import '../widgets/rating_badge.dart';
import '../widgets/section_title.dart';

class ProfileScreen extends StatefulWidget {
  /// Abre el detalle de una cancha (al tocar un favorito).
  final ValueChanged<String>? onSelectCourt;
  const ProfileScreen({super.key, this.onSelectCourt});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0; // 0 = Perfil, 1 = Amigos

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final profile = session.profile ?? const Profile(name: 'Invitado');

    return Container(
      color: AppColors.bg,
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accent.withAlpha(48), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 56),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MI PERFIL',
                      style: AppText.grotesk(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.white(0.4),
                        letterSpacing: 0.2,
                      ),
                    ),
                    Row(
                      children: [
                        _notifButton(context),
                        const SizedBox(width: 8),
                        if (context.read<Session>().isLoggedIn)
                          GestureDetector(
                            onTap: () => _editPrivacy(context, profile),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.white(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.white(0.08)),
                              ),
                              child: const Icon(Icons.settings_outlined,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _confirmLogout(context),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.white(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.white(0.08)),
                            ),
                            child: const Icon(Icons.logout,
                                color: Colors.white, size: 18),
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
                child: _tab == 0
                    ? _profileView(profile)
                    : _FriendsTab(profile: profile),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Botón de campana con badge de notificaciones sin leer. Abre el listado.
  Widget _notifButton(BuildContext context) {
    final unread = context.watch<PlaySessionService>().unreadCount;
    return GestureDetector(
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
              color: AppColors.white(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.white(0.08)),
            ),
            child: const Icon(Icons.notifications_outlined,
                color: Colors.white, size: 18),
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
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.bg, width: 2),
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x331A2430),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.white(0.08)),
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
        onTap: () => setState(() => _tab = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.grotesk(
              size: 13,
              weight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : AppColors.white(0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileView(Profile profile) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 180),
      children: [
        Padding(
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
                      style: AppText.archivo(size: 24, weight: FontWeight.w900),
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
                          GestureDetector(
                            onTap: () => _editHandle(context, profile.handle),
                            behavior: HitTestBehavior.opaque,
                            child: Icon(Icons.edit, size: 13, color: AppColors.accent),
                          ),
                        ],
                      ],
                    ),
                    // Título (coloreado por rareza) y posición (local) como
                    // chips independientes. Cada uno se muestra solo si existe.
                    _identityBadges(profile),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (context.read<Session>().isLoggedIn) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () => _editClanBadge(context, profile),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.white(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.white(0.1)),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: _editPosition,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.white(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.white(0.1)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sports_basketball_outlined,
                        size: 18, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Text('Posición',
                        style: AppText.grotesk(size: 14, weight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      context.watch<Session>().localPosition.isEmpty
                          ? 'Definir'
                          : context.watch<Session>().localPosition,
                      style: AppText.grotesk(size: 13, color: AppColors.white(0.5)),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 18, color: AppColors.white(0.4)),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _levelWithHistory(),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              _StatBox(
                label: 'Partidos',
                value: '${context.watch<PlaySessionService>().totalPlays}',
                accent: true,
              ),
              _StatBox(
                label: 'Canchas',
                value: '${context.watch<PlaySessionService>().uniqueCourtsCount}',
              ),
              _StatBox(
                label: 'Racha',
                value: '${context.watch<PlaySessionService>().streak}',
                icon: Icons.local_fire_department,
                onTap: () => _showStreaks(context),
              ),
              _StatBox(
                label: 'Rating (en construcción)',
                value: profile.rating > 0 ? profile.rating.toStringAsFixed(1) : '—',
                icon: Icons.star_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _totalTimeCard(),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(title: 'Tiempo jugado'),
              _playTimeSection(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Favoritos'),
              _favoritesSection(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Títulos'),
              _titlesSection(profile),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Logros'),
              _achievementsSection(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Últimos partidos'),
              _historySection(),
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 3),
        gradient: useImage
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, _darkenColor(color)],
              ),
        image: useImage
            ? DecorationImage(image: NetworkImage(profile.avatar), fit: BoxFit.cover)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(85),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
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
    return framedAvatar(frameById(profile.avatarFrame), 24, inner);
  }

  Widget _levelCard() {
    final pts = context.watch<PlaySessionService>().points;
    final lvl = levelForPoints(pts);
    final start = pointsForLevel(lvl);
    final next = pointsForLevel(lvl + 1);
    final progress = ((pts - start) / (next - start)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        // Fondo SÓLIDO equivalente al translúcido 0x801A2430 compuesto sobre el
        // fondo de la app, para que el mazo de partidos que va detrás no se
        // transparente a través del nivel.
        color: Color.alphaBlend(const Color(0x801A2430), AppColors.bg),
        border: Border.all(color: AppColors.white(0.08)),
        borderRadius: BorderRadius.circular(18),
      ),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.white(0.08),
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
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
    const peek = 22.0; // cuánto asoma cada carta por debajo de la anterior
    const overlap = 14.0; // cuánto se mete la 1ra carta debajo del nivel
    // Más angostas y más transparentes hacia el final.
    const widths = [0.94, 0.85, 0.76];
    const opacities = [1.0, 0.5, 0.18];

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
    // Fondo SÓLIDO (los translúcidos dejaban ver la carta de atrás al solaparse
    // en el mazo). Componemos sobre el fondo de la app.
    final base = Color.alphaBlend(const Color(0xE61A2430), AppColors.bg);
    switch (r) {
      case PlayResult.win:
        return Color.alphaBlend(AppColors.open.withAlpha(48), base);
      case PlayResult.loss:
        return Color.alphaBlend(const Color(0xFFFF6B6B).withAlpha(48), base);
      case PlayResult.tie:
        return Color.alphaBlend(Colors.white.withAlpha(30), base);
      default:
        return Color.alphaBlend(const Color(0xCC1A2430), AppColors.bg);
    }
  }

  Color _resultBorder(PlayResult? r) {
    switch (r) {
      case PlayResult.win:
        return AppColors.open.withAlpha(110);
      case PlayResult.loss:
        return const Color(0xFFFF6B6B).withAlpha(110);
      case PlayResult.tie:
        return AppColors.white(0.22);
      default:
        return AppColors.white(0.08);
    }
  }

  Widget _recentPointsRow(PlaySession s, double height) {
    final (color, label) = _resultStyle(s.result);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _resultBg(s.result),
        border: Border.all(color: _resultBorder(s.result)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: color.withAlpha(120)),
            ),
            child: Text(label,
                style: AppText.grotesk(
                    size: 9, weight: FontWeight.w800, color: color)),
          ),
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
          const SizedBox(width: 2),
          Text('pts',
              style: AppText.grotesk(size: 10, color: AppColors.white(0.45))),
        ],
      ),
    );
  }

  /// Tiempo total general (todas las canchas). Va pegado justo debajo del grid
  /// de stats.
  Widget _totalTimeCard() {
    final total = context.watch<PlaySessionService>().totalSeconds;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0x801A2430),
        border: Border.all(color: AppColors.white(0.06)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: AppColors.accent, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total',
                  style: AppText.grotesk(size: 11, color: AppColors.white(0.5))),
              const SizedBox(height: 2),
              Text(
                PlaySessionService.fmt(total),
                style: AppText.archivo(
                    size: 20, weight: FontWeight.w900, color: AppColors.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _playTimeSection() {
    final ps = context.watch<PlaySessionService>();
    final items =
        ps.breakdown.where((e) => e.seconds > 0).toList().reversed.toList();
    return Column(
      children: [
        // Desglose por cancha.
        for (final e in items) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => widget.onSelectCourt?.call(e.courtId),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x801A2430),
                border: Border.all(color: AppColors.white(0.06)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 16, color: AppColors.white(0.45)),
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
          ),
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Todavía no jugaste en ninguna cancha.',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.45)),
            ),
          ),
      ],
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

  /// Botón "Ver más" que abre un modal con la lista completa.
  Widget _seeMore(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.white(0.08)),
        ),
        child: Text(label,
            style: AppText.grotesk(
                size: 13, weight: FontWeight.w700, color: AppColors.accent)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    GestureDetector(
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
  static const List<String> _positions = [
    'Base',
    'Escolta',
    'Alero',
    'Ala-Pívot',
    'Pívot',
  ];

  /// Chips de identidad bajo el nombre: título equipado (color de rareza) y
  /// posición de juego (local). Cada uno aparece solo si está definido.
  Widget _identityBadges(Profile profile) {
    final localPos = context.watch<Session>().localPosition;
    final hasTitle = profile.title.isNotEmpty;
    if (!hasTitle && localPos.isEmpty) return const SizedBox.shrink();
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
            ),
          if (localPos.isNotEmpty) AppChip(label: localPos),
        ],
      ),
    );
  }

  /// Selector de posición (bottom sheet). Guarda la elección en local.
  void _editPosition() {
    final current = context.read<Session>().localPosition;
    Widget row(BuildContext ctx, String label, {bool clear = false}) {
      final selected = clear ? current.isEmpty : current == label;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () {
            context.read<Session>().setLocalPosition(clear ? '' : label);
            Navigator.pop(ctx);
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withAlpha(30)
                  : const Color(0x801A2430),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.white(0.08),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  clear ? Icons.not_interested : Icons.sports_basketball,
                  size: 18,
                  color: selected ? AppColors.accent : AppColors.white(0.5),
                ),
                const SizedBox(width: 12),
                Text(clear ? 'Sin posición' : label,
                    style: AppText.grotesk(size: 14, weight: FontWeight.w600)),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle, size: 18, color: AppColors.accent),
              ],
            ),
          ),
        ),
      );
    }

    _showSheet('Elegí tu posición', (ctx) => [
          for (final p in _positions) row(ctx, p),
          row(ctx, '', clear: true),
        ]);
  }

  Widget _achievementsSection() {
    final s = _stats();
    const preview = 5;
    final extra = kAchievements.length - preview;
    return Column(
      children: [
        for (var i = 0; i < kAchievements.length && i < preview; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _achievementRow(kAchievements[i], s),
        ],
        if (extra > 0) ...[
          const SizedBox(height: 10),
          _seeMore('Ver los $extra logros restantes', _showAllAchievements),
        ],
      ],
    );
  }

  void _showAllAchievements() {
    _showSheet('Logros', (ctx) {
      final s = _statsOf(ctx.read<PlaySessionService>());
      return [
        for (var i = 0; i < kAchievements.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _achievementRow(kAchievements[i], s),
        ],
      ];
    });
  }

  Widget _achievementRow(Achievement a, PlayStats s) {
    // Desbloqueado si las stats actuales lo cumplen O si ya quedó registrado en
    // el set permanente (sobrevive al reinstalar, sembrado desde Notion).
    final badges = context.watch<PlaySessionService>().unlockedBadges;
    final unlocked = badges.contains(a.id) || a.unlocked(s);
    final color = unlocked ? kGold : AppColors.white(0.3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x801A2430),
        border: Border.all(
            color: unlocked ? kGold.withAlpha(90) : AppColors.white(0.06)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withAlpha(unlocked ? 38 : 20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(a.icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(a.name,
                    style: AppText.grotesk(
                        size: 13, weight: FontWeight.w700, color: color)),
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
                  style:
                      AppText.grotesk(size: 12, color: AppColors.white(0.45))),
        ],
      ),
    );
  }

  Widget _titlesSection(Profile profile) {
    const preview = 5;
    final extra = kTitles.length - preview;
    return Column(
      children: [
        for (var i = 0; i < kTitles.length && i < preview; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _titleRow(kTitles[i], profile),
        ],
        if (extra > 0) ...[
          const SizedBox(height: 10),
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
        for (var i = 0; i < kTitles.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _titleRow(kTitles[i], profile),
        ],
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
    // Desbloqueado: color de su rareza. Bloqueado: gris.
    final rarity = t.color;
    final color = unlocked ? rarity : AppColors.white(0.3);
    return GestureDetector(
      onTap: (unlocked && loggedIn) ? () => _toggleTitle(t.name, equipped) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: equipped ? rarity.withAlpha(30) : const Color(0x801A2430),
          border: Border.all(
            color: equipped
                ? rarity
                : (unlocked ? rarity.withAlpha(90) : AppColors.white(0.06)),
            width: equipped ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(unlocked ? Icons.workspace_premium : Icons.lock_outline,
                size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.name,
                      style: AppText.grotesk(
                          size: 13, weight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                  Text(
                    '${t.rarity.label} · ${t.unlockDesc}',
                    style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
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
              Text('Equipar',
                  style: AppText.grotesk(
                      size: 12, weight: FontWeight.w600, color: AppColors.accent)),
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
    return Column(
      children: [
        for (var i = 0; i < log.length && i < 20; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _historyRow(log[i]),
        ],
      ],
    );
  }

  Widget _historyRow(PlaySession s) {
    final (color, label) = _resultStyle(s.result);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _resultBg(s.result),
        border: Border.all(color: _resultBorder(s.result)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(120)),
            ),
            child: Text(label,
                style: AppText.grotesk(
                    size: 10, weight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 10),
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
                const SizedBox(height: 2),
                Text(
                  '${_fmtDate(s.endedAtMillis)} · ${PlaySessionService.fmt(s.seconds)}',
                  style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _resultStyle(PlayResult? r) {
    switch (r) {
      case PlayResult.win:
        return (AppColors.open, 'GANÓ');
      case PlayResult.loss:
        return (const Color(0xFFFF6B6B), 'PERDIÓ');
      case PlayResult.tie:
        return (AppColors.white(0.7), 'EMPATÓ');
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
    return Column(
      children: [
        for (var i = 0; i < favs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _favoriteCard(favs[i]),
        ],
      ],
    );
  }

  Widget _favoriteCard(Court c) {
    return GestureDetector(
      onTap: () => widget.onSelectCourt?.call(c.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x801A2430),
          border: Border.all(color: AppColors.white(0.06)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CourtImage(
              url: c.img,
              width: 52,
              height: 52,
              borderRadius: BorderRadius.circular(10),
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
            RatingBadge(value: c.rating, size: 11),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => context.read<FavoritesProvider>().toggle(c.id),
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.favorite, size: 18, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0x801A2430),
        border: Border.all(color: AppColors.white(0.06)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: AppText.grotesk(size: 13, color: AppColors.white(0.5)),
      ),
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
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElev,
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

  Future<void> _editPrivacy(BuildContext context, Profile profile) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PrivacyDialog(profile: profile),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElev,
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
                    color: const Color(0xE011181F),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.white(0.1)),
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
              GestureDetector(
                onTap: _adding ? null : _add,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.accent, AppColors.accentDark],
                    ),
                    borderRadius: BorderRadius.circular(14),
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
              final friends = snap.data ?? [];
              if (friends.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0x801A2430),
                        border: Border.all(color: AppColors.white(0.06)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Todavía no agregaste amigos. Buscá su handle arriba y agregalos',
                        style: AppText.grotesk(size: 13, color: AppColors.white(0.5)),
                      ),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
                itemCount: friends.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _friendCard(friends[i]),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
        gradient: useImage
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, _darkenColor(color)],
              ),
        image: useImage
            ? DecorationImage(image: NetworkImage(fp!.avatar), fit: BoxFit.cover)
            : null,
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
    return framedAvatar(frameById(fp?.avatarFrame ?? ''), 12, inner);
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x801A2430),
        border: Border.all(color: AppColors.white(0.06)),
        borderRadius: BorderRadius.circular(14),
      ),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: AppColors.accent.withAlpha(90)),
                      ),
                      child: Text('Nivel $friendLevel',
                          style: AppText.grotesk(
                              size: 9,
                              weight: FontWeight.w700,
                              color: AppColors.accent)),
                    ),
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
          GestureDetector(
            onTap: () => _remove(f),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.person_remove_outlined, size: 20, color: AppColors.white(0.4)),
            ),
          ),
        ],
      ),
    );
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
    return AlertDialog(
      backgroundColor: AppColors.bgElev,
      title: Text('Editar handle',
          style: AppText.archivo(size: 18, weight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xE011181F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.white(0.1)),
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
                style: AppText.grotesk(size: 12, color: const Color(0xFFFF8A8D))),
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
TextStyle clanFontStyle(
  String family, {
  required double size,
  Color color = Colors.white,
  FontWeight weight = FontWeight.w900,
}) {
  final fam = family.trim().isEmpty ? 'Archivo' : family.trim();
  try {
    return GoogleFonts.getFont(fam, fontSize: size, fontWeight: weight, color: color);
  } catch (_) {
    return GoogleFonts.archivo(fontSize: size, fontWeight: weight, color: color);
  }
}

/// Convierte un hex de 6 dígitos (sin '#') en Color. Vacío o inválido =>
/// color de acento por defecto (usado para el fondo del avatar).
Color clanColor(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.isEmpty) return AppColors.accent;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return AppColors.accent;
  return Color(0xFF000000 | v);
}

/// Igual que [clanColor] pero el default (vacío/inválido) es blanco; se usa
/// para el color de las letras del clan.
Color clanTextColor(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.isEmpty) return Colors.white;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return Colors.white;
  return Color(0xFF000000 | v);
}

/// Envuelve el avatar [child] con el marco equipado: un anillo con degradado y
/// un resplandor exterior. Si el marco es 'none' devuelve el avatar tal cual.
Widget framedAvatar(AvatarFrame frame, double radius, Widget child) {
  if (frame.isNone) return child;
  return Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius + 5),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: frame.ring,
      ),
      boxShadow: [
        BoxShadow(color: frame.glow.withAlpha(140), blurRadius: 20, spreadRadius: 1),
      ],
    ),
    child: child,
  );
}

/// Versión más oscura de un color, para el degradado del avatar.
Color _darkenColor(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
}

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
    return GestureDetector(
      onTap: unlocked ? onTap : null,
      child: Opacity(
        opacity: unlocked ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withAlpha(40)
                : const Color(0xE011181F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.white(0.1),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              if (!unlocked) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock, size: 12, color: AppColors.white(0.55)),
                const SizedBox(width: 2),
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
    return AlertDialog(
      backgroundColor: AppColors.bgElev,
      scrollable: true,
      title: Text('Insignia de Clan',
          style: AppText.archivo(size: 18, weight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview en vivo del avatar (con el marco equipado).
          Center(
            child: framedAvatar(
              frameById(_frame),
              20,
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: bg, width: 3),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [bg, _darkenColor(bg)],
                  ),
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
          Text('Hasta 4 caracteres',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.5))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xE011181F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.white(0.1)),
            ),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
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
                  child: Text(preview, style: clanFontStyle(f.family, size: 18)),
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
                style: AppText.grotesk(size: 12, color: const Color(0xFFFF8A8D))),
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
              : Text('Aplicar',
                  style: AppText.grotesk(
                      size: 13, weight: FontWeight.w700, color: AppColors.accent)),
        ),
      ],
    );
  }
}

/// Selector de color reutilizable: paleta de muestras + input hexadecimal,
/// sincronizados entre sí. Notifica el hex elegido (6 dígitos) vía [onChanged].
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
  late final TextEditingController _hexCtrl;
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
    _hexCtrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _select(String hex) {
    setState(() => _value = hex);
    _hexCtrl.text = hex;
    _hexCtrl.selection = TextSelection.collapsed(offset: hex.length);
    widget.onChanged(hex);
  }

  void _onHex(String value) {
    final h = value.toUpperCase();
    if (RegExp(r'^[0-9A-F]{6}$').hasMatch(h)) {
      setState(() => _value = h);
      widget.onChanged(h);
    } else {
      setState(() {});
    }
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
                return GestureDetector(
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
                        border: Border.all(
                          color:
                              selected ? Colors.white : AppColors.white(0.15),
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
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xE011181F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.white(0.1)),
          ),
          child: Row(
            children: [
              Text('#',
                  style: AppText.archivo(
                      size: 16, weight: FontWeight.w800, color: AppColors.accent)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  style: AppText.grotesk(
                      size: 14, weight: FontWeight.w600, letterSpacing: 0.05),
                  cursorColor: AppColors.accent,
                  textInputAction: TextInputAction.done,
                  onChanged: _onHex,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(6),
                    _UpperCaseFormatter(),
                  ],
                  decoration: InputDecoration(
                    hintText: 'FF6B1A',
                    hintStyle: AppText.grotesk(size: 14, color: AppColors.white(0.3)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: clanColor(_value),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white(0.2)),
                ),
              ),
            ],
          ),
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
    return AlertDialog(
      backgroundColor: AppColors.bgElev,
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
            (v) => setState(() => _background = v),
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

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final IconData? icon;
  final VoidCallback? onTap;

  const _StatBox({
    required this.label,
    required this.value,
    this.accent = false,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: accent
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accent, AppColors.accentDark],
              )
            : null,
        color: accent ? null : const Color(0x991A2430),
        border: accent ? null : Border.all(color: AppColors.white(0.08)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: accent
            ? [
                BoxShadow(
                  color: AppColors.accent.withAlpha(68),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          if (icon != null)
            Positioned(
              top: 0,
              right: 0,
              child: Icon(
                icon,
                size: 16,
                color: accent ? AppColors.white(0.7) : AppColors.white(0.45),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: AppText.archivo(
                  size: 32,
                  weight: FontWeight.w900,
                  letterSpacing: -0.03,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label.toUpperCase(),
                style: AppText.grotesk(
                  size: 10,
                  weight: FontWeight.w600,
                  color: accent ? AppColors.white(0.85) : AppColors.white(0.5),
                  letterSpacing: 0.14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return box;
    return GestureDetector(
        onTap: onTap, behavior: HitTestBehavior.opaque, child: box);
  }
}
