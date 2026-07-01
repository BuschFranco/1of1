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
      await this.notion.ensureProperties(this.notion.cfg.db.courts, {
        CreatedByClan: 'rich_text',
        CreatedByEmail: 'rich_text',
      });
      this.log.log('Schema de Notion verificado.');
    } catch (e) {
      this.log.warn(`ensureالسchema: ${(e as Error)?.message ?? e}`);
    }
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
