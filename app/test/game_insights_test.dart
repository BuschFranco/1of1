import 'package:flutter_test/flutter_test.dart';
import 'package:triplesapp/data/game_insights.dart';
import 'package:triplesapp/services/play_session_service.dart';

PlaySession _s(
  DateTime ended, {
  int minutes = 90,
  PlayResult? result,
  int? games,
  int? wins,
  int? trainings,
  List<int>? formats,
  List<int>? gamePoints,
  int? userPoints,
}) =>
    PlaySession(
      courtId: 'c',
      courtName: 'Cancha',
      seconds: minutes * 60,
      endedAtMillis: ended.millisecondsSinceEpoch,
      result: result,
      matchCount: games,
      winCount: wins,
      trainingCount: trainings,
      gameFormats: formats,
      gamePoints: gamePoints,
      userPoints: userPoints,
    );

void main() {
  final now = DateTime(2026, 10, 19, 20);

  test('récord por partido, sin contar entrenamientos', () {
    final i = GameInsights.from([
      _s(DateTime(2026, 10, 18, 20),
          games: 5, wins: 4, trainings: 1, formats: [3]),
      _s(DateTime(2026, 10, 10, 20), result: PlayResult.loss),
      _s(DateTime(2026, 10, 9, 20), result: PlayResult.tie),
      _s(DateTime(2026, 10, 8, 20), result: PlayResult.training),
    ], now: now);
    expect(i.wins, 4);
    expect(i.losses, 2); // 1 de la sesión de 5 + la derrota suelta
    expect(i.ties, 1);
    expect(i.games, 7);
    expect(i.trainings, 2);
    expect(i.trainingShare, 22); // 2 de 9 actividades
  });

  test('por formato: partidos solo de sesiones de un formato; puntos por partido', () {
    final i = GameInsights.from([
      _s(DateTime(2026, 10, 18, 20), games: 3, wins: 2, formats: [3, 3, 3]),
      _s(DateTime(2026, 10, 17, 20),
          games: 2, wins: 1, formats: [1, 5], gamePoints: [4, 10]),
    ], now: now);
    expect(i.byFormat[3]!.games, 3);
    expect(i.byFormat[3]!.winRate, 67);
    expect(i.byFormat.containsKey(1), isTrue); // solo puntos
    expect(i.byFormat[1]!.games, 0);
    expect(i.byFormat[5]!.avgPoints, 10);
    expect(i.favoriteFormat, 3);
  });

  test('mes actual contra el anterior', () {
    final i = GameInsights.from([
      _s(DateTime(2026, 10, 18, 20), games: 4, wins: 3, userPoints: 20),
      _s(DateTime(2026, 9, 12, 20), games: 2, wins: 0, userPoints: 4),
      _s(DateTime(2026, 8, 1, 20), games: 9, wins: 9, userPoints: 90),
    ], now: now);
    expect(i.thisMonth.games, 4);
    expect(i.thisMonth.winRate, 75);
    expect(i.thisMonth.avgPoints, 5);
    expect(i.lastMonth.games, 2);
    expect(i.lastMonth.winRate, 0);
  });

  test('tiempo, constancia y cuándo jugás', () {
    final i = GameInsights.from([
      // Sábados a la tarde (la franja sale de la hora de INICIO).
      _s(DateTime(2026, 10, 17, 18), minutes: 120, games: 2, wins: 1),
      _s(DateTime(2026, 10, 10, 18), minutes: 60, games: 4, wins: 2),
      _s(DateTime(2026, 9, 1, 10), minutes: 60, games: 1, wins: 1),
    ], now: now);
    expect(i.totalSeconds, 240 * 60);
    expect(i.monthSeconds, 180 * 60);
    expect(i.avgSessionSeconds, 80 * 60);
    expect(i.sessionsPerWeek, 0.5); // 2 en las últimas 4 semanas
    expect(i.gamesPerSession, closeTo(7 / 3, 0.001));
    expect(i.favoriteWeekday, DateTime.saturday);
    expect(i.favoriteBand, 'tarde');
  });

  test('historial vacío', () {
    final i = GameInsights.from(const [], now: now);
    expect(i.hasData, isFalse);
    expect(i.favoriteFormat, isNull);
  });
}
