import {
  Body,
  Controller,
  Delete,
  Get,
  NotFoundException,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { IsBoolean, IsOptional, IsString } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { Profile } from '../notion/models';
import { ProfilesService } from './profiles.service';

class SetHandleDto {
  @IsString() handle!: string;
}

class SetPresenceDto {
  @IsBoolean() playing!: boolean;
  @IsOptional() @IsString() courtId?: string;
  @IsOptional() @IsString() since?: string;
}

/** Perfil propio del usuario autenticado. */
@Controller('me')
@UseGuards(JwtAuthGuard)
export class MeController {
  constructor(private readonly profiles: ProfilesService) {}

  @Get()
  me(@CurrentUser() user: AuthUser) {
    return this.profiles.getById(user.profileId);
  }

  /** Actualiza campos del perfil (flush de stats, clan, título, privacidad, etc). */
  @Patch()
  update(@CurrentUser() user: AuthUser, @Body() patch: Partial<Profile>) {
    return this.profiles.update(user.profileId, patch);
  }

  @Post('handle')
  setHandle(@CurrentUser() user: AuthUser, @Body() dto: SetHandleDto) {
    return this.profiles.setHandle(user.profileId, dto.handle);
  }

  @Patch('presence')
  setPresence(@CurrentUser() user: AuthUser, @Body() dto: SetPresenceDto) {
    return this.profiles.setPresence(
      user.profileId,
      dto.playing,
      dto.courtId ?? '',
      dto.since ?? null,
    );
  }

  /** Borra la cuenta y sus datos (requisito de las tiendas). */
  @Delete()
  remove(@CurrentUser() user: AuthUser) {
    return this.profiles.deleteAccount(user.email, user.profileId, user.sub);
  }
}

/** Perfiles de otros usuarios (para amigos / proponentes / presencia). */
@Controller('profiles')
@UseGuards(JwtAuthGuard)
export class ProfilesController {
  constructor(private readonly profiles: ProfilesService) {}

  @Get()
  all() {
    return this.profiles.getAll();
  }

  @Get('by-handle')
  async byHandle(@Query('handle') handle: string) {
    const p = await this.profiles.searchByHandle(handle ?? '');
    if (!p) throw new NotFoundException('No existe un perfil con ese handle.');
    return p;
  }
}
