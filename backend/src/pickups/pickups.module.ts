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
  ServiceUnavailableException,
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
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import {
  CrewChat,
  chatFromNotion,
  chatToNotionProps,
  Pickup,
  pickupFromNotion,
  pickupToNotionProps,
} from '../notion/entities';
import { NotionService } from '../notion/notion.service';

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
  constructor(private readonly notion: NotionService) {}

  private get db() {
    return this.notion.cfg.db;
  }

  private eq(a: string, b: string): boolean {
    return a.trim().toLowerCase() === b.trim().toLowerCase();
  }

  /** Código de invitación de 5 dígitos (10000–99999). */
  private genInviteCode(): string {
    return (Math.floor(Math.random() * 90000) + 10000).toString();
  }

  /** Pickups donde el usuario es creador o miembro de un equipo. Deduplicado. */
  async listForUser(email: string): Promise<Pickup[]> {
    const e = email.trim().toLowerCase();
    const rows = await this.notion.queryDatabaseAll(this.db.pickups, {
      filter: NotionService.filterOr([
        NotionService.filterText('CreatedBy', e),
        NotionService.filterTextContains('TeamAMembers', e),
        NotionService.filterTextContains('TeamBMembers', e),
      ]),
    });
    const seen = new Set<string>();
    const out: Pickup[] = [];
    for (const r of rows) {
      const p = pickupFromNotion(r);
      if (!seen.has(p.pageId)) {
        seen.add(p.pageId);
        out.push(p);
      }
    }
    return out;
  }

  private async getById(pageId: string): Promise<Pickup> {
    const page = await this.notion.retrievePage(pageId);
    return pickupFromNotion(page);
  }

  async create(createdBy: string, dto: CreatePickupDto): Promise<Pickup> {
    const page = await this.notion.createPage(
      this.db.pickups,
      pickupToNotionProps({
        title: dto.title,
        courtId: dto.courtId,
        createdBy,
        dateTime: dto.dateTime ?? null,
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
      }),
    );
    return pickupFromNotion(page);
  }

  /** Actualiza (read-modify-write) solo los campos provistos. Solo creador o
   * miembro. Cubre aceptar/rechazar/mover/quitar/abandonar/reenviar. */
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
    const merged: Omit<Pickup, 'pageId'> = {
      title: dto.title ?? cur.title,
      courtId: cur.courtId,
      createdBy: cur.createdBy,
      dateTime: dto.dateTime ?? cur.dateTime,
      maxPlayers: dto.maxPlayers ?? cur.maxPlayers,
      vibe: dto.vibe ?? cur.vibe,
      notes: dto.notes ?? cur.notes,
      teamSize: dto.teamSize ?? cur.teamSize,
      teamAName: dto.teamAName ?? cur.teamAName,
      teamBName: dto.teamBName ?? cur.teamBName,
      teamAColor: dto.teamAColor ?? cur.teamAColor,
      teamBColor: dto.teamBColor ?? cur.teamBColor,
      teamAMembers: dto.teamAMembers ?? cur.teamAMembers,
      teamBMembers: dto.teamBMembers ?? cur.teamBMembers,
      targetScore: dto.targetScore ?? cur.targetScore,
      acceptedMembers: dto.acceptedMembers ?? cur.acceptedMembers,
      declinedMembers: dto.declinedMembers ?? cur.declinedMembers,
      inviteCode: cur.inviteCode, // inmutable
    };
    const page = await this.notion.updatePage(
      pageId,
      pickupToNotionProps(merged),
    );
    return pickupFromNotion(page);
  }

  /** Unirse por código: entra al equipo con espacio (el de menos miembros
   * primero), como miembro aceptado. Calca PickupsProvider.joinByCode. */
  async join(code: string, email: string): Promise<Pickup> {
    const e = email.trim().toLowerCase();
    const rows = await this.notion.queryDatabase(this.db.pickups, {
      filter: NotionService.filterText('InviteCode', code.trim()),
    });
    if (rows.length === 0) {
      throw new NotFoundException('Código inválido. Revisá los 5 dígitos.');
    }
    const p = pickupFromNotion(rows[0]);

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
        const accepted = [
          ...p.acceptedMembers.filter((m) => !this.eq(m, e)),
          e,
        ];
        const page = await this.notion.updatePage(
          p.pageId,
          pickupToNotionProps({ ...p, acceptedMembers: accepted }),
        );
        return pickupFromNotion(page);
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
    const updated: Omit<Pickup, 'pageId'> = {
      ...p,
      teamAMembers: toA ? [...p.teamAMembers, e] : p.teamAMembers,
      teamBMembers: toA ? p.teamBMembers : [...p.teamBMembers, e],
      acceptedMembers: [
        ...p.acceptedMembers.filter((m) => !this.eq(m, e)),
        e,
      ],
    };
    const page = await this.notion.updatePage(
      p.pageId,
      pickupToNotionProps(updated),
    );
    return pickupFromNotion(page);
  }

  /** Elimina (archiva) el pickup y sus chats. Solo el creador. */
  async remove(pageId: string, email: string): Promise<void> {
    const cur = await this.getById(pageId);
    if (!this.eq(cur.createdBy, email)) {
      throw new ForbiddenException('Solo quien creó el pickup puede eliminarlo.');
    }
    if (this.db.chats) {
      try {
        const chats = await this.notion.queryDatabaseAll(this.db.chats, {
          filter: NotionService.filterText('PickupId', pageId),
        });
        for (const c of chats) {
          const id = c.id?.toString();
          if (id) await this.notion.archivePage(id);
        }
      } catch {
        // best-effort: igual archivamos el pickup.
      }
    }
    await this.notion.archivePage(pageId);
  }

  async createChat(createdBy: string, dto: CreateChatDto): Promise<CrewChat> {
    if (!this.db.chats) {
      throw new ServiceUnavailableException(
        'El chat de crew no está configurado (NOTION_DB_CHATS vacío).',
      );
    }
    const page = await this.notion.createPage(
      this.db.chats,
      chatToNotionProps({
        name: dto.name,
        pickupId: dto.pickupId,
        createdBy,
        date: dto.date ?? new Date().toISOString(),
        teamAName: dto.teamAName ?? 'Equipo A',
        teamBName: dto.teamBName ?? 'Equipo B',
        teamAColor: dto.teamAColor ?? '#FF6B1A',
        teamBColor: dto.teamBColor ?? '#3B82F6',
        lastMessage: dto.lastMessage ?? '',
      }),
    );
    return chatFromNotion(page);
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
