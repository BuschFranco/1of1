import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:triplesapp/data/scores.dart';

/// Partido real (PHX 113 - GS 116, 2/11/2026) tal como lo devuelve el backend.
/// Al final del partido, el box reconstruido jugada a jugada tiene que dar lo
/// mismo que el box oficial de ESPN.
void main() {
  final box = BoxScore.fromApi((jsonDecode(
          File('test/fixtures/box_nba_401909919.json').readAsStringSync())
      as Map)
      .cast<String, dynamic>());
  final tl = box.timeline!;

  test('al final coincide con el box oficial (todas las columnas)', () {
    final live = boxAt(box, tl.plays.length - 1);
    var checked = 0;
    for (final t in box.teams) {
      for (final p in t.players) {
        if (p.dnp) continue;
        final cells = live[p.id]!.cells();
        for (var c = 0; c < box.columns.length; c++) {
          var official = p.stats[c];
          // ESPN escribe +/- "0" sin signo y los positivos con '+'.
          if (c == box.columns.length - 1 && !official.startsWith('-') &&
              official != '0' && !official.startsWith('+')) {
            official = '+$official';
          }
          if (c == 0) {
            // Minutos: redondeo de ESPN vs el nuestro, ±1.
            expect((int.parse(cells[c]) - int.parse(official)).abs(),
                lessThanOrEqualTo(1),
                reason: '${p.name} MIN');
          } else {
            expect(cells[c], official, reason: '${p.name} ${box.columns[c]}');
          }
          checked++;
        }
      }
    }
    expect(checked, greaterThan(200));
  });

  test('en el entretiempo, los puntos suman el marcador', () {
    final half = tl.plays.lastIndexWhere((p) => p.period == 2);
    final live = boxAt(box, half);
    final play = tl.plays[half];
    int sum(bool home) => box.teams
        .where((t) => t.isHome == home)
        .expand((t) => t.players)
        .fold(0, (a, p) => a + (live[p.id]?.pts ?? 0));
    expect(sum(true), play.home);
    expect(sum(false), play.away);
    // Nadie jugó más que el tiempo transcurrido.
    for (final l in live.values) {
      expect(l.seconds, lessThanOrEqualTo(play.t));
    }
  });

  test('al arrancar todo está en cero', () {
    final live = boxAt(box, 0);
    expect(live.values.every((l) => l.pts == 0 && l.reb == 0), isTrue);
  });

  test('porcentajes y totales del equipo', () {
    expect(pctOf('8-18'), '44');
    expect(pctOf('0-0'), '—');
    expect(columnsWithPct(box.columns),
        containsAllInOrder(['TC', 'TC%', '3P', '3P%', 'TL', 'TL%']));
    for (final t in box.teams) {
      final rows = [for (final p in t.players) if (!p.dnp) p.stats];
      final total = teamTotals(box.columns, rows);
      // Los puntos sumados dan el marcador final del equipo.
      expect(total[box.columns.indexOf('PTS')], t.score, reason: t.abbr);
      // TC sumado: convertidos ≤ intentados.
      final tc = total[box.columns.indexOf('TC')].split('-').map(int.parse).toList();
      expect(tc[0], lessThanOrEqualTo(tc[1]));
      final withPct = cellsWithPct(box.columns, total);
      expect(withPct.length, columnsWithPct(box.columns).length);
    }
  });
}
