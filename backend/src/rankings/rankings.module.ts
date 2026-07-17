import {
  BadRequestException,
  Controller,
  Get,
  Injectable,
  Module,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { NotionService } from '../notion/notion.service';

// Ranking GLOBAL por período (semana/mes/temporada): top de jugadores y de
// clanes de toda la app, sumando la DB Partidos desde el corte. Los clanes son
// la insignia del perfil normalizada (misma regla que clans.module).

type PlayerRow = { name: string; handle: string; points: number };
type ClanRow = { clan: string; points: number; members: number };
type MeRow = {
  playerRank: number | null;
  playerPoints: number;
  clan: string | null;
  clanRank: number | null;
  clanPoints: number;
};

type ProfileLite = { name: string; handle: string; clan: string };

const TOP = 50;

// ── Service ─────────────────────────────────────────────────────────────────

@Injectable()
class RankingsService {
  constructor(private readonly notion: NotionService) {}

  // Identidades (nombre/handle/clan por email) cacheadas: cambian poco y se
  // necesitan en cada request para resolver los emails de los partidos.
  private idCache: { at: number; byEmail: Map<string, ProfileLite> } | null =
    null;
  private static readonly cacheTtlMs = 60_000;

  private get profilesDb() {
    return this.notion.cfg.db.profiles;
  }
  private get matchesDb() {
    return this.notion.cfg.db.matches;
  }

  private static clanKey(raw: string): string {
    return raw.trim().toUpperCase();
  }

  /** Todos los perfiles → email→{name, handle, clan}. queryDatabaseAll capea
   * (~2000 filas): límite aceptado en beta. */
  private async identities(): Promise<Map<string, ProfileLite>> {
    const cached = this.idCache;
    if (cached && Date.now() - cached.at < RankingsService.cacheTtlMs) {
      return cached.byEmail;
    }
    const byEmail = new Map<string, ProfileLite>();
    const rows = await this.notion.queryDatabaseAll(this.profilesDb, {});
    for (const r of rows) {
      const p = r.properties;
      const email = NotionService.readText(p, 'UserEmail').trim().toLowerCase();
      if (!email) continue;
      byEmail.set(email, {
        name: NotionService.readTitle(p, 'Name'),
        handle: NotionService.readText(p, 'Handle'),
        clan: RankingsService.clanKey(NotionService.readText(p, 'Clan')),
      });
    }
    this.idCache = { at: Date.now(), byEmail };
    return byEmail;
  }

  /** Ranking global del período: top 50 jugadores + top 50 clanes + mi
   * posición (como jugador y la de mi clan) aunque quede fuera del top. */
  async global(
    since: string,
    myEmail: string,
  ): Promise<{ players: PlayerRow[]; clans: ClanRow[]; me: MeRow }> {
    if (!this.matchesDb || !this.profilesDb) {
      return {
        players: [],
        clans: [],
        me: {
          playerRank: null,
          playerPoints: 0,
          clan: null,
          clanRank: null,
          clanPoints: 0,
        },
      };
    }
    const ids = await this.identities();
    const rows = await this.notion.queryDatabaseAll(this.matchesDb, {
      filter: NotionService.filterDateOnOrAfter('EndedAt', since),
      maxPages: 30,
    });

    // Una sola pasada por los partidos alimenta ambos agregados.
    const byPlayer = new Map<string, number>();
    const byClan = new Map<string, number>();
    for (const r of rows) {
      const p = r.properties;
      const email = NotionService.readTitle(p, 'Email').trim().toLowerCase();
      if (!email) continue;
      const pts = NotionService.readInt(p, 'Points');
      byPlayer.set(email, (byPlayer.get(email) ?? 0) + pts);
      // El clan sale de la FILA (estampado al jugar): cambiar de clan no muda
      // los puntos ya aportados. Filas legadas sin Clan → clan actual del autor.
      const clan =
        RankingsService.clanKey(NotionService.readText(p, 'Clan')) ||
        ids.get(email)?.clan;
      if (clan) byClan.set(clan, (byClan.get(clan) ?? 0) + pts);
    }

    // Jugadores: orden points desc → email asc (estable). El nombre/handle
    // sale del perfil; sin perfil (cuenta borrada) se usa el alias del email.
    const players = [...byPlayer.entries()].sort(
      (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]),
    );
    const playerRows: PlayerRow[] = players.slice(0, TOP).map(([email, pts]) => {
      const id = ids.get(email);
      return {
        name: id?.name || email.split('@')[0],
        handle: id?.handle ?? '',
        points: pts,
      };
    });

    // Clanes: miembros según perfiles; mismo desempate que /clans/ranking.
    const clanMembers = new Map<string, number>();
    for (const id of ids.values()) {
      if (id.clan) clanMembers.set(id.clan, (clanMembers.get(id.clan) ?? 0) + 1);
    }
    const clans = [...byClan.entries()]
      .map(([clan, pts]) => ({
        clan,
        points: pts,
        members: clanMembers.get(clan) ?? 0,
      }))
      .sort(
        (a, b) =>
          b.points - a.points ||
          a.members - b.members ||
          a.clan.localeCompare(b.clan),
      );

    // Mi posición (1-based sobre el ranking COMPLETO, no solo el top).
    const email = myEmail.trim().toLowerCase();
    const myIdx = players.findIndex(([e]) => e === email);
    const myClan = ids.get(email)?.clan || null;
    const myClanIdx = myClan ? clans.findIndex((c) => c.clan === myClan) : -1;

    return {
      players: playerRows,
      clans: clans.slice(0, TOP),
      me: {
        playerRank: myIdx >= 0 ? myIdx + 1 : null,
        playerPoints: myIdx >= 0 ? players[myIdx][1] : 0,
        clan: myClan,
        clanRank: myClanIdx >= 0 ? myClanIdx + 1 : null,
        clanPoints: myClanIdx >= 0 ? clans[myClanIdx].points : 0,
      },
    };
  }
}

// ── Controller ──────────────────────────────────────────────────────────────

@Controller('rankings')
@UseGuards(JwtAuthGuard)
class RankingsController {
  constructor(private readonly rankings: RankingsService) {}

  @Get('global')
  global(@CurrentUser() user: AuthUser, @Query('since') since: string) {
    const s = (since ?? '').trim();
    if (!s || isNaN(new Date(s).getTime())) {
      throw new BadRequestException('since (ISO) requerido');
    }
    return this.rankings.global(s, user.email);
  }
}

@Module({
  controllers: [RankingsController],
  providers: [RankingsService],
})
export class RankingsModule {}
