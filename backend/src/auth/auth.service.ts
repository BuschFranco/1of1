import {
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash } from 'crypto';
import { OAuth2Client } from 'google-auth-library';
import { Profile, profileWire } from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';
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
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  /** Mismo esquema que siempre: sha256("<email_lowercase>:<password>") hex.
   * Se mantiene para que los hashes migrados de Notion sigan funcionando. */
  private hash(email: string, password: string): string {
    return createHash('sha256')
      .update(`${email.toLowerCase()}:${password}`)
      .digest('hex');
  }

  private sign(
    userId: string,
    email: string,
    profileId: string,
    isAdmin: boolean,
  ): string {
    const payload: JwtPayload = { sub: userId, email, profileId, isAdmin };
    return this.jwt.sign(payload);
  }

  async login(dto: LoginDto): Promise<{ token: string; profile: Profile }> {
    const email = dto.email.trim().toLowerCase();
    const user = await this.prisma.user.findFirst({
      where: { email, archived: false },
    });
    if (!user) {
      throw new UnauthorizedException('No existe una cuenta con ese email.');
    }
    if (user.passwordHash !== this.hash(email, dto.password)) {
      throw new UnauthorizedException('Contraseña incorrecta.');
    }
    const profile = await this.prisma.profile.findUnique({
      where: { id: user.profileId },
    });
    if (!profile) {
      throw new UnauthorizedException('La cuenta no tiene perfil.');
    }
    return {
      token: this.sign(user.id, email, user.profileId, user.isAdmin),
      profile: profileWire(profile),
    };
  }

  async register(dto: RegisterDto): Promise<{ token: string; profile: Profile }> {
    const email = dto.email.trim().toLowerCase();
    const existing = await this.prisma.user.findFirst({
      where: { email, archived: false },
    });
    if (existing) {
      throw new ConflictException('Ya existe una cuenta con ese email.');
    }

    // El handle NO se autogenera: se define después en la pantalla de handle.
    const { profile, user } = await this.prisma.$transaction(async (tx) => {
      const profile = await tx.profile.create({
        data: {
          name: dto.name.trim(),
          city: (dto.city ?? '').trim(),
          phone: (dto.phone ?? '').trim(),
          birthdate: dto.birthdate ? new Date(`${dto.birthdate.trim()}T00:00:00Z`) : null,
          userEmail: email,
        },
      });
      const user = await tx.user.create({
        data: {
          email,
          passwordHash: this.hash(email, dto.password),
          profileId: profile.id,
        },
      });
      return { profile, user };
    });

    return {
      token: this.sign(user.id, email, profile.id, false),
      profile: profileWire(profile),
    };
  }

  /** Login/registro con Google: verifica el idToken server-side y hace
   * find-or-create (mismo criterio que siempre: PasswordHash = 'google:'). */
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
    const existing = await this.prisma.user.findFirst({
      where: { email, archived: false },
    });
    if (existing) {
      const profile = await this.prisma.profile.findUnique({
        where: { id: existing.profileId },
      });
      if (!profile) {
        throw new UnauthorizedException('La cuenta no tiene perfil.');
      }
      return {
        token: this.sign(existing.id, email, existing.profileId, existing.isAdmin),
        profile: profileWire(profile),
      };
    }

    // Nuevo: crear Profile + User (PasswordHash 'google:').
    const { profile, user } = await this.prisma.$transaction(async (tx) => {
      const profile = await tx.profile.create({
        data: { name: name.trim(), avatar: avatarUrl, userEmail: email },
      });
      const user = await tx.user.create({
        data: { email, passwordHash: 'google:', profileId: profile.id },
      });
      return { profile, user };
    });
    return {
      token: this.sign(user.id, email, profile.id, false),
      profile: profileWire(profile),
    };
  }
}
