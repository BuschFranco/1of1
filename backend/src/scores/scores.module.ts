import {
  Controller,
  Get,
  Injectable,
  Logger,
  Module,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import axios from 'axios';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Partidos de NBA / WNBA (resultados, box score y posiciones) por cuenta del
// backend, misma fuente y mismo criterio que NewsModule: la API no oficial de
// ESPN (site.api.espn.com), sin key. La app nunca le pega directo: acá se
// cachea (todos los usuarios comparten la respuesta) y se mapea a una forma
// chica y estable, así si ESPN cambia algo se arregla en un solo lugar.
//
// Nunca lanza hacia la app: ante cualquier falla degrada a vacío / null.
//
// Liga Nacional NO está: no hay fuente libre (FeedConstruct tiene los derechos
// exclusivos de datos); la app muestra un link al fixture oficial.

type League = 'nba' | 'wnba';

const ESPN = 'https://site.api.espn.com/apis';
// Días hacia atrás que se muestran como "recientes" (más el de hoy).
const RECENT_DAYS = 3;
// Con algún partido en vivo la info vence rápido; si no, puede esperar.
const TTL_LIVE_MS = 60 * 1000;
const TTL_IDLE_MS = 10 * 60 * 1000;
const TTL_FINAL_GAME_MS = 6 * 60 * 60 * 1000;
const TTL_STANDINGS_MS = 30 * 60 * 1000;

type TeamLine = {
  name: string;
  abbr: string;
  logo: string;
  score: string;
  winner: boolean;
  record: string;
};

type Game = {
  id: string;
  date: string; // ISO
  state: 'pre' | 'in' | 'post';
  status: string; // "Final", "Q3 5:12", "7:30 PM ET"…
  home: TeamLine;
  away: TeamLine;
};

type PlayerLine = {
  name: string;
  position: string;
  starter: boolean;
  dnp: boolean;
  stats: string[]; // alineado con `columns`
};

type BoxTeam = {
  name: string;
  abbr: string;
  logo: string;
  score: string;
  players: PlayerLine[];
};

type BoxScore = {
  game: Game | null;
  columns: string[];
  teams: BoxTeam[];
};

type StandingRow = {
  seed: number;
  name: string;
  abbr: string;
  logo: string;
  wins: number;
  losses: number;
  pct: string;
  gamesBehind: string;
  streak: string;
};

type StandingGroup = { name: string; rows: StandingRow[] };

/// Columnas del box score que se muestran, en este orden. ESPN manda más
/// (rebotes ofensivos/defensivos, faltas…); estas son las que entran en un celu.
const BOX_COLUMNS: { key: string; label: string }[] = [
  { key: 'minutes', label: 'MIN' },
  { key: 'points', label: 'PTS' },
  { key: 'rebounds', label: 'REB' },
  { key: 'assists', label: 'AST' },
  { key: 'fieldGoalsMade-fieldGoalsAttempted', label: 'TC' },
  { key: 'threePointFieldGoalsMade-threePointFieldGoalsAttempted', label: '3P' },
  { key: 'freeThrowsMade-freeThrowsAttempted', label: 'TL' },
  { key: 'steals', label: 'ROB' },
  { key: 'blocks', label: 'TAP' },
  { key: 'turnovers', label: 'PER' },
  { key: 'plusMinus', label: '+/-' },
];

@Injectable()
export class ScoresService {
  private readonly log = new Logger(ScoresService.name);
  private readonly cache = new Map<string, { until: number; value: unknown }>();

  private cached<T>(key: string): T | undefined {
    const hit = this.cache.get(key);
    return hit && Date.now() < hit.until ? (hit.value as T) : undefined;
  }

  private store<T>(key: string, value: T, ttlMs: number): T {
    this.cache.set(key, { until: Date.now() + ttlMs, value });
    return value;
  }

  private async espn(path: string): Promise<any> {
    const res = await axios.get(`${ESPN}${path}`, {
      timeout: 8000,
      headers: { 'Accept-Encoding': 'gzip' },
    });
    return res.data;
  }

  /// Fechas (YYYYMMDD, hora de Nueva York: es como ESPN agrupa la jornada)
  /// de hoy y los [RECENT_DAYS] anteriores, más nuevas primero.
  private recentDates(): string[] {
    const fmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/New_York',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    const out: string[] = [];
    for (let i = 0; i <= RECENT_DAYS; i++) {
      out.push(fmt.format(new Date(Date.now() - i * 86_400_000)).replace(/-/g, ''));
    }
    return out;
  }

  private team(c: any): TeamLine {
    const t = c?.team ?? {};
    return {
      name: t.displayName ?? t.name ?? '',
      abbr: t.abbreviation ?? '',
      logo: t.logo ?? t.logos?.[0]?.href ?? '',
      score: c?.score?.displayValue ?? (typeof c?.score === 'string' ? c.score : '') ?? '',
      winner: c?.winner === true,
      record: c?.records?.[0]?.summary ?? '',
    };
  }

  private game(e: any): Game | null {
    const comp = e?.competitions?.[0];
    const cs: any[] = comp?.competitors ?? [];
    const home = cs.find((c) => c.homeAway === 'home');
    const away = cs.find((c) => c.homeAway === 'away');
    if (!e?.id || !home || !away) return null;
    const st = e.status?.type ?? comp?.status?.type ?? {};
    const state = st.state === 'in' || st.state === 'post' ? st.state : 'pre';
    return {
      id: String(e.id),
      date: e.date ?? comp?.date ?? '',
      state,
      status: st.shortDetail ?? st.detail ?? '',
      home: this.team(home),
      away: this.team(away),
    };
  }

  /// Partidos de hoy y de los últimos días, más nuevos primero.
  async games(league: League): Promise<Game[]> {
    const key = `games:${league}`;
    const hit = this.cached<Game[]>(key);
    if (hit) return hit;
    try {
      const days = await Promise.all(
        this.recentDates().map((d) =>
          this.espn(`/site/v2/sports/basketball/${league}/scoreboard?dates=${d}`)
            .then((data) => (data?.events ?? []) as any[])
            .catch(() => [] as any[]),
        ),
      );
      const seen = new Set<string>();
      const games: Game[] = [];
      for (const e of days.flat()) {
        const g = this.game(e);
        if (g && !seen.has(g.id)) {
          seen.add(g.id);
          games.push(g);
        }
      }
      games.sort((a, b) => b.date.localeCompare(a.date));
      const live = games.some((g) => g.state === 'in');
      return this.store(key, games, live ? TTL_LIVE_MS : TTL_IDLE_MS);
    } catch (e) {
      this.log.error(`scoreboard ${league} falló: ${(e as Error)?.message ?? e}`);
      return [];
    }
  }

  /// Box score de un partido. null si no existe o ESPN falló.
  async boxScore(league: League, id: string): Promise<BoxScore | null> {
    const key = `box:${league}:${id}`;
    const hit = this.cached<BoxScore>(key);
    if (hit) return hit;
    try {
      const d = await this.espn(
        `/site/v2/sports/basketball/${league}/summary?event=${encodeURIComponent(id)}`,
      );
      // El header trae el mismo formato que el scoreboard (para marcador/estado).
      const headerComp = d?.header?.competitions?.[0];
      const game = headerComp
        ? this.game({ id, date: headerComp.date, status: headerComp.status, competitions: [headerComp] })
        : null;
      const scores = new Map<string, string>();
      for (const c of headerComp?.competitors ?? []) {
        scores.set(c?.team?.abbreviation ?? '', c?.score ?? '');
      }
      const teams: BoxTeam[] = [];
      for (const p of (d?.boxscore?.players ?? []) as any[]) {
        const block = p?.statistics?.[0] ?? {};
        const keys: string[] = block.keys ?? [];
        const idx = BOX_COLUMNS.map((c) => keys.indexOf(c.key));
        const players: PlayerLine[] = ((block.athletes ?? []) as any[]).map((a) => ({
          name: a?.athlete?.displayName ?? '',
          position: a?.athlete?.position?.abbreviation ?? '',
          starter: a?.starter === true,
          dnp: a?.didNotPlay === true || !(a?.stats ?? []).length,
          stats: idx.map((i) => (i >= 0 ? String(a?.stats?.[i] ?? '') : '')),
        }));
        const abbr = p?.team?.abbreviation ?? '';
        teams.push({
          name: p?.team?.displayName ?? '',
          abbr,
          logo: p?.team?.logo ?? '',
          score: scores.get(abbr) ?? '',
          players,
        });
      }
      const box: BoxScore = { game, columns: BOX_COLUMNS.map((c) => c.label), teams };
      const ttl =
        game?.state === 'post' ? TTL_FINAL_GAME_MS : game?.state === 'in' ? TTL_LIVE_MS : TTL_IDLE_MS;
      return this.store(key, box, ttl);
    } catch (e) {
      this.log.error(`summary ${league}/${id} falló: ${(e as Error)?.message ?? e}`);
      return null;
    }
  }

  /// Tabla de posiciones por conferencia, ordenada por puesto.
  async standings(league: League): Promise<StandingGroup[]> {
    const key = `standings:${league}`;
    const hit = this.cached<StandingGroup[]>(key);
    if (hit) return hit;
    try {
      const d = await this.espn(`/v2/sports/basketball/${league}/standings`);
      const groups: any[] = d?.children?.length ? d.children : [d];
      const out: StandingGroup[] = groups.map((g) => {
        const rows: StandingRow[] = ((g?.standings?.entries ?? []) as any[]).map((e) => {
          const stat = (name: string) =>
            ((e?.stats ?? []) as any[]).find((s) => s?.name === name);
          return {
            seed: Number(stat('playoffSeed')?.value ?? 0),
            name: e?.team?.displayName ?? '',
            abbr: e?.team?.abbreviation ?? '',
            logo: e?.team?.logos?.[0]?.href ?? '',
            wins: Number(stat('wins')?.value ?? 0),
            losses: Number(stat('losses')?.value ?? 0),
            pct: stat('winPercent')?.displayValue ?? '',
            gamesBehind: stat('gamesBehind')?.displayValue ?? '',
            streak: stat('streak')?.displayValue ?? '',
          };
        });
        rows.sort((a, b) => (a.seed || 99) - (b.seed || 99));
        return { name: g?.name ?? '', rows };
      });
      return this.store(key, out, TTL_STANDINGS_MS);
    } catch (e) {
      this.log.error(`standings ${league} falló: ${(e as Error)?.message ?? e}`);
      return [];
    }
  }
}

function parseLeague(league: string): League | null {
  return league === 'nba' || league === 'wnba' ? league : null;
}

@Controller('scores')
@UseGuards(JwtAuthGuard)
class ScoresController {
  constructor(private readonly svc: ScoresService) {}

  /// Partidos de hoy y de los últimos días (`?league=nba|wnba`).
  @Get('games')
  games(@Query('league') league: string) {
    const l = parseLeague(league);
    return l ? this.svc.games(l) : [];
  }

  /// Box score de un partido (`/scores/games/:id?league=nba`). null si no hay.
  @Get('games/:id')
  game(@Param('id') id: string, @Query('league') league: string) {
    const l = parseLeague(league);
    if (!l || !/^\d{1,15}$/.test(id)) return null;
    return this.svc.boxScore(l, id);
  }

  /// Tabla de posiciones por conferencia.
  @Get('standings')
  standings(@Query('league') league: string) {
    const l = parseLeague(league);
    return l ? this.svc.standings(l) : [];
  }
}

@Module({
  controllers: [ScoresController],
  providers: [ScoresService],
})
export class ScoresModule {}
