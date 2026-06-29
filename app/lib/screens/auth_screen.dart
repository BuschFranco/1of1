import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/bball_glyph.dart';

enum AuthMode { login, signup }

class AuthScreen extends StatefulWidget {
  final AuthMode initialMode;
  const AuthScreen({super.key, this.initialMode = AuthMode.signup});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _mode = widget.initialMode;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  bool _keepLoggedIn = true; // "Mantener sesión abierta": marcado por defecto.
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _cityCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool get _isSignup => _mode == AuthMode.signup;

  // Email bien formado: parte local + dominio con extensión válida (al menos
  // 2 letras). "user@gmail" o "user@gmail.c" no pasan; "user@gmail.com" sí.
  static final _emailRe =
      RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-zA-Z]{2,}$');

  Future<void> _submit() async {
    // Validaciones locales antes de pegarle a la red.
    final email = _emailCtrl.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Ingresá un email válido (ej. nombre@gmail.com).');
      return;
    }
    if (_isSignup && _passCtrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<Session>();
    final err = _isSignup
        ? await session.signup(
            emailRaw: _emailCtrl.text,
            password: _passCtrl.text,
            name: _nameCtrl.text,
            city: _cityCtrl.text,
            phone: _phoneCtrl.text,
          )
        : await session.login(_emailCtrl.text, _passCtrl.text,
            persist: _keepLoggedIn);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
    // En éxito, Session notifica y _Root cambia a MainShell. No hace falta navegar.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Orange glow top-right (consistente con onboarding)
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
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _brand(),
                  const SizedBox(height: 40),
                  Text(
                    _isSignup ? 'Creá tu cuenta' : 'Bienvenido de vuelta',
                    style: AppText.archivo(size: 30, weight: FontWeight.w900, height: 1.05),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignup
                        ? 'Unite a la comunidad de ballers.'
                        : 'Ingresá para encontrar tu próxima cancha.',
                    style: AppText.grotesk(size: 14, color: AppColors.white(0.6)),
                  ),
                  const SizedBox(height: 24),
                  _tabs(),
                  const SizedBox(height: 20),
                  if (_isSignup) ...[
                    _label('Nombre'),
                    _field(_nameCtrl, 'Tu nombre y apellido'),
                    const SizedBox(height: 16),
                  ],
                  _label('Email'),
                  _field(_emailCtrl, 'tu@email.com',
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  _label('Contraseña'),
                  _field(_passCtrl, 'Mínimo 6 caracteres', isPassword: true),
                  if (_isSignup) ...[
                    const SizedBox(height: 16),
                    _label('Confirmar contraseña'),
                    _field(_pass2Ctrl, 'Repetí tu contraseña', isPassword: true),
                    const SizedBox(height: 16),
                    _label('Ciudad (opcional)'),
                    _field(_cityCtrl, 'Ej. Buenos Aires'),
                    const SizedBox(height: 16),
                    _label('Teléfono (opcional)'),
                    _field(_phoneCtrl, '+54 11 ...',
                        keyboard: TextInputType.phone),
                  ],
                  if (!_isSignup) ...[
                    const SizedBox(height: 14),
                    _keepLoggedInRow(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _errorBox(_error!),
                  ],
                  const SizedBox(height: 28),
                  _submitBtn(),
                  const SizedBox(height: 16),
                  Center(child: _switchModeLink()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent, AppColors.accentDark],
            ),
          ),
          child: const Center(child: BBallGlyph(size: 22)),
        ),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            style: AppText.archivo(size: 20, weight: FontWeight.w900),
            children: [
              const TextSpan(text: '1'),
              TextSpan(text: 'of', style: AppText.archivo(size: 20, weight: FontWeight.w900, color: AppColors.accent)),
              const TextSpan(text: '1'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x331A2430),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.white(0.08)),
      ),
      child: Row(
        children: [
          _tabBtn('Ingresar', AuthMode.login),
          _tabBtn('Registrarse', AuthMode.signup),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, AuthMode mode) {
    final active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: _loading
            ? null
            : () => setState(() {
                  _mode = mode;
                  _error = null;
                }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.grotesk(
              size: 13,
              weight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : AppColors.white(0.6),
            ),
          ),
        ),
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

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool isPassword = false,
    TextInputType? keyboard,
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: isPassword && _obscurePass,
                  keyboardType: keyboard,
                  style: AppText.grotesk(size: 14),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: AppText.grotesk(size: 14, color: AppColors.white(0.35)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (isPassword)
                GestureDetector(
                  onTap: () => setState(() => _obscurePass = !_obscurePass),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                      color: AppColors.white(0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keepLoggedInRow() {
    return GestureDetector(
      onTap: _loading
          ? null
          : () => setState(() => _keepLoggedIn = !_keepLoggedIn),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _keepLoggedIn ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _keepLoggedIn ? AppColors.accent : AppColors.white(0.3),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: _keepLoggedIn
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            'Mantener sesión abierta',
            style: AppText.grotesk(size: 13, color: AppColors.white(0.7)),
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

  Widget _submitBtn() {
    return GestureDetector(
      onTap: _loading ? null : _submit,
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
                _isSignup ? 'CREAR CUENTA' : 'INGRESAR',
                style: AppText.archivo(size: 14, weight: FontWeight.w900, letterSpacing: 0.04),
              ),
      ),
    );
  }

  Widget _switchModeLink() {
    return GestureDetector(
      onTap: _loading
          ? null
          : () => setState(() {
                _mode = _isSignup ? AuthMode.login : AuthMode.signup;
                _error = null;
              }),
      child: RichText(
        text: TextSpan(
          style: AppText.grotesk(size: 12.5, color: AppColors.white(0.5)),
          children: [
            TextSpan(text: _isSignup ? '¿Ya tenés cuenta? ' : '¿No tenés cuenta? '),
            TextSpan(
              text: _isSignup ? 'Ingresar' : 'Registrate',
              style: AppText.grotesk(size: 12.5, weight: FontWeight.w700, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
