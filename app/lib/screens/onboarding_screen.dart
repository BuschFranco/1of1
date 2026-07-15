import 'package:flutter/material.dart';
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
                _stats(),
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
          Text(
            'Encontrá tu\npróxima\ncancha.',
            style: AppText.archivo(
              size: 46,
              weight: FontWeight.w900,
              color: AppColors.accent,
              letterSpacing: -0.01,
              height: 0.98,
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

  Widget _stats() {
    final items = [
      ('340+', 'Canchas'),
      ('12k', 'Jugadores'),
      ('4.8★', 'Rating'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(
              // Cajita sólida con borde franco (sin blur "glass").
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppShape.rCard),
                  border: Border.all(color: AppColors.line, width: 1),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[i].$1,
                      style: AppText.archivo(
                        size: 20,
                        weight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      items[i].$2.toUpperCase(),
                      style: AppText.grotesk(
                        size: 10,
                        color: AppColors.white(0.5),
                        letterSpacing: 0.08,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1) const SizedBox(width: 8),
          ],
        ],
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
                  const TextSpan(text: '¿Ya tenés cuenta? '),
                  TextSpan(
                    text: 'Ingresar',
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
