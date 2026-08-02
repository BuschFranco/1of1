import {
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
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

  // ── Hashes de contraseña ───────────────────────────────────────────────
  //
  // Esquema actual: bcrypt con salt (bcryptjs, puro JS: sin binarios nativos,
  // corre igual en Windows y en Render). Formato `$2a$/$2b$/$2y$` estándar.
  //
  // Esquema legado (cuentas migradas de Notion): sha256("<email>:<password>")
  // hex, SIN salt. NO se genera más, solo se VERIFICA para no romper el login
  // de los usuarios existentes, y en el momento de loguear bien se hace el
  // upgrade en caliente a bcrypt (migración lazy). Las cuentas de Google se
  // guardan con 'google:' (no tienen contraseña) y no pasan por password.

  /** Costo de bcrypt. 10 es el estándar; subir de acá duplica el tiempo por
   * hash sin ganancia práctica a este volumen. */
  private static readonly BCRYPT_ROUNDS = 10;

  private static isBcryptHash(h: string): boolean {
    return h.startsWith('$2a$') || h.startsWith('$2b$') || h.startsWith('$2y$');
  }

  private static isLegacySha256(h: string): boolean {
    return /^[0-9a-f]{64}$/i.test(h);
  }

  /** Verifica la contraseña contra el hash almacenado, soportando ambos
   * esquemas. Devuelve true si coincide; además avisa si el hash era del
   * esquema viejo (para el upgrade en caliente). */
  private async verifyPassword(
    email: string,
    password: string,
    stored: string,
  ): Promise<{ ok: boolean; legacy: boolean }> {
    if (AuthService.isBcryptHash(stored)) {
      return { ok: await bcrypt.compare(password, stored), legacy: false };
    }
    if (AuthService.isLegacySha256(stored)) {
      return {
        ok: stored === this.legacySha256(email, password),
        legacy: true,
      };
    }
    // 'google:' u otro valor no parseable: no hay contraseña que validar.
    return { ok: false, legacy: false };
  }

  /** sha256("<email_lowercase>:<password>") hex — esquema legado de Notion.
   * Solo para verificar hashes existentes (y derivar el upgrade a bcrypt). */
  private legacySha256(email: string, password: string): string {
    return createHash('sha256')
      .update(`${email.trim().toLowerCase()}:${password}`)
      .digest('hex');
  }

  private async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, AuthService.BCRYPT_ROUNDS);
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
    const { ok, legacy } = await this.verifyPassword(
      email,
      dto.password,
      user.passwordHash,
    );
    if (!ok) {
      throw new UnauthorizedException('Contraseña incorrecta.');
    }
    // Migración en caliente: el hash era del esquema viejo (sha256 sin salt) →
    // se reemplaza por bcrypt con la contraseña recién verificada. De esta
    // forma cada cuenta pasa a bcrypt en su próximo login sin interrumpir a
    // nadie, y los hashes viejos dejan de circular.
    if (legacy) {
      await this.prisma.user.update({
        where: { id: user.id },
        data: { passwordHash: await this.hashPassword(dto.password) },
      });
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
          passwordHash: await this.hashPassword(dto.password),
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
