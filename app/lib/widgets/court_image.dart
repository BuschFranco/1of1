import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/cache/court_image_cache.dart';
import '../theme/app_theme.dart';
import 'skeleton.dart';

/// Imagen de una cancha. Mientras carga muestra un skeleton con brillo y al
/// llegar entra con un fade; queda guardada en disco ([courtImageCache]) y las
/// próximas veces aparece al instante. Sin URL (o si falla) muestra un fondo
/// con una pelota tenue: "sin foto", distinto de "cargando".
class CourtImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const CourtImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = url.trim().isEmpty
        ? _placeholder()
        : CachedNetworkImage(
            imageUrl: url,
            cacheManager: courtImageCache,
            width: width,
            height: height,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 320),
            fadeOutDuration: const Duration(milliseconds: 120),
            placeholder: (_, _) => Skeleton(width: width, height: height),
            errorWidget: (_, _, _) => _placeholder(),
          );
    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      // Placeholder plano (neobrutalismo): sin degradado.
      color: AppColors.card,
      child: LayoutBuilder(
        builder: (_, c) {
          final size = (c.biggest.shortestSide * 0.34).clamp(18.0, 56.0);
          return Center(
            child: Icon(
              Icons.sports_basketball,
              size: size,
              color: AppColors.white(0.12),
            ),
          );
        },
      ),
    );
  }
}
