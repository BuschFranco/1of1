import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';

/// Primitivas visuales compartidas por los formularios y sheets de la app.
///
/// Existen para que el resultado del partido, el alta de pickup y el chat hablen
/// el MISMO idioma. Antes cada pantalla resolvía lo suyo con
/// `Container(color: AppColors.white(0.05))` + radio propio, y el resultado eran
/// cajas grises apiladas sin jerarquía: el perfil ya había resuelto esto (ver el
/// grid de stats en `profile_screen.dart`, "lo destacado es el VALOR, no el box")
/// pero esas tres pantallas se quedaron afuera de la pasada.

/// Etiqueta micro de sección: MAYÚSCULAS, chica y apagada.
///
/// Es el contrapunto del titular grande — el salto de escala entre 10 px y 30 px
/// es lo que crea la jerarquía. Con todo a 13-14 px no hay diseño posible.
Widget microLabel(String text, {Color? color}) => Text(
      text.toUpperCase(),
      style: AppText.grotesk(
        size: 10,
        weight: FontWeight.w700,
        color: color ?? AppColors.white(0.45),
        letterSpacing: 0.1,
      ),
    );

/// Titular en Anton con halo. Centraliza el trío tamaño/tracking/halo para que
/// todos los titulares queden iguales sin repetirlo en cada pantalla.
Widget displayTitle(
  String text, {
  double size = 30,
  Color? color,
  TextAlign? align,
}) {
  final c = color ?? AppColors.ink;
  return Text(
    text,
    textAlign: align,
    style: AppText.display(
      size: size,
      color: c,
      letterSpacing: -0.01,
      height: 1.0,
      // Halo naranja si el titular ya es de acento, blanco tenue si es tinta.
      shadows: c == AppColors.accent ? AppFx.accentGlow() : AppFx.inkGlow(),
    ),
  );
}

/// Campo de texto SIN caja: solo un hairline abajo que se enciende en acento al
/// enfocar. Reemplaza al `filled: true` + `fillColor: white(0.05)` + radio 12
/// que llenaba de rectángulos grises los tres formularios.
///
/// [focus] permite el borde del color del equipo, que es el único caso donde el
/// foco no es naranja.
InputDecoration hairlineField({
  String? hint,
  String? prefix,
  Color focus = AppColors.accent,
  double hintSize = 14,
  bool center = false,
}) =>
    InputDecoration(
      hintText: hint,
      prefixText: prefix,
      hintStyle: AppText.grotesk(size: hintSize, color: AppColors.white(0.28)),
      prefixStyle: AppText.grotesk(size: hintSize, color: AppColors.white(0.45)),
      filled: false,
      isDense: true,
      counterText: '',
      contentPadding: EdgeInsets.only(bottom: center ? 6 : 8, top: 4),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.white(0.12)),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: focus, width: 2),
      ),
    );

/// Separador fino. Reemplaza a los bordes de caja: una superficie por sección y
/// hairlines adentro, en vez de N cajas anidadas.
Widget hairline({double opacity = 0.08}) =>
    Container(height: 1, color: AppColors.white(opacity));

/// Botón principal: píldora de acento a ancho completo con la sombra dura que el
/// perfil ya usa como firma de la app.
Widget primaryButton(String label, {bool enabled = true, Widget? child}) =>
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? AppColors.accent : AppColors.white(0.10),
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        boxShadow: enabled ? AppFx.hardShadow(offset: const Offset(0, 3)) : null,
      ),
      child: child ??
          Text(
            label.toUpperCase(),
            style: AppText.archivo(
              size: 14,
              weight: FontWeight.w800,
              letterSpacing: 0.06,
              color: enabled ? Colors.white : AppColors.white(0.4),
            ),
          ),
    );
