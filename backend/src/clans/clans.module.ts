import {
  Controller,
  Get,
  Injectable,
  Module,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { parseUtc } from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';
import { seasonStart } from '../season';

// Un "clan" NO es una entidad: es la insignia de texto (≤4 chars) que cada
// usuario escribe en su perfil (columna clan de profiles). Acá se agrupa por
// esa insignia normalizada (trim + mayúsculas) y se agregan puntos.

type ClanRow = { clan: string; points: number; members: number };

type CourtLeaders = {
  king: { name: string; handle: string; points: number } | null;
  clan: ClanRow | null;
};

// Caché en memoria de `courtLeaders`: lo piden todos los usuarios al abrir el
// mapa, y solo cambia cuando se suben partidos (MatchesService lo invalida).
let leadersCache: { at: number; value: Record<string, CourtLeaders> } | null =
  null;

export function invalidateCourtLeaders(): void {
  leadersCache = null;
}

// ── Service ─────────────────────────────────────────────────────────────────

@Injectable()
class ClansService {
  constructor(private readonly prisma: PrismaService) {}

  /** Normalización canónica de la insignia ("nba" y "NBA" son el mismo clan). */
  private static clanKey(raw: string): string {
    return raw.trim().toUpperCase();
  }

  /** Perfiles con clan: email→clanKey + cantidad de miembros por clan. */
  private async clanMap(): Promise<{
    byEmail: Map<string, string>;
    members: Map<string, number>;
  }> {
    const rows = await this.prisma.profile.findMany({
      where: { clan: { not: '' }, archived: false },
      select: { userEmail: true, clan: true },
    });
    const byEmail = new Map<string, string>();
    const members = new Map<string, number>();
    for (const r of rows) {
      const email = r.userEmail.trim().toLowerCase();
      const clan = ClansService.clanKey(r.clan);
      if (!email || !clan) continue;
      byEmail.set(email, clan);
      members.set(clan, (members.get(clan) ?? 0) + 1);
    }
    return { byEmail, members };
  }

  /** Ordena y corta el agregado {clan: puntos} a top 50. Empates: menos
   * miembros primero (mismos puntos con menos gente = mejor), luego alfabético. */
  private static toSorted(
    points: Map<string, number>,
    members: Map<string, number>,
  ): ClanRow[] {
    return [...points.entries()]
      .map(([clan, pts]) => ({
        clan,
        points: pts,
        members: members.get(clan) ?? 0,
      }))
      .sort(
        (a, b) =>
          b.points - a.points ||
          a.members - b.members ||
          a.clan.localeCompare(b.clan),
      )
      .slice(0, 50);
  }

  /** Suma de puntos por clan de los partidos que cumplen [where]. El clan sale
   * de la FILA (estampado al jugar): cambiar de clan no muda los puntos ya
   * aportados. Filas legadas sin clan → clan actual del autor. */
  private async pointsByClan(
    where: Record<string, any>,
    byEmail: Map<string, string>,
  ): Promise<Map<string, number>> {
    const rows = await this.prisma.match.findMany({
      where: { ...where, archived: false },
      select: { email: true, clan: true, exp: true },
    });
    const points = new Map<string, number>();
    for (const r of rows) {
      const clan =
        ClansService.clanKey(r.clan) ||
        byEmail.get(r.email.trim().toLowerCase());
      if (!clan) continue;
      points.set(clan, (points.get(clan) ?? 0) + r.exp);
    }
    return points;
  }

  /** Ranking global de clanes. Sin [since] = Total (suma de Points de los
   * perfiles); con [since] (ISO) = suma de partidos del período. */
  async ranking(since?: string): Promise<ClanRow[]> {
    const start = parseUtc(since);

    if (!start || start.getTime() <= 0) {
      // Total: los Points acumulados viven en el propio perfil.
      const rows = await this.prisma.profile.findMany({
        where: { clan: { not: '' }, archived: false },
        select: { clan: true, exp: true },
      });
      const points = new Map<string, number>();
      const members = new Map<string, number>();
      for (const r of rows) {
        const clan = ClansService.clanKey(r.clan);
        if (!clan) continue;
        points.set(clan, (points.get(clan) ?? 0) + r.exp);
        members.set(clan, (members.get(clan) ?? 0) + 1);
      }
      return ClansService.toSorted(points, members);
    }

    const { byEmail, members } = await this.clanMap();
    const points = await this.pointsByClan({ endedAt: { gte: start } }, byEmail);
    return ClansService.toSorted(points, members);
  }

  private static readonly LEADERS_TTL_MS = 5 * 60 * 1000;

  /** Rey (jugador) y clan dueño de TODAS las canchas en la temporada actual,
   * en una sola pasada. Mismas reglas que [courtOwner] y `courtKing` de
   * matches; reemplaza las dos llamadas que la app hacía por cada tarjeta. */
  async courtLeaders(): Promise<Record<string, CourtLeaders>> {
    const hit = leadersCache;
    if (hit && Date.now() - hit.at < ClansService.LEADERS_TTL_MS) {
      return hit.value;
    }

    const { byEmail, members } = await this.clanMap();
    const rows = await this.prisma.match.findMany({
      where: { endedAt: { gte: seasonStart() }, archived: false },
      select: { courtId: true, email: true, clan: true, exp: true },
    });

    // courtId → (email → puntos) y courtId → (clan → puntos).
    const byPlayer = new Map<string, Map<string, number>>();
    const byClan = new Map<string, Map<string, number>>();
    for (const r of rows) {
      if (!r.courtId) continue;
      const email = r.email.trim().toLowerCase();
      const players = byPlayer.get(r.courtId) ?? new Map<string, number>();
      players.set(email, (players.get(email) ?? 0) + r.exp);
      byPlayer.set(r.courtId, players);

      const clan = ClansService.clanKey(r.clan) || byEmail.get(email);
      if (clan) {
        const clans = byClan.get(r.courtId) ?? new Map<string, number>();
        clans.set(clan, (clans.get(clan) ?? 0) + r.exp);
        byClan.set(r.courtId, clans);
      }
    }

    // Rey por cancha (el de más puntos) y un solo lookup de sus nombres.
    const kingOf = new Map<string, { email: string; points: number }>();
    for (const [courtId, players] of byPlayer) {
      let best: { email: string; points: number } | null = null;
      for (const [email, points] of players) {
        if (!best || points > best.points) best = { email, points };
      }
      if (best && best.points > 0) kingOf.set(courtId, best);
    }
    const emails = [...new Set([...kingOf.values()].map((k) => k.email))];
    const profiles = emails.length
      ? await this.prisma.profile.findMany({
          where: { userEmail: { in: emails }, archived: false },
          select: { userEmail: true, name: true, handle: true },
        })
      : [];
    const nameOf = new Map(
      profiles.map((p) => [p.userEmail.trim().toLowerCase(), p]),
    );

    const out: Record<string, CourtLeaders> = {};
    const courtIds = new Set([...byPlayer.keys(), ...byClan.keys()]);
    for (const courtId of courtIds) {
      const k = kingOf.get(courtId);
      const p = k ? nameOf.get(k.email) : undefined;
      const clans = byClan.get(courtId);
      const top = clans ? ClansService.toSorted(clans, members)[0] : undefined;
      out[courtId] = {
        king: k
          ? {
              name: p?.name || k.email.split('@')[0],
              handle: p?.handle ?? '',
              points: k.points,
            }
          : null,
        clan: top && top.points > 0 ? top : null,
      };
    }

    leadersCache = { at: Date.now(), value: out };
    return out;
  }

  /** Clan que "conquistó" la cancha: el de más puntos acumulados ahí EN LA
   * TEMPORADA ACTUAL (la conquista se reinicia cada temporada). */
  async courtOwner(courtId: string): Promise<{ owner: ClanRow | null }> {
    if (!courtId) return { owner: null };
    const { byEmail, members } = await this.clanMap();
    const points = await this.pointsByClan(
      { courtId, endedAt: { gte: seasonStart() } },
      byEmail,
    );
    const top = ClansService.toSorted(points, members)[0];
    return { owner: top && top.points > 0 ? top : null };
  }
}

// ── Controller ──────────────────────────────────────────────────────────────

@Controller('clans')
@UseGuards(JwtAuthGuard)
class ClansController {
  constructor(private readonly clans: ClansService) {}

  @Get('ranking')
  ranking(@Query('since') since?: string) {
    return this.clans.ranking((since ?? '').trim());
  }

  @Get('court-owner')
  courtOwner(@Query('courtId') courtId: string) {
    return this.clans.courtOwner((courtId ?? '').trim());
  }

  /** Rey y clan dueño de todas las canchas (temporada actual). */
  @Get('court-leaders')
  async courtLeaders() {
    return { leaders: await this.clans.courtLeaders() };
  }
}

@Module({
  controllers: [ClansController],
  providers: [ClansService],
})
export class ClansModule {}
