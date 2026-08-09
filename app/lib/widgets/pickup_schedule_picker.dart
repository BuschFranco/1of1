import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../services/pickups_provider.dart';
import '../theme/app_theme.dart';
import 'busy_overlay.dart';
import 'pressable_widget.dart';

/// Elección de fecha + horario de un pickup, respetando el horario de apertura
/// de la cancha Y los horarios que ya están ocupados por otros pickups. Vive acá
/// (y no en una pantalla) porque lo usan tanto la creación del pickup como la
/// edición desde su chat: una sola fuente para la lógica de slots evita que las
/// dos pantallas se desincronicen.
///
/// [teamSize] define cuánto ocupa el pickup: un 5v5 es cancha completa (2 aros),
/// un 4v4 o menos es media cancha (1). Por eso el mismo horario puede estar
/// libre para un 3v3 y ocupado para un 5v5.
///
/// [excludePickupId] es el pickup que se está reprogramando: sin esto chocaría
/// contra su propio horario actual.
///
/// Devuelve null si el usuario cancela en cualquiera de los dos pasos.
Future<DateTime?> pickPickupDateTime(
  BuildContext context,
  Court? court, {
  DateTime? initial,
  int teamSize = 3,
  String? excludePickupId,
}) async {
  final now = DateTime.now();
  // Si la fecha guardada ya pasó, el picker no puede arrancar ahí (firstDate es
  // hoy): caemos en hoy.
  final initialDate =
      (initial != null && !initial.isBefore(now)) ? initial : now;

  final datePicked = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: now,
    lastDate: now.add(const Duration(days: 90)),
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.bg,
        ),
      ),
      child: child!,
    ),
  );
  if (datePicked == null || !context.mounted) return null;

  // Qué está ocupado ese día lo sabe SOLO el backend: la lista local de pickups
  // tiene únicamente los propios, no los de otros usuarios. Va con overlay
  // porque el server duerme y puede tardar 30-60 s en despertar.
  var availability = CourtAvailability.unknown;
  if (court != null) {
    availability = await runBusy(
          context,
          () => context.read<PickupsProvider>().availability(
                court.id,
                datePicked,
                excludePickupId: excludePickupId,
              ),
        ) ??
        CourtAvailability.unknown;
    if (!context.mounted) return null;
  }

  final slot = await _pickTimeSlot(
    context,
    court,
    datePicked,
    initial,
    availability,
    teamSize,
  );
  if (slot == null) return null;

  return DateTime(
    datePicked.year,
    datePicked.month,
    datePicked.day,
    slot.hour,
    slot.minute,
  );
}

/// Horarios disponibles (cada 30 min) según el horario de la cancha. 24h, sin
/// cancha o sin horario parseable → todo el día. Maneja rangos que cruzan
/// medianoche (ej. 18:00–02:00).
List<TimeOfDay> courtTimeSlots(Court? c) {
  final slots = <TimeOfDay>[];
  if (c == null || c.is24h || c.openTod == null || c.closeTod == null) {
    for (var m = 0; m < 24 * 60; m += 30) {
      slots.add(TimeOfDay(hour: m ~/ 60, minute: m % 60));
    }
    return slots;
  }
  final start = c.openTod!.hour * 60 + c.openTod!.minute;
  var end = c.closeTod!.hour * 60 + c.closeTod!.minute;
  if (end <= start) end += 24 * 60; // cruza medianoche
  for (var m = start; m < end; m += 30) {
    final mm = m % (24 * 60);
    slots.add(TimeOfDay(hour: mm ~/ 60, minute: mm % 60));
  }
  return slots;
}

/// Un horario de la rueda con el motivo por el que no se puede elegir, si lo hay.
class _Slot {
  final TimeOfDay time;

  /// Ya pasó. Solo puede ser true cuando la fecha elegida es hoy.
  final bool past;

  /// La cancha no tiene aros libres a esa hora para este formato de partido.
  final bool busy;

  const _Slot(this.time, {required this.past, required this.busy});

  bool get free => !past && !busy;

  String get label =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Cruza los slots de la cancha con la ocupación y con el reloj.
List<_Slot> _buildSlots(
  Court? court,
  DateTime date,
  CourtAvailability availability,
  int teamSize,
) {
  final now = DateTime.now();
  final isToday =
      date.year == now.year && date.month == now.month && date.day == now.day;
  return courtTimeSlots(court).map((t) {
    final start = DateTime(date.year, date.month, date.day, t.hour, t.minute);
    return _Slot(
      t,
      past: isToday && start.isBefore(now),
      busy: !availability.fits(start, teamSize),
    );
  }).toList();
}

/// Bottom sheet compacto para elegir un horario: una rueda que se desliza entre
/// los slots de la cancha. Los ocupados y los que ya pasaron se muestran en gris
/// y no se pueden confirmar — se muestran igual (en vez de esconderlos) para que
/// se vea de un vistazo a partir de qué hora hay lugar.
Future<TimeOfDay?> _pickTimeSlot(
  BuildContext context,
  Court? court,
  DateTime forDate,
  DateTime? initial,
  CourtAvailability availability,
  int teamSize,
) async {
  final slots = _buildSlots(court, forDate, availability, teamSize);
  if (slots.isEmpty) return null;

  final hoursLabel = court == null
      ? 'Horario libre'
      : (court.is24h
          ? 'Abierta 24h'
          : (court.openTod != null && court.closeTod != null
              ? court.hoursLabel
              : 'Horario libre'));

  final firstFree = slots.indexWhere((s) => s.free);
  final subtitle = firstFree < 0
      ? 'Sin horarios libres ese día'
      : 'Libre desde ${slots[firstFree].label} · $hoursLabel';

  // Arranca en el horario que ya tenía el pickup (si estamos editando); si no,
  // en el primer slot LIBRE. Nunca en uno ocupado: sería ofrecer algo que el
  // botón de confirmar va a rechazar.
  var startIndex = firstFree < 0 ? 0 : firstFree;
  if (initial != null) {
    final target = initial.hour * 60 + initial.minute;
    final i = slots.indexWhere(
        (s) => s.free && s.time.hour * 60 + s.time.minute >= target);
    if (i >= 0) startIndex = i;
  }

  var selected = startIndex;
  final controller = FixedExtentScrollController(initialItem: startIndex);

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: AppColors.bgElev,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.rCard)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final canConfirm = slots[selected].free;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.white(0.2),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Elegí un horario',
                    style: AppText.archivo(
                        size: 18,
                        weight: FontWeight.w900,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule, size: 13, color: AppColors.accent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(subtitle,
                          textAlign: TextAlign.center,
                          style: AppText.grotesk(
                              size: 12, color: AppColors.white(0.5))),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Rueda de horarios con banda de selección al centro.
                SizedBox(
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: canConfirm
                              ? AppColors.accent.withAlpha(26)
                              : AppColors.white(0.06),
                          borderRadius: BorderRadius.circular(AppShape.rBtn),
                        ),
                      ),
                      ListWheelScrollView.useDelegate(
                        controller: controller,
                        itemExtent: 44,
                        diameterRatio: 1.6,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) =>
                            setSheetState(() => selected = i),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: slots.length,
                          builder: (_, i) {
                            final s = slots[i];
                            return Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    s.label,
                                    style: AppText.archivo(
                                      size: 20,
                                      weight: FontWeight.w800,
                                      color: s.free
                                          ? Colors.white
                                          : AppColors.white(0.25),
                                    ),
                                  ),
                                  if (!s.free) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      s.past ? 'ya pasó' : 'ocupado',
                                      style: AppText.grotesk(
                                          size: 11,
                                          color: AppColors.white(0.3)),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PressableWidget(
                  onTap: canConfirm
                      ? () => Navigator.pop(ctx, slots[selected].time)
                      : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          canConfirm ? AppColors.accent : AppColors.white(0.10),
                      borderRadius: BorderRadius.circular(AppShape.rBtn),
                    ),
                    child: Text(
                      canConfirm
                          ? 'CONFIRMAR'
                          : (slots[selected].past
                              ? 'ESE HORARIO YA PASÓ'
                              : 'HORARIO OCUPADO'),
                      style: AppText.archivo(
                        size: 14,
                        weight: FontWeight.w800,
                        letterSpacing: 0.04,
                        color: canConfirm ? Colors.white : AppColors.white(0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  ).whenComplete(controller.dispose);
}
