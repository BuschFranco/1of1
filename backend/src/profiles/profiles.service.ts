import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { normalizeHandle, validateHandleFormat } from '../common/handle';
import {
  parseUtc,
  Profile,
  profilePatchToData,
  profileWire,
} from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';

@Injectable()
export class ProfilesService {
  constructor(private readonly prisma: PrismaService) {}

  /** Borra (archiva) la cuenta y sus datos, en el mismo orden de siempre:
   * matches → reviews → friends → pickups (+chats) → perfil → usuario.
   * Borrado lógico (archived=true); devuelve el conteo por tabla. */
  async deleteAccount(
    email: string,
    profileId: string,
    userId: string,
  ): Promise<{ ok: boolean; archived: Record<string, number> }> {
    const e = email.trim().toLowerCase();
    const archived: Record<string, number> = {};

    const res = await this.prisma.$transaction(async (tx) => {
      const out: Record<string, number> = {};
      out.matches = (
        await tx.match.updateMany({
          where: { email: e, archived: false },
          data: { archived: true },
        })
      ).count;
      out.reviews = (
        await tx.review.updateMany({
          where: { userEmail: e, archived: false },
          data: { archived: true },
        })
      ).count;
      out.friends = (
        await tx.friend.updateMany({
          where: { ownerEmail: e, archived: false },
          data: { archived: true },
        })
      ).count;

      // Pickups creados por el usuario + sus chats asociados.
      const pickups = await tx.pickup.findMany({
        where: { createdBy: e, archived: false },
        select: { id: true },
      });
      const pickupIds = pickups.map((p) => p.id);
      if (pickupIds.length > 0) {
        await tx.chat.updateMany({
          where: { pickupId: { in: pickupIds }, archived: false },
          data: { archived: true },
        });
        await tx.pickup.updateMany({
          where: { id: { in: pickupIds } },
          data: { archived: true },
        });
      }
      out.pickups = pickupIds.length;

      // Mensajes: los de sus pickups Y los que escribió en pickups ajenos.
      out.messages = (
        await tx.message.updateMany({
          where: {
            archived: false,
            OR: [{ email: e }, ...(pickupIds.length ? [{ pickupId: { in: pickupIds } }] : [])],
          },
          data: { archived: true },
        })
      ).count;

      out.profile = (
        await tx.profile.updateMany({
          where: { id: profileId },
          data: { archived: true },
        })
      ).count;
      out.user = (
        await tx.user.updateMany({
          where: { id: userId },
          data: { archived: true },
        })
      ).count;
      return out;
    });

    Object.assign(archived, res);
    return { ok: true, archived };
  }

  async getById(profileId: string): Promise<Profile> {
    const row = await this.prisma.profile.findUnique({
      where: { id: profileId },
    });
    if (!row) throw new NotFoundException('Perfil no encontrado.');
    return profileWire(row);
  }

  async update(profileId: string, patch: Record<string, any>): Promise<Profile> {
    const data = profilePatchToData(patch ?? {});
    const row = await this.prisma.profile.update({
      where: { id: profileId },
      data,
    });
    return profileWire(row);
  }

  /** Todos los perfiles (para resolver proponentes y presencia "jugando").
   * Mismo tope de 100 que tenía la query simple del gateway.
   * [fields] permite seleccionar solo campos específicos para reducir payload. */
  async getAll(fields?: string[]): Promise<Record<string, any>[]> {
    // Mapeo de nombres de wire → columnas de Prisma.
    const fieldMap: Record<string, string> = {
      pageId: 'id',
      name: 'name',
      handle: 'handle',
      phone: 'phone',
      city: 'city',
      lat: 'lat',
      lng: 'lng',
      avatar: 'avatar',
      position: 'position',
      height: 'height',
      games: 'games',
      courts: 'courts',
      streak: 'streak',
      points: 'exp', // clave de wire "points" -> columna "exp"
      rating: 'rating',
      userEmail: 'userEmail',
      birthdate: 'birthdate',
      clan: 'clan',
      avatarColor: 'avatarColor',
      clanTextColor: 'clanTextColor',
      clanFont: 'clanFont',
      avatarFrame: 'avatarFrame',
      title: 'title',
      level: 'level',
      unlockedBadges: 'unlockedBadges',
      playSeconds: 'playSeconds',
      playTimeByCourt: 'playTimeByCourt',
      shareStatus: 'shareStatus',
      shareCourt: 'shareCourt',
      shareTime: 'shareTime',
      playing: 'playing',
      playingCourtId: 'playingCourtId',
      playingSince: 'playingSince',
      lastPlayedCourtId: 'lastPlayedCourtId',
      lastPlayedAt: 'lastPlayedAt',
      showLastPlayed: 'showLastPlayed',
      clanJoinedAt: 'clanJoinedAt',
    };

    // Si se piden campos específicos, usar select; si no, traer todo.
    const select = fields
      ? Object.fromEntries(
          fields
            .filter((f) => fieldMap[f])
            .map((f) => [fieldMap[f], true]),
        )
      : undefined;

    const rows = await this.prisma.profile.findMany({
      where: { archived: false },
      take: 100,
      ...(select ? { select: { id: true, ...select } } : {}),
    });

    // Si se usó select, mapear manualmente; si no, usar profileWire.
    if (select) {
      return rows.map((r) => {
        const out: Record<string, any> = {};
        for (const [wireField, dbCol] of Object.entries(fieldMap)) {
          if (wireField === 'pageId') {
            out[wireField] = r.id;
          } else if ((r as any)[dbCol] !== undefined) {
            out[wireField] = (r as any)[dbCol];
          }
        }
        // Fechas ISO
        if (r.birthdate) out.birthdate = r.birthdate.toISOString();
        if (r.playingSince) out.playingSince = r.playingSince.toISOString();
        if (r.lastPlayedAt) out.lastPlayedAt = r.lastPlayedAt.toISOString();
        if (r.clanJoinedAt) out.clanJoinedAt = r.clanJoinedAt.toISOString();
        return out;
      });
    }

    return rows.map(profileWire);
  }

  /** Busca un perfil por handle exacto. Devuelve null si no existe. */
  async searchByHandle(handleRaw: string): Promise<Profile | null> {
    const handle = normalizeHandle(handleRaw);
    if (!handle) return null;
    const row = await this.prisma.profile.findFirst({
      where: { handle, archived: false },
    });
    return row ? profileWire(row) : null;
  }

  /** True si el handle ya lo tiene OTRO perfil (excluye el propio). */
  async isHandleTaken(handleRaw: string, excludeId: string): Promise<boolean> {
    const handle = normalizeHandle(handleRaw);
    const row = await this.prisma.profile.findFirst({
      where: { handle, archived: false, id: { not: excludeId } },
      select: { id: true },
    });
    return row !== null;
  }

  /** Define/cambia el handle con validación de formato y unicidad. */
  async setHandle(profileId: string, handleRaw: string): Promise<Profile> {
    const fmtErr = validateHandleFormat(handleRaw);
    if (fmtErr) throw new BadRequestException(fmtErr);
    const handle = normalizeHandle(handleRaw);
    if (await this.isHandleTaken(handle, profileId)) {
      throw new ConflictException('Ese handle ya está en uso. Probá con otro.');
    }
    const row = await this.prisma.profile.update({
      where: { id: profileId },
      data: { handle },
    });
    return profileWire(row);
  }

  /** Actualiza la presencia "jugando" del perfil. */
  async setPresence(
    profileId: string,
    playing: boolean,
    courtId: string,
    since: string | null,
  ): Promise<Profile> {
    const row = await this.prisma.profile.update({
      where: { id: profileId },
      data: {
        playing,
        playingCourtId: playing ? courtId : '',
        playingSince: playing && since ? parseUtc(since) : null,
      },
    });
    return profileWire(row);
  }
}
