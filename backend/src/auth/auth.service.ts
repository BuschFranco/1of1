import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash } from 'crypto';
import {
  appUserFromNotion,
  profileFromNotion,
  profileToNotionProps,
  Profile,
} from '../notion/models';
import { NotionService } from '../notion/notion.service';
import { LoginDto, RegisterDto } from './dto';
import { JwtPayload } from './jwt.strategy';

@Injectable()
export class AuthService {
  constructor(
    private readonly notion: NotionService,
    private readonly jwt: JwtService,
  ) {}

  /** Mismo esquema que la app Dart: sha256("<email_lowercase>:<password>") hex. */
  private hash(email: string, password: string): string {
    return createHash('sha256')
      .update(`${email.toLowerCase()}:${password}`)
      .digest('hex');
  }

  private sign(userPageId: string, email: string, profileId: string): string {
    const payload: JwtPayload = { sub: userPageId, email, profileId };
    return this.jwt.sign(payload);
  }

  async login(dto: LoginDto): Promise<{ token: string; profile: Profile }> {
    const email = dto.email.trim().toLowerCase();
    const rows = await this.notion.queryDatabase(this.notion.cfg.db.users, {
      filter: NotionService.filterTitle('Email', email),
    });
    if (rows.length === 0) {
      throw new UnauthorizedException('No existe una cuenta con ese email.');
    }
    const user = appUserFromNotion(rows[0]);
    if (user.passwordHash !== this.hash(email, dto.password)) {
      throw new UnauthorizedException('Contraseña incorrecta.');
    }
    const profilePage = await this.notion.retrievePage(user.profileId);
    const profile = profileFromNotion(profilePage);
    return { token: this.sign(user.pageId, email, user.profileId), profile };
  }

  async register(dto: RegisterDto): Promise<{ token: string; profile: Profile }> {
    const email = dto.email.trim().toLowerCase();
    const existing = await this.notion.queryDatabase(this.notion.cfg.db.users, {
      filter: NotionService.filterTitle('Email', email),
    });
    if (existing.length > 0) {
      throw new ConflictException('Ya existe una cuenta con ese email.');
    }

    // El handle NO se autogenera: se define después en la pantalla de handle.
    const profilePage = await this.notion.createPage(
      this.notion.cfg.db.profiles,
      profileToNotionProps({
        name: dto.name.trim(),
        handle: '',
        city: (dto.city ?? '').trim(),
        phone: (dto.phone ?? '').trim(),
        userEmail: email,
      }),
    );
    const profileId = profilePage.id?.toString() ?? '';

    const userPage = await this.notion.createPage(this.notion.cfg.db.users, {
      Email: NotionService.title(email),
      PasswordHash: NotionService.richText(this.hash(email, dto.password)),
      ProfileId: NotionService.richText(profileId),
      CreatedAt: NotionService.date(new Date().toISOString()),
    });

    const profile = profileFromNotion(profilePage);
    return {
      token: this.sign(userPage.id?.toString() ?? '', email, profileId),
      profile,
    };
  }
}
