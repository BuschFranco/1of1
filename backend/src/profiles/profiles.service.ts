import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
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
}
