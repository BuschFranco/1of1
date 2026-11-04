import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_tour.dart';
import '../widgets/segmented_tabs.dart';
import 'games_screen.dart';
import 'news_screen.dart';

/// Pestaña "Social": Partidos (resultados y posiciones de NBA / WNBA) y
/// Noticias (NBA / WNBA / Liga Nacional / 3x3), en dos segmentos deslizables.
/// Crew (pickups + chats) se mudó al Perfil (Perfil/Amigos/Crew). El índice
/// del segmento vive en `main_shell.dart` (como `_profileTab`), para que el
/// swipe entre pestañas principales y entre segmentos comparta el mismo gesto.
class SocialScreen extends StatelessWidget {
  final int activeTab;
  final ValueChanged<int> onTabChange;

  const SocialScreen({
    super.key,
    required this.activeTab,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    // Mismo color que _bgForTab(AppTab.chat) en main_shell.dart — tiene que
    // coincidir, si no queda un parpadeo de color al entrar a la pestaña.
    return Container(
      color: AppColors.lilac,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedTabs(
                key: TourKeys.socialTabs,
                labels: const ['Partidos', 'Noticias'],
                activeIndex: activeTab,
                onChange: onTabChange,
              ),
            ),
            Expanded(
              // IndexedStack, no swap condicional: mantiene vivo el estado de
              // los dos segmentos (la liga y la vista elegidas no se pierden
              // al ir y volver de Noticias).
              child: IndexedStack(
                index: activeTab,
                children: const [
                  GamesScreen(topPadding: 8),
                  NewsScreen(topPadding: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
