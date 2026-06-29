import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/bball_glyph.dart';

class OnboardingScreen extends StatelessWidget {
  final VoidCallback? onStart;
  final VoidCallback? onLogin;
  const OnboardingScreen({super.key, this.onStart, this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.network(
            'https://images.unsplash.com/photo-1546519638-68e109498ffc?w=1000&q=80',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(color: AppColors.bg),
          ),
          // Gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x4D0A0F14),
                  Color(0xD90A0F14),
                  AppColors.bg,
                ],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          // Orange glow top-right
          Positioned(
            top: -120,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withAlpha(102),
                    Colors.transparent,
                  ],
                ),
              ),
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
        ],
      ),
    );
  }

  Widget _brand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Row(
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
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withAlpha(85),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(child: BBallGlyph(size: 22)),
          ),
          const SizedBox(width: 10),
          RichText(
            text: TextSpan(
              style: AppText.archivo(
                size: 20,
                weight: FontWeight.w900,
                letterSpacing: -0.03,
              ),
              children: [
                const TextSpan(text: '1'),
                TextSpan(
                  text: 'of',
                  style: AppText.archivo(
                    size: 20,
                    weight: FontWeight.w900,
                    color: AppColors.accent,
                  ),
                ),
                const TextSpan(text: '1'),
              ],
            ),
          ),
        ],
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
          RichText(
            text: TextSpan(
              style: AppText.archivo(
                size: 44,
                weight: FontWeight.w900,
                letterSpacing: -0.04,
                height: 0.95,
              ),
              children: [
                const TextSpan(text: 'Encontrá tu\npróxima\n'),
                TextSpan(
                  text: 'cancha.',
                  style: AppText.archivo(
                    size: 44,
                    weight: FontWeight.w900,
                    color: AppColors.accent,
                    letterSpacing: -0.04,
                    height: 0.95,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.white(0.08)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
                elevation: 12,
                shadowColor: AppColors.accent.withAlpha(85),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'EMPEZAR A JUGAR',
                    style: AppText.archivo(
                      size: 15,
                      weight: FontWeight.w800,
                      letterSpacing: 0.04,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
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
