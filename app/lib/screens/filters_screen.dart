import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';

class FiltersScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const FiltersScreen({super.key, this.onBack});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  String _type = 'todas';
  String _price = 'todas';
  String _surface = 'todas';
  Set<String> _amenities = {'lit'};
  double _distance = 5;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              children: [
                _section('Tipo de cancha', _chipRow(
                  [('todas', 'Todas'), ('exterior', 'Exterior'), ('interior', 'Interior')],
                  _type,
                  (k) => setState(() => _type = k),
                )),
                _section('Precio', _chipRow(
                  [('todas', 'Todas'), ('gratis', 'Gratis'), ('pago', 'Pago')],
                  _price,
                  (k) => setState(() => _price = k),
                )),
                _section('Superficie', _chipRow(
                  [
                    ('todas', 'Todas'),
                    ('asfalto', 'Asfalto'),
                    ('cemento', 'Cemento'),
                    ('parquet', 'Parquet'),
                    ('caucho', 'Caucho'),
                  ],
                  _surface,
                  (k) => setState(() => _surface = k),
                )),
                _section('Amenities', Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in const [
                      ('lit', 'Iluminada'),
                      ('park', 'Estacionam.'),
                      ('lock', 'Vestuarios'),
                      ('water', 'Bebedero'),
                      ('reg', 'Reglamentaria'),
                      ('night', '24h'),
                    ])
                      AppChip(
                        label: o.$2,
                        active: _amenities.contains(o.$1),
                        onTap: () => setState(() {
                          _amenities = Set.of(_amenities);
                          if (_amenities.contains(o.$1)) {
                            _amenities.remove(o.$1);
                          } else {
                            _amenities.add(o.$1);
                          }
                        }),
                      ),
                  ],
                )),
                _section('Distancia máxima · ${_distance.toInt()} km', _slider()),
                _section('Vibe', Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    AppChip(label: 'Casual'),
                    AppChip(label: 'Competitivo'),
                    AppChip(label: 'Profesional'),
                    AppChip(label: 'Entrenamiento'),
                    AppChip(label: 'Callejero'),
                  ],
                )),
                const SizedBox(height: 20),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.white(0.06))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.white(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.white(0.08)),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
          Text(
            'FILTROS',
            style: AppText.archivo(size: 18, weight: FontWeight.w900),
          ),
          Text(
            'Reset',
            style: AppText.grotesk(
              size: 12,
              weight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppText.archivo(
              size: 12,
              weight: FontWeight.w800,
              letterSpacing: 0.14,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _chipRow(
    List<(String, String)> options,
    String selected,
    ValueChanged<String> onTap,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          AppChip(
            label: o.$2,
            active: selected == o.$1,
            onTap: () => onTap(o.$1),
          ),
      ],
    );
  }

  Widget _slider() {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.white(0.06),
            thumbColor: Colors.white,
            overlayColor: AppColors.accent.withAlpha(40),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 4,
            ),
          ),
          child: Slider(
            value: _distance,
            min: 1,
            max: 20,
            onChanged: (v) => setState(() => _distance = v),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final v in [1, 5, 10, 15, 20])
              GestureDetector(
                onTap: () => setState(() => _distance = v.toDouble()),
                child: Text(
                  '${v}km',
                  style: AppText.grotesk(
                    size: 11,
                    weight: FontWeight.w600,
                    color: _distance.toInt() == v
                        ? AppColors.accent
                        : AppColors.white(0.4),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      decoration: BoxDecoration(
        color: const Color(0xE60A0F14),
        border: Border(top: BorderSide(color: AppColors.white(0.06))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: widget.onBack,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            elevation: 12,
            shadowColor: AppColors.accent.withAlpha(85),
          ),
          child: Text(
            'VER 127 CANCHAS',
            style: AppText.archivo(
              size: 13,
              weight: FontWeight.w800,
              letterSpacing: 0.06,
            ),
          ),
        ),
      ),
    );
  }
}
