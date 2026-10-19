import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/body_fields.dart';
import '../widgets/pressable_widget.dart';

/// Pantalla obligatoria que se muestra justo después del registro para que el
/// usuario elija su handle (no se autogenera). Valida formato y unicidad.
class HandleSetupScreen extends StatefulWidget {
  const HandleSetupScreen({super.key});

  @override
  State<HandleSetupScreen> createState() => _HandleSetupScreenState();
}

class _HandleSetupScreenState extends State<HandleSetupScreen> {
  final _ctrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String? _sex;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final double? weight;
    try {
      weight = BodyFields.parseWeight(_weightCtrl.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<Session>();
    // Opcionales y locales: se guardan ANTES del handle, porque un handle OK
    // hace que _Root pase solo a MainShell.
    if (weight != null || _sex != null) {
      await session.setBody(weightKg: weight, sex: _sex);
    }
    final err = await session.setHandle(_ctrl.text);
    if (!mounted) return;
    // Si OK, Session notifica y _Root pasa a MainShell solo. Si falla, mostramos.
    setState(() {
      _loading = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = context.read<Session>().profile?.name ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Con nombre, el nombre va en acento; sin nombre no hay nada
                  // que resaltar y el saludo queda entero en tinta.
                  Text.rich(
                    TextSpan(
                      text: name.isEmpty ? '¡Bienvenido! 🏀' : '¡Bienvenido, ',
                      style: AppText.display(
                        size: 28,
                        weight: FontWeight.w900,
                        height: 1.05,
                        shadows: AppFx.inkGlow(),
                      ),
                      children: [
                        if (name.isNotEmpty) ...[
                          TextSpan(
                            text: name.split(' ').first,
                            style: AppText.display(
                              size: 28,
                              weight: FontWeight.w900,
                              color: AppColors.accent,
                              height: 1.05,
                              shadows: AppFx.accentGlow(),
                            ),
                          ),
                          const TextSpan(text: '! 🏀'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Elegí tu handle: es tu nombre de usuario único, con el que tus amigos te van a encontrar.',
                    style: AppText.grotesk(size: 14, color: AppColors.white(0.6)),
                  ),
                  const SizedBox(height: 28),
                  _label('Tu handle'),
                  _handleField(),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _errorBox(_error!),
                  ],
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      '3–20 caracteres · letras, números, punto (.) o guion bajo (_)',
                      style: AppText.grotesk(size: 11.5, color: AppColors.white(0.4)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _label('Para medir mejor tus calorías (opcional)'),
                  Text(
                    'Con tu sexo y tu peso, las calorías que estimamos desde el '
                    'pulso de tu reloj salen más precisas. Se guardan solo en '
                    'tu celular y podés cambiarlos después desde tu perfil.',
                    style: AppText.grotesk(
                        size: 12.5, color: AppColors.white(0.5), height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  BodyFields(
                    sex: _sex,
                    onSex: (v) => setState(() => _sex = v),
                    weight: _weightCtrl,
                  ),
                  const SizedBox(height: 28),
                  _saveBtn(),
                  const SizedBox(height: 16),
                  Center(
                    child: PressableWidget(
                      onTap: _loading
                          ? null
                          : () => context.read<Session>().logout(),
                      child: Text(
                        'Cerrar sesión',
                        style: AppText.grotesk(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: AppColors.white(0.45),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
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

  Widget _handleField() {
    // Input protagonista: sólido con borde franco (sin blur "glass").
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
              Text('@',
                  style: AppText.archivo(
                      size: 18, weight: FontWeight.w800, color: AppColors.accent)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  style: AppText.grotesk(size: 15),
                  cursorColor: AppColors.accent,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: InputDecoration(
                    hintText: 'tu.handle',
                    hintStyle: AppText.grotesk(size: 15, color: AppColors.white(0.35)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentDark.withAlpha(28),
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        // Estado de error: borde rojo pleno, franco.
        border: Border.all(color: AppColors.accentDark, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.accentDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: AppText.grotesk(size: 12.5, color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _saveBtn() {
    return PressableWidget(
      onTap: _loading ? null : _save,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          // CTA: acento plano + borde negro + sombra dura (sin degradado ni
          // glow).
          color: _loading ? AppColors.white(0.1) : AppColors.accent,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: _loading
              ? null
              : Border.all(color: AppColors.line, width: 1),
          boxShadow: _loading ? null : AppFx.hardShadow(),
        ),
        alignment: Alignment.center,
        child: _loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white(0.6)),
              )
            : Text(
                'CONFIRMAR HANDLE',
                style: AppText.archivo(size: 14, weight: FontWeight.w900, letterSpacing: 0.04),
              ),
      ),
    );
  }
}
