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
import { parseUtc } from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';
import { seasonStart } from '../season';

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
  constructor(private readonly prisma: PrismaService) {}

  /** Insignia de clan ACTUAL del autor, normalizada (misma regla que
   * clans/rankings: trim + mayúsculas). Vacía si no tiene clan. */
  private async currentClan(email: string): Promise<string> {
    const p = await this.prisma.profile.findFirst({
      where: { userEmail: email, archived: false },
      select: { clan: true },
    });
    return (p?.clan ?? '').trim().toUpperCase();
  }

  /** Sube un lote de partidos resueltos. El email sale del token. Devuelve
   * ok/err por ítem (el cliente reintenta los fallidos). Cada fila queda
   * estampada con el clan del autor al momento de subir: los puntos de clan no
   * migran cuando el usuario se cambia de insignia. */
  async upload(
    email: string,
    items: MatchItemDto[],
  ): Promise<{ results: { ok: boolean }[] }> {
    const clan = await this.currentClan(email);
    const results: { ok: boolean }[] = [];
    for (const m of items) {
      try {
        const endedAt = parseUtc(m.endedAt);
        if (!endedAt) throw new Error('endedAt inválido');
        await this.prisma.match.create({
          data: {
            email,
            points: m.points,
            endedAt,
            courtId: m.courtId ?? '',
            courtName: m.courtName ?? '',
            result: m.result ?? '',
            seconds: m.seconds ?? 0,
            clan,
          },
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
    const rows = await this.prisma.match.findMany({
      where: { email, archived: false },
      select: { endedAt: true },
      orderBy: { endedAt: 'desc' },
    });
    return { endedAt: rows.map((r) => r.endedAt.toISOString()) };
  }

  /** Jugador con más puntos en la cancha EN LA TEMPORADA ACTUAL ("rey de la
   * cancha"). Se reinicia cada temporada, igual que la conquista de clan. */
  async courtKing(
    courtId: string,
  ): Promise<{ king: { name: string; handle: string; points: number } | null }> {
    if (!courtId) return { king: null };
    const top = await this.prisma.match.groupBy({
      by: ['email'],
      where: { courtId, endedAt: { gte: seasonStart() }, archived: false },
      _sum: { points: true },
      orderBy: { _sum: { points: 'desc' } },
      take: 1,
    });
    const email = top[0]?.email ?? '';
    const points = top[0]?._sum.points ?? 0;
    if (!email || points <= 0) return { king: null };
    const p = await this.prisma.profile.findFirst({
      where: { userEmail: email, archived: false },
      select: { name: true, handle: true },
    });
    return {
      king: {
        name: p?.name || email.split('@')[0],
        handle: p?.handle ?? '',
        points,
      },
    };
  }

  /** Puntos del usuario en una cancha: total histórico Y de la temporada
   * actual por separado (para el detalle de cancha). */
  async courtPoints(
    email: string,
    courtId: string,
  ): Promise<{
    points: number;
    matches: number;
    seasonPoints: number;
    seasonMatches: number;
  }> {
    if (!courtId) {
      return { points: 0, matches: 0, seasonPoints: 0, seasonMatches: 0 };
    }
    const season = seasonStart();
    const rows = await this.prisma.match.findMany({
      where: { email, courtId, archived: false },
      select: { points: true, endedAt: true },
    });
    let points = 0;
    let seasonPoints = 0;
    let seasonMatches = 0;
    for (const r of rows) {
      points += r.points;
      if (r.endedAt >= season) {
        seasonPoints += r.points;
        seasonMatches++;
      }
    }
    return { points, matches: rows.length, seasonPoints, seasonMatches };
  }

  /** Puntos por email desde [since] (ISO) para los emails dados. Agrupa y suma
   * server-side. */
  async ranking(
    since: string,
    emails: string[],
  ): Promise<{ email: string; points: number }[]> {
    const start = parseUtc(since);
    if (!start || emails.length === 0) return [];
    const capped = emails.slice(0, 100);
    const rows = await this.prisma.match.groupBy({
      by: ['email'],
      where: {
        email: { in: capped },
        endedAt: { gte: start },
        archived: false,
      },
      _sum: { points: true },
    });
    return rows.map((r) => ({ email: r.email, points: r._sum.points ?? 0 }));
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
