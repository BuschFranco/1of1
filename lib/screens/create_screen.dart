import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import '../services/courts_provider.dart';
import '../services/notion_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/under_construction.dart';
import 'add_court_screen.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  static const _options = [
    ('Crear pickup game', 'Organizá un partido en cualquier cancha', Icons.sports_basketball),
    ('Agregar cancha', '¿Conocés una cancha que no está?', Icons.add_location_alt_outlined),
    ('Check-in', 'Avisá que estás jugando ahora', Icons.check_circle_outline),
    ('Reservar cancha', 'Reservá un horario', Icons.event_available_outlined),
  ];

  void _onTap(BuildContext context, int i) {
    if (i == 0) {
      _openPickupSheet(context);
    } else if (i == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddCourtScreen()),
      );
    } else {
      showUnderConstruction(context, _options[i].$1);
    }
  }

  // Las opciones 2 y 3 (Check-in, Reservar) todavía no tienen backend.
  static const _wip = {2, 3};

  Future<void> _openPickupSheet(BuildContext context) async {
    final courts = context.read<CourtsProvider>().courts;
    final session = context.read<Session>();
    if (session.email == null) return;
    if (courts.isEmpty) return;

    final notion = NotionService();
    Court selected = courts.first;
    DateTime? when;
    int maxPlayers = 10;
    final notesCtrl = TextEditingController();
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          top: false,
          child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nuevo pickup', style: AppText.archivo(size: 22, weight: FontWeight.w900)),
              const SizedBox(height: 18),
              _label('Cancha'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0x331A2430),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.white(0.1)),
                ),
                child: DropdownButton<Court>(
                  value: selected,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.bgElev,
                  style: AppText.grotesk(size: 14),
                  items: [
                    for (final c in courts)
                      DropdownMenuItem(value: c, child: Text(c.name)),
                  ],
                  onChanged: (c) => setLocal(() => selected = c ?? selected),
                ),
              ),
              const SizedBox(height: 16),
              _label('Cuándo'),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) setLocal(() => when = picked);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0x331A2430),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.white(0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: AppColors.white(0.6)),
                      const SizedBox(width: 10),
                      Text(
                        when == null
                            ? 'Elegir fecha'
                            : '${when!.day}/${when!.month}/${when!.year}',
                        style: AppText.grotesk(
                          size: 14,
                          color: when == null ? AppColors.white(0.4) : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _label('Jugadores máximos'),
              Row(
                children: [
                  _stepBtn(Icons.remove, () {
                    if (maxPlayers > 2) setLocal(() => maxPlayers--);
                  }),
                  const SizedBox(width: 16),
                  Text('$maxPlayers', style: AppText.archivo(size: 20, weight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  _stepBtn(Icons.add, () {
                    if (maxPlayers < 30) setLocal(() => maxPlayers++);
                  }),
                ],
              ),
              const SizedBox(height: 16),
              _label('Notas (opcional)'),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                style: AppText.grotesk(size: 14),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: 'Ej. 5v5, nivel intermedio',
                  hintStyle: AppText.grotesk(size: 13, color: AppColors.white(0.35)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.white(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: saving
                    ? null
                    : () async {
                        setLocal(() => saving = true);
                        try {
                          await notion.createPage(
                            NotionConfig.dbPickups,
                            Pickup(
                              title: 'Pickup en ${selected.name}',
                              courtId: selected.id,
                              createdBy: session.email!,
                              dateTime: when?.toIso8601String(),
                              maxPlayers: maxPlayers,
                              vibe: selected.vibe,
                              notes: notesCtrl.text.trim(),
                            ).toNotionProperties(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('¡Pickup creado!', style: AppText.grotesk(size: 13)),
                                backgroundColor: AppColors.accent,
                              ),
                            );
                          }
                        } catch (_) {
                          setLocal(() => saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('No se pudo crear el pickup.',
                                    style: AppText.grotesk(size: 13)),
                                backgroundColor: AppColors.bg,
                              ),
                            );
                          }
                        }
                      },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: saving
                        ? null
                        : const LinearGradient(
                            colors: [AppColors.accent, AppColors.accentDark],
                          ),
                    color: saving ? AppColors.white(0.1) : null,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  alignment: Alignment.center,
                  child: saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white(0.6)),
                        )
                      : Text('CREAR PICKUP',
                          style: AppText.archivo(size: 14, weight: FontWeight.w900, letterSpacing: 0.04)),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  static Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: AppText.grotesk(
            size: 11,
            weight: FontWeight.w700,
            color: AppColors.white(0.45),
            letterSpacing: 0.08,
          ),
        ),
      );

  static Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x331A2430),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.white(0.1)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
        children: [
          Text(
            'Nuevo',
            style: AppText.archivo(
              size: 34,
              weight: FontWeight.w900,
              letterSpacing: -0.03,
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _options.length; i++)
            GestureDetector(
              onTap: () => _onTap(context, i),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0x991A2430),
                  border: Border.all(color: AppColors.white(0.06)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(_options[i].$3, size: 28, color: AppColors.accent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _options[i].$1,
                                  style: AppText.archivo(size: 16, weight: FontWeight.w800),
                                ),
                              ),
                              if (_wip.contains(i)) ...[
                                const SizedBox(width: 8),
                                const UnderConstructionBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _options[i].$2,
                            style: AppText.grotesk(size: 12, color: AppColors.white(0.55)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
