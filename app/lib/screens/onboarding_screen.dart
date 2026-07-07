import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/pop_background.dart';
import '../widgets/pop_button.dart';

class OnboardingScreen extends StatelessWidget {
  final VoidCallback? onStart;
  final VoidCallback? onLogin;
  const OnboardingScreen({super.key, this.onStart, this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lilac,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo plano de sección (retro-pop): lila.
          const PopBackground(color: AppColors.lilac),
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
              color: AppColors.accent,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Encontrá tu\npróxima\ncancha.',
            style: AppText.archivo(
              size: 46,
              weight: FontWeight.w900,
              color: AppColors.sun,
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
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(AppShape.rCard),
                  border: Border.all(color: AppColors.white(0.25), width: 1.5),
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
