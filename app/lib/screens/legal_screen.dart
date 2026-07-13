import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/legal_content.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_widget.dart';

/// Documento legal (Política de Privacidad o Términos) mostrado in-app.
/// Fuente del texto: [legal_content.dart]. Si hay una URL pública configurada,
/// ofrece abrirla en el navegador; si no, muestra la versión embebida.
class LegalScreen extends StatelessWidget {
  final String title;
  final String body;
  final String url;
  const LegalScreen({
    super.key,
    required this.title,
    required this.body,
    this.url = '',
  });

  /// Atajos para las dos pantallas legales.
  static LegalScreen privacy() => const LegalScreen(
        title: 'Política de Privacidad',
        body: kPrivacyPolicy,
        url: kPrivacyPolicyUrl,
      );
  static LegalScreen terms() => const LegalScreen(
        title: 'Términos y Condiciones',
        body: kTermsAndConditions,
        url: kTermsUrl,
      );

  static void open(BuildContext context, LegalScreen screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  PressableWidget(
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.arrow_back_ios_new, size: 20),
                    ),
                  ),
                  Expanded(
                    child: Text(title,
                        style: AppText.archivo(
                            size: 16, weight: FontWeight.w800)),
                  ),
                  if (url.isNotEmpty)
                    PressableWidget(
                      onTap: () => launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.open_in_new, size: 18),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                child: Text(
                  body.trim(),
                  style: AppText.grotesk(
                      size: 13.5, height: 1.55, color: AppColors.white(0.8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
