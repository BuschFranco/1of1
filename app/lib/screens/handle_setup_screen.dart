import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';

/// Pantalla obligatoria que se muestra justo después del registro para que el
/// usuario elija su handle (no se autogenera). Valida formato y unicidad.
class HandleSetupScreen extends StatefulWidget {
  const HandleSetupScreen({super.key});

  @override
  State<HandleSetupScreen> createState() => _HandleSetupScreenState();
}

class _HandleSetupScreenState extends State<HandleSetupScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<Session>().setHandle(_ctrl.text);
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
          Positioned(
            top: -120,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accent.withAlpha(70), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? '¡Bienvenido! 🏀' : '¡Bienvenido, ${name.split(' ').first}! 🏀',
                    style: AppText.archivo(size: 28, weight: FontWeight.w900, height: 1.05),
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
                  _saveBtn(),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
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
        ),
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D).withAlpha(28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5484D).withAlpha(90)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFE5484D)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: AppText.grotesk(size: 12.5, color: const Color(0xFFFF8A8D))),
          ),
        ],
      ),
    );
  }

  Widget _saveBtn() {
    return GestureDetector(
      onTap: _loading ? null : _save,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: _loading
              ? null
              : const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: _loading ? AppColors.white(0.1) : null,
          borderRadius: BorderRadius.circular(100),
          boxShadow: _loading
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
