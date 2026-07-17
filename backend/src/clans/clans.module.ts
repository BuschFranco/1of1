import {
  Controller,
  Get,
  Injectable,
  Module,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { NotionService } from '../notion/notion.service';
import { seasonStartIso } from '../season';

// Un "clan" NO es una entidad: es la insignia de texto (≤4 chars) que cada
// usuario escribe en su perfil (columna Clan de Profiles). Acá se agrupa por
// esa insignia normalizada (trim + mayúsculas) y se agregan puntos.

type ClanRow = { clan: string; points: number; members: number };

// ── Service ─────────────────────────────────────────────────────────────────

@Injectable()
class ClansService {
  constructor(private readonly notion: NotionService) {}

  // Mapeo email→clan cacheado en memoria: el ranking por período y el dueño de
  // cancha lo necesitan en cada request, y los perfiles cambian poco.
  private clanCache: {
    at: number;
    byEmail: Map<string, string>;
    members: Map<string, number>;
  } | null = null;
  private static readonly cacheTtlMs = 60_000;

  private get profilesDb() {
    return this.notion.cfg.db.profiles;
  }
  private get matchesDb() {
    return this.notion.cfg.db.matches;
  }

  /** Normalización canónica de la insignia ("nba" y "NBA" son el mismo clan). */
  private static clanKey(raw: string): string {
    return raw.trim().toUpperCase();
  }

  /** Perfiles con clan: email→clanKey + cantidad de miembros por clan.
   * queryDatabaseAll capea (~2000 filas): límite aceptado en beta. */
  private async loadClanMap(): Promise<{
    byEmail: Map<string, string>;
    members: Map<string, number>;
  }> {
    const cached = this.clanCache;
    if (cached && Date.now() - cached.at < ClansService.cacheTtlMs) {
      return cached;
    }
    const byEmail = new Map<string, string>();
    const members = new Map<string, number>();
    const rows = await this.notion.queryDatabaseAll(this.profilesDb, {
      filter: NotionService.filterTextNotEmpty('Clan'),
    });
    for (const r of rows) {
      const p = r.properties;
      const email = NotionService.readText(p, 'UserEmail').trim().toLowerCase();
      const clan = ClansService.clanKey(NotionService.readText(p, 'Clan'));
      if (!email || !clan) continue;
      byEmail.set(email, clan);
      members.set(clan, (members.get(clan) ?? 0) + 1);
    }
    this.clanCache = { at: Date.now(), byEmail, members };
    return this.clanCache;
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

  /** Ranking global de clanes. Sin [since] = Total (suma de Points de los
   * perfiles); con [since] (ISO) = suma de partidos del período. */
  async ranking(since?: string): Promise<ClanRow[]> {
    if (!this.profilesDb) return [];

    const isTotal =
      !since ||
      new Date(since).getTime() <= 0 ||
      isNaN(new Date(since).getTime());
    const points = new Map<string, number>();

    if (isTotal) {
      // Total: los Points acumulados viven en el propio perfil. Una sola query
      // fresca a Profiles resuelve puntos Y miembros (usar la cache acá haría
      // que un clan recién creado aparezca con 0 miembros hasta que expire).
      const members = new Map<string, number>();
      const rows = await this.notion.queryDatabaseAll(this.profilesDb, {
        filter: NotionService.filterTextNotEmpty('Clan'),
      });
      for (const r of rows) {
        const p = r.properties;
        const clan = ClansService.clanKey(NotionService.readText(p, 'Clan'));
        if (!clan) continue;
        points.set(
          clan,
          (points.get(clan) ?? 0) + NotionService.readInt(p, 'Points'),
        );
        members.set(clan, (members.get(clan) ?? 0) + 1);
      }
      return ClansService.toSorted(points, members);
    }

    if (!this.matchesDb) return [];
    const { byEmail, members } = await this.loadClanMap();
    const rows = await this.notion.queryDatabaseAll(this.matchesDb, {
      filter: NotionService.filterDateOnOrAfter('EndedAt', since),
      maxPages: 30,
    });
    for (const r of rows) {
      const p = r.properties;
      const email = NotionService.readTitle(p, 'Email').trim().toLowerCase();
      // Clan de la FILA (estampado al jugar); legadas sin Clan → clan actual.
      const clan =
        ClansService.clanKey(NotionService.readText(p, 'Clan')) ||
        byEmail.get(email);
      if (!clan) continue;
      points.set(
        clan,
        (points.get(clan) ?? 0) + NotionService.readInt(p, 'Points'),
      );
    }
    return ClansService.toSorted(points, members);
  }

  /** Clan que "conquistó" la cancha: el de más puntos acumulados ahí EN LA
   * TEMPORADA ACTUAL (la conquista se reinicia cada temporada, filtrando por
   * fecha — el histórico queda intacto en la DB). */
  async courtOwner(courtId: string): Promise<{ owner: ClanRow | null }> {
    if (!this.profilesDb || !this.matchesDb || !courtId) {
      return { owner: null };
    }
    const { byEmail, members } = await this.loadClanMap();
    const rows = await this.notion.queryDatabaseAll(this.matchesDb, {
      filter: NotionService.filterAnd([
        NotionService.filterText('CourtId', courtId),
        NotionService.filterDateOnOrAfter('EndedAt', seasonStartIso()),
      ]),
    });
    const points = new Map<string, number>();
    for (const r of rows) {
      const p = r.properties;
      const email = NotionService.readTitle(p, 'Email').trim().toLowerCase();
      // Clan de la FILA (estampado al jugar); legadas sin Clan → clan actual.
      const clan =
        ClansService.clanKey(NotionService.readText(p, 'Clan')) ||
        byEmail.get(email);
      if (!clan) continue;
      points.set(
        clan,
        (points.get(clan) ?? 0) + NotionService.readInt(p, 'Points'),
      );
    }
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
}

@Module({
  controllers: [ClansController],
  providers: [ClansService],
})
export class ClansModule {}
