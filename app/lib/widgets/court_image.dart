import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Imagen de una cancha con placeholder. Si no hay URL (o falla la carga),
/// muestra un fondo gris oscuro con un ícono tenue, dando la impresión de
/// "sin imagen". Llena el tamaño dado (o se expande si width/height son null).
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
        : Image.network(
            url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(),
            loadingBuilder: (ctx, child, progress) =>
                progress == null ? child : _placeholder(),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF222B38), Color(0xFF151C26)],
        ),
      ),
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
