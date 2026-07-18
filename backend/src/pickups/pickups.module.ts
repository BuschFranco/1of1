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
  IsInt,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
} from 'class-validator';
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
} from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';

// ── DTOs ────────────────────────────────────────────────────────────────────

class CreatePickupDto {
  @IsString() title!: string;
  @IsString() courtId!: string;
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
}

class JoinPickupDto {
  @IsString() @Length(5, 5) code!: string;
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

  async create(createdBy: string, dto: CreatePickupDto): Promise<Pickup> {
    const row = await this.prisma.pickup.create({
      data: {
        title: dto.title,
        courtId: dto.courtId,
        createdBy,
        dateTime: parseUtc(dto.dateTime),
        maxPlayers: dto.maxPlayers ?? 10,
        vibe: dto.vibe ?? 'Casual',
        notes: dto.notes ?? '',
        teamSize: dto.teamSize ?? 3,
        teamAName: dto.teamAName ?? 'Equipo A',
        teamBName: dto.teamBName ?? 'Equipo B',
        teamAColor: dto.teamAColor ?? '#FF6B1A',
        teamBColor: dto.teamBColor ?? '#3B82F6',
        teamAMembers: dto.teamAMembers ?? [],
        teamBMembers: dto.teamBMembers ?? [],
        targetScore: dto.targetScore ?? 21,
        acceptedMembers: dto.acceptedMembers ?? [],
        declinedMembers: dto.declinedMembers ?? [],
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
      },
    });
    return pickupWire(row);
  }

  /** Unirse por código: entra al equipo con espacio (el de menos miembros
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

    // Expirado (24h después del horario)?
    const d = p.dateTime ? Date.parse(p.dateTime) : NaN;
    if (!Number.isNaN(d) && Date.now() > d + 24 * 60 * 60 * 1000) {
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
