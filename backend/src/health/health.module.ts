import { Controller, Get, Module } from '@nestjs/common';

// Health check público (sin JWT): lo usan el health check de Render y el ping
// keep-alive (cron externo cada ~10 min) para que el free tier no se duerma.
@Controller('health')
class HealthController {
  @Get()
  health() {
    return { ok: true };
  }
}

@Module({ controllers: [HealthController] })
export class HealthModule {}
