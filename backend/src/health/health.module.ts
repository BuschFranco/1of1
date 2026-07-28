import { Controller, Get, Module, Res } from '@nestjs/common';
import type { Response } from 'express';

// Health check público (sin JWT): lo usan el health check de Render y el ping
// keep-alive (cron externo cada ~10 min) para que el free tier no se duerma.
//
// Responde "1" en text/plain con Content-Length explícito (no chunked): los
// servicios de cron gratuitos miden el tamaño de la respuesta y algunos marcan
// "output too large" cuando no pueden determinarlo de antemano. Un byte con
// largo declarado no deja lugar a dudas.
@Controller('health')
class HealthController {
  @Get()
  health(@Res() res: Response) {
    const body = '1';
    res
      .status(200)
      .type('text/plain')
      .set('Content-Length', Buffer.byteLength(body).toString())
      .set('Cache-Control', 'no-store')
      .send(body);
  }
}

@Module({ controllers: [HealthController] })
export class HealthModule {}
