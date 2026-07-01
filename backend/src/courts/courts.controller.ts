import {
  Body,
  Controller,
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

  @Get('courts/:courtId/reviews')
  reviews(@Param('courtId') courtId: string) {
    return this.courts.listReviews(courtId);
  }

  @Post('courts/:courtId/reviews')
  addReview(
    @CurrentUser() user: AuthUser,
    @Param('courtId') courtId: string,
    @Body() dto: AddReviewDto,
  ) {
    return this.courts.addReview(courtId, user.email, dto.rating, dto.comment);
  }
}
