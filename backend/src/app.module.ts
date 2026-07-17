import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { ClansModule } from './clans/clans.module';
import { CourtsModule } from './courts/courts.module';
import { FriendsModule } from './friends/friends.module';
import { MatchesModule } from './matches/matches.module';
import { NotionModule } from './notion/notion.module';
import { PickupsModule } from './pickups/pickups.module';
import { ProfilesModule } from './profiles/profiles.module';
import { RankingsModule } from './rankings/rankings.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    NotionModule,
    AuthModule,
    ProfilesModule,
    CourtsModule,
    PickupsModule,
    FriendsModule,
    MatchesModule,
    ClansModule,
    RankingsModule,
  ],
})
export class AppModule {}
