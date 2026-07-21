import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/geocoding_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/beta_tag.dart';
import '../widgets/pop_background.dart';
import '../widgets/pressable_widget.dart';
import 'legal_screen.dart';

enum AuthMode { login, signup }

class AuthScreen extends StatefulWidget {
  final AuthMode initialMode;
  /// Mensaje a mostrar apenas se abre (ej. la verificación de arranque falló).
  final String? initialError;
  const AuthScreen(
      {super.key, this.initialMode = AuthMode.signup, this.initialError});

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
  bool _keepLoggedIn = true;
  // Age gate: fecha de nacimiento elegida en el registro.
  DateTime? _birthdate;
  // Aceptación de Términos + Política de Privacidad (obligatoria para registrar).
  bool _acceptedTerms = false;
  String? _error;

  /// Edad mínima para crear cuenta (COPPA en EE.UU.; menores requieren
  /// representación en AR). Bloqueamos por debajo de 13.
  static const int _minAge = 13;

  /// Último email con el que se inició sesión. Sobrevive al logout para
  /// prellenar el login (la contraseña NO se guarda acá: la maneja el gestor
  /// de contraseñas del sistema vía autofill, cifrada).
  static const _kLastEmail = 'last_login_email';

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
    // Consumir el error de arranque para que no reaparezca en cada rebuild.
    if (widget.initialError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<Session>().clearStartupError();
      });
    }
    _prefillLastEmail();
  }

  // Autocompletado de Ciudad: una sola vez por sesión de registro. Pide el
  // permiso de ubicación en contexto (el usuario tocó el campo) y, si hay fix,
  // resuelve la ciudad con reverse geocoding. Siempre editable; si algo falla
  // el campo queda manual como siempre.
  bool _cityAutofillTried = false;
  Future<void> _maybeAutofillCity() async {
    if (_cityAutofillTried || _cityCtrl.text.trim().isNotEmpty) return;
    _cityAutofillTried = true;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return; // denegado (o para siempre): no insistimos en pleno registro
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 10));
      final city =
          await GeocodingService.cityFromLatLng(pos.latitude, pos.longitude);
      if (!mounted || city == null || _cityCtrl.text.trim().isNotEmpty) return;
      setState(() => _cityCtrl.text = city);
    } catch (_) {/* sin fix o sin Geocoding API: queda manual */}
  }

  Future<void> _prefillLastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_kLastEmail) ?? '';
    if (last.isNotEmpty && mounted && _emailCtrl.text.isEmpty) {
      _emailCtrl.text = last;
    }
  }

  Future<void> _rememberEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastEmail, email.trim().toLowerCase());
  }

  int _ageFrom(DateTime dob, DateTime now) {
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  static final _google = GoogleSignIn(
    // Client OAuth de tipo Web: en Android `clientId` se ignora; hace falta
    // `serverClientId` para que Google devuelva el idToken.
    serverClientId:
        '823840378752-4rmlor8ivgmgkjsle7irmhu23cbtbabl.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

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

  // Dirección del deslizamiento al cambiar de modo (+1: el formulario nuevo
  // entra desde la derecha; -1: desde la izquierda), como las pestañas de la app.
  int _modeSlideDir = 1;

  /// Cambia de modo con la animación de entrada correspondiente. Limpia el
  /// error para no arrastrar mensajes del formulario anterior.
  void _setMode(AuthMode mode) {
    if (_loading || mode == _mode) return;
    setState(() {
      // Orden visual: [Ingresar | Registrarse] → ir a signup entra desde la
      // derecha; volver a login, desde la izquierda.
      _modeSlideDir = mode == AuthMode.signup ? 1 : -1;
      _mode = mode;
      _error = null;
    });
  }

  /// Swipe horizontal para alternar login/registro (mismo gesto que las
  /// pestañas dentro de la app): izquierda → Registrarse, derecha → Ingresar.
  void _handleModeSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v == 0) return;
    _setMode(v < 0 ? AuthMode.signup : AuthMode.login);
  }

  // Email bien formado: parte local + dominio con extensión válida (al menos
  // 2 letras). "user@gmail" o "user@gmail.c" no pasan; "user@gmail.com" sí.
  static final _emailRe = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-zA-Z]{2,}$');

  Future<void> _submit() async {
    // Validaciones locales antes de pegarle a la red.
    final email = _emailCtrl.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(
        () => _error = 'Ingresá un email válido (ej. nombre@gmail.com).',
      );
      return;
    }
    if (_isSignup && _passCtrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (_isSignup) {
      if (_birthdate == null) {
        setState(() => _error = 'Ingresá tu fecha de nacimiento.');
        return;
      }
      if (_ageFrom(_birthdate!, DateTime.now()) < _minAge) {
        setState(() => _error =
            'Necesitás tener al menos $_minAge años para crear una cuenta.');
        return;
      }
      if (!_acceptedTerms) {
        setState(() => _error =
            'Aceptá los Términos y la Política de Privacidad para continuar.');
        return;
      }
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
            birthdate:
                '${_birthdate!.year.toString().padLeft(4, '0')}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}',
          )
        : await session.login(
            _emailCtrl.text,
            _passCtrl.text,
            persist: _keepLoggedIn,
          );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
    if (err == null) {
      // Éxito: dispara el "¿Guardar contraseña?" del gestor del sistema
      // (Google/Samsung) y recuerda el email para prellenarlo la próxima.
      TextInput.finishAutofillContext();
      unawaited(_rememberEmail(email));
    }
    // En éxito, Session notifica y _Root cambia a MainShell. No hace falta navegar.
  }

  Future<void> _googleLogin() async {
    setState(() { _loading = true; _error = null; });
    try {
      final account = await _google.signIn();
      if (account == null) {
        if (mounted) setState(() { _loading = false; _error = 'Se canceló el login con Google.'; });
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        await _google.signOut();
        if (mounted) setState(() { _loading = false; _error = 'No se pudo autenticar con Google.'; });
        return;
      }

      if (!mounted) return;
      final session = context.read<Session>();
      // El backend verifica el idToken server-side y hace find-or-create.
      final err = await session.googleSignIn(idToken: idToken);
      if (err == null) unawaited(_rememberEmail(account.email));
      if (!mounted) return;
      setState(() { _loading = false; _error = err; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Error con Google: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: PopBackground(color: AppColors.bg)),
          // Marca de versión: chiquita y gris en una esquina.
          const SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 26, 24, 0),
                child: BetaTag(),
              ),
            ),
          ),
          SafeArea(
            // Swipe horizontal en toda la pantalla para alternar login/registro
            // (el scroll es vertical, así que no compite con este gesto).
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: _handleModeSwipe,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                // Entrada animada del formulario al cambiar de modo: se desliza
                // desde el lado del swipe (un solo hijo montado: los controllers
                // de los campos son compartidos y no admiten doble montaje).
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_mode),
                  tween: Tween(begin: 1, end: 0),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Transform.translate(
                    offset: Offset(_modeSlideDir * 56 * t, 0),
                    child: Opacity(opacity: (1 - t).clamp(0, 1), child: child),
                  ),
                  // AutofillGroup: agrupa email+contraseña para que el gestor
                  // de contraseñas del sistema los reconozca como un login.
                  child: AutofillGroup(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _brand(),
                      const SizedBox(height: 40),
                      Text(
                        _isSignup ? 'Creá tu cuenta' : 'Bienvenido de vuelta',
                        style: AppText.archivo(
                          size: 30,
                          weight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSignup
                            ? 'Unite a la comunidad de ballers.'
                            : 'Ingresá para encontrar tu próxima cancha.',
                        style: AppText.grotesk(
                          size: 14,
                          color: AppColors.white(0.6),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _tabs(),
                      const SizedBox(height: 20),
                      if (_isSignup) ...[
                        _label('Nombre'),
                        _field(_nameCtrl, 'Tu nombre y apellido',
                            autofillHints: const [AutofillHints.name]),
                        const SizedBox(height: 16),
                      ],
                      _label('Email'),
                      _field(
                        _emailCtrl,
                        'tu@email.com',
                        keyboard: TextInputType.emailAddress,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                      ),
                      const SizedBox(height: 16),
                      _label('Contraseña'),
                      _field(
                        _passCtrl,
                        'Mínimo 6 caracteres',
                        isPassword: true,
                        // En login es el último campo: "Listo" envía el form.
                        action: _isSignup
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: _isSignup ? null : _submit,
                        // newPassword en registro dispara el "¿guardar?" del
                        // gestor; password en login ofrece la guardada.
                        autofillHints: [
                          _isSignup
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                      ),
                      if (_isSignup) ...[
                        const SizedBox(height: 16),
                        _label('Confirmar contraseña'),
                        _field(
                          _pass2Ctrl,
                          'Repetí tu contraseña',
                          isPassword: true,
                          autofillHints: const [AutofillHints.newPassword],
                        ),
                        const SizedBox(height: 16),
                        _label('Fecha de nacimiento'),
                        _birthdateField(),
                        const SizedBox(height: 16),
                        _label('Ciudad (opcional)'),
                        // Al enfocar por primera vez pedimos ubicación EN
                        // CONTEXTO y autocompletamos la ciudad (editable).
                        Focus(
                          onFocusChange: (has) {
                            if (has) _maybeAutofillCity();
                          },
                          child: _field(_cityCtrl, 'Ej. Buenos Aires'),
                        ),
                        const SizedBox(height: 16),
                        _label('Teléfono (opcional)'),
                        _field(
                          _phoneCtrl,
                          '+54 11 ...',
                          keyboard: TextInputType.phone,
                          // Último campo de texto del registro.
                          action: TextInputAction.done,
                        ),
                        const SizedBox(height: 16),
                        _termsRow(),
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
                      const SizedBox(height: 20),
                      _orDivider(),
                      const SizedBox(height: 20),
                      _googleBtn(),
                      const SizedBox(height: 16),
                      Center(child: _switchModeLink()),
                    ],
                    ),
                  ),
                ),
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
    // Selector plano: fill sutil sin borde (mismo lenguaje editorial que el
    // resto de la app); el activo se marca solo con el acento.
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white(0.06),
        borderRadius: BorderRadius.circular(AppShape.rBtn),
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
      child: PressableWidget(
        onTap: () => _setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            // Acento plano (sin degradado ni glow); radio chip por estar
            // anidado dentro del selector rBtn.
            color: active ? AppColors.accent : null,
            borderRadius: BorderRadius.circular(AppShape.rChip),
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
    TextInputAction action = TextInputAction.next,
    VoidCallback? onSubmitted,
    List<String>? autofillHints,
  }) {
    return _GlowField(
      controller: controller,
      hint: hint,
      isPassword: isPassword,
      keyboard: keyboard,
      obscure: isPassword && _obscurePass,
      onToggleObscure: isPassword
          ? () => setState(() => _obscurePass = !_obscurePass)
          : null,
      action: action,
      onSubmitted: onSubmitted,
      autofillHints: autofillHints,
    );
  }

  Widget _keepLoggedInRow() {
    return PressableWidget(
      onTap: _loading
          ? null
          : () => setState(() => _keepLoggedIn = !_keepLoggedIn),
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

  Widget _birthdateField() {
    final has = _birthdate != null;
    final label = has
        ? '${_birthdate!.day.toString().padLeft(2, '0')}/${_birthdate!.month.toString().padLeft(2, '0')}/${_birthdate!.year}'
        : 'Tocá para elegir';
    return PressableWidget(
      onTap: _loading ? null : _pickBirthdate,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.cake_outlined, size: 18, color: AppColors.white(0.5)),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppText.grotesk(
                size: 14,
                color: has ? AppColors.ink : AppColors.white(0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    // Arrancamos el picker en una edad razonable (18) y permitimos desde hace
    // 100 años hasta hoy.
    final initial = _birthdate ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Tu fecha de nacimiento',
    );
    if (picked != null && mounted) setState(() => _birthdate = picked);
  }

  Widget _termsRow() {
    return PressableWidget(
      onTap: _loading
          ? null
          : () => setState(() => _acceptedTerms = !_acceptedTerms),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _acceptedTerms ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _acceptedTerms ? AppColors.accent : AppColors.white(0.3),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: _acceptedTerms
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.grotesk(size: 12.5, color: AppColors.white(0.7)),
                children: [
                  const TextSpan(text: 'Acepto los '),
                  _linkSpan('Términos',
                      () => LegalScreen.open(context, LegalScreen.terms())),
                  const TextSpan(text: ' y la '),
                  _linkSpan('Política de Privacidad',
                      () => LegalScreen.open(context, LegalScreen.privacy())),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _linkSpan(String text, VoidCallback onTap) => TextSpan(
        text: text,
        style: AppText.grotesk(
          size: 12.5,
          weight: FontWeight.w700,
          color: AppColors.accent,
        ),
        recognizer: (TapGestureRecognizer()..onTap = onTap),
      );

  Widget _errorBox(String msg) {
    // Error plano: tinte del color de error, sin borde; el color vive en el
    // ícono y el texto.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentDark.withAlpha(28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.accentDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: AppText.grotesk(
                size: 12.5,
                weight: FontWeight.w600,
                color: AppColors.accentDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitBtn() {
    return PressableWidget(
      onTap: _loading ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 54,
        width: double.infinity,
        alignment: Alignment.center,
        // CTA plano: acento pleno, sin borde ni sombra dura (mismo lenguaje
        // que "Crear pickup" y "Compartir resultado").
        decoration: BoxDecoration(
          color: _loading ? AppColors.white(0.1) : AppColors.accent,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: _loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.white(0.6)),
              )
            : Text(
                (_isSignup ? 'Crear cuenta' : 'Ingresar').toUpperCase(),
                style: AppText.display(
                  size: 14,
                  weight: FontWeight.w800,
                  letterSpacing: 0.04,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'O',
            style: AppText.grotesk(
              size: 12,
              color: AppColors.white(0.4),
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: AppColors.line)),
      ],
    );
  }

  Widget _googleBtn() {
    return PressableWidget(
      onTap: _loading ? null : _googleLogin,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        // Botón secundario plano: fill sutil sin borde.
        decoration: BoxDecoration(
          color: AppColors.white(0.06),
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo "G" oficial de Google (asset de branding, no dibujado).
            Image.asset(
              'assets/images/google_g.png',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 12),
            Text(
              'Continuar con Google',
              style: AppText.grotesk(
                size: 14,
                weight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchModeLink() {
    return PressableWidget(
      onTap: () => _setMode(_isSignup ? AuthMode.login : AuthMode.signup),
      child: RichText(
        text: TextSpan(
          style: AppText.grotesk(size: 12.5, color: AppColors.white(0.5)),
          children: [
            TextSpan(
              text: _isSignup ? '¿Ya tenés cuenta? ' : '¿No tenés cuenta? ',
            ),
            TextSpan(
              text: _isSignup ? 'Ingresar' : 'Registrate',
              style: AppText.grotesk(
                size: 12.5,
                weight: FontWeight.w700,
                color: AppColors.accent,
              ),
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

  /// Botón de acción del teclado: `next` salta al siguiente campo (default),
  /// `done` cierra el teclado (último campo del formulario).
  final TextInputAction action;

  /// Callback al confirmar desde el teclado (ej. enviar el login desde el
  /// campo de contraseña).
  final VoidCallback? onSubmitted;

  /// Hints de autofill (AutofillHints.email/password/...): permiten que el
  /// gestor de contraseñas del sistema sugiera y guarde las credenciales.
  final List<String>? autofillHints;

  const _GlowField({
    required this.controller,
    required this.hint,
    required this.isPassword,
    required this.keyboard,
    required this.obscure,
    required this.onToggleObscure,
    this.action = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
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
    // Input plano (lenguaje editorial): fill sutil sin borde; el foco se marca
    // con un borde de acento fino, único momento con borde.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AppColors.white(0.05),
        borderRadius: BorderRadius.circular(12),
        // Borde transparente cuando no hay foco para que el layout no salte.
        border: Border.all(
          color: focused ? AppColors.accent : Colors.transparent,
          width: 1.5,
        ),
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
              // "Siguiente" salta solo al próximo campo (comportamiento nativo
              // de TextInputAction.next); "Listo" cierra el teclado.
              textInputAction: widget.action,
              onSubmitted: widget.onSubmitted == null
                  ? null
                  : (_) => widget.onSubmitted!(),
              autofillHints: widget.autofillHints,
              style: AppText.grotesk(size: 14),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: AppText.grotesk(
                  size: 14,
                  color: AppColors.white(0.35),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (widget.isPassword)
            PressableWidget(
              onTap: widget.onToggleObscure,
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
    );
  }
}
