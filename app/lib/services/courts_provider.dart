import 'package:flutter/foundation.dart';
import '../data/courts.dart';
import '../notion/notion_config.dart';
import 'notion_service.dart';

/// Fuente de canchas para la app. Carga desde Notion.
/// Si no hay token o falla, la lista queda vacía.
class CourtsProvider extends ChangeNotifier {
  CourtsProvider({NotionService? notion}) : _notion = notion ?? NotionService();

  final NotionService _notion;

  List<Court> _courts = [];
  bool _loading = false;
  bool _fromNotion = false;

  List<Court> get courts => _courts;
  bool get loading => _loading;
  bool get fromNotion => _fromNotion;

  Future<void> load() async {
    if (!_notion.isConfigured) {
      _courts = [];
      _fromNotion = false;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final rows = await _notion.queryDatabase(
        NotionConfig.dbCourts,
        filter: NotionService.filterSelect('Aprobacion', CourtApproval.approved),
      );
      _courts = rows.map(Court.fromNotion).toList();
      _fromNotion = true;
    } catch (_) {
      _courts = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Crea una cancha en Notion en estado "Sin definir" (pendiente de
  /// moderación). No aparece en la app hasta que se apruebe en Notion.
  Future<void> addCourt(
    Court court, {
    String? createdBy,
    String? createdByClan,
    String? createdByEmail,
  }) async {
    await _notion.createPage(
      NotionConfig.dbCourts,
      court.toNotionProperties(
        createdBy: createdBy,
        createdByClan: createdByClan,
        createdByEmail: createdByEmail,
        approval: CourtApproval.pending,
      ),
    );
    await load();
  }
}
