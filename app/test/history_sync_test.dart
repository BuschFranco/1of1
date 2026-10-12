import 'package:flutter_test/flutter_test.dart';
import 'package:triplesapp/services/play_session_service.dart';

/// Sesión con TODOS los campos de salud cargados, para comprobar que ninguno
/// llega al servidor. El resto del historial (marcador, formato, puntos) sí.
PlaySession _full(int endedAt, {String court = 'c1'}) => PlaySession(
      courtId: court,
      courtName: 'Chacarita',
      seconds: 3600,
      endedAtMillis: endedAt,
      result: PlayResult.win,
      points: 70,
      // ── salud: NO debe viajar ──
      calories: 480,
      avgHr: 138,
      maxHr: 181,
      steps: 5200,
      distance: 3100,
      hrZones: const [60, 300, 900, 1200, 300],
      spo2: 97,
      restingHr: 58,
      hrv: 44,
      respiratoryRate: 15,
      speed: 2.4,
      caloriesEstimated: true,
      distanceEstimated: true,
      fromWorkout: true,
      calorieRecord: true,
      // ── historial: SÍ viaja ──
      userPoints: 24,
      userPts3: 4,
      userPts2: 5,
      userPts1: 2,
      matchCount: 3,
      trainingCount: 1,
      winCount: 2,
      gamePoints: const [10, 8, 6],
      gameFormats: const [3, 3, 5],
      hiddenSections: {MatchSection.ubicacion},
    );

PlaySession _bare(int endedAt) => PlaySession(
      courtId: 'c1',
      courtName: 'Chacarita',
      seconds: 1800,
      endedAtMillis: endedAt,
    );

void main() {
  group('toSyncJson: la salud NUNCA viaja', () {
    const prohibidas = [
      'calories', 'avgHr', 'maxHr', 'steps', 'distance', 'hrZones', 'spo2',
      'restHr', 'hrv', 'resp', 'speed', 'calEst', 'distEst', 'fromWorkout',
      'calorieRecord',
    ];
    // Las mismas claves que la lista blanca del servidor (backend/src/sync).
    const permitidas = {
      'courtId', 'courtName', 'seconds', 'result', 'points', 'uPts', 'u3', 'u2',
      'uFT', 'nMatches', 'nTrainings', 'nWins', 'gamePts', 'gameFmt', 'hidden',
    };

    test('ninguna clave de salud aparece, aunque la sesión las tenga todas', () {
      final j = _full(1760000000000).toSyncJson();
      for (final k in prohibidas) {
        expect(j.containsKey(k), isFalse, reason: 'se coló "$k"');
      }
    });

    test('solo salen claves de la lista blanca del servidor', () {
      final j = _full(1760000000000).toSyncJson();
      expect(j.keys.toSet().difference(permitidas), isEmpty,
          reason: 'clave nueva que el servidor descartaría en silencio');
    });

    test('la identidad (endedAt) viaja aparte, no dentro de data', () {
      expect(_full(1760000000000).toSyncJson().containsKey('endedAt'), isFalse);
    });
  });

  group('ida y vuelta', () {
    test('marcador, formato y puntos sobreviven', () {
      final s = _full(1760000000000);
      final back =
          PlaySession.fromSyncJson(s.endedAtMillis, s.toSyncJson());
      expect(back.endedAtMillis, s.endedAtMillis);
      expect(back.result, PlayResult.win);
      expect(back.points, 70);
      expect(back.userPoints, 24);
      expect(back.userPts3, 4);
      expect(back.userPts2, 5);
      expect(back.userPts1, 2);
      expect(back.matchCount, 3);
      expect(back.trainingCount, 1);
      expect(back.winCount, 2);
      expect(back.gamePoints, [10, 8, 6]);
      expect(back.gameFormats, [3, 3, 5]);
      expect(back.hiddenSections, {MatchSection.ubicacion});
    });

    test('lo restaurado viene SIN salud (nunca se subió)', () {
      final s = _full(1760000000000);
      final back =
          PlaySession.fromSyncJson(s.endedAtMillis, s.toSyncJson());
      expect(back.calories, 0);
      expect(back.avgHr, isNull);
      expect(back.steps, 0);
      expect(back.hrZones, isNull);
      expect(back.spo2, isNull);
      expect(back.calorieRecord, isFalse);
    });

    test('una sesión sin desglose sigue sin desglose (null ≠ 0)', () {
      final back = PlaySession.fromSyncJson(5, _bare(5).toSyncJson());
      expect(back.matchCount, isNull);
      expect(back.userPoints, isNull);
      expect(back.hiddenSections, isNull); // sigue el default del usuario
      expect(back.isMultiGame, isFalse);
    });
  });

  group('mergeSessionHistory', () {
    test('en un choque GANA LO LOCAL: conserva la salud', () {
      final local = [_full(1000)];
      final remote = [PlaySession.fromSyncJson(1000, _full(1000).toSyncJson())];
      final out = mergeSessionHistory(local, remote);
      expect(out, hasLength(1));
      expect(out.first.calories, 480);
      expect(out.first.avgHr, 138);
    });

    test('entran las que solo están en el servidor (reinstalación)', () {
      final remote = [_bare(3000), _bare(2000), _bare(1000)];
      final out = mergeSessionHistory(const [], remote);
      expect(out.map((e) => e.endedAtMillis), [3000, 2000, 1000]);
    });

    test('unión de las dos partes, más nueva primero', () {
      final out = mergeSessionHistory([_bare(4000), _bare(2000)],
          [_bare(3000), _bare(1000)]);
      expect(out.map((e) => e.endedAtMillis), [4000, 3000, 2000, 1000]);
    });

    test('se recorta a las N más nuevas', () {
      final remote = [for (var i = 1; i <= 150; i++) _bare(i * 1000)];
      final out = mergeSessionHistory(const [], remote, cap: 100);
      expect(out, hasLength(100));
      expect(out.first.endedAtMillis, 150000);
      expect(out.last.endedAtMillis, 51000);
    });

    test('idempotente: fusionar dos veces da lo mismo que una', () {
      final local = [_full(2000)];
      final remote = [_bare(3000), _bare(1000)];
      final once = mergeSessionHistory(local, remote);
      final twice = mergeSessionHistory(once, remote);
      expect(twice.map((e) => e.endedAtMillis),
          once.map((e) => e.endedAtMillis));
    });

    test('ignora entradas sin identidad (endedAt <= 0)', () {
      final out = mergeSessionHistory([_bare(0)], [_bare(-5), _bare(1000)]);
      expect(out.map((e) => e.endedAtMillis), [1000]);
    });

    test('con todo vacío no revienta', () {
      expect(mergeSessionHistory(const [], const []), isEmpty);
    });
  });

  group('mergeStreakHistory', () {
    test('unión por fecha, más nueva primero, sin duplicar', () {
      final out = mergeStreakHistory(
        [const StreakEntry(2000, 3), const StreakEntry(1000, 1)],
        [const StreakEntry(3000, 7), const StreakEntry(1000, 1)],
      );
      expect(out.map((e) => e.endedAtMillis), [3000, 2000, 1000]);
      expect(out.map((e) => e.wins), [7, 3, 1]);
    });
  });
}
