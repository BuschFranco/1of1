import {
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash } from 'crypto';
import { OAuth2Client } from 'google-auth-library';
import {
  appUserFromNotion,
  profileFromNotion,
  profileToNotionProps,
  Profile,
} from '../notion/models';
import { NotionService } from '../notion/notion.service';
import { GoogleDto, LoginDto, RegisterDto } from './dto';
import { JwtPayload } from './jwt.strategy';

@Injectable()
export class AuthService {
  private readonly log = new Logger(AuthService.name);
  // aud permitido para los idToken de Google (CSV en GOOGLE_CLIENT_IDS).
  private readonly googleClient = new OAuth2Client();
  private readonly googleAudience = (process.env.GOOGLE_CLIENT_IDS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

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

  private sign(
    userPageId: string,
    email: string,
    profileId: string,
    isAdmin: boolean,
  ): string {
    const payload: JwtPayload = { sub: userPageId, email, profileId, isAdmin };
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
    return {
      token: this.sign(user.pageId, email, user.profileId, user.isAdmin),
      profile,
    };
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
        birthdate: (dto.birthdate ?? '').trim(),
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
      token: this.sign(userPage.id?.toString() ?? '', email, profileId, false),
      profile,
    };
  }

  /** Login/registro con Google: verifica el idToken server-side y hace
   * find-or-create (mismo criterio que la app: PasswordHash = 'google:'). */
  async google(dto: GoogleDto): Promise<{ token: string; profile: Profile }> {
    let payload: Record<string, any> | undefined;
    try {
      const ticket = await this.googleClient.verifyIdToken({
        idToken: dto.idToken,
        // Si no se configuró GOOGLE_CLIENT_IDS no restringimos el aud (dev).
        audience: this.googleAudience.length ? this.googleAudience : undefined,
      });
      payload = ticket.getPayload() ?? undefined;
    } catch (e) {
      this.log.warn(`google verifyIdToken falló: ${(e as Error)?.message ?? e}`);
      throw new UnauthorizedException('Token de Google inválido.');
    }
    const email = (payload?.email ?? '').toString().trim().toLowerCase();
    if (!email) {
      throw new UnauthorizedException('El token de Google no trae email.');
    }
    const name = (payload?.name ?? '').toString();
    const avatarUrl = (payload?.picture ?? '').toString();

    // ¿Ya existe? → login directo.
    const existing = await this.notion.queryDatabase(this.notion.cfg.db.users, {
      filter: NotionService.filterTitle('Email', email),
    });
    if (existing.length > 0) {
      const user = appUserFromNotion(existing[0]);
      const profilePage = await this.notion.retrievePage(user.profileId);
      return {
        token: this.sign(user.pageId, email, user.profileId, user.isAdmin),
        profile: profileFromNotion(profilePage),
      };
    }

    // Nuevo: crear Profile + User (PasswordHash 'google:').
    const profilePage = await this.notion.createPage(
      this.notion.cfg.db.profiles,
      profileToNotionProps({
        name: name.trim(),
        handle: '',
        avatar: avatarUrl,
        userEmail: email,
      }),
    );
    const profileId = profilePage.id?.toString() ?? '';
    const userPage = await this.notion.createPage(this.notion.cfg.db.users, {
      Email: NotionService.title(email),
      PasswordHash: NotionService.richText('google:'),
      ProfileId: NotionService.richText(profileId),
      CreatedAt: NotionService.date(new Date().toISOString()),
    });
    return {
      token: this.sign(userPage.id?.toString() ?? '', email, profileId, false),
      profile: profileFromNotion(profilePage),
    };
  }
}
