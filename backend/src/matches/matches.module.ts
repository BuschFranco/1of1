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

  /** Sube un lote de partidos resueltos. El email sale del token (title). Devuelve
   * ok/err por ítem (el cliente reintenta los fallidos). */
  async upload(
    email: string,
    items: MatchItemDto[],
  ): Promise<{ results: { ok: boolean }[] }> {
    if (!this.db) return { results: items.map(() => ({ ok: false })) };
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
        });
        results.push({ ok: true });
      } catch {
        results.push({ ok: false });
      }
    }
    return { results };
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
