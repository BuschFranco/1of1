import 'package:flutter/material.dart';
import '../data/cosmetics.dart';
import '../data/models.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// Insignia de un jugador (misma jerarquía que el avatar del perfil):
/// clan (texto) > foto (URL) > inicial sobre color. Extraída del patrón que
/// usan el perfil y el crew para poder reutilizarla en filas/mazos de
/// avatares (p. ej. "Jugando ahora" en el detalle de cancha).
class PlayerAvatar extends StatelessWidget {
  final Profile? profile;

  /// Fallback cuando no hay perfil o el perfil no tiene nombre.
  final String initial;
  final double size;

  const PlayerAvatar({
    super.key,
    required this.profile,
    this.initial = '?',
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final hasClan = (p?.clan ?? '').trim().isNotEmpty;
    final color = clanColor(p?.avatarColor ?? '');
    final textColor = clanTextColor(p?.clanTextColor ?? '');
    final useImage = !hasClan && (p?.avatar ?? '').isNotEmpty;
    final fallbackInitial =
        (p?.name.isNotEmpty ?? false) ? p!.name[0].toUpperCase() : initial;
    final label = hasClan ? p!.clan.trim().toUpperCase() : fallbackInitial;
    final inner = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(color: AppColors.line, width: 1),
        color: useImage ? null : color,
        image: useImage
            ? DecorationImage(
                image: NetworkImage(p!.avatar), fit: BoxFit.cover)
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
                  style: clanFontStyle(p?.clanFont ?? '',
                      size: hasClan ? size * 0.36 : size * 0.45,
                      color: textColor),
                ),
              ),
            ),
    );
    return framedAvatar(frameById(p?.avatarFrame ?? ''), AppShape.rBtn, inner);
  }
}
