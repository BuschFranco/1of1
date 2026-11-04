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
const TTL_POWER_MS = 6 * 60 * 60 * 1000;
const TTL_PROFILE_MS = 60 * 60 * 1000;
const TTL_OVERVIEW_MS = 6 * 60 * 60 * 1000;
const ESPN_WEB = 'https://site.web.api.espn.com/apis';

type TeamLine = {
  id: string;
  name: string;
  abbr: string;
  logo: string;
  score: string;
  winner: boolean;
  record: string;
  color: string; // hex sin '#', '' si ESPN no lo manda
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
  id: string;
  name: string;
  shortName: string;
  headshot: string;
  position: string;
  starter: boolean;
  dnp: boolean;
  stats: string[]; // alineado con `columns`
};

type BoxTeam = {
  id: string;
  side: 'home' | 'away';
  name: string;
  abbr: string;
  logo: string;
  score: string;
  color: string;
  altColor: string;
  linescores: number[]; // puntos por período
  players: PlayerLine[];
};

/// Una jugada de la línea de tiempo, ya clasificada (la app no sabe de ESPN).
/// `d` son los cambios de estadística que produce: [idJugador, stat, n], con
/// stat ∈ pts reb ast stl blk to fgm fga tpm tpa ftm fta pf. Con eso la app
/// arma el box score de CUALQUIER momento del partido sumando hasta ahí (se
/// validó contra el box final de ESPN: 0 diferencias).
type Play = {
  t: number; // segundos de juego transcurridos
  per: number; // período (5+ = suplementario)
  clock: string; // reloj del período ("5:12", "38.8")
  h: number; // marcador local después de la jugada
  a: number; // marcador visitante
  side: 'h' | 'a' | '';
  kind: string; // made · miss · ft · reb · to · foul · sub · timeout · end · jump · other
  v: number; // puntos de la jugada
  text: string; // en castellano
  d: [string, string, number][];
  in?: string; // sustitución: entra
  out?: string; // sustitución: sale
  wp?: number; // probabilidad de ganar del local (0..1), si ESPN la da
};

type Timeline = {
  periods: number; // períodos de juego regulares
  periodLen: number; // segundos por período
  otLen: number; // segundos del suplementario
  plays: Play[];
};

type SideList<T> = { home: T[]; away: T[] };

/// Previa / contexto del partido (también para partidos ya jugados).
type Preview = {
  /// Pronóstico de ESPN antes del partido (0..1). null si no lo publica.
  winProb: { home: number; away: number } | null;
  h2h: {
    summary: string;
    games: { date: string; home: string; away: string; homeScore: string; awayScore: string; done: boolean }[];
  } | null;
  /// Últimos 5 de cada uno: resultado (W/L), rival, marcador, local/visitante.
  form: SideList<{ result: string; opp: string; score: string; atVs: string }>;
  /// Comparativa. `season` true = promedios de la temporada (previa);
  /// false = números del partido (ya jugado).
  compare: { season: boolean; rows: { label: string; home: string; away: string; higherIsBetter: boolean }[] };
  /// Líderes (de temporada en la previa, del partido si ya se jugó).
  leaders: SideList<{ cat: string; id: string; name: string; headshot: string; value: string }>;
  injuries: SideList<{ name: string; status: string; detail: string }>;
};

type BoxScore = {
  game: Game | null;
  columns: string[];
  teams: BoxTeam[];
  timeline: Timeline | null;
  preview: Preview | null;
};

type PowerRow = {
  id: string;
  name: string;
  abbr: string;
  logo: string;
  rank: number;
  bpi: number;
  projW: number;
  projL: number;
  playoffs: number; // 0..100
  playIn: number;
  finals: number;
  title: number;
};

type PlayerProfile = {
  id: string;
  name: string;
  headshot: string;
  position: string;
  jersey: string;
  team: { id: string; name: string; abbr: string; logo: string; color: string };
  info: { label: string; value: string }[]; // altura, peso, edad, experiencia…
  season: { labels: string[]; values: string[] } | null;
  career: { labels: string[]; values: string[] } | null;
  lastGames: { date: string; opp: string; oppLogo: string; atVs: string; result: string; score: string; labels: string[]; stats: string[] }[];
};

type TeamProfile = {
  id: string;
  name: string;
  abbr: string;
  logo: string;
  color: string;
  record: string;
  standing: string;
  power: PowerRow | null;
  averages: { label: string; value: string }[];
  roster: { id: string; name: string; headshot: string; position: string; jersey: string; pts: string; reb: string; ast: string; min: string }[];
};

type StandingRow = {
  id: string;
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

// ── Castellano: ESPN manda todo en inglés y en unidades imperiales ─────────

const BODY: Record<string, string> = {
  Ankle: 'Tobillo', Knee: 'Rodilla', Hamstring: 'Isquiotibial', Hip: 'Cadera',
  Back: 'Espalda', Calf: 'Pantorrilla', Foot: 'Pie', Shoulder: 'Hombro',
  Wrist: 'Muñeca', Illness: 'Enfermedad', Quadriceps: 'Cuádriceps',
  Groin: 'Ingle', Achilles: 'Aquiles', Hand: 'Mano', Finger: 'Dedo',
  Thumb: 'Pulgar', Toe: 'Dedo del pie', Elbow: 'Codo', Neck: 'Cuello',
  Concussion: 'Conmoción', Rest: 'Descanso', Personal: 'Motivos personales',
  Abdomen: 'Abdomen', Chest: 'Pecho', Head: 'Cabeza', Face: 'Cara',
  Eye: 'Ojo', Nose: 'Nariz', Leg: 'Pierna', Shin: 'Tibia', Heel: 'Talón',
  Oblique: 'Oblicuo', Adductor: 'Aductor', Glute: 'Glúteo', Pelvis: 'Pelvis',
  'Lower Leg': 'Pierna', 'Lower Back': 'Zona lumbar', Rib: 'Costilla',
  Bruise: 'Golpe', Sprain: 'Esguince', Strain: 'Distensión',
  Soreness: 'Molestia', Surgery: 'Cirugía', Fracture: 'Fractura',
  Tear: 'Rotura', Tendinitis: 'Tendinitis', Inflammation: 'Inflamación',
  Contusion: 'Contusión', Dislocation: 'Luxación', Spasms: 'Espasmos',
  Tightness: 'Contractura', Management: 'Dosificación de cargas',
  Recovery: 'Recuperación', Suspension: 'Suspensión',
};
const tr = (v?: string) => (v ? BODY[v] ?? v : '');

const POSITION: Record<string, string> = {
  'Point Guard': 'Base', 'Shooting Guard': 'Escolta', 'Small Forward': 'Alero',
  'Power Forward': 'Ala-pívot', Center: 'Pívot', Guard: 'Escolta',
  Forward: 'Alero', 'Guard-Forward': 'Escolta-alero',
  'Forward-Center': 'Ala-pívot', 'Center-Forward': 'Pívot-alero',
};

/// 6' 2" → "1,88 m".
function heightEs(v?: string): string {
  const m = /(\d+)'\s*(\d+)?/.exec(v ?? '');
  if (!m) return v ?? '';
  const cm = (Number(m[1]) * 12 + Number(m[2] ?? 0)) * 2.54;
  return `${(cm / 100).toFixed(2).replace('.', ',')} m`;
}

/// "185 lbs" → "84 kg".
function weightEs(v?: string): string {
  const m = /(\d+)/.exec(v ?? '');
  return m ? `${Math.round(Number(m[1]) * 0.4536)} kg` : v ?? '';
}

/// "18th Season" → "18.ª temporada"; "Rookie" → "Novato".
function experienceEs(v?: string): string {
  if (!v) return '';
  if (/rookie/i.test(v)) return 'Novato';
  const m = /(\d+)/.exec(v);
  return m ? `${m[1]}.ª temporada` : v;
}

/// "2009: Rd 1, Pk 7 (GS)" → "2009 · ronda 1, elección 7 (GS)".
function draftEs(v?: string): string {
  if (!v) return '';
  return v.replace(/^(\d{4}):\s*/, '$1 · ').replace(/Rd\s*/i, 'ronda ').replace(/Pk\s*/i, 'elección ');
}

/// "2nd in Pacific Division" → "2.º en la división Pacific".
function standingEs(v?: string): string {
  if (!v) return '';
  const m = /^(\d+)(?:st|nd|rd|th) in (.+?)( Division| Conference)?$/i.exec(v);
  if (!m) return v;
  const kind = /conference/i.test(m[3] ?? '') ? 'la conferencia' : m[3] ? 'la división' : '';
  return `${m[1]}.º en ${kind ? `${kind} ` : ''}${m[2]}`;
}

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
  private recentDates(from = 0, to = RECENT_DAYS): string[] {
    const fmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/New_York',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    const out: string[] = [];
    for (let i = from; i <= to; i++) {
      out.push(fmt.format(new Date(Date.now() - i * 86_400_000)).replace(/-/g, ''));
    }
    return out;
  }

  private team(c: any): TeamLine {
    const t = c?.team ?? {};
    return {
      id: String(t.id ?? ''),
      name: t.displayName ?? t.name ?? '',
      abbr: t.abbreviation ?? '',
      logo: t.logo ?? t.logos?.[0]?.href ?? '',
      score: c?.score?.displayValue ?? (typeof c?.score === 'string' ? c.score : '') ?? '',
      winner: c?.winner === true,
      record: c?.records?.[0]?.summary ?? '',
      color: t.color ?? '',
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
      const fetchDays = (dates: string[]) =>
        Promise.all(
          dates.map((d) =>
            this.espn(`/site/v2/sports/basketball/${league}/scoreboard?dates=${d}`)
              .then((data) => (data?.events ?? []) as any[])
              .catch(() => [] as any[]),
          ),
        ).then((days) => days.flat());
      let events = await fetchDays(this.recentDates());
      // Sin partidos recientes (receso, fin de temporada): se busca más atrás,
      // de a una semana y hasta un mes, para mostrar los últimos resultados.
      for (let from = RECENT_DAYS + 1; !events.length && from <= 31; from += 7) {
        events = await fetchDays(this.recentDates(from, from + 6));
      }
      const seen = new Set<string>();
      const games: Game[] = [];
      for (const e of events) {
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
      const header = new Map<string, any>(); // abbr → competidor del header
      for (const c of headerComp?.competitors ?? []) {
        header.set(c?.team?.abbreviation ?? '', c);
      }
      const teams: BoxTeam[] = [];
      for (const p of (d?.boxscore?.players ?? []) as any[]) {
        const block = p?.statistics?.[0] ?? {};
        const keys: string[] = block.keys ?? [];
        const idx = BOX_COLUMNS.map((c) => keys.indexOf(c.key));
        const players: PlayerLine[] = ((block.athletes ?? []) as any[]).map((a) => ({
          id: String(a?.athlete?.id ?? ''),
          name: a?.athlete?.displayName ?? '',
          shortName: a?.athlete?.shortName ?? a?.athlete?.displayName ?? '',
          headshot: a?.athlete?.headshot?.href ?? '',
          position: a?.athlete?.position?.abbreviation ?? '',
          starter: a?.starter === true,
          dnp: a?.didNotPlay === true || !(a?.stats ?? []).length,
          stats: idx.map((i) => (i >= 0 ? String(a?.stats?.[i] ?? '') : '')),
        }));
        const abbr = p?.team?.abbreviation ?? '';
        const h = header.get(abbr);
        teams.push({
          id: String(p?.team?.id ?? h?.team?.id ?? ''),
          side: h?.homeAway === 'home' ? 'home' : 'away',
          name: p?.team?.displayName ?? '',
          abbr,
          logo: p?.team?.logo ?? '',
          score: h?.score ?? '',
          color: h?.team?.color ?? p?.team?.color ?? '',
          altColor: h?.team?.alternateColor ?? p?.team?.alternateColor ?? '',
          linescores: ((h?.linescores ?? []) as any[]).map((l) =>
            Number(l?.displayValue ?? l?.value ?? 0),
          ),
          players,
        });
      }
      const box: BoxScore = {
        game,
        columns: BOX_COLUMNS.map((c) => c.label),
        teams,
        timeline: this.timeline(d, headerComp, teams),
        preview: this.preview(d, headerComp),
      };
      const ttl =
        game?.state === 'post' ? TTL_FINAL_GAME_MS : game?.state === 'in' ? TTL_LIVE_MS : TTL_IDLE_MS;
      return this.store(key, box, ttl);
    } catch (e) {
      this.log.error(`summary ${league}/${id} falló: ${(e as Error)?.message ?? e}`);
      return null;
    }
  }

  /// Arma la línea de tiempo desde el play-by-play de ESPN. null si el partido
  /// no tiene jugadas (todavía no empezó, o ESPN no las publica).
  private timeline(d: any, headerComp: any, teams: BoxTeam[]): Timeline | null {
    const raw: any[] = d?.plays ?? [];
    if (!raw.length) return null;
    const periods = Number(d?.format?.regulation?.periods ?? 4);
    const periodLen = Number(d?.format?.regulation?.clock ?? 720);
    const otLen = Number(d?.format?.overtime?.clock ?? 300);

    // id de equipo de ESPN → lado.
    const sideOf = new Map<string, 'h' | 'a'>();
    for (const c of headerComp?.competitors ?? []) {
      sideOf.set(String(c?.team?.id ?? c?.id ?? ''), c?.homeAway === 'home' ? 'h' : 'a');
    }
    const short = new Map<string, string>();
    for (const t of teams) for (const p of t.players) short.set(p.id, p.shortName);
    const nm = (id?: string) => (id ? short.get(id) ?? '' : '');

    const wp = new Map<string, number>();
    for (const w of (d?.winprobability ?? []) as any[]) {
      if (w?.playId != null && typeof w?.homeWinPercentage === 'number') {
        wp.set(String(w.playId), w.homeWinPercentage);
      }
    }

    const secs = (c: string): number => {
      const v = String(c ?? '0');
      if (v.includes(':')) {
        const [m, x] = v.split(':');
        return Number(m) * 60 + Number(x);
      }
      return Number(v) || 0;
    };
    const elapsed = (per: number, clock: string): number => {
      const base = per > periods ? periods * periodLen + (per - periods - 1) * otLen : (per - 1) * periodLen;
      const len = per > periods ? otLen : periodLen;
      return Math.max(0, Math.round(base + len - secs(clock)));
    };

    const plays: Play[] = [];
    for (const p of raw) {
      const type: string = p?.type?.text ?? '';
      const tx: string = p?.text ?? '';
      const tl = tx.toLowerCase();
      const ids: string[] = ((p?.participants ?? []) as any[])
        .map((x) => String(x?.athlete?.id ?? ''))
        .filter((x) => x);
      const [a1, a2] = ids;
      const per = Number(p?.period?.number ?? 1);
      const clock: string = p?.clock?.displayValue ?? '';
      const dl: [string, string, number][] = [];
      let kind = 'other';
      let text = tx;
      let v = 0;
      let subIn: string | undefined;
      let subOut: string | undefined;

      if (type === 'Substitution' && a1 && a2) {
        kind = 'sub';
        subIn = a1;
        subOut = a2;
        text = `Entra ${nm(a1)} por ${nm(a2)}`;
      } else if (p?.shootingPlay && a1) {
        const made = p?.scoringPlay === true;
        if (type.startsWith('Free Throw')) {
          kind = 'ft';
          dl.push([a1, 'fta', 1]);
          if (made) {
            v = 1;
            dl.push([a1, 'ftm', 1], [a1, 'pts', 1]);
          }
          const m = type.match(/(\d+) of (\d+)/);
          const which = m ? ` ${m[1]} de ${m[2]}` : type.includes('Technical') ? ' (técnica)' : '';
          text = `${nm(a1)} ${made ? 'convierte' : 'falla'} libre${which}`;
        } else {
          // `pointsAttempted` marca el triple aunque el texto no lo diga
          // ("misses running pullup jump shot" puede ser de tres).
          const three = Number(p?.pointsAttempted ?? 0) === 3 || tl.includes('three point');
          dl.push([a1, 'fga', 1]);
          if (three) dl.push([a1, 'tpa', 1]);
          if (made) {
            kind = 'made';
            v = Number(p?.scoreValue ?? (three ? 3 : 2));
            dl.push([a1, 'fgm', 1], [a1, 'pts', v]);
            if (three) dl.push([a1, 'tpm', 1]);
            const dunk = /dunk/i.test(type);
            text = `${nm(a1)} ${three ? 'anota un triple' : dunk ? 'la vuela' : 'anota de dos'}`;
            if (tl.includes('assists') && a2) {
              dl.push([a2, 'ast', 1]);
              text += ` · asist. ${nm(a2)}`;
            }
          } else {
            kind = 'miss';
            text = `${nm(a1)} falla ${three ? 'un triple' : 'de dos'}`;
            if (tl.includes('blocks') && a2) {
              dl.push([a2, 'blk', 1]);
              text += ` · tapa de ${nm(a2)}`;
            }
          }
        }
      } else if (type.includes('Rebound')) {
        kind = 'reb';
        const off = type.includes('Offensive');
        if (a1) {
          dl.push([a1, 'reb', 1]);
          text = `Rebote ${off ? 'ofensivo' : 'defensivo'} de ${nm(a1)}`;
        } else {
          text = `Rebote ${off ? 'ofensivo' : 'defensivo'} del equipo`;
        }
      } else if (tl.includes('turnover') || type === 'Traveling') {
        kind = 'to';
        if (a1) dl.push([a1, 'to', 1]);
        text = a1 ? `Pérdida de ${nm(a1)}` : 'Pérdida del equipo';
        if (tl.includes('steals') && a2) {
          dl.push([a2, 'stl', 1]);
          text += ` · robo de ${nm(a2)}`;
        }
      } else if (type.includes('Foul')) {
        kind = 'foul';
        if (a1 && !type.includes('Technical')) dl.push([a1, 'pf', 1]);
        text = `${type.includes('Technical') ? 'Técnica' : 'Falta'}${a1 ? ` de ${nm(a1)}` : ''}`;
      } else if (type.includes('Timeout')) {
        kind = 'timeout';
        text = 'Tiempo muerto';
      } else if (type === 'End Period' || type === 'End Game') {
        kind = 'end';
        text =
          type === 'End Game'
            ? 'Final del partido'
            : per > periods
              ? 'Fin del suplementario'
              : `Fin del ${per}° ${periods === 4 ? 'cuarto' : 'período'}`;
      } else if (type === 'Jumpball') {
        kind = 'jump';
        text = 'Salto inicial';
      }

      const side = sideOf.get(String(p?.team?.id ?? '')) ?? '';
      const play: Play = {
        t: elapsed(per, clock),
        per,
        clock,
        h: Number(p?.homeScore ?? 0),
        a: Number(p?.awayScore ?? 0),
        side,
        kind,
        v,
        text,
        d: dl,
      };
      if (subIn) play.in = subIn;
      if (subOut) play.out = subOut;
      const w = wp.get(String(p?.id ?? ''));
      if (w != null) play.wp = w;
      plays.push(play);
    }
    return { periods, periodLen, otLen, plays };
  }

  /// Previa del partido desde el summary de ESPN. Nunca lanza.
  private preview(d: any, headerComp: any): Preview | null {
    try {
      const sideById = new Map<string, 'home' | 'away'>();
      for (const c of headerComp?.competitors ?? []) {
        sideById.set(String(c?.team?.id ?? c?.id ?? ''), c?.homeAway === 'home' ? 'home' : 'away');
      }
      const sideOf = (id: any) => sideById.get(String(id ?? ''));

      const pr = d?.predictor;
      const ph = Number(pr?.homeTeam?.gameProjection);
      const pa = Number(pr?.awayTeam?.gameProjection);
      const winProb =
        Number.isFinite(ph) && Number.isFinite(pa) && ph + pa > 0
          ? { home: ph / 100, away: pa / 100 }
          : null;

      const ss = (d?.seasonseries ?? [])[0];
      const h2h = ss
        ? {
            summary: ss.summary ?? '',
            games: ((ss.events ?? []) as any[]).map((e) => {
              const cs: any[] = e?.competitors ?? [];
              const h = cs.find((c) => c.homeAway === 'home');
              const a = cs.find((c) => c.homeAway === 'away');
              return {
                date: e?.date ?? '',
                home: h?.team?.abbreviation ?? '',
                away: a?.team?.abbreviation ?? '',
                homeScore: String(h?.score ?? ''),
                awayScore: String(a?.score ?? ''),
                done: e?.statusType?.completed === true,
              };
            }),
          }
        : null;

      const form: Preview['form'] = { home: [], away: [] };
      for (const t of (d?.lastFiveGames ?? []) as any[]) {
        const side = sideOf(t?.team?.id);
        if (!side) continue;
        form[side] = ((t?.events ?? []) as any[]).slice(0, 5).map((e) => ({
          result: e?.gameResult ?? '',
          opp: e?.opponent?.abbreviation ?? '',
          score: e?.score ?? '',
          atVs: e?.atVs ?? '',
        }));
      }

      // Comparativa: en la previa ESPN manda promedios de temporada; con el
      // partido jugado, los totales del partido.
      const SEASON: [string, string, boolean][] = [
        ['avgPoints', 'Puntos', true],
        ['avgPointsAgainst', 'Puntos en contra', false],
        ['fieldGoalPct', 'Tiros de campo %', true],
        ['threePointFieldGoalPct', 'Triples %', true],
        ['avgRebounds', 'Rebotes', true],
        ['avgAssists', 'Asistencias', true],
        ['avgSteals', 'Robos', true],
        ['avgBlocks', 'Tapas', true],
        ['avgTotalTurnovers', 'Pérdidas', false],
      ];
      const GAME: [string, string, boolean][] = [
        ['fieldGoalPct', 'Tiros de campo %', true],
        ['threePointFieldGoalPct', 'Triples %', true],
        ['freeThrowPct', 'Libres %', true],
        ['totalRebounds', 'Rebotes', true],
        ['offensiveRebounds', 'Rebotes ofensivos', true],
        ['assists', 'Asistencias', true],
        ['steals', 'Robos', true],
        ['blocks', 'Tapas', true],
        ['turnovers', 'Pérdidas', false],
        ['pointsInPaint', 'Puntos en la pintura', true],
        ['fastBreakPoints', 'Contraataque', true],
        ['largestLead', 'Mayor ventaja', true],
      ];
      const statsBySide: Record<'home' | 'away', Map<string, string>> = {
        home: new Map(),
        away: new Map(),
      };
      for (const t of (d?.boxscore?.teams ?? []) as any[]) {
        const side = t?.homeAway === 'home' || t?.homeAway === 'away' ? t.homeAway : sideOf(t?.team?.id);
        if (!side) continue;
        for (const st of (t?.statistics ?? []) as any[]) {
          if (st?.name) statsBySide[side as 'home' | 'away'].set(st.name, String(st.displayValue ?? ''));
        }
      }
      const season = statsBySide.home.has('avgPoints');
      const rows = (season ? SEASON : GAME)
        .filter(([k]) => statsBySide.home.has(k) && statsBySide.away.has(k))
        .map(([k, label, higherIsBetter]) => ({
          label,
          home: statsBySide.home.get(k)!,
          away: statsBySide.away.get(k)!,
          higherIsBetter,
        }));

      const CAT: Record<string, string> = {
        points: 'Puntos',
        pointsPerGame: 'Puntos',
        rebounds: 'Rebotes',
        reboundsPerGame: 'Rebotes',
        assists: 'Asistencias',
        assistsPerGame: 'Asistencias',
      };
      const leaders: Preview['leaders'] = { home: [], away: [] };
      for (const t of (d?.leaders ?? []) as any[]) {
        const side = sideOf(t?.team?.id);
        if (!side) continue;
        for (const c of (t?.leaders ?? []) as any[]) {
          const cat = CAT[c?.name ?? ''];
          const l = c?.leaders?.[0];
          if (!cat || !l?.athlete) continue;
          leaders[side].push({
            cat,
            id: String(l.athlete.id ?? ''),
            name: l.athlete.shortName ?? l.athlete.displayName ?? '',
            headshot: l.athlete.headshot?.href ?? '',
            value: String(l.displayValue ?? ''),
          });
        }
      }

      const STATUS: Record<string, string> = {
        Out: 'Afuera',
        'Day-To-Day': 'Día a día',
        Questionable: 'En duda',
        Doubtful: 'Dudoso',
        Probable: 'Probable',
        Suspension: 'Suspendido',
      };
      const injuries: Preview['injuries'] = { home: [], away: [] };
      for (const t of (d?.injuries ?? []) as any[]) {
        const side = sideOf(t?.team?.id);
        if (!side) continue;
        for (const i of (t?.injuries ?? []) as any[]) {
          const status = String(i?.status ?? '');
          injuries[side].push({
            name: i?.athlete?.shortName ?? i?.athlete?.displayName ?? '',
            status: STATUS[status] ?? status,
            detail: [tr(i?.details?.type), tr(i?.details?.detail)]
              .filter((x) => x && x !== 'Not Specified')
              .join(' · '),
          });
        }
      }

      return { winProb, h2h, form, compare: { season, rows }, leaders, injuries };
    } catch (e) {
      this.log.error(`preview falló: ${(e as Error)?.message ?? e}`);
      return null;
    }
  }

  /// Power ranking de ESPN (BPI) con las proyecciones de la temporada.
  async power(league: League): Promise<PowerRow[]> {
    const key = `power:${league}`;
    const hit = this.cached<PowerRow[]>(key);
    if (hit) return hit;
    try {
      const d = await axios
        .get(`${ESPN_WEB}/fitt/v3/sports/basketball/${league}/powerindex?region=us&lang=en&limit=50`, {
          timeout: 8000,
        })
        .then((r) => r.data);
      // Las columnas se buscan por nombre: NBA y WNBA no traen las mismas.
      const cats: any[] = d?.categories ?? [];
      const col = (cat: string, label: string): number =>
        (cats.find((c) => c?.name === cat)?.labels ?? []).indexOf(label);
      const at = (t: any, cat: string, label: string): number => {
        const i = col(cat, label);
        const vals: any[] = (t?.categories ?? []).find((c: any) => c?.name === cat)?.values ?? [];
        const v = i >= 0 ? Number(vals[i]) : NaN;
        return Number.isFinite(v) ? v : 0;
      };
      const rows: PowerRow[] = ((d?.teams ?? []) as any[]).map((t) => ({
        id: String(t?.team?.id ?? ''),
        name: t?.team?.displayName ?? '',
        abbr: t?.team?.abbreviation ?? '',
        logo: t?.team?.logos?.[0]?.href ?? '',
        rank: at(t, 'bpi', 'bpiRank'),
        bpi: at(t, 'bpi', 'BPI'),
        projW: at(t, 'projections', 'ProjW'),
        projL: at(t, 'projections', 'ProjL'),
        playoffs: at(t, 'projections', 'Playoffs%'),
        playIn: at(t, 'projections', 'playIn%'),
        finals: at(t, 'playoffs', 'Finals%'),
        title: at(t, 'playoffs', 'WinTitle%'),
      }));
      rows.sort((a, b) => (a.rank || 99) - (b.rank || 99));
      return this.store(key, rows, TTL_POWER_MS);
    } catch (e) {
      this.log.error(`power ${league} falló: ${(e as Error)?.message ?? e}`);
      return [];
    }
  }

  /// Overview de ESPN de un jugador (promedios + últimos partidos), cacheado.
  private async overview(league: League, id: string): Promise<any> {
    const key = `ov:${league}:${id}`;
    const hit = this.cached<any>(key);
    if (hit) return hit;
    const d = await axios
      .get(`${ESPN_WEB}/common/v3/sports/basketball/${league}/athletes/${id}/overview`, { timeout: 8000 })
      .then((r) => r.data);
    return this.store(key, d, TTL_OVERVIEW_MS);
  }

  /// Promedios (temporada y carrera) de un overview.
  private splits(ov: any): { season: PlayerProfile['season']; career: PlayerProfile['career'] } {
    const st = ov?.statistics ?? {};
    const labels: string[] = st.labels ?? [];
    const splits: any[] = st.splits ?? [];
    const pick = (re: RegExp) => {
      const sp = splits.find((x) => re.test(x?.displayName ?? ''));
      return sp ? { labels, values: (sp.stats ?? []).map((v: any) => String(v)) } : null;
    };
    return { season: pick(/regular|season|temporada/i), career: pick(/career|carrera/i) };
  }

  async player(league: League, id: string): Promise<PlayerProfile | null> {
    const key = `player:${league}:${id}`;
    const hit = this.cached<PlayerProfile>(key);
    if (hit) return hit;
    try {
      const [info, ov] = await Promise.all([
        axios
          .get(`${ESPN_WEB}/common/v3/sports/basketball/${league}/athletes/${id}`, { timeout: 8000 })
          .then((r) => r.data?.athlete ?? r.data),
        this.overview(league, id).catch(() => null),
      ]);
      const { season, career } = this.splits(ov);
      const gl = ov?.gameLog ?? {};
      const glStats = (gl.statistics ?? [])[0] ?? {};
      const lastGames = ((glStats.events ?? []) as any[]).map((ev) => {
        const e = gl.events?.[ev?.eventId] ?? {};
        return {
          date: e.gameDate ?? '',
          opp: e.opponent?.abbreviation ?? '',
          oppLogo: e.opponent?.logo ?? '',
          atVs: e.atVs ?? '',
          result: e.gameResult ?? '',
          score: e.score ?? '',
          labels: (glStats.labels ?? []) as string[],
          stats: ((ev?.stats ?? []) as any[]).map((v) => String(v)),
        };
      });
      const infoRows = [
        ['Altura', heightEs(info?.displayHeight)],
        ['Peso', weightEs(info?.displayWeight)],
        ['Edad', info?.age != null ? `${info.age} años` : ''],
        ['Experiencia', experienceEs(info?.displayExperience)],
        ['Draft', draftEs(info?.displayDraft)],
        ['Origen', info?.displayBirthPlace],
      ]
        .filter(([, v]) => v)
        .map(([label, value]) => ({ label: String(label), value: String(value) }));
      const profile: PlayerProfile = {
        id,
        name: info?.displayName ?? '',
        headshot: info?.headshot?.href ?? '',
        position:
          POSITION[info?.position?.displayName ?? ''] ??
          info?.position?.displayName ??
          info?.position?.abbreviation ??
          '',
        jersey: info?.jersey ?? '',
        team: {
          id: String(info?.team?.id ?? ''),
          name: info?.team?.displayName ?? '',
          abbr: info?.team?.abbreviation ?? '',
          logo: info?.team?.logos?.[0]?.href ?? info?.team?.logo ?? '',
          color: info?.team?.color ?? '',
        },
        info: infoRows,
        season,
        career,
        lastGames,
      };
      return this.store(key, profile, TTL_PROFILE_MS);
    } catch (e) {
      this.log.error(`player ${league}/${id} falló: ${(e as Error)?.message ?? e}`);
      return null;
    }
  }

  async teamProfile(league: League, id: string): Promise<TeamProfile | null> {
    const key = `team:${league}:${id}`;
    const hit = this.cached<TeamProfile>(key);
    if (hit) return hit;
    try {
      const base = `/site/v2/sports/basketball/${league}/teams/${id}`;
      const [page, stats, roster, power] = await Promise.all([
        this.espn(base).then((d) => d?.team ?? {}),
        this.espn(`${base}/statistics`).catch(() => null),
        this.espn(`${base}/roster`).catch(() => null),
        this.power(league),
      ]);
      const rec = page?.record?.items?.[0] ?? {};
      const recStat = (n: string) => (rec.stats ?? []).find((x: any) => x?.name === n)?.value;
      const statVal = new Map<string, string>();
      for (const c of (stats?.results?.stats?.categories ?? []) as any[]) {
        for (const st of (c?.stats ?? []) as any[]) {
          if (st?.name) statVal.set(st.name, String(st.displayValue ?? ''));
        }
      }
      const fmt1 = (v: any) => (typeof v === 'number' ? v.toFixed(1) : '');
      const averages = [
        ['Puntos', fmt1(recStat('avgPointsFor'))],
        ['Puntos en contra', fmt1(recStat('avgPointsAgainst'))],
        ['Diferencia', fmt1(recStat('differential'))],
        ['Tiros de campo %', statVal.get('fieldGoalPct')],
        ['Triples %', statVal.get('threePointPct') ?? statVal.get('threePointFieldGoalPct')],
        ['Libres %', statVal.get('freeThrowPct')],
        ['Rebotes', statVal.get('avgRebounds')],
        ['Asistencias', statVal.get('avgAssists')],
        ['Robos', statVal.get('avgSteals')],
        ['Tapas', statVal.get('avgBlocks')],
        ['Pérdidas', statVal.get('avgTurnovers') ?? statVal.get('avgTotalTurnovers')],
      ]
        .filter(([, v]) => v)
        .map(([label, value]) => ({ label: String(label), value: String(value) }));

      // Plantel con promedios: overview de cada jugador en paralelo (cacheado).
      const athletes: any[] = roster?.athletes ?? [];
      const players = await Promise.all(
        athletes.map(async (a) => {
          const aid = String(a?.id ?? '');
          let season: PlayerProfile['season'] = null;
          try {
            season = this.splits(await this.overview(league, aid)).season;
          } catch {
            season = null;
          }
          const v = (label: string) => {
            const i = season?.labels.indexOf(label) ?? -1;
            return i >= 0 ? season!.values[i] ?? '' : '';
          };
          return {
            id: aid,
            name: a?.displayName ?? '',
            headshot: a?.headshot?.href ?? '',
            position: a?.position?.abbreviation ?? '',
            jersey: a?.jersey ?? '',
            pts: v('PTS'),
            reb: v('REB'),
            ast: v('AST'),
            min: v('MIN'),
          };
        }),
      );
      players.sort((x, y) => (Number(y.pts) || 0) - (Number(x.pts) || 0));
      const profile: TeamProfile = {
        id,
        name: page?.displayName ?? '',
        abbr: page?.abbreviation ?? '',
        logo: page?.logos?.[0]?.href ?? '',
        color: page?.color ?? '',
        record: rec.summary ?? '',
        standing: standingEs(page?.standingSummary),
        power: power.find((r) => r.id === id) ?? null,
        averages,
        roster: players,
      };
      return this.store(key, profile, TTL_PROFILE_MS);
    } catch (e) {
      this.log.error(`team ${league}/${id} falló: ${(e as Error)?.message ?? e}`);
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
            id: String(e?.team?.id ?? ''),
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

  /// Power ranking BPI con proyecciones (% playoffs, final, campeón).
  @Get('power')
  power(@Query('league') league: string) {
    const l = parseLeague(league);
    return l ? this.svc.power(l) : [];
  }

  /// Perfil de un jugador: promedios de temporada y carrera, últimos partidos.
  @Get('players/:id')
  player(@Param('id') id: string, @Query('league') league: string) {
    const l = parseLeague(league);
    if (!l || !/^\d{1,15}$/.test(id)) return null;
    return this.svc.player(l, id);
  }

  /// Perfil de un equipo: récord, BPI, promedios y plantel con promedios.
  @Get('teams/:id')
  team(@Param('id') id: string, @Query('league') league: string) {
    const l = parseLeague(league);
    if (!l || !/^\d{1,6}$/.test(id)) return null;
    return this.svc.teamProfile(l, id);
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
