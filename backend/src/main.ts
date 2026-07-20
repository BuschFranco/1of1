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
  // 0.0.0.0 explícito: la app en el celu se conecta por la IP LAN de esta PC.
  await app.listen(port, '0.0.0.0');
  // eslint-disable-next-line no-console
  console.log(`1of1 backend escuchando en http://0.0.0.0:${port}`);
}
bootstrap();
