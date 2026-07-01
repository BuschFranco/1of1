import {
  Body,
  Controller,
  Injectable,
  Module,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { pickupFromNotion, pickupToNotionProps } from '../notion/entities';
import { NotionService } from '../notion/notion.service';

class CreatePickupDto {
  @IsString() title!: string;
  @IsString() courtId!: string;
  @IsOptional() @IsString() dateTime?: string;
  @IsOptional() @IsInt() @Min(2) @Max(50) maxPlayers?: number;
  @IsOptional() @IsString() vibe?: string;
  @IsOptional() @IsString() notes?: string;
}

@Injectable()
class PickupsService {
  constructor(private readonly notion: NotionService) {}

  async create(createdBy: string, dto: CreatePickupDto) {
    const page = await this.notion.createPage(
      this.notion.cfg.db.pickups,
      pickupToNotionProps({
        title: dto.title,
        courtId: dto.courtId,
        createdBy,
        dateTime: dto.dateTime ?? null,
        maxPlayers: dto.maxPlayers ?? 10,
        vibe: dto.vibe ?? 'Casual',
        notes: dto.notes ?? '',
      }),
    );
    return pickupFromNotion(page);
  }
}

@Controller('pickups')
@UseGuards(JwtAuthGuard)
class PickupsController {
  constructor(private readonly pickups: PickupsService) {}

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreatePickupDto) {
    return this.pickups.create(user.email, dto);
  }
}

@Module({
  controllers: [PickupsController],
  providers: [PickupsService],
})
export class PickupsModule {}
