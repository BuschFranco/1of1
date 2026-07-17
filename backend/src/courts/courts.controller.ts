import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { ProfilesService } from '../profiles/profiles.service';
import { CourtsService } from './courts.service';
import { AddReviewDto, ProposeCourtDto } from './dto';

@Controller()
@UseGuards(JwtAuthGuard)
export class CourtsController {
  constructor(
    private readonly courts: CourtsService,
    private readonly profiles: ProfilesService,
  ) {}

  @Get('courts')
  list() {
    return this.courts.listApproved();
  }

  /** Canchas propuestas por mí (todos los estados) para detectar aprobación/rechazo. */
  @Get('courts/mine')
  mine(@CurrentUser() user: AuthUser) {
    return this.courts.listMine(user.email);
  }

  @Post('courts')
  async propose(@CurrentUser() user: AuthUser, @Body() dto: ProposeCourtDto) {
    // El autor (handle/clan/email) se toma del perfil autenticado, no del body.
    const me = await this.profiles.getById(user.profileId);
    return this.courts.propose(dto, {
      createdBy: me.handle,
      createdByClan: me.clan,
      createdByEmail: user.email,
    });
  }

  @Delete('courts/:courtId')
  async remove(@CurrentUser() user: AuthUser, @Param('courtId') courtId: string) {
    if (!user.isAdmin) throw new ForbiddenException('Solo un admin puede eliminar canchas.');
    await this.courts.remove(courtId);
    return { ok: true };
  }

  @Get('courts/:courtId/reviews')
  reviews(@Param('courtId') courtId: string) {
    return this.courts.listReviews(courtId);
  }

  @Post('courts/:courtId/reviews')
  async addReview(
    @CurrentUser() user: AuthUser,
    @Param('courtId') courtId: string,
    @Body() dto: AddReviewDto,
  ) {
    const me = await this.profiles.getById(user.profileId);
    return this.courts.addReview(
      courtId,
      user.email,
      me.handle,
      dto.rating,
      dto.comment,
    );
  }

  @Delete('reviews/:pageId')
  async removeReview(
    @CurrentUser() user: AuthUser,
    @Param('pageId') pageId: string,
  ) {
    // El dueño puede borrar su propia reseña; un admin, cualquiera.
    if (!user.isAdmin) {
      const review = await this.courts.getReview(pageId);
      if (review.userEmail.trim().toLowerCase() !== user.email.trim().toLowerCase()) {
        throw new ForbiddenException('Solo podés eliminar tus propias reseñas.');
      }
    }
    await this.courts.removeReview(pageId);
    return { ok: true };
  }
}
