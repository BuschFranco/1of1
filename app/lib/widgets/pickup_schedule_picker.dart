import 'package:flutter/material.dart';
import '../data/courts.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

/// Elección de fecha + horario de un pickup, respetando el horario de apertura
/// de la cancha. Vive acá (y no en una pantalla) porque lo usan tanto la
/// creación del pickup como la edición desde su chat: una sola fuente para la
/// lógica de slots evita que las dos pantallas se desincronicen.
///
/// Devuelve null si el usuario cancela en cualquiera de los dos pasos.
Future<DateTime?> pickPickupDateTime(
  BuildContext context,
  Court? court, {
  DateTime? initial,
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

  final slot = await _pickTimeSlot(context, court, datePicked, initial);
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

/// Bottom sheet compacto para elegir un horario: una rueda que se desliza entre
/// los slots válidos de la cancha.
Future<TimeOfDay?> _pickTimeSlot(
  BuildContext context,
  Court? court,
  DateTime forDate,
  DateTime? initial,
) async {
  final slots = courtTimeSlots(court);
  if (slots.isEmpty) return null;
  final subtitle = court == null
      ? 'Horario libre'
      : (court.is24h
          ? 'Abierta 24h'
          : (court.openTod != null && court.closeTod != null
              ? court.hoursLabel
              : 'Horario libre'));

  // Arranca en el horario que ya tenía el pickup (si estamos editando); si no,
  // en el primer slot posterior a ahora cuando la fecha elegida es HOY. Para
  // una fecha futura arranca en el primer slot de la cancha.
  final now = DateTime.now();
  final isToday = forDate.year == now.year &&
      forDate.month == now.month &&
      forDate.day == now.day;
  var startIndex = 0;
  if (initial != null) {
    final target = initial.hour * 60 + initial.minute;
    final i = slots.indexWhere((s) => s.hour * 60 + s.minute >= target);
    if (i >= 0) startIndex = i;
  } else if (isToday) {
    final nowMin = now.hour * 60 + now.minute;
    final i = slots.indexWhere((s) => s.hour * 60 + s.minute >= nowMin);
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
    builder: (ctx) => SafeArea(
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
                    size: 18, weight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule, size: 13, color: AppColors.accent),
                const SizedBox(width: 5),
                Text(subtitle,
                    style:
                        AppText.grotesk(size: 12, color: AppColors.white(0.5))),
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
                      color: AppColors.accent.withAlpha(26),
                      borderRadius: BorderRadius.circular(AppShape.rBtn),
                    ),
                  ),
                  ListWheelScrollView.useDelegate(
                    controller: controller,
                    itemExtent: 44,
                    diameterRatio: 1.6,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => selected = i,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: slots.length,
                      builder: (_, i) {
                        final s = slots[i];
                        return Center(
                          child: Text(
                            '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}',
                            style: AppText.archivo(
                                size: 20,
                                weight: FontWeight.w800,
                                color: Colors.white),
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
              onTap: () => Navigator.pop(ctx, slots[selected]),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppShape.rBtn),
                ),
                child: Text('CONFIRMAR',
                    style: AppText.archivo(
                        size: 14,
                        weight: FontWeight.w800,
                        letterSpacing: 0.04,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  ).whenComplete(controller.dispose);
}
