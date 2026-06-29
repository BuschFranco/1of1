import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../data/courts.dart';
import '../services/courts_provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';

const _kMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0d1520"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8896a7"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0a0f14"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c0c8d8"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a2a3a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#1e3040"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1a3a52"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0a1929"}]}
]
''';

class AddCourtScreen extends StatefulWidget {
  const AddCourtScreen({super.key});

  @override
  State<AddCourtScreen> createState() => _AddCourtScreenState();
}

class _AddCourtScreenState extends State<AddCourtScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  // Imagen elegida desde el celular. Por ahora solo vive en el front (preview);
  // todavía no se sube a la base de datos.
  XFile? _pickedImage;

  String _type = 'Exterior';
  String _surface = 'Asfalto';
  int _hoops = 2;
  String _vibe = 'Casual';
  bool _free = true;
  bool _lit = false;
  bool _hasCost = false;
  final _priceCtrl = TextEditingController();
  String _priceUnit = 'hora';
  final Set<String> _amenities = {};
  LatLng _pinLocation = const LatLng(-34.6037, -58.3816);
  GoogleMapController? _mapCtrl;
  bool _locating = false;
  bool _submitted = false;

  static const _surfaces = ['Asfalto', 'Cemento', 'Parquet', 'Goma'];
  static const _vibes = ['Casual', 'Competitivo', 'Entrenamiento', 'Callejero', 'Profesional'];
  static const _amenityOptions = ['Vestuarios', 'Estacionamiento', 'Bebedero', 'Techada', 'Reserva', 'Torneos'];

  @override
  void initState() {
    super.initState();
    _tryLoadCurrentLocation();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _priceCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _tryLoadCurrentLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _pinLocation = loc);
      _mapCtrl?.animateCamera(CameraUpdate.newLatLng(loc));
    } catch (_) {}
  }

  Future<void> _locateMe() async {
    setState(() => _locating = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _pinLocation = loc);
      await _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(loc, 16));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  List<String> _buildBadges() {
    return [
      if (_free) 'Gratis',
      if (_lit) 'Iluminada',
      ..._amenities.where(kAllowedBadges.contains),
    ];
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ponele un nombre a la cancha', style: AppText.grotesk(size: 13)),
          backgroundColor: AppColors.bgElev,
        ),
      );
      return;
    }
    setState(() => _submitted = true);

    final court = Court(
      id: '',
      name: _nameCtrl.text.trim(),
      area: '',
      dist: '',
      // TODO: subir _pickedImage a storage y guardar la URL acá. Por ahora la
      // imagen elegida solo se previsualiza en el front y no se persiste.
      img: '',
      rating: 0,
      reviews: 0,
      type: _type,
      free: _free,
      lit: _lit,
      hoops: _hoops,
      surface: _surface,
      status: CourtStatus.open,
      players: 0,
      vibe: _vibe,
      hours: _hoursCtrl.text.trim(),
      badges: _buildBadges(),
      desc: _descCtrl.text.trim(),
      lat: _pinLocation.latitude,
      lng: _pinLocation.longitude,
    );

    final courtsProvider = context.read<CourtsProvider>();
    // Guardamos el email (inmutable) para resolver en vivo el handle y clan
    // actuales del proponente, más un snapshot de ambos como fallback.
    final session = context.read<Session>();
    final profile = session.profile;
    final handle = profile?.handle ?? '';
    final clan = profile?.clan ?? '';
    final email = session.email ?? profile?.userEmail ?? '';

    try {
      await courtsProvider.addCourt(
        court,
        createdBy: handle,
        createdByClan: clan,
        createdByEmail: email,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Cancha enviada para revisión!',
              style: AppText.grotesk(size: 13)),
          backgroundColor: AppColors.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitted = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo publicar. Revisá la conexión con Notion.',
              style: AppText.grotesk(size: 13)),
          backgroundColor: AppColors.bgElev,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, 40 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Nombre'),
                    _glassField(
                      controller: _nameCtrl,
                      hint: 'Ej. Cancha de Palermo Chico',
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Foto'),
                    _imgField(),
                    const SizedBox(height: 24),
                    _sectionTitle('Ubicación'),
                    _mapPicker(),
                    const SizedBox(height: 24),
                    _sectionTitle('Tipo'),
                    _chipRow(['Exterior', 'Interior'], _type, (v) => setState(() => _type = v)),
                    const SizedBox(height: 24),
                    _sectionTitle('Superficie'),
                    _chipRow(_surfaces, _surface, (v) => setState(() => _surface = v)),
                    const SizedBox(height: 24),
                    _sectionTitle('Cantidad de aros'),
                    _hoopsStepper(),
                    const SizedBox(height: 24),
                    _sectionTitle('Vibe'),
                    _chipRow(_vibes, _vibe, (v) => setState(() => _vibe = v)),
                    const SizedBox(height: 24),
                    _sectionTitle('Características'),
                    _toggleRow(),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _hasCost ? _priceField() : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Comodidades'),
                    _amenitiesGrid(),
                    const SizedBox(height: 24),
                    _sectionTitle('Horarios'),
                    _glassField(
                      controller: _hoursCtrl,
                      hint: 'Ej. 06:00 — 23:00 o Abierto 24h',
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Descripción'),
                    _glassField(
                      controller: _descCtrl,
                      hint: 'Contá algo sobre esta cancha...',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 32),
                    _submitBtn(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            ),
            Text(
              'Agregar cancha',
              style: AppText.archivo(size: 22, weight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
  }

  Widget _glassField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xE011181F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white(0.1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: 1,
            style: AppText.grotesk(size: 14),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.grotesk(size: 14, color: AppColors.white(0.35)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapPicker() {
    return SizedBox(
      width: double.infinity,
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GoogleMap(
            style: _kMapStyle,
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            initialCameraPosition: CameraPosition(target: _pinLocation, zoom: 15),
            onCameraMove: (pos) => _pinLocation = pos.target,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            tiltGesturesEnabled: false,
            // Let the map claim pan/zoom gestures so the surrounding
            // SingleChildScrollView doesn't swallow them.
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
          // Centered crosshair pin
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_pin, color: AppColors.accent, size: 40),
                SizedBox(height: 20),
              ],
            ),
          ),
          // Locate me button
          Positioned(
            right: 10,
            bottom: 10,
            child: GestureDetector(
              onTap: _locateMe,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xE011181F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.white(0.1)),
                ),
                child: _locating
                    ? Padding(
                        padding: const EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      )
                    : Icon(Icons.my_location, color: AppColors.accent, size: 18),
              ),
            ),
          ),
          // Paints background color over corners to simulate border-radius
          // (ClipRRect breaks Android platform view rendering)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _MapCornerPainter(AppColors.bg)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _pickedImage = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo acceder a la imagen',
              style: AppText.grotesk(size: 13)),
          backgroundColor: AppColors.bgElev,
        ),
      );
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _imgSourceOption(Icons.photo_library_outlined, 'Elegir de la galería', () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.gallery);
              }),
              _imgSourceOption(Icons.camera_alt_outlined, 'Tomar una foto', () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.camera);
              }),
              if (_pickedImage != null)
                _imgSourceOption(Icons.delete_outline, 'Quitar imagen', () {
                  Navigator.pop(sheetCtx);
                  setState(() => _pickedImage = null);
                }, danger: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imgSourceOption(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? const Color(0xFFE05A5A) : Colors.white;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color, size: 22),
      title: Text(label, style: AppText.grotesk(size: 15, color: color)),
    );
  }

  Widget _imgField() {
    final hasImg = _pickedImage != null;
    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: double.infinity,
          height: 180,
          child: hasImg
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(_pickedImage!.path), fit: BoxFit.cover),
                    // Botón flotante para cambiar la imagen
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xCC11181F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.white(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, size: 14, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Text('Cambiar',
                                style: AppText.grotesk(size: 12, weight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : _imgUploadPlaceholder(),
        ),
      ),
    );
  }

  Widget _imgUploadPlaceholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x331A2430),
        border: Border.all(color: AppColors.white(0.12)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add_a_photo_outlined, size: 22, color: AppColors.accent),
          ),
          const SizedBox(height: 12),
          Text('Subir una imagen',
              style: AppText.grotesk(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Galería o cámara',
              style: AppText.grotesk(size: 12, color: AppColors.white(0.4))),
        ],
      ),
    );
  }

  Widget _chipRow(List<String> options, String selected, ValueChanged<String> onSelect) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final active = opt == selected;
        return GestureDetector(
          onTap: () => onSelect(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppColors.accent : const Color(0x331A2430),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: active ? AppColors.accent : AppColors.white(0.1),
              ),
            ),
            child: Text(
              opt,
              style: AppText.grotesk(
                size: 13,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : AppColors.white(0.7),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _hoopsStepper() {
    return Row(
      children: [
        _stepBtn(Icons.remove, () {
          if (_hoops > 1) setState(() => _hoops--);
        }),
        const SizedBox(width: 16),
        Text(
          '$_hoops',
          style: AppText.archivo(size: 24, weight: FontWeight.w900),
        ),
        const SizedBox(width: 16),
        _stepBtn(Icons.add, () {
          if (_hoops < 10) setState(() => _hoops++);
        }),
        const SizedBox(width: 12),
        Text(
          _hoops == 1 ? 'aro' : 'aros',
          style: AppText.grotesk(size: 14, color: AppColors.white(0.5)),
        ),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
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
  }

  Widget _toggleRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _toggle('Gratis', Icons.attach_money, _free, (v) => setState(() => _free = v))),
            const SizedBox(width: 10),
            Expanded(child: _toggle('Iluminada', Icons.lightbulb_outline, _lit, (v) => setState(() => _lit = v))),
            const SizedBox(width: 10),
            Expanded(child: _toggle('Precio', Icons.monetization_on_outlined, _hasCost, (v) => setState(() => _hasCost = v))),
          ],
        ),
      ],
    );
  }

  Widget _priceField() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unit selector
          Row(
            children: [
              _priceUnitChip('hora'),
              const SizedBox(width: 8),
              _priceUnitChip('partido'),
            ],
          ),
          const SizedBox(height: 10),
          // Price input
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xE011181F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accent.withAlpha(80)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('\$', style: AppText.archivo(size: 18, weight: FontWeight.w700, color: AppColors.accent)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: AppText.archivo(size: 18, weight: FontWeight.w700),
                        cursorColor: AppColors.accent,
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: AppText.archivo(size: 18, weight: FontWeight.w700, color: AppColors.white(0.25)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    Text(
                      'por $_priceUnit',
                      style: AppText.grotesk(size: 13, color: AppColors.white(0.45)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceUnitChip(String unit) {
    final active = _priceUnit == unit;
    return GestureDetector(
      onTap: () => setState(() => _priceUnit = unit),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withAlpha(40) : const Color(0x331A2430),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active ? AppColors.accent.withAlpha(120) : AppColors.white(0.1),
          ),
        ),
        child: Text(
          'Por $unit',
          style: AppText.grotesk(
            size: 12,
            weight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.accent : AppColors.white(0.6),
          ),
        ),
      ),
    );
  }

  Widget _toggle(String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? AppColors.accent.withAlpha(40) : const Color(0x331A2430),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? AppColors.accent.withAlpha(120) : AppColors.white(0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: value ? AppColors.accent : AppColors.white(0.5)),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppText.grotesk(
                size: 13,
                weight: FontWeight.w600,
                color: value ? AppColors.accent : AppColors.white(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amenitiesGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _amenityOptions.map((opt) {
        final active = _amenities.contains(opt);
        return GestureDetector(
          onTap: () => setState(() {
            if (active) {
              _amenities.remove(opt);
            } else {
              _amenities.add(opt);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppColors.accent.withAlpha(40) : const Color(0x331A2430),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: active ? AppColors.accent.withAlpha(120) : AppColors.white(0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active) ...[
                  Icon(Icons.check, size: 12, color: AppColors.accent),
                  const SizedBox(width: 4),
                ],
                Text(
                  opt,
                  style: AppText.grotesk(
                    size: 13,
                    weight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? AppColors.accent : AppColors.white(0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _submitBtn() {
    return GestureDetector(
      onTap: _submitted ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: _submitted
              ? null
              : const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: _submitted ? AppColors.white(0.1) : null,
          borderRadius: BorderRadius.circular(100),
          boxShadow: _submitted
              ? null
              : [
                  BoxShadow(
                    color: AppColors.accent.withAlpha(80),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: _submitted
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white(0.6)),
              )
            : Text(
                'PUBLICAR CANCHA',
                style: AppText.archivo(size: 14, weight: FontWeight.w900, letterSpacing: 0.04),
              ),
      ),
    );
  }
}

class _MapCornerPainter extends CustomPainter {
  final Color color;
  const _MapCornerPainter(this.color);

  static const _radius = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(_radius),
      ))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MapCornerPainter old) => old.color != color;
}
