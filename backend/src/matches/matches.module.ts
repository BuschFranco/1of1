import {
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { NotionService } from '../notion/notion.service';
import { seasonStart, seasonStartIso } from '../season';

// ── DTOs ────────────────────────────────────────────────────────────────────

class MatchItemDto {
  @IsInt() points!: number;
  @IsString() endedAt!: string;
  @IsOptional() @IsString() courtId?: string;
  @IsOptional() @IsString() courtName?: string;
  @IsOptional() @IsString() result?: string;
  @IsOptional() @IsInt() seconds?: number;
}

class UploadMatchesDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MatchItemDto)
  matches!: MatchItemDto[];
}

// ── Service ───────────────────────────────────────────────────────────────

@Injectable()
class MatchesService {
  constructor(private readonly notion: NotionService) {}

  private get db() {
    return this.notion.cfg.db.matches;
  }

  /** Insignia de clan ACTUAL del autor, normalizada (misma regla que
   * clans/rankings: trim + mayúsculas). Vacía si no tiene clan o falla. */
  private async currentClan(email: string): Promise<string> {
    const profilesDb = this.notion.cfg.db.profiles;
    if (!profilesDb) return '';
    try {
      const rows = await this.notion.queryDatabase(profilesDb, {
        filter: NotionService.filterText('UserEmail', email),
        pageSize: 1,
      });
      const p = rows[0]?.properties;
      return p ? NotionService.readText(p, 'Clan').trim().toUpperCase() : '';
    } catch {
      return '';
    }
  }

  /** Sube un lote de partidos resueltos. El email sale del token (title). Devuelve
   * ok/err por ítem (el cliente reintenta los fallidos). Cada fila queda
   * estampada con el clan del autor al momento de subir: los puntos de clan no
   * migran cuando el usuario se cambia de insignia. */
  async upload(
    email: string,
    items: MatchItemDto[],
  ): Promise<{ results: { ok: boolean }[] }> {
    if (!this.db) return { results: items.map(() => ({ ok: false })) };
    const clan = await this.currentClan(email);
    const results: { ok: boolean }[] = [];
    for (const m of items) {
      try {
        await this.notion.createPage(this.db, {
          Email: NotionService.title(email),
          Points: NotionService.number(m.points),
          EndedAt: NotionService.date(m.endedAt),
          CourtId: NotionService.richText(m.courtId ?? ''),
          CourtName: NotionService.richText(m.courtName ?? ''),
          Result: NotionService.select(m.result ?? null),
          Seconds: NotionService.number(m.seconds ?? 0),
          Clan: NotionService.richText(clan),
        });
        results.push({ ok: true });
      } catch {
        results.push({ ok: false });
      }
    }
    return { results };
  }

  /** Fechas de fin (ISO) de MIS partidos ya registrados. Lo usa la app para
   * dedupear el backfill del log local (sube solo lo que falta). */
  async mine(email: string): Promise<{ endedAt: string[] }> {
    if (!this.db) return { endedAt: [] };
    const rows = await this.notion.queryDatabaseAll(this.db, {
      filter: NotionService.filterTitle('Email', email),
    });
    const out: string[] = [];
    for (const r of rows) {
      const d = NotionService.readDate(r.properties, 'EndedAt');
      if (d) out.push(d);
    }
    return { endedAt: out };
  }

  /** Puntos por email desde [since] (ISO) para los emails dados. Agrupa y suma
   * server-side (lo que la app hoy hace en el cliente). */
  async ranking(
    since: string,
    emails: string[],
  ): Promise<{ email: string; points: number }[]> {
    if (!this.db || emails.length === 0 || !since) return [];
    const capped = emails.slice(0, 100);
    const rows = await this.notion.queryDatabaseAll(this.db, {
      filter: NotionService.filterAnd([
        NotionService.filterDateOnOrAfter('EndedAt', since),
        NotionService.filterOr(
          capped.map((e) => NotionService.filterTitle('Email', e)),
        ),
      ]),
    });
    const totals = new Map<string, number>();
    for (const r of rows) {
      const p = r.properties;
      const email = NotionService.readTitle(p, 'Email').trim().toLowerCase();
      if (!email) continue;
      const points = NotionService.readInt(p, 'Points');
      totals.set(email, (totals.get(email) ?? 0) + points);
    }
    return [...totals.entries()].map(([email, points]) => ({ email, points }));
  }

  /** Jugador con más puntos en la cancha EN LA TEMPORADA ACTUAL ("rey de la
   * cancha"): agrupa todos los partidos de la cancha por email, filtra por
   * temporada y devuelve el máximo con su nombre/handle. Se reinicia cada
   * temporada, igual que la conquista de clan. */
  async courtKing(
    courtId: string,
  ): Promise<{ king: { name: string; handle: string; points: number } | null }> {
    if (!this.db || !courtId) return { king: null };
    const rows = await this.notion.queryDatabaseAll(this.db, {
      filter: NotionService.filterAnd([
        NotionService.filterText('CourtId', courtId),
        NotionService.filterDateOnOrAfter('EndedAt', seasonStartIso()),
      ]),
    });
    const byEmail = new Map<string, number>();
    for (const r of rows) {
      const email = NotionService.readTitle(r.properties, 'Email')
        .trim()
        .toLowerCase();
      if (!email) continue;
      byEmail.set(
        email,
        (byEmail.get(email) ?? 0) +
          NotionService.readInt(r.properties, 'Points'),
      );
    }
    let topEmail = '';
    let topPoints = 0;
    for (const [email, pts] of byEmail) {
      if (pts > topPoints) {
        topPoints = pts;
        topEmail = email;
      }
    }
    if (!topEmail || topPoints <= 0) return { king: null };
    const id = await this.identity(topEmail);
    return {
      king: {
        name: id.name || topEmail.split('@')[0],
        handle: id.handle,
        points: topPoints,
      },
    };
  }

  /** Nombre y handle de un perfil por email (para el rey de la cancha). */
  private async identity(
    email: string,
  ): Promise<{ name: string; handle: string }> {
    const profilesDb = this.notion.cfg.db.profiles;
    if (!profilesDb) return { name: '', handle: '' };
    try {
      const rows = await this.notion.queryDatabase(profilesDb, {
        filter: NotionService.filterText('UserEmail', email),
        pageSize: 1,
      });
      const p = rows[0]?.properties;
      return {
        name: p ? NotionService.readTitle(p, 'Name') : '',
        handle: p ? NotionService.readText(p, 'Handle') : '',
      };
    } catch {
      return { name: '', handle: '' };
    }
  }

  /** Puntos del usuario en una cancha, sumados desde la DB Partidos: total
   * histórico Y de la temporada actual por separado. Fuente de verdad para el
   * detalle de cancha: a diferencia del log local de la app, sobrevive
   * reinstalaciones y no está capado a los últimos 100 partidos. */
  async courtPoints(
    email: string,
    courtId: string,
  ): Promise<{
    points: number;
    matches: number;
    seasonPoints: number;
    seasonMatches: number;
  }> {
    if (!this.db || !courtId) {
      return { points: 0, matches: 0, seasonPoints: 0, seasonMatches: 0 };
    }
    const rows = await this.notion.queryDatabaseAll(this.db, {
      filter: NotionService.filterAnd([
        NotionService.filterTitle('Email', email),
        NotionService.filterText('CourtId', courtId),
      ]),
    });
    const season = seasonStart();
    let points = 0;
    let seasonPoints = 0;
    let seasonMatches = 0;
    for (const r of rows) {
      const pts = NotionService.readInt(r.properties, 'Points');
      points += pts;
      const ended = NotionService.readDate(r.properties, 'EndedAt');
      if (ended && new Date(ended) >= season) {
        seasonPoints += pts;
        seasonMatches++;
      }
    }
    return { points, matches: rows.length, seasonPoints, seasonMatches };
  }
}

// ── Controller ──────────────────────────────────────────────────────────────

@Controller('matches')
@UseGuards(JwtAuthGuard)
class MatchesController {
  constructor(private readonly matches: MatchesService) {}

  @Post()
  upload(@CurrentUser() user: AuthUser, @Body() dto: UploadMatchesDto) {
    return this.matches.upload(user.email, dto.matches);
  }

  @Get('mine')
  mine(@CurrentUser() user: AuthUser) {
    return this.matches.mine(user.email);
  }

  @Get('court-king')
  courtKing(@Query('courtId') courtId: string) {
    return this.matches.courtKing((courtId ?? '').trim());
  }

  @Get('court-points')
  courtPoints(@CurrentUser() user: AuthUser, @Query('courtId') courtId: string) {
    return this.matches.courtPoints(user.email, (courtId ?? '').trim());
  }

  @Get('ranking')
  ranking(@Query('since') since: string, @Query('emails') emails: string) {
    const list = (emails ?? '')
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .filter((s) => s.length > 0);
    return this.matches.ranking(since ?? '', list);
  }
}

@Module({
  controllers: [MatchesController],
  providers: [MatchesService],
})
export class MatchesModule {}
