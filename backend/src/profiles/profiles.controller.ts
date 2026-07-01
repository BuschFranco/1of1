import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { Profile } from '../notion/models';
import { ProfilesService } from './profiles.service';

@Controller('me')
@UseGuards(JwtAuthGuard)
export class ProfilesController {
  constructor(private readonly profiles: ProfilesService) {}

  /** Perfil del usuario autenticado. */
  @Get()
  me(@CurrentUser() user: AuthUser) {
    return this.profiles.getById(user.profileId);
  }

  /** Actualiza campos del perfil (subconjunto editable). */
  @Patch()
  update(@CurrentUser() user: AuthUser, @Body() patch: Partial<Profile>) {
    return this.profiles.update(user.profileId, patch);
  }
}
