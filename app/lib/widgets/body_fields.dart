import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'app_chip.dart';

/// Sexo y peso, opcionales. Los comparten el alta (pantalla del handle) y el
/// lápiz del perfil. Se usan solo para estimar calorías desde el pulso del
/// reloj y se guardan únicamente en el celu.
///
/// Sexo: 'male' / 'female' / 'none' (prefiere no decir) / null (sin elegir).
class BodyFields extends StatelessWidget {
  final String? sex;
  final ValueChanged<String?> onSex;
  final TextEditingController weight;

  const BodyFields({
    super.key,
    required this.sex,
    required this.onSex,
    required this.weight,
  });

  static const _options = [
    ('male', 'Masculino'),
    ('female', 'Femenino'),
    ('none', 'Prefiero no decir'),
  ];

  /// Peso válido en kg, null si está vacío. Lanza [FormatException] con el
  /// mensaje para el usuario si está fuera de rango.
  static double? parseWeight(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v < 30 || v > 250) {
      throw const FormatException('El peso tiene que estar entre 30 y 250 kg.');
    }
    return v;
  }

  /// "75 kg · Masculino", lo que haya, o null si no hay nada.
  static String? summary(double? weightKg, String? sex) {
    final parts = [
      if (weightKg != null)
        '${weightKg == weightKg.roundToDouble() ? weightKg.round() : weightKg.toStringAsFixed(1)} kg',
      if (sex == 'male') 'Masculino',
      if (sex == 'female') 'Femenino',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sexo',
            style: AppText.grotesk(
                size: 12, weight: FontWeight.w700, color: AppColors.white(0.6))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in _options)
              AppChip(
                label: label,
                active: sex == value,
                // Tocar el elegido lo deselecciona (vuelve a "sin especificar").
                onTap: () => onSex(sex == value ? null : value),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Peso',
            style: AppText.grotesk(
                size: 12, weight: FontWeight.w700, color: AppColors.white(0.6))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bgElev,
            borderRadius: BorderRadius.circular(AppShape.rBtn),
            border: Border.all(color: AppColors.white(0.25), width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  style: AppText.grotesk(size: 14),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    hintText: 'Ej: 75',
                    hintStyle:
                        AppText.grotesk(size: 14, color: AppColors.white(0.35)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              Text('kg',
                  style: AppText.grotesk(
                      size: 13, color: AppColors.white(0.5))),
            ],
          ),
        ),
      ],
    );
  }
}
