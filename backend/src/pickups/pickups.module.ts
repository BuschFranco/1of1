import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { Prisma } from '@prisma/client';
import { Query } from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import {
  chatWire,
  CrewChat,
  parseUtc,
  Pickup,
  pickupWire,
  rewardsFromDb,
  settingsFromDb,
} from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';

/** Un pickup se considera TERMINADO 24 h después de su fecha/hora. Es la regla
 * de retención (el pickup y su chat se borran un día después del partido) y la
 * usan: unirse (`addMember`), el listado público, y el límite de un pickup
 * activo por creador (`create`). Su gemela en la app es `Pickup.isExpired`. */
const PICKUP_TTL_MS = 24 * 60 * 60 * 1000;

/** Cuánto ocupa la cancha un pickup, contado desde su horario de inicio.
 * `Pickup` no tiene campo de duración a propósito: es un bloque fijo. Se manda
 * al cliente en `availability()` para que el picker no duplique el número. */
const PICKUP_SLOT_MS = 90 * 60 * 1000;

/** Aros que consume un pickup según su formato: un **5v5 es cancha completa**
 * (usa los dos aros) y un **4v4 o menos es media cancha** (uno solo). Por eso
 * una cancha de 4 aros aguanta 2 partidos de 5v5 o 4 de 4v4.
 *
 * Se clampea a [capacity] para que un 5v5 siga siendo creable en una cancha de
 * un aro (ocupándola entera) en vez de quedar prohibido para siempre. */
function hoopCost(teamSize: number, capacity: number): number {
  return Math.min(teamSize >= 5 ? 2 : 1, capacity);
}

// ── DTOs ────────────────────────────────────────────────────────────────────

/** Recompensa de un pickup (opcional, 1 por tipo): monetaria (monto en ARS),
 * indumentaria o accesorios (qué es). Validación anidada con class-validator. */
class PickupRewardDto {
  @IsIn(['monetaria', 'indumentaria', 'accesorios', 'otro'])
  type!: string;

  @IsOptional() @IsInt() @Min(1) amount?: number;

  @IsOptional() @IsString() @MaxLength(40) detail?: string;
}

/** Configuración personalizada del pickup (informativa). La normalización
 * fina (clamps, descarte de inválidos) la hace settingsFromDb. */
class PickupSettingDto {
  @IsIn(['edad', 'altura', 'peso', 'nivel', 'modalidad', 'marca', 'precio_entrada'])
  type!: string;

  @IsOptional() @IsInt() @Min(1) min?: number;
  @IsOptional() @IsInt() @Min(1) minCm?: number;
  @IsOptional() @IsInt() @Min(1) maxKg?: number;

  @IsOptional()
  @IsIn(['profesional', 'amateur', 'competencia', 'casual'])
  value?: string;

  @IsOptional() @IsString() @MaxLength(40) brand?: string;
  @IsOptional() @IsBoolean() useKit?: boolean;
}

class CreatePickupDto {
  @IsString() title!: string;
  @IsString() courtId!: string;
  // Fecha/hora obligatoria: el pickup necesita cuándo (chat, recordatorios y
  // detalle público se apoyan en la fecha).
  @IsString() dateTime!: string;
  @IsOptional() @IsInt() @Min(2) @Max(50) maxPlayers?: number;
  @IsOptional() @IsString() vibe?: string;
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsInt() @Min(1) @Max(10) teamSize?: number;
  @IsOptional() @IsString() teamAName?: string;
  @IsOptional() @IsString() teamBName?: string;
  @IsOptional() @IsString() teamAColor?: string;
  @IsOptional() @IsString() teamBColor?: string;
  @IsOptional() @IsArray() @IsString({ each: true }) teamAMembers?: string[];
  @IsOptional() @IsArray() @IsString({ each: true }) teamBMembers?: string[];
  @IsOptional() @IsInt() @Min(1) targetScore?: number;
  @IsOptional() @IsArray() @IsString({ each: true }) acceptedMembers?: string[];
  @IsOptional() @IsArray() @IsString({ each: true }) declinedMembers?: string[];
  @IsOptional() @IsBoolean() isPublic?: boolean;
  @IsOptional() @IsArray() @ValidateNested({ each: true })
  @Type(() => PickupRewardDto)
  rewards?: PickupRewardDto[];
  @IsOptional() @IsArray() @ValidateNested({ each: true })
  @Type(() => PickupSettingDto)
  settings?: PickupSettingDto[];
}

// Update: todos opcionales (cubre aceptar/rechazar/mover/quitar/abandonar/reenviar).
class UpdatePickupDto {
  @IsOptional() @IsString() title?: string;
  @IsOptional() @IsString() dateTime?: string;
  @IsOptional() @IsInt() @Min(2) @Max(50) maxPlayers?: number;
  @IsOptional() @IsString() vibe?: string;
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsInt() @Min(1) @Max(10) teamSize?: number;
  @IsOptional() @IsString() teamAName?: string;
  @IsOptional() @IsString() teamBName?: string;
  @IsOptional() @IsString() teamAColor?: string;
  @IsOptional() @IsString() teamBColor?: string;
  @IsOptional() @IsArray() @IsString({ each: true }) teamAMembers?: string[];
  @IsOptional() @IsArray() @IsString({ each: true }) teamBMembers?: string[];
  @IsOptional() @IsInt() @Min(1) targetScore?: number;
  @IsOptional() @IsArray() @IsString({ each: true }) acceptedMembers?: string[];
  @IsOptional() @IsArray() @IsString({ each: true }) declinedMembers?: string[];
  @IsOptional() @IsBoolean() isPublic?: boolean;
  @IsOptional() @IsArray() @ValidateNested({ each: true })
  @Type(() => PickupRewardDto)
  rewards?: PickupRewardDto[];
  @IsOptional() @IsArray() @ValidateNested({ each: true })
  @Type(() => PickupSettingDto)
  settings?: PickupSettingDto[];
}

class JoinPickupDto {
  @IsString() @Length(5, 5) code!: string;
}

class JoinPublicPickupDto {
  @IsString() pickupId!: string;
}

class SendMessageDto {
  @IsString() @Length(1, 500) text!: string;
}

class CreateChatDto {
  @IsString() name!: string;
  @IsString() pickupId!: string;
  @IsOptional() @IsString() date?: string;
  @IsOptional() @IsString() teamAName?: string;
  @IsOptional() @IsString() teamBName?: string;
  @IsOptional() @IsString() teamAColor?: string;
  @IsOptional() @IsString() teamBColor?: string;
  @IsOptional() @IsString() lastMessage?: string;
}

// ── Service ───────────────────────────────────────────────────────────────

@Injectable()
class PickupsService {
  constructor(private readonly prisma: PrismaService) {}

  private eq(a: string, b: string): boolean {
    return a.trim().toLowerCase() === b.trim().toLowerCase();
  }

  /** Código de invitación de 5 dígitos (10000–99999). */
  private genInviteCode(): string {
    return (Math.floor(Math.random() * 90000) + 10000).toString();
  }

  /** Pickups donde el usuario es creador o miembro de un equipo. */
  async listForUser(email: string): Promise<Pickup[]> {
    const e = email.trim().toLowerCase();
    const rows = await this.prisma.pickup.findMany({
      where: {
        archived: false,
        OR: [
          { createdBy: e },
          { teamAMembers: { has: e } },
          { teamBMembers: { has: e } },
        ],
      },
    });
    return rows.map(pickupWire);
  }

  private async getById(pageId: string): Promise<Pickup> {
    const row = await this.prisma.pickup.findUnique({ where: { id: pageId } });
    if (!row || row.archived) {
      throw new NotFoundException('Pickup no encontrado.');
    }
    return pickupWire(row);
  }

  /** Capacidad de la cancha en aros. Mínimo 1: hay filas viejas en 0 y con 0
   * no se podría crear nada. */
  private async courtCapacity(courtId: string): Promise<number> {
    const court = await this.prisma.court.findUnique({
      where: { id: courtId },
      select: { hoops: true },
    });
    return Math.max(1, court?.hoops ?? 1);
  }

  /** Valida que el horario tenga lugar en la cancha: la suma de aros de los
   * pickups que se solapan no puede superar la capacidad.
   *
   * Como todos los pickups ocupan el mismo bloque (`PICKUP_SLOT_MS`), dos se
   * solapan exactamente cuando sus inicios distan menos de un bloque — así que
   * el rango de la query YA es el test de solapamiento, sin filtrado extra.
   *
   * [excludeId] es el propio pickup al reprogramar: no debe chocar consigo mismo.
   */
  private async assertSlotLibre(
    courtId: string,
    startsAt: Date,
    teamSize: number,
    excludeId?: string,
  ): Promise<void> {
    const capacity = await this.courtCapacity(courtId);
    const start = startsAt.getTime();
    const rows = await this.prisma.pickup.findMany({
      where: {
        courtId,
        archived: false,
        ...(excludeId && { id: { not: excludeId } }),
        dateTime: {
          gt: new Date(start - PICKUP_SLOT_MS),
          lt: new Date(start + PICKUP_SLOT_MS),
        },
      },
      select: { teamSize: true },
    });
    const usados = rows.reduce(
      (acc, r) => acc + hoopCost(r.teamSize, capacity),
      0,
    );
    if (usados + hoopCost(teamSize, capacity) > capacity) {
      throw new ForbiddenException(
        'Ese horario ya está ocupado en esta cancha. Elegí otro.',
      );
    }
  }

  /** Horarios ocupados de una cancha en un día, para pintar el picker.
   *
   * Devuelve SOLO tiempos y aros: nada de títulos, creadores ni ids. Un pickup
   * privado no debe filtrar más que "la cancha está ocupada a tal hora".
   *
   * [dateIso] es el día en `YYYY-MM-DD`. Los límites se calculan en UTC porque
   * las fechas se guardan como reloj de pared en UTC (ver `parseUtc`).
   */
  async availability(
    courtId: string,
    dateIso: string,
    excludePickupId?: string,
  ): Promise<{
    hoops: number;
    slotMinutes: number;
    busy: { startsAt: string; hoops: number }[];
  }> {
    const capacity = await this.courtCapacity(courtId);
    const from = parseUtc(`${dateIso.trim().slice(0, 10)}T00:00:00`);
    if (!from) {
      return { hoops: capacity, slotMinutes: PICKUP_SLOT_MS / 60000, busy: [] };
    }
    const to = new Date(from.getTime() + 24 * 60 * 60 * 1000);
    const rows = await this.prisma.pickup.findMany({
      where: {
        courtId,
        archived: false,
        ...(excludePickupId && { id: { not: excludePickupId } }),
        // ±1 bloque para captar los que se derraman del día anterior/siguiente.
        dateTime: {
          gt: new Date(from.getTime() - PICKUP_SLOT_MS),
          lt: new Date(to.getTime() + PICKUP_SLOT_MS),
        },
      },
      select: { dateTime: true, teamSize: true },
      orderBy: { dateTime: 'asc' },
    });
    return {
      hoops: capacity,
      slotMinutes: PICKUP_SLOT_MS / 60000,
      busy: rows
        .filter((r) => r.dateTime !== null)
        .map((r) => ({
          startsAt: r.dateTime!.toISOString(),
          hoops: hoopCost(r.teamSize, capacity),
        })),
    };
  }

  async create(createdBy: string, dto: CreatePickupDto): Promise<Pickup> {
    const e = createdBy.trim().toLowerCase();
    const teamSize = dto.teamSize ?? 3;
    const startsAt = parseUtc(dto.dateTime);

    // Un pickup activo por creador: hasta que el suyo no termine (o lo elimine)
    // no puede abrir otro. Se valida acá porque el cliente puede quedar con la
    // lista desactualizada; el guard de la app es solo para avisar antes.
    const activo = await this.prisma.pickup.findFirst({
      where: {
        archived: false,
        createdBy: { equals: e, mode: 'insensitive' },
        // Activo = sin fecha (legacy, nunca expira) o dentro de la ventana de
        // 24 h posteriores al partido.
        OR: [
          { dateTime: null },
          { dateTime: { gte: new Date(Date.now() - PICKUP_TTL_MS) } },
        ],
      },
    });
    if (activo) {
      throw new ForbiddenException(
        'Ya tenés un pickup activo. Vas a poder crear otro cuando termine, o si lo eliminás.',
      );
    }

    // No pisar el horario de otro pickup en la misma cancha.
    if (startsAt) {
      await this.assertSlotLibre(dto.courtId, startsAt, teamSize);
    }

    // El creador SIEMPRE participa: va al Equipo A (el de menos miembros si A
    // está lleno). Los contadores de la app (jugadores, cupo, equipos del chat)
    // se leen de estas listas, así que sin esto un pickup recién creado figura
    // con 0 jugadores. Dedup case-insensitive por si el cliente ya lo mandó.
    const teamA = [...(dto.teamAMembers ?? [])].filter((m) => !this.eq(m, e));
    const teamB = [...(dto.teamBMembers ?? [])].filter((m) => !this.eq(m, e));
    // El creador elige su equipo: se respeta dónde lo mandó el cliente (A o
    // B). Si no lo mandó (clientes viejos), cae al equipo con lugar (A primero).
    const askedA = (dto.teamAMembers ?? []).some((m) => this.eq(m, e));
    const askedB = (dto.teamBMembers ?? []).some((m) => this.eq(m, e));
    const creatorToA = askedB ? false : askedA ? true : teamA.length < teamSize;
    const accepted = [
      e,
      ...(dto.acceptedMembers ?? []).filter((m) => !this.eq(m, e)),
    ];
    const row = await this.prisma.pickup.create({
      data: {
        title: dto.title,
        courtId: dto.courtId,
        createdBy,
        dateTime: startsAt,
        maxPlayers: dto.maxPlayers ?? 10,
        vibe: dto.vibe ?? 'Casual',
        notes: dto.notes ?? '',
        teamSize,
        teamAName: dto.teamAName ?? 'Equipo A',
        teamBName: dto.teamBName ?? 'Equipo B',
        teamAColor: dto.teamAColor ?? '#FF6B1A',
        teamBColor: dto.teamBColor ?? '#3B82F6',
        teamAMembers: creatorToA ? [e, ...teamA] : teamA,
        teamBMembers: creatorToA ? teamB : [e, ...teamB],
        targetScore: dto.targetScore ?? 21,
        acceptedMembers: accepted,
        declinedMembers: (dto.declinedMembers ?? []).filter((m) => !this.eq(m, e)),
        isPublic: dto.isPublic ?? false,
        // rewards: el DTO valida forma; acá se normaliza (reglas cruzadas:
        // monetaria exige amount, el resto detail; 1 solo reward por tipo).
        rewards: rewardsFromDb(dto.rewards ?? []) as unknown as Prisma.InputJsonValue,
        // settings: requisitos/configs personalizadas (informativos), 1 por tipo.
        settings: settingsFromDb(dto.settings ?? []) as unknown as Prisma.InputJsonValue,
        // El código lo genera el server (autoritativo), no el cliente.
        inviteCode: this.genInviteCode(),
      },
    });
    return pickupWire(row);
  }

  /** Actualiza solo los campos provistos. Solo creador o miembro. Cubre
   * aceptar/rechazar/mover/quitar/abandonar/reenviar. */
  async update(
    pageId: string,
    email: string,
    dto: UpdatePickupDto,
  ): Promise<Pickup> {
    const cur = await this.getById(pageId);
    const isMember =
      this.eq(cur.createdBy, email) ||
      cur.teamAMembers.some((m) => this.eq(m, email)) ||
      cur.teamBMembers.some((m) => this.eq(m, email));
    if (!isMember) {
      throw new ForbiddenException('No participás de este pickup.');
    }
    // Reprogramar tampoco puede pisar a otro: sin esto, el chat del pickup sería
    // una puerta de atrás para saltear la validación de create(). Se excluye a sí
    // mismo, si no chocaría con su propio horario actual.
    //
    // OJO: solo se valida si la fecha REALMENTE cambia. La app manda el pickup
    // entero en cada PATCH (aceptar, rechazar, mover jugadores...), así que
    // validar por `!== undefined` haría fallar esas acciones en pickups que hoy
    // ya están solapados — nada lo impedía antes de esta regla.
    if (dto.dateTime !== undefined) {
      const startsAt = parseUtc(dto.dateTime);
      const actual = parseUtc(cur.dateTime);
      const cambia = startsAt?.getTime() !== actual?.getTime();
      if (startsAt && cambia) {
        await this.assertSlotLibre(
          cur.courtId,
          startsAt,
          dto.teamSize ?? cur.teamSize,
          pageId,
        );
      }
    }
    const row = await this.prisma.pickup.update({
      where: { id: pageId },
      data: {
        // courtId, createdBy e inviteCode son inmutables.
        ...(dto.title !== undefined && { title: dto.title }),
        ...(dto.dateTime !== undefined && { dateTime: parseUtc(dto.dateTime) }),
        ...(dto.maxPlayers !== undefined && { maxPlayers: dto.maxPlayers }),
        ...(dto.vibe !== undefined && { vibe: dto.vibe }),
        ...(dto.notes !== undefined && { notes: dto.notes }),
        ...(dto.teamSize !== undefined && { teamSize: dto.teamSize }),
        ...(dto.teamAName !== undefined && { teamAName: dto.teamAName }),
        ...(dto.teamBName !== undefined && { teamBName: dto.teamBName }),
        ...(dto.teamAColor !== undefined && { teamAColor: dto.teamAColor }),
        ...(dto.teamBColor !== undefined && { teamBColor: dto.teamBColor }),
        ...(dto.teamAMembers !== undefined && { teamAMembers: dto.teamAMembers }),
        ...(dto.teamBMembers !== undefined && { teamBMembers: dto.teamBMembers }),
        ...(dto.targetScore !== undefined && { targetScore: dto.targetScore }),
        ...(dto.acceptedMembers !== undefined && {
          acceptedMembers: dto.acceptedMembers,
        }),
        ...(dto.declinedMembers !== undefined && {
          declinedMembers: dto.declinedMembers,
        }),
        ...(dto.isPublic !== undefined && { isPublic: dto.isPublic }),
        ...(dto.rewards !== undefined && {
          rewards: rewardsFromDb(dto.rewards) as unknown as Prisma.InputJsonValue,
        }),
        // Solo si dto.settings vino definido: los PATCH de aceptar/mover/etc.
        // reenvían parte del pickup y no deben pisar las configs existentes.
        ...(dto.settings !== undefined && {
          settings: settingsFromDb(dto.settings) as unknown as Prisma.InputJsonValue,
        }),
      },
    });
    return pickupWire(row);
  }

  /** Unirse por código: entra al equipo con el espacio (el de menos miembros
   * primero), como miembro aceptado. */
  async join(code: string, email: string): Promise<Pickup> {
    const e = email.trim().toLowerCase();
    const row = await this.prisma.pickup.findFirst({
      where: { inviteCode: code.trim(), archived: false },
    });
    if (!row) {
      throw new NotFoundException('Código inválido. Revisá los 5 dígitos.');
    }
    const p = pickupWire(row);
    return this.addMember(p, e);
  }

  /** Pickups públicos (abiertos, sin invitación) de una cancha, no vencidos.
   * Devuelve los próximos primero (sin fecha al final). Los pickups del propio
   * usuario se incluyen igual: el cliente los marca como suyos. */
  async listPublicForCourt(courtId: string): Promise<Pickup[]> {
    const rows = await this.prisma.pickup.findMany({
      where: { courtId, archived: false, isPublic: true },
      orderBy: { dateTime: 'asc' },
    });
    return rows
      .filter((p) => {
        const d = p.dateTime ? Date.parse(p.dateTime.toISOString()) : NaN;
        return Number.isNaN(d) || Date.now() <= d + PICKUP_TTL_MS;
      })
      .map(pickupWire);
  }

  /** Unirse a un pickup PÚBLICO por id (sin código): validaciones idénticas a
   * join() salvo que el pickup tiene que ser público y no hace falta el código. */
  async joinById(pageId: string, email: string): Promise<Pickup> {
    const p = await this.getById(pageId);
    if (!p.isPublic) {
      throw new ForbiddenException(
        'Este pickup no es público: unite con el código de invitación.',
      );
    }
    return this.addMember(p, email);
  }

  /** Valida y agrega a [email] a un pickup: expiración, propio, ya-miembro,
   * capacidad y alta en el equipo con espacio (como miembro aceptado). */
  private async addMember(p: Pickup, email: string): Promise<Pickup> {
    const e = email.trim().toLowerCase();

    // Expirado (24h después del horario)?
    const d = p.dateTime ? Date.parse(p.dateTime) : NaN;
    if (!Number.isNaN(d) && Date.now() > d + PICKUP_TTL_MS) {
      throw new ForbiddenException('Ese pickup ya terminó.');
    }
    if (this.eq(p.createdBy, e)) {
      throw new ForbiddenException('Este pickup es tuyo 🙂');
    }
    const inA = p.teamAMembers.some((m) => this.eq(m, e));
    const inB = p.teamBMembers.some((m) => this.eq(m, e));
    if (inA || inB) {
      // Ya es miembro: si estaba pendiente, aceptar; si no, error.
      if (!p.acceptedMembers.some((m) => this.eq(m, e))) {
        const updated = await this.prisma.pickup.update({
          where: { id: p.pageId },
          data: {
            acceptedMembers: [
              ...p.acceptedMembers.filter((m) => !this.eq(m, e)),
              e,
            ],
          },
        });
        return pickupWire(updated);
      }
      throw new ForbiddenException('Ya estás en este pickup.');
    }
    const aFree = p.teamAMembers.length < p.teamSize;
    const bFree = p.teamBMembers.length < p.teamSize;
    if (!aFree && !bFree) {
      throw new ForbiddenException('El pickup ya está completo.');
    }
    const toA =
      aFree && (!bFree || p.teamAMembers.length <= p.teamBMembers.length);
    const updated = await this.prisma.pickup.update({
      where: { id: p.pageId },
      data: {
        teamAMembers: toA ? [...p.teamAMembers, e] : p.teamAMembers,
        teamBMembers: toA ? p.teamBMembers : [...p.teamBMembers, e],
        acceptedMembers: [
          ...p.acceptedMembers.filter((m) => !this.eq(m, e)),
          e,
        ],
      },
    });
    return pickupWire(updated);
  }

  /** Elimina (archiva) el pickup, sus chats y sus mensajes. Solo el creador. */
  async remove(pageId: string, email: string): Promise<void> {
    const cur = await this.getById(pageId);
    if (!this.eq(cur.createdBy, email)) {
      throw new ForbiddenException('Solo quien creó el pickup puede eliminarlo.');
    }
    await this.prisma.$transaction([
      this.prisma.chat.updateMany({
        where: { pickupId: pageId, archived: false },
        data: { archived: true },
      }),
      this.prisma.message.updateMany({
        where: { pickupId: pageId, archived: false },
        data: { archived: true },
      }),
      this.prisma.pickup.updateMany({
        where: { id: pageId },
        data: { archived: true },
      }),
    ]);
  }

  /** Valida que [email] sea creador o miembro del pickup; devuelve el pickup. */
  private async requireMember(pageId: string, email: string): Promise<Pickup> {
    const p = await this.getById(pageId);
    const isMember =
      this.eq(p.createdBy, email) ||
      p.teamAMembers.some((m) => this.eq(m, email)) ||
      p.teamBMembers.some((m) => this.eq(m, email));
    if (!isMember) {
      throw new ForbiddenException('No participás de este pickup.');
    }
    return p;
  }

  /** Mensajes del chat del pickup, orden cronológico. [afterIso] = polling
   * incremental (solo los posteriores a esa fecha). Límite 200. */
  async listMessages(
    pageId: string,
    email: string,
    afterIso?: string,
  ): Promise<{ messages: { id: string; email: string; text: string; createdAt: string }[] }> {
    await this.requireMember(pageId, email);
    const after = parseUtc(afterIso);
    const rows = await this.prisma.message.findMany({
      where: {
        pickupId: pageId,
        archived: false,
        ...(after && { createdAt: { gt: after } }),
      },
      orderBy: { createdAt: 'asc' },
      take: 200,
    });
    return {
      messages: rows.map((m) => ({
        id: m.id,
        email: m.email,
        text: m.text,
        createdAt: m.createdAt.toISOString(),
      })),
    };
  }

  /** Envía un mensaje al chat del pickup (solo creador/miembros). */
  async sendMessage(
    pageId: string,
    email: string,
    text: string,
  ): Promise<{ id: string; email: string; text: string; createdAt: string }> {
    await this.requireMember(pageId, email);
    const m = await this.prisma.message.create({
      data: { pickupId: pageId, email, text: text.trim() },
    });
    return {
      id: m.id,
      email: m.email,
      text: m.text,
      createdAt: m.createdAt.toISOString(),
    };
  }

  async createChat(createdBy: string, dto: CreateChatDto): Promise<CrewChat> {
    const row = await this.prisma.chat.create({
      data: {
        name: dto.name,
        pickupId: dto.pickupId,
        createdBy,
        date: parseUtc(dto.date) ?? new Date(),
        teamAName: dto.teamAName ?? 'Equipo A',
        teamBName: dto.teamBName ?? 'Equipo B',
        teamAColor: dto.teamAColor ?? '#FF6B1A',
        teamBColor: dto.teamBColor ?? '#3B82F6',
        lastMessage: dto.lastMessage ?? '',
      },
    });
    return chatWire(row);
  }
}

// ── Controllers ─────────────────────────────────────────────────────────────

@Controller('pickups')
@UseGuards(JwtAuthGuard)
class PickupsController {
  constructor(private readonly pickups: PickupsService) {}

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.pickups.listForUser(user.email);
  }

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreatePickupDto) {
    return this.pickups.create(user.email, dto);
  }

  @Post('join')
  join(@CurrentUser() user: AuthUser, @Body() dto: JoinPickupDto) {
    return this.pickups.join(dto.code, user.email);
  }

  // Ojo con el orden: rutas estáticas ANTES de los parámetros dinámicos.
  // "public" no colisiona con ":pageId" (segmentos distintos), pero se deja
  // acá arriba por legibilidad del bloque público.

  /** Pickups públicos de una cancha (para el detalle de cancha). */
  @Get('public')
  publicList(@Query('courtId') courtId: string) {
    return this.pickups.listPublicForCourt(courtId ?? '');
  }

  /** Unirse a un pickup público por id (sin código de invitación). */
  @Post('public/join')
  publicJoin(@CurrentUser() user: AuthUser, @Body() dto: JoinPublicPickupDto) {
    return this.pickups.joinById(dto.pickupId, user.email);
  }

  /** Horarios ocupados de una cancha en un día (para el picker de horarios).
   * `date` va en `YYYY-MM-DD`; `excludePickupId` es el pickup que se está
   * reprogramando, para que no figure ocupándose a sí mismo. */
  @Get('availability')
  availability(
    @Query('courtId') courtId: string,
    @Query('date') date: string,
    @Query('excludePickupId') excludePickupId?: string,
  ) {
    return this.pickups.availability(courtId ?? '', date ?? '', excludePickupId);
  }

  @Patch(':pageId')
  update(
    @CurrentUser() user: AuthUser,
    @Param('pageId') pageId: string,
    @Body() dto: UpdatePickupDto,
  ) {
    return this.pickups.update(pageId, user.email, dto);
  }

  @Delete(':pageId')
  async remove(
    @CurrentUser() user: AuthUser,
    @Param('pageId') pageId: string,
  ) {
    await this.pickups.remove(pageId, user.email);
    return { ok: true };
  }

  @Get(':pageId/messages')
  messages(
    @CurrentUser() user: AuthUser,
    @Param('pageId') pageId: string,
    @Query('after') after?: string,
  ) {
    return this.pickups.listMessages(pageId, user.email, after);
  }

  @Post(':pageId/messages')
  sendMessage(
    @CurrentUser() user: AuthUser,
    @Param('pageId') pageId: string,
    @Body() dto: SendMessageDto,
  ) {
    return this.pickups.sendMessage(pageId, user.email, dto.text);
  }
}

@Controller('chats')
@UseGuards(JwtAuthGuard)
class ChatsController {
  constructor(private readonly pickups: PickupsService) {}

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateChatDto) {
    return this.pickups.createChat(user.email, dto);
  }
}

@Module({
  controllers: [PickupsController, ChatsController],
  providers: [PickupsService],
})
export class PickupsModule {}
