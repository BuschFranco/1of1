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
import {
  Friend,
  friendFromNotion,
  friendToNotionProps,
} from '../notion/entities';
import { NotionService } from '../notion/notion.service';

class AddFriendDto {
  @IsString() friendHandle!: string;
  @IsString() friendName!: string;
  @IsEmail() friendEmail!: string;
}

@Injectable()
class FriendsService {
  constructor(private readonly notion: NotionService) {}

  async list(ownerEmail: string): Promise<Friend[]> {
    const rows = await this.notion.queryDatabase(this.notion.cfg.db.friends, {
      filter: NotionService.filterText('OwnerEmail', ownerEmail),
    });
    return rows.map(friendFromNotion);
  }

  async add(ownerEmail: string, dto: AddFriendDto): Promise<Friend> {
    const page = await this.notion.createPage(
      this.notion.cfg.db.friends,
      friendToNotionProps({
        ownerEmail,
        friendHandle: dto.friendHandle,
        friendName: dto.friendName,
        friendEmail: dto.friendEmail,
      }),
    );
    return friendFromNotion(page);
  }

  async remove(pageId: string): Promise<void> {
    await this.notion.archivePage(pageId);
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
