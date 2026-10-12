import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  Param,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  ArrayMaxSize,
  IsArray,
  IsInt,
  IsObject,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { PrismaService } from '../prisma/prisma.module';

// Respaldo en la base de lo que la app guardaba SOLO en el teléfono: el historial
// de sesiones de juego y un puñado de listas chicas. Si el usuario reinstala o
// cambia de celular, al loguear la app lo vuelve a bajar.
//
// ── Lo que este módulo NO guarda: DATOS DE SALUD ─────────────────────────────
// Pulso, calorías, pasos, distancia, zonas, oxígeno, variabilidad cardíaca, etc.
// quedan únicamente en el dispositivo; así lo declara la política de privacidad y
// el formulario de Seguridad de datos de Play. La app ya no los manda, pero acá
// se aplica una LISTA BLANCA ([sanitizeSessionData]) que descarta cualquier otra
// clave: un bug futuro en el cliente no puede filtrar salud al servidor.
//
// No se toca la tabla `matches`: los rankings, los clanes y el rey de la cancha
// leen de ahí. Esta es aparte y con unicidad, para que reintentar sea seguro.

const MAX_BATCH = 50;
const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 200;

// ── Sanitización (lista blanca) ─────────────────────────────────────────────

const RESULTS = ['win', 'loss', 'tie', 'notCounted', 'training'];

/** Entero acotado, o null si no es un número entero válido. */
function bounded(v: unknown, min: number, max: number): number | null {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  const n = Math.trunc(v);
  return n < min || n > max ? null : n;
}

function text(v: unknown, max: number): string | null {
  return typeof v === 'string' ? v.trim().slice(0, max) : null;
}

/** Arreglo de enteros acotados (máx. [maxLen] elementos); descarta los inválidos. */
function ints(v: unknown, maxLen: number, min: number, max: number): number[] | null {
  if (!Array.isArray(v)) return null;
  return v
    .slice(0, maxLen)
    .map((x) => bounded(x, min, max))
    .filter((x): x is number => x !== null);
}

/**
 * Deja pasar SOLO las claves conocidas del historial de una sesión, con tipo y
 * rango validados. Todo lo demás —incluida cualquier métrica de salud— se
 * descarta en silencio. Devuelve null si el payload ni siquiera es un objeto.
 *
 * Las claves son las mismas que `PlaySession.toSyncJson` de la app.
 */
export function sanitizeSessionData(raw: unknown): Record<string, unknown> | null {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const out: Record<string, unknown> = {};

  const courtId = text(r.courtId, 80);
  if (courtId !== null) out.courtId = courtId;
  const courtName = text(r.courtName, 120);
  if (courtName !== null) out.courtName = courtName;

  const seconds = bounded(r.seconds, 0, 48 * 3600);
  if (seconds !== null) out.seconds = seconds;
  // EXP ganada por la sesión.
  const points = bounded(r.points, 0, 100000);
  if (points !== null) out.points = points;

  if (typeof r.result === 'string' && RESULTS.includes(r.result)) out.result = r.result;

  // Lo que anotó el usuario: total y desglose por VALOR del tiro (u3 = puntos
  // anotados en tiros de 3, etc.; `uFT` es el nombre histórico de "de 1").
  for (const k of ['uPts', 'u3', 'u2', 'uFT'] as const) {
    const n = bounded(r[k], 0, 20000);
    if (n !== null) out[k] = n;
  }

  // Desglose de la sesión: partidos, entrenamientos y victorias (la app los
  // limita a 12 cada uno).
  for (const k of ['nMatches', 'nTrainings', 'nWins'] as const) {
    const n = bounded(r[k], 0, 12);
    if (n !== null) out[k] = n;
  }
  const gamePts = ints(r.gamePts, 12, 0, 20000);
  if (gamePts !== null && gamePts.length > 0) out.gamePts = gamePts;
  const gameFmt = ints(r.gameFmt, 12, 1, 5);
  if (gameFmt !== null && gameFmt.length > 0) out.gameFmt = gameFmt;

  // Secciones que el usuario ocultó solo para esta sesión (override). Un arreglo
  // vacío significa "esta sesión muestra todo", distinto de ausente.
  if (Array.isArray(r.hidden)) {
    out.hidden = r.hidden
      .slice(0, 12)
      .map((x) => text(x, 24))
      .filter((x): x is string => !!x);
  }
  return out;
}

// ── Listas chicas por usuario ───────────────────────────────────────────────

const KINDS = ['streak_history', 'favorites', 'blocked'] as const;
type Kind = (typeof KINDS)[number];

function isKind(v: string): v is Kind {
  return (KINDS as readonly string[]).includes(v);
}

/** Normaliza el contenido de un `kind`; null si el formato no corresponde. */
function sanitizeKindData(kind: Kind, raw: unknown): unknown[] | null {
  if (!Array.isArray(raw)) return null;
  const list = raw.slice(0, 500);
  if (kind === 'streak_history') {
    return list
      .map((e) => {
        if (typeof e !== 'object' || e === null) return null;
        const o = e as Record<string, unknown>;
        const endedAt = bounded(o.endedAt, 1, 8_640_000_000_000_000);
        const wins = bounded(o.wins, 0, 100000);
        return endedAt !== null && wins !== null ? { endedAt, wins } : null;
      })
      .filter((e) => e !== null);
  }
  // favorites (ids de cancha) y blocked (emails normalizados): strings únicos.
  const max = kind === 'favorites' ? 80 : 160;
  const seen = new Set<string>();
  for (const e of list) {
    const s = text(e, max);
    if (s) seen.add(kind === 'blocked' ? s.toLowerCase() : s);
  }
  return [...seen];
}

// ── DTOs ────────────────────────────────────────────────────────────────────

class SessionItemDto {
  /** Epoch en ms del fin de la sesión: es su IDENTIDAD. Un entero no tiene la
   * ambigüedad de huso horario que sí tiene la fecha ingenua de `/matches`. */
  @IsInt() @Min(1) endedAtMs!: number;
  @IsObject() data!: Record<string, unknown>;
}

class UploadSessionsDto {
  @IsArray()
  @ArrayMaxSize(MAX_BATCH)
  @ValidateNested({ each: true })
  @Type(() => SessionItemDto)
  sessions!: SessionItemDto[];
}

class PutDataDto {
  @IsArray() data!: unknown[];
}

// ── Service ───────────────────────────────────────────────────────────────

@Injectable()
class SyncService {
  constructor(private readonly prisma: PrismaService) {}

  /** Siempre en minúsculas: así coincide con `deleteAccount`, que normaliza
   * igual (el `matches.upload` no lo hace, y esa discrepancia no se repite). */
  private norm(email: string): string {
    return email.trim().toLowerCase();
  }

  /** Sube un lote. `upsert` por (email, endedAtMs): reintentar la misma sesión
   * —incluso tras perder la respuesta— NO duplica. Devuelve ok/err por ítem,
   * alineado por posición, y el cliente reintenta los fallidos. */
  async upsertSessions(
    emailRaw: string,
    items: SessionItemDto[],
  ): Promise<{ results: { ok: boolean }[] }> {
    const email = this.norm(emailRaw);
    const now = Date.now();
    const results: { ok: boolean }[] = [];
    for (const it of items) {
      try {
        // Rechaza fechas absurdas: ni anteriores a 2020 ni del futuro lejano.
        if (it.endedAtMs < 1577836800000 || it.endedAtMs > now + 86_400_000) {
          results.push({ ok: false });
          continue;
        }
        const data = sanitizeSessionData(it.data);
        if (!data) {
          results.push({ ok: false });
          continue;
        }
        const json = data as unknown as Prisma.InputJsonValue;
        await this.prisma.playSession.upsert({
          where: { email_endedAtMs: { email, endedAtMs: BigInt(it.endedAtMs) } },
          create: { email, endedAtMs: BigInt(it.endedAtMs), data: json },
          // No se resucita `archived`: si la cuenta se borró, lo borrado sigue
          // borrado aunque el cliente vuelva a mandar la misma sesión.
          update: { data: json },
        });
        results.push({ ok: true });
      } catch {
        results.push({ ok: false });
      }
    }
    return { results };
  }

  /** Sesiones del usuario, más nuevas primero. `before` (epoch ms) pagina. */
  async listSessions(emailRaw: string, limit: number, before?: number) {
    const rows = await this.prisma.playSession.findMany({
      where: {
        email: this.norm(emailRaw),
        archived: false,
        ...(before ? { endedAtMs: { lt: BigInt(before) } } : {}),
      },
      orderBy: { endedAtMs: 'desc' },
      take: limit,
      select: { endedAtMs: true, data: true },
    });
    return {
      // BigInt no es serializable a JSON: los epoch en ms entran de sobra en un
      // Number (límite seguro ≈ 9×10^15).
      sessions: rows.map((r) => ({
        endedAtMs: Number(r.endedAtMs),
        data: sanitizeSessionData(r.data) ?? {},
      })),
    };
  }

  /** Todas las listas del usuario. Un `kind` AUSENTE significa "nunca se
   * sincronizó"; uno vacío significa "el usuario lo vació". La app necesita
   * distinguirlos para no pisar lo local con una lista que nunca existió. */
  async getData(emailRaw: string): Promise<Record<string, unknown[]>> {
    const rows = await this.prisma.userData.findMany({
      where: { email: this.norm(emailRaw), archived: false },
      select: { kind: true, data: true },
    });
    const out: Record<string, unknown[]> = {};
    for (const r of rows) {
      if (isKind(r.kind) && Array.isArray(r.data)) out[r.kind] = r.data as unknown[];
    }
    return out;
  }

  /** Reemplaza el contenido de un `kind`. */
  async putData(emailRaw: string, kind: string, data: unknown[]) {
    if (!isKind(kind)) throw new BadRequestException('Tipo de dato inválido.');
    const clean = sanitizeKindData(kind, data);
    if (!clean) throw new BadRequestException('Formato inválido.');
    const email = this.norm(emailRaw);
    const json = clean as unknown as Prisma.InputJsonValue;
    await this.prisma.userData.upsert({
      where: { email_kind: { email, kind } },
      create: { email, kind, data: json },
      // Reemplazo total: si la fila quedó archivada por un borrado de cuenta y el
      // mismo email se vuelve a registrar, el contenido nuevo la reemplaza.
      update: { data: json, archived: false },
    });
    return { ok: true, count: clean.length };
  }
}

// ── Controller ──────────────────────────────────────────────────────────────

@Controller('sync')
@UseGuards(JwtAuthGuard)
class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post('sessions')
  upload(@CurrentUser() user: AuthUser, @Body() dto: UploadSessionsDto) {
    return this.sync.upsertSessions(user.email, dto.sessions);
  }

  @Get('sessions')
  sessions(
    @CurrentUser() user: AuthUser,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    const n = Math.min(Math.max(parseInt(limit ?? '', 10) || DEFAULT_LIMIT, 1), MAX_LIMIT);
    const b = parseInt(before ?? '', 10);
    return this.sync.listSessions(user.email, n, Number.isFinite(b) && b > 0 ? b : undefined);
  }

  @Get('data')
  data(@CurrentUser() user: AuthUser) {
    return this.sync.getData(user.email);
  }

  @Put('data/:kind')
  putData(
    @CurrentUser() user: AuthUser,
    @Param('kind') kind: string,
    @Body() dto: PutDataDto,
  ) {
    return this.sync.putData(user.email, kind, dto.data);
  }
}

@Module({
  controllers: [SyncController],
  providers: [SyncService],
})
export class SyncModule {}
