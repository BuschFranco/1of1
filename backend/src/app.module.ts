import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { ClansModule } from './clans/clans.module';
import { CourtsModule } from './courts/courts.module';
import { FriendsModule } from './friends/friends.module';
import { MatchesModule } from './matches/matches.module';
import { PrismaModule } from './prisma/prisma.module';
import { PickupsModule } from './pickups/pickups.module';
import { ProfilesModule } from './profiles/profiles.module';
import { RankingsModule } from './rankings/rankings.module';
import { UploadsModule } from './uploads/uploads.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    AuthModule,
    ProfilesModule,
    CourtsModule,
    PickupsModule,
    FriendsModule,
    MatchesModule,
    ClansModule,
    RankingsModule,
    UploadsModule,
  ],
})
export class AppModule {}
