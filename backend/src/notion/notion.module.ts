import { Global, Module } from '@nestjs/common';
import { NotionService } from './notion.service';

/** Global para que cualquier módulo inyecte NotionService sin re-importar. */
@Global()
@Module({
  providers: [NotionService],
  exports: [NotionService],
})
export class NotionModule {}
