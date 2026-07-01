import { Module } from '@nestjs/common';
import { ProfilesModule } from '../profiles/profiles.module';
import { CourtsController } from './courts.controller';
import { CourtsService } from './courts.service';

@Module({
  imports: [ProfilesModule],
  controllers: [CourtsController],
  providers: [CourtsService],
})
export class CourtsModule {}
