import 'package:url_launcher/url_launcher.dart';
import '../data/legal_content.dart';

/// Reporte de contenido/usuarios inapropiados. Abre el cliente de mail del
/// usuario con un correo prellenado a [kSupportEmail]. Es el mecanismo que
/// exigen las tiendas (Apple 1.2 / Google UGC) para denunciar contenido y que
/// el equipo pueda actuar en ≤ 24 h. Sin backend propio, el mail es la vía
/// más directa y universalmente aceptada.
class ReportService {
  /// Lanza el mail de reporte. Devuelve true si se pudo abrir el cliente.
  static Future<bool> report({
    required String tipo, // 'usuario' | 'reseña' | 'cancha' | 'perfil'
    required String referencia, // handle/email/id o texto que identifica el contenido
    String reportadoPor = '',
    String detalle = '',
  }) async {
    final subject = '[1of1] Reporte de $tipo';
    final body = StringBuffer()
      ..writeln('Tipo de contenido: $tipo')
      ..writeln('Referencia: $referencia')
      ..writeln('Reportado por: ${reportadoPor.isEmpty ? "—" : reportadoPor}')
      ..writeln('')
      ..writeln('Motivo / detalle:')
      ..writeln(detalle.isEmpty ? '(describí acá el problema)' : detalle)
      ..writeln('')
      ..writeln('— Enviado desde 1of1');

    final uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: _encodeQuery({'subject': subject, 'body': body.toString()}),
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  // Uri(query:) no codifica igual que los clientes de mail esperan; armamos el
  // query a mano con encodeComponent para respetar espacios y saltos de línea.
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
}
