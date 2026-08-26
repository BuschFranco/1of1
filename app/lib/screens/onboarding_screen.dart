import 'package:flutter/material.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/beta_tag.dart';
import '../widgets/pop_background.dart';
import '../widgets/pop_button.dart';

class OnboardingScreen extends StatelessWidget {
  final VoidCallback? onStart;
  final VoidCallback? onLogin;
  const OnboardingScreen({super.key, this.onStart, this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const PopBackground(color: AppColors.bg),
          // Imagen hero en el espacio superior (el contenido queda anclado
          // abajo por el Spacer): foto local + scrim de 2 stops que la funde
          // con el fondo para que no pelee con el headline (mismo patrón que
          // el hero del detalle de cancha).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.58,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/onboarding_hero.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.black(0.25),
                        Colors.transparent,
                        AppColors.bg,
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _brand(),
                const Spacer(),
                _headline(),
                const SizedBox(height: 20),
                _slogan(),
                const SizedBox(height: 24),
                _cta(onStart, onLogin),
                const SizedBox(height: 28),
              ],
            ),
          ),
          // Marca de versión: chiquita y gris en una esquina.
          const SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 22, 24, 0),
                child: BetaTag(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppLogo(height: 44),
      ),
    );
  }

  Widget _headline() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BASKETBALL · ARGENTINA',
            style: AppText.grotesk(
              size: 11,
              weight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 14),
          // Antes era todo naranja; partido gana fuerza porque el acento tiene
          // con qué contrastar (mismo criterio que el hero del sitio).
          Text.rich(
            TextSpan(
              text: 'Encontrá tu\npróxima\n',
              style: AppText.display(
                size: 46,
                weight: FontWeight.w900,
                letterSpacing: -0.01,
                height: 0.98,
                shadows: AppFx.inkGlow(),
              ),
              children: [
                TextSpan(
                  text: 'cancha.',
                  style: AppText.display(
                    size: 46,
                    weight: FontWeight.w900,
                    color: AppColors.accent,
                    letterSpacing: -0.01,
                    height: 0.98,
                    shadows: AppFx.accentGlow(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 280,
            child: Text(
              'Descubrí, reservá y jugá en las mejores canchas cerca tuyo. Conectá con ballers de tu zona.',
              style: AppText.grotesk(
                size: 15,
                color: AppColors.white(0.7),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Slogan de cierre del hero. Reemplaza a los tres contadores que había acá
  /// (canchas / jugadores / rating): eran valores inventados de maqueta y
  /// publicarlos sería mentirle al usuario en la primera pantalla que ve.
  ///
  /// A propósito NO se reemplazaron por los números reales: con un catálogo
  /// todavía chico, mostrarlos juega en contra. Cuando la comunidad crezca y
  /// los datos hablen a favor, este es el lugar donde van.
  Widget _slogan() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      // IntrinsicHeight para que la barra de acento tome la altura real del
      // texto: con `height` fijo quedaba corta al pasar a dos bloques, y a
      // distintos tamaños de fuente del sistema el desfasaje empeora.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de acento: el mismo recurso que marca las secciones fuertes
            // en el resto de la app (resultado del partido, aviso del reloj).
            Container(width: 3, color: AppColors.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vos jugá. Del resto nos encargamos.',
                    style: AppText.archivo(
                      size: 14.5,
                      weight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.01,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'La ventaja táctica definitiva para el jugador moderno.',
                    style: AppText.grotesk(
                      size: 12,
                      color: AppColors.white(0.5),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cta(VoidCallback? onStart, VoidCallback? onLogin) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          PopButton(
            label: 'Empezar a jugar',
            icon: Icons.arrow_forward,
            height: 56,
            onPressed: onStart,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onLogin,
            child: RichText(
              text: TextSpan(
                style: AppText.grotesk(
                  size: 12,
                  color: AppColors.white(0.5),
                ),
                children: [
                  const TextSpan(text: '¿No tenés cuenta? '),
                  TextSpan(
                    text: 'Registrate',
                    style: AppText.grotesk(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.accent,
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
}
