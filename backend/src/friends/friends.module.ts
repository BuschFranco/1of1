import {
  Body,
  Controller,
  Delete,
  Get,
  Injectable,
  Module,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsEmail, IsString } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { Friend, friendWire } from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';

class AddFriendDto {
  @IsString() friendHandle!: string;
  @IsString() friendName!: string;
  @IsEmail() friendEmail!: string;
}

@Injectable()
class FriendsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(ownerEmail: string): Promise<Friend[]> {
    const rows = await this.prisma.friend.findMany({
      where: { ownerEmail, archived: false },
    });
    return rows.map(friendWire);
  }

  async add(ownerEmail: string, dto: AddFriendDto): Promise<Friend> {
    const row = await this.prisma.friend.create({
      data: {
        ownerEmail,
        friendHandle: dto.friendHandle,
        friendName: dto.friendName,
        friendEmail: dto.friendEmail,
      },
    });
    return friendWire(row);
  }

  async remove(pageId: string): Promise<void> {
    await this.prisma.friend.updateMany({
      where: { id: pageId },
      data: { archived: true },
    });
  }
}

@Controller('friends')
@UseGuards(JwtAuthGuard)
class FriendsController {
  constructor(private readonly friends: FriendsService) {}

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.friends.list(user.email);
  }

  @Post()
  add(@CurrentUser() user: AuthUser, @Body() dto: AddFriendDto) {
    return this.friends.add(user.email, dto);
  }

  @Delete(':pageId')
  async remove(@Param('pageId') pageId: string) {
    await this.friends.remove(pageId);
    return { ok: true };
  }
}

@Module({
  controllers: [FriendsController],
  providers: [FriendsService],
})
export class FriendsModule {}
