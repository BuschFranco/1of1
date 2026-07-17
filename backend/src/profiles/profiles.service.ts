import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { normalizeHandle, validateHandleFormat } from '../common/handle';
import {
  Profile,
  profileFromNotion,
  profileToNotionProps,
} from '../notion/models';
import { NotionService } from '../notion/notion.service';

@Injectable()
export class ProfilesService implements OnModuleInit {
  private readonly log = new Logger(ProfilesService.name);
  constructor(private readonly notion: NotionService) {}

  /** Asegura el schema de Notion al arrancar (movido desde main.dart de la app). */
  async onModuleInit(): Promise<void> {
    if (!this.notion.isConfigured) {
      this.log.warn('NOTION_TOKEN vacío: el backend no podrá hablar con Notion.');
      return;
    }
    try {
      await this.notion.ensureProperties(this.notion.cfg.db.profiles, {
        Clan: 'rich_text',
        AvatarColor: 'rich_text',
        ClanTextColor: 'rich_text',
        ClanFont: 'rich_text',
        AvatarFrame: 'rich_text',
        EquippedTitle: 'rich_text',
        Level: 'rich_text',
        ShareStatus: 'checkbox',
        ShareCourt: 'checkbox',
        ShareTime: 'checkbox',
        Playing: 'checkbox',
        PlayingCourtId: 'rich_text',
        PlayingSince: 'date',
        LastPlayedCourtId: 'rich_text',
        LastPlayedAt: 'date',
        ShowLastPlayed: 'checkbox',
        ClanJoinedAt: 'date',
      });
      // OJO: no declarar columnas SELECT existentes (Aprobacion/Status/Result):
      // ensureProperties hace PATCH {select:{}} y borra sus opciones.
      await this.notion.ensureProperties(this.notion.cfg.db.courts, {
        CreatedByClan: 'rich_text',
        CreatedByEmail: 'rich_text',
        OpenTime: 'rich_text',
        CloseTime: 'rich_text',
      });
      await this.notion.ensureProperties(this.notion.cfg.db.reviews, {
        UserHandle: 'rich_text',
      });
      await this.notion.ensureProperties(this.notion.cfg.db.pickups, {
        TeamSize: 'number',
        TargetScore: 'number',
        TeamAName: 'rich_text',
        TeamBName: 'rich_text',
        TeamAColor: 'rich_text',
        TeamBColor: 'rich_text',
        TeamAMembers: 'rich_text',
        TeamBMembers: 'rich_text',
        AcceptedMembers: 'rich_text',
        DeclinedMembers: 'rich_text',
        InviteCode: 'rich_text',
      });
      if (this.notion.cfg.db.matches) {
        await this.notion.ensureProperties(this.notion.cfg.db.matches, {
          Points: 'number',
          Seconds: 'number',
          EndedAt: 'date',
          CourtId: 'rich_text',
          CourtName: 'rich_text',
          // Clan del autor AL MOMENTO de jugar: congela el historial en el
          // clan donde se ganaron los puntos (cambiar de clan no los muda).
          Clan: 'rich_text',
        });
      }
      if (this.notion.cfg.db.chats) {
        await this.notion.ensureProperties(this.notion.cfg.db.chats, {
          PickupId: 'rich_text',
          CreatedBy: 'rich_text',
          Date: 'date',
          TeamAName: 'rich_text',
          TeamBName: 'rich_text',
          TeamAColor: 'rich_text',
          TeamBColor: 'rich_text',
          LastMessage: 'rich_text',
        });
      }
      this.log.log('Schema de Notion verificado.');
    } catch (e) {
      this.log.warn(`ensureSchema: ${(e as Error)?.message ?? e}`);
    }
  }

  /** Borra (archiva) la cuenta y sus datos, en el mismo orden que la app
   * (session.dart deleteAccount): matches → reviews → friends → pickups (+chats)
   * → perfil → usuario. Best-effort por base; devuelve el conteo archivado. */
  async deleteAccount(
    email: string,
    profileId: string,
    userPageId: string,
  ): Promise<{ ok: boolean; archived: Record<string, number> }> {
    const e = email.trim().toLowerCase();
    const db = this.notion.cfg.db;
    const archived: Record<string, number> = {};

    const archiveWhere = async (
      key: string,
      dbId: string,
      filter: any,
    ): Promise<void> => {
      if (!dbId) return;
      try {
        const rows = await this.notion.queryDatabaseAll(dbId, { filter });
        let n = 0;
        for (const r of rows) {
          const id = r.id?.toString();
          if (id) {
            await this.notion.archivePage(id);
            n++;
          }
        }
        archived[key] = n;
      } catch {
        // best-effort: seguimos con las demás bases.
      }
    };

    await archiveWhere('matches', db.matches, NotionService.filterTitle('Email', e));
    await archiveWhere('reviews', db.reviews, NotionService.filterText('UserEmail', e));
    await archiveWhere('friends', db.friends, NotionService.filterText('OwnerEmail', e));

    // Pickups creados por el usuario + sus chats asociados.
    if (db.pickups) {
      try {
        const pickups = await this.notion.queryDatabaseAll(db.pickups, {
          filter: NotionService.filterText('CreatedBy', e),
        });
        let n = 0;
        for (const p of pickups) {
          const pid = p.id?.toString();
          if (!pid) continue;
          if (db.chats) {
            try {
              const chats = await this.notion.queryDatabaseAll(db.chats, {
                filter: NotionService.filterText('PickupId', pid),
              });
              for (const c of chats) {
                const cid = c.id?.toString();
                if (cid) await this.notion.archivePage(cid);
              }
            } catch {
              // ignorar: el pickup igual se archiva.
            }
          }
          await this.notion.archivePage(pid);
          n++;
        }
        archived['pickups'] = n;
      } catch {
        // best-effort.
      }
    }

    // Perfil y credencial.
    try {
      await this.notion.archivePage(profileId);
      archived['profile'] = 1;
    } catch {
      archived['profile'] = 0;
    }
    try {
      await this.notion.archivePage(userPageId);
      archived['user'] = 1;
    } catch {
      archived['user'] = 0;
    }

    return { ok: true, archived };
  }

  async getById(profileId: string): Promise<Profile> {
    const page = await this.notion.retrievePage(profileId);
    return profileFromNotion(page);
  }

  async update(profileId: string, patch: Partial<Profile>): Promise<Profile> {
    const page = await this.notion.updatePage(
      profileId,
      profileToNotionProps(patch),
    );
    return profileFromNotion(page);
  }

  /** Todos los perfiles (para resolver proponentes y presencia "jugando"). */
  async getAll(): Promise<Profile[]> {
    const rows = await this.notion.queryDatabase(this.notion.cfg.db.profiles);
    return rows.map(profileFromNotion);
  }

  /** Busca un perfil por handle exacto. Devuelve null si no existe. */
  async searchByHandle(handleRaw: string): Promise<Profile | null> {
    const handle = normalizeHandle(handleRaw);
    if (!handle) return null;
    const rows = await this.notion.queryDatabase(this.notion.cfg.db.profiles, {
      filter: NotionService.filterText('Handle', handle),
    });
    return rows.length ? profileFromNotion(rows[0]) : null;
  }

  /** True si el handle ya lo tiene OTRO perfil (excluye el propio). */
  async isHandleTaken(handleRaw: string, excludePageId: string): Promise<boolean> {
    const handle = normalizeHandle(handleRaw);
    const rows = await this.notion.queryDatabase(this.notion.cfg.db.profiles, {
      filter: NotionService.filterText('Handle', handle),
    });
    return rows.some((r) => (r.id?.toString() ?? '') !== excludePageId);
  }

  /** Define/cambia el handle con validación de formato y unicidad. */
  async setHandle(profileId: string, handleRaw: string): Promise<Profile> {
    const fmtErr = validateHandleFormat(handleRaw);
    if (fmtErr) throw new BadRequestException(fmtErr);
    const handle = normalizeHandle(handleRaw);
    if (await this.isHandleTaken(handle, profileId)) {
      throw new ConflictException('Ese handle ya está en uso. Probá con otro.');
    }
    return this.update(profileId, { handle });
  }

  /** Actualiza la presencia "jugando" del perfil. */
  async setPresence(
    profileId: string,
    playing: boolean,
    courtId: string,
    since: string | null,
  ): Promise<Profile> {
    return this.update(profileId, {
      playing,
      playingCourtId: playing ? courtId : '',
      playingSince: playing && since ? since : '',
    });
  }
}
