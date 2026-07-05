import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/pop_background.dart';
import '../widgets/pop_button.dart';

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
          const Positioned.fill(child: PopBackground()),
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
    return const Align(
      alignment: Alignment.centerLeft,
      child: AppLogo(height: 44),
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
            gradient: active ? AppFx.accentGradient() : null,
            borderRadius: BorderRadius.circular(100),
            boxShadow: active
                ? AppFx.neonGlow(AppColors.accent, blur: 14, alpha: 80)
                : null,
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
    return _GlowField(
      controller: controller,
      hint: hint,
      isPassword: isPassword,
      keyboard: keyboard,
      obscure: isPassword && _obscurePass,
      onToggleObscure:
          isPassword ? () => setState(() => _obscurePass = !_obscurePass) : null,
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
    return PopButton(
      label: _isSignup ? 'Crear cuenta' : 'Ingresar',
      loading: _loading,
      onPressed: _loading ? null : _submit,
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

/// Campo de texto glass con glow neón al enfocar (pop-futurismo). Borde y glow
/// se intensifican en foco, dentro de la paleta actual.
class _GlowField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool isPassword;
  final TextInputType? keyboard;
  final bool obscure;
  final VoidCallback? onToggleObscure;

  const _GlowField({
    required this.controller,
    required this.hint,
    required this.isPassword,
    required this.keyboard,
    required this.obscure,
    required this.onToggleObscure,
  });

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField> {
  final FocusNode _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: const Color(0xE011181F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused
                  ? AppColors.accent.withAlpha(180)
                  : AppColors.white(0.1),
              width: focused ? 1.4 : 1,
            ),
            boxShadow: focused
                ? AppFx.neonGlow(AppColors.accent, blur: 16, alpha: 70)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _node,
                  obscureText: widget.obscure,
                  keyboardType: widget.keyboard,
                  style: AppText.grotesk(size: 14),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle:
                        AppText.grotesk(size: 14, color: AppColors.white(0.35)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (widget.isPassword)
                GestureDetector(
                  onTap: widget.onToggleObscure,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      widget.obscure ? Icons.visibility_off : Icons.visibility,
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
}
