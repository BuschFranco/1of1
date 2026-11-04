import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import compression from 'compression';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Compresión gzip para respuestas JSON (~85-90% reducción de tamaño).
  app.use(compression());

  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, transform: true }),
  );
  app.enableCors({ origin: process.env.CORS_ORIGIN ?? '*' });

  const port = Number(process.env.PORT ?? 3000);
  // 0.0.0.0 por defecto: en dev la app en el celu se conecta por la IP LAN de
  // esta PC. En la VPS HOST=127.0.0.1 (solo Caddy le habla).
  const host = process.env.HOST ?? '0.0.0.0';
  await app.listen(port, host);
  // eslint-disable-next-line no-console
  console.log(`1of1 backend escuchando en http://${host}:${port}`);
}
bootstrap();
