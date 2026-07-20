import 'package:flutter/material.dart';

/// Color dorado para logros/títulos desbloqueados. Oscurecido para leer bien
/// sobre las superficies claras del branding retro-pop.
const Color kGold = Color(0xFFB8860B);

/// Nivel de rareza de un título. Define su color al mostrarse.
enum TitleRarity { comun, raro, epico, legendario }

extension TitleRarityX on TitleRarity {
  /// Color asociado a la rareza (verde común, azul raro, violeta épico,
  /// dorado legendario). Tonos oscuros: legibles como texto sobre fondo claro.
  Color get color => switch (this) {
        TitleRarity.comun => const Color(0xFF2E9E5B), // verde
        TitleRarity.raro => const Color(0xFF2563EB), // azul
        TitleRarity.epico => const Color(0xFF7E22CE), // violeta
        TitleRarity.legendario => kGold, // dorado
      };

  String get label => switch (this) {
        TitleRarity.comun => 'Común',
        TitleRarity.raro => 'Raro',
        TitleRarity.epico => 'Épico',
        TitleRarity.legendario => 'Legendario',
      };
}

/// Niveles numéricos, infinitos. Curva creciente: cada nivel cuesta más que el
/// anterior, así subir se vuelve progresivamente más difícil.
///
/// Puntos acumulados necesarios para alcanzar [level] (nivel 1 = 0 puntos).
/// El factor (40) define el ritmo: subir del nivel L al L+1 cuesta 80·L puntos.
int pointsForLevel(int level) => level <= 1 ? 0 : 40 * level * (level - 1);

/// Nivel (1..∞) correspondiente a una cantidad de puntos.
int levelForPoints(int points) {
  var l = 1;
  while (pointsForLevel(l + 1) <= points) {
    l++;
  }
  return l;
}

/// Métricas locales sobre las que se evalúan los logros.
enum AchievementMetric {
  partidos,
  canchas,
  victorias,
  racha,
  horas,
  entrenamientos,
  victoriasAnio, // victorias en los últimos 365 días
  nivel, // nivel del jugador (según puntos)
}

/// Snapshot de las estadísticas del jugador para evaluar logros.
class PlayStats {
  final int partidos;
  final int canchas;
  final int victorias;
  final int maxRacha;
  final int segundos;
  final int entrenamientos;
  final int victoriasAnio;
  final int nivel;

  const PlayStats({
    required this.partidos,
    required this.canchas,
    required this.victorias,
    required this.maxRacha,
    required this.segundos,
    required this.entrenamientos,
    required this.victoriasAnio,
    this.nivel = 1,
  });

  int value(AchievementMetric m) => switch (m) {
        AchievementMetric.partidos => partidos,
        AchievementMetric.canchas => canchas,
        AchievementMetric.victorias => victorias,
        AchievementMetric.racha => maxRacha,
        AchievementMetric.horas => segundos ~/ 3600,
        AchievementMetric.entrenamientos => entrenamientos,
        AchievementMetric.victoriasAnio => victoriasAnio,
        AchievementMetric.nivel => nivel,
      };
}

/// Un logro: se desbloquea cuando la métrica alcanza [goal].
class Achievement {
  final String id;
  final String name;
  final String desc;
  final IconData icon;
  final AchievementMetric metric;
  final int goal;

  const Achievement({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    required this.metric,
    required this.goal,
  });

  bool unlocked(PlayStats s) => s.value(metric) >= goal;
  int progress(PlayStats s) => s.value(metric).clamp(0, goal);
}

/// Catálogo de logros. Basado en lo que la app ya mide: partidos jugados,
/// canchas únicas, victorias, racha de victorias y horas jugadas.
const List<Achievement> kAchievements = [
  // ── Partidos ──────────────────────────────────────────────────────────────
  Achievement(
    id: 'play_1',
    name: 'Primeros pasos',
    desc: 'Jugá tu primer partido',
    icon: Icons.sports_basketball,
    metric: AchievementMetric.partidos,
    goal: 1,
  ),
  Achievement(
    id: 'play_10',
    name: 'Habitué',
    desc: 'Jugá 10 partidos',
    icon: Icons.repeat,
    metric: AchievementMetric.partidos,
    goal: 10,
  ),
  Achievement(
    id: 'play_25',
    name: 'Frecuente',
    desc: 'Jugá 25 partidos',
    icon: Icons.event_repeat,
    metric: AchievementMetric.partidos,
    goal: 25,
  ),
  Achievement(
    id: 'play_50',
    name: 'Veterano',
    desc: 'Jugá 50 partidos',
    icon: Icons.military_tech,
    metric: AchievementMetric.partidos,
    goal: 50,
  ),
  Achievement(
    id: 'play_100',
    name: 'Leyenda',
    desc: 'Jugá 100 partidos',
    icon: Icons.auto_awesome,
    metric: AchievementMetric.partidos,
    goal: 100,
  ),
  Achievement(
    id: 'play_200',
    name: 'Inoxidable',
    desc: 'Jugá 200 partidos',
    icon: Icons.fitness_center,
    metric: AchievementMetric.partidos,
    goal: 200,
  ),
  Achievement(
    id: 'play_500',
    name: 'Eterno',
    desc: 'Jugá 500 partidos',
    icon: Icons.all_inclusive,
    metric: AchievementMetric.partidos,
    goal: 500,
  ),
  // ── Canchas ───────────────────────────────────────────────────────────────
  Achievement(
    id: 'courts_5',
    name: 'Explorador',
    desc: 'Jugá en 5 canchas diferentes',
    icon: Icons.explore,
    metric: AchievementMetric.canchas,
    goal: 5,
  ),
  Achievement(
    id: 'courts_10',
    name: 'Andariego',
    desc: 'Jugá en 10 canchas diferentes',
    icon: Icons.travel_explore,
    metric: AchievementMetric.canchas,
    goal: 10,
  ),
  Achievement(
    id: 'courts_20',
    name: 'Trotamundos',
    desc: 'Jugá en 20 canchas diferentes',
    icon: Icons.map,
    metric: AchievementMetric.canchas,
    goal: 20,
  ),
  Achievement(
    id: 'courts_30',
    name: 'Nómada',
    desc: 'Jugá en 30 canchas diferentes',
    icon: Icons.route,
    metric: AchievementMetric.canchas,
    goal: 30,
  ),
  Achievement(
    id: 'courts_50',
    name: 'Coleccionista',
    desc: 'Jugá en 50 canchas diferentes',
    icon: Icons.collections_bookmark,
    metric: AchievementMetric.canchas,
    goal: 50,
  ),
  Achievement(
    id: 'courts_100',
    name: 'Conquistador',
    desc: 'Jugá en 100 canchas diferentes',
    icon: Icons.public,
    metric: AchievementMetric.canchas,
    goal: 100,
  ),
  // ── Victorias ─────────────────────────────────────────────────────────────
  Achievement(
    id: 'wins_10',
    name: 'Ganador',
    desc: 'Ganá 10 partidos',
    icon: Icons.thumb_up,
    metric: AchievementMetric.victorias,
    goal: 10,
  ),
  Achievement(
    id: 'wins_25',
    name: 'Competitivo',
    desc: 'Ganá 25 partidos',
    icon: Icons.emoji_events,
    metric: AchievementMetric.victorias,
    goal: 25,
  ),
  Achievement(
    id: 'wins_50',
    name: 'Campeón',
    icon: Icons.emoji_events,
    desc: 'Ganá 50 partidos',
    metric: AchievementMetric.victorias,
    goal: 50,
  ),
  Achievement(
    id: 'wins_100',
    name: 'Estrella',
    desc: 'Ganá 100 partidos',
    icon: Icons.star,
    metric: AchievementMetric.victorias,
    goal: 100,
  ),
  Achievement(
    id: 'wins_200',
    name: 'Dominante',
    desc: 'Ganá 200 partidos',
    icon: Icons.stars,
    metric: AchievementMetric.victorias,
    goal: 200,
  ),
  // ── Rachas ────────────────────────────────────────────────────────────────
  Achievement(
    id: 'streak_3',
    name: 'En llamas',
    desc: 'Conseguí una racha de 3 victorias',
    icon: Icons.local_fire_department,
    metric: AchievementMetric.racha,
    goal: 3,
  ),
  Achievement(
    id: 'streak_5',
    name: 'Imparable',
    desc: 'Conseguí una racha de 5 victorias',
    icon: Icons.bolt,
    metric: AchievementMetric.racha,
    goal: 5,
  ),
  Achievement(
    id: 'streak_7',
    name: 'Caliente',
    desc: 'Conseguí una racha de 7 victorias',
    icon: Icons.whatshot,
    metric: AchievementMetric.racha,
    goal: 7,
  ),
  Achievement(
    id: 'streak_10',
    name: 'Invencible',
    desc: 'Conseguí una racha de 10 victorias',
    icon: Icons.shield_moon,
    metric: AchievementMetric.racha,
    goal: 10,
  ),
  Achievement(
    id: 'streak_15',
    name: 'Racha histórica',
    desc: 'Conseguí una racha de 15 victorias',
    icon: Icons.local_fire_department,
    metric: AchievementMetric.racha,
    goal: 15,
  ),
  Achievement(
    id: 'streak_20',
    name: 'Tsunami',
    desc: 'Conseguí una racha de 20 victorias',
    icon: Icons.tsunami,
    metric: AchievementMetric.racha,
    goal: 20,
  ),
  // ── Horas ─────────────────────────────────────────────────────────────────
  Achievement(
    id: 'hours_10',
    name: 'Maratonista',
    desc: 'Acumulá 10 horas jugadas',
    icon: Icons.timer,
    metric: AchievementMetric.horas,
    goal: 10,
  ),
  Achievement(
    id: 'hours_25',
    name: 'Persistente',
    desc: 'Acumulá 25 horas jugadas',
    icon: Icons.hourglass_bottom,
    metric: AchievementMetric.horas,
    goal: 25,
  ),
  Achievement(
    id: 'hours_50',
    name: 'Incansable',
    desc: 'Acumulá 50 horas jugadas',
    icon: Icons.bedtime_off,
    metric: AchievementMetric.horas,
    goal: 50,
  ),
  Achievement(
    id: 'hours_100',
    name: 'Sin cansancio',
    desc: 'Acumulá 100 horas jugadas',
    icon: Icons.schedule,
    metric: AchievementMetric.horas,
    goal: 100,
  ),
  Achievement(
    id: 'hours_200',
    name: 'Adicto',
    desc: 'Acumulá 200 horas jugadas',
    icon: Icons.access_time,
    metric: AchievementMetric.horas,
    goal: 200,
  ),
  // ── Entrenamientos ────────────────────────────────────────────────────────
  Achievement(
    id: 'train_10',
    name: 'Constante',
    desc: 'Completá 10 entrenamientos',
    icon: Icons.directions_run,
    metric: AchievementMetric.entrenamientos,
    goal: 10,
  ),
  Achievement(
    id: 'train_30',
    name: 'Disciplinado',
    desc: 'Completá 30 entrenamientos',
    icon: Icons.self_improvement,
    metric: AchievementMetric.entrenamientos,
    goal: 30,
  ),
  Achievement(
    id: 'train_50',
    name: 'Metódico',
    desc: 'Completá 50 entrenamientos',
    icon: Icons.fitness_center,
    metric: AchievementMetric.entrenamientos,
    goal: 50,
  ),
  Achievement(
    id: 'train_100',
    name: 'Máquina de entrenar',
    desc: 'Completá 100 entrenamientos',
    icon: Icons.sports_martial_arts,
    metric: AchievementMetric.entrenamientos,
    goal: 100,
  ),
  // ── Victorias por año ─────────────────────────────────────────────────────
  Achievement(
    id: 'wins_year_10',
    name: 'Sensación novata',
    desc: 'Ganá 10 partidos en un año',
    icon: Icons.trending_up,
    metric: AchievementMetric.victoriasAnio,
    goal: 10,
  ),
  Achievement(
    id: 'wins_year_25',
    name: 'Año soñado',
    desc: 'Ganá 25 partidos en un año',
    icon: Icons.calendar_month,
    metric: AchievementMetric.victoriasAnio,
    goal: 25,
  ),
  Achievement(
    id: 'wins_year_50',
    name: 'Golpe de efecto',
    desc: 'Ganá 50 partidos en un año',
    icon: Icons.bolt,
    metric: AchievementMetric.victoriasAnio,
    goal: 50,
  ),
  // ── Nivel ─────────────────────────────────────────────────────────────────
  Achievement(
    id: 'level_5',
    name: 'En ascenso',
    desc: 'Alcanzá el nivel 5',
    icon: Icons.trending_up,
    metric: AchievementMetric.nivel,
    goal: 5,
  ),
  Achievement(
    id: 'level_10',
    name: 'Subiendo fuerte',
    desc: 'Alcanzá el nivel 10',
    icon: Icons.stairs,
    metric: AchievementMetric.nivel,
    goal: 10,
  ),
  Achievement(
    id: 'level_15',
    name: 'Consolidado',
    desc: 'Alcanzá el nivel 15',
    icon: Icons.leaderboard,
    metric: AchievementMetric.nivel,
    goal: 15,
  ),
  Achievement(
    id: 'level_20',
    name: 'Elite',
    desc: 'Alcanzá el nivel 20',
    icon: Icons.workspace_premium,
    metric: AchievementMetric.nivel,
    goal: 20,
  ),
  Achievement(
    id: 'level_25',
    name: 'Prestigio',
    desc: 'Alcanzá el nivel 25',
    icon: Icons.emoji_events,
    metric: AchievementMetric.nivel,
    goal: 25,
  ),
  Achievement(
    id: 'level_30',
    name: 'Cúspide',
    desc: 'Alcanzá el nivel 30',
    icon: Icons.diamond,
    metric: AchievementMetric.nivel,
    goal: 30,
  ),
  Achievement(
    id: 'level_40',
    name: 'Trascendente',
    desc: 'Alcanzá el nivel 40',
    icon: Icons.military_tech,
    metric: AchievementMetric.nivel,
    goal: 40,
  ),
  Achievement(
    id: 'level_50',
    name: 'Inalcanzable',
    desc: 'Alcanzá el nivel 50',
    icon: Icons.local_fire_department,
    metric: AchievementMetric.nivel,
    goal: 50,
  ),
];

Achievement? achievementById(String id) {
  for (final a in kAchievements) {
    if (a.id == id) return a;
  }
  return null;
}

/// Un título coleccionable: se desbloquea al conseguir TODOS los logros de
/// [requires] (uno o más).
class GameTitle {
  final String name;
  final List<String> requires; // ids de logros requeridos
  final TitleRarity rarity;

  const GameTitle(this.name, this.requires,
      {this.rarity = TitleRarity.comun});

  bool unlocked(PlayStats s) =>
      requires.every((id) => achievementById(id)?.unlocked(s) ?? false);

  /// True si el título no requiere ningún logro: viene desbloqueado de base.
  bool get isBase => requires.isEmpty;

  /// Color del título según su rareza.
  Color get color => rarity.color;

  /// Texto "Se desbloquea al conseguir el logro X" / "los logros X, Y y Z".
  String get unlockDesc {
    if (requires.isEmpty) return 'Disponible desde el inicio.';
    final names = requires
        .map((id) => achievementById(id)?.name ?? id)
        .map((n) => '"$n"')
        .toList();
    if (names.length == 1) {
      return 'Se desbloquea al conseguir el logro ${names.first}.';
    }
    final last = names.removeLast();
    return 'Se desbloquea al conseguir los logros ${names.join(', ')} y $last.';
  }
}

/// Catálogo de títulos. Los primeros vienen desbloqueados de base (sin logros
/// requeridos); el resto requiere uno o varios logros.
const List<GameTitle> kTitles = [
  // ── Comunes (verde): desbloqueados de base, sin requisitos. ──────────────
  GameTitle('Baller', [], rarity: TitleRarity.comun),
  GameTitle('Pibe de barrio', [], rarity: TitleRarity.comun),
  GameTitle('Promesa', [], rarity: TitleRarity.comun),
  GameTitle('Fierita', [], rarity: TitleRarity.comun),
  GameTitle('Novato', [], rarity: TitleRarity.comun),
  GameTitle('Jugador recreativo', [], rarity: TitleRarity.comun),
  GameTitle('Aspirante', [], rarity: TitleRarity.comun),
  // ── Raros (azul): un logro de dificultad media. ──────────────────────────
  GameTitle('Veterano de la cancha', ['play_50'], rarity: TitleRarity.raro),
  GameTitle('Trotamundos', ['courts_20'], rarity: TitleRarity.raro),
  GameTitle('Imparable', ['streak_5'], rarity: TitleRarity.raro),
  GameTitle('Maratonista', ['hours_10'], rarity: TitleRarity.raro),
  GameTitle('Rookie del año', ['wins_year_10'], rarity: TitleRarity.raro),
  GameTitle('El Profe', ['train_10'], rarity: TitleRarity.raro),
  GameTitle('Caminante', ['courts_10'], rarity: TitleRarity.raro),
  GameTitle('Frecuente', ['play_25'], rarity: TitleRarity.raro),
  GameTitle('Competitivo', ['wins_25'], rarity: TitleRarity.raro),
  GameTitle('Persistente', ['hours_25'], rarity: TitleRarity.raro),
  GameTitle('Constante', ['train_30'], rarity: TitleRarity.raro),
  // ── Épicos (violeta): un logro exigente. ─────────────────────────────────
  GameTitle('Leyenda viviente', ['play_100'], rarity: TitleRarity.epico),
  GameTitle('Coleccionista de canchas', ['courts_50'],
      rarity: TitleRarity.epico),
  GameTitle('Campeón', ['wins_50'], rarity: TitleRarity.epico),
  GameTitle('Invencible', ['streak_10'], rarity: TitleRarity.epico),
  GameTitle('Rata de gimnasio', ['train_30'], rarity: TitleRarity.epico),
  GameTitle('Nómada', ['courts_30'], rarity: TitleRarity.epico),
  GameTitle('Caliente', ['streak_7'], rarity: TitleRarity.epico),
  GameTitle('Metódico', ['train_50'], rarity: TitleRarity.epico),
  GameTitle('Goleador del año', ['wins_year_25'], rarity: TitleRarity.epico),
  GameTitle('Consolidado', ['level_15'], rarity: TitleRarity.epico),
  GameTitle('Figura', ['level_10'], rarity: TitleRarity.epico),
  GameTitle('Crack del barrio', ['level_20'], rarity: TitleRarity.epico),
  // ── Legendarios (dorado): varios logros o las metas más altas. ────────────
  GameTitle('Maestro del juego', ['play_100', 'wins_50'],
      rarity: TitleRarity.legendario),
  GameTitle('Crack total', ['courts_50', 'hours_50', 'streak_10'],
      rarity: TitleRarity.legendario),
  GameTitle('MVP', ['wins_100'], rarity: TitleRarity.legendario),
  GameTitle('Iron Man', ['play_200'], rarity: TitleRarity.legendario),
  GameTitle('La Mamba Negra', ['streak_10', 'wins_50'],
      rarity: TitleRarity.legendario),
  GameTitle('El Elegido', ['play_100', 'wins_100'],
      rarity: TitleRarity.legendario),
  GameTitle('Fuego eterno', ['streak_15'], rarity: TitleRarity.legendario),
  GameTitle('Inmortal', ['hours_100'], rarity: TitleRarity.legendario),
  GameTitle('Hall of Fame', ['level_30'], rarity: TitleRarity.legendario),
  GameTitle('Conquistador', ['courts_100'], rarity: TitleRarity.legendario),
  GameTitle('Dominante', ['wins_200'], rarity: TitleRarity.legendario),
  GameTitle('Tsunami', ['streak_20'], rarity: TitleRarity.legendario),
  GameTitle('Adicto', ['hours_200'], rarity: TitleRarity.legendario),
  GameTitle('Máquina', ['train_100'], rarity: TitleRarity.legendario),
  GameTitle('Golpe de efecto', ['wins_year_50'], rarity: TitleRarity.legendario),
  GameTitle('Eterno', ['play_500'], rarity: TitleRarity.legendario),
  // ── Legendarios multi-logro: requieren varios logros épicos. ──────────────
  GameTitle('La leyenda absoluta',
      ['play_200', 'wins_100', 'courts_50'], rarity: TitleRarity.legendario),
  GameTitle('Rey de la cancha',
      ['streak_15', 'wins_50', 'level_25'], rarity: TitleRarity.legendario),
  GameTitle('Trascendente',
      ['level_40', 'play_200'], rarity: TitleRarity.legendario),
  GameTitle('Inalcanzable',
      ['level_50', 'wins_200', 'hours_100'], rarity: TitleRarity.legendario),
];

/// Busca un título por su nombre (para resolver su rareza/color al mostrarlo).
GameTitle? titleByName(String name) {
  for (final t in kTitles) {
    if (t.name == name) return t;
  }
  return null;
}
