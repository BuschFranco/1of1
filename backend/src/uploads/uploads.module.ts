import {
  BadRequestException,
  Controller,
  Injectable,
  Logger,
  Module,
  Post,
  ServiceUnavailableException,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import axios from 'axios';
import { randomUUID } from 'crypto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Subida de imágenes a Supabase Storage (bucket público "media"). La app
// comprime a WebP ANTES de mandar (flutter_image_compress); acá solo se valida
// tipo/tamaño y se sube con la service key (server-side, bypassa RLS). La URL
// pública resultante se guarda como texto (courts.img) — la DB nunca ve bytes.

const BUCKET = 'media';
const MAX_BYTES = 8 * 1024 * 1024; // 8 MB post-compresión: holgado
const ALLOWED: Record<string, string> = {
  'image/webp': 'webp',
  'image/jpeg': 'jpg',
  'image/png': 'png',
};

@Injectable()
class UploadsService {
  private readonly log = new Logger(UploadsService.name);
  private readonly baseUrl = (process.env.SUPABASE_URL ?? '').replace(/\/$/, '');
  private readonly serviceKey = process.env.SUPABASE_SERVICE_KEY ?? '';

  get isConfigured(): boolean {
    return this.baseUrl.length > 0 && this.serviceKey.length > 0;
  }

  /** Sube el buffer a `media/<folder>/<uuid>.<ext>` y devuelve la URL pública. */
  async upload(
    folder: string,
    file: { buffer: Buffer; mimetype: string; size: number },
  ): Promise<{ url: string }> {
    if (!this.isConfigured) {
      throw new ServiceUnavailableException(
        'Storage no configurado (SUPABASE_URL / SUPABASE_SERVICE_KEY).',
      );
    }
    const ext = ALLOWED[file.mimetype];
    if (!ext) {
      throw new BadRequestException('Formato no soportado (webp/jpeg/png).');
    }
    if (file.size > MAX_BYTES) {
      throw new BadRequestException('La imagen supera los 8 MB.');
    }
    const path = `${folder}/${randomUUID()}.${ext}`;
    try {
      await axios.post(
        `${this.baseUrl}/storage/v1/object/${BUCKET}/${path}`,
        file.buffer,
        {
          headers: {
            Authorization: `Bearer ${this.serviceKey}`,
            'Content-Type': file.mimetype,
            'x-upsert': 'false',
          },
          maxBodyLength: MAX_BYTES + 1024,
          timeout: 30_000,
        },
      );
    } catch (e) {
      this.log.error(`upload a Storage falló: ${(e as Error)?.message ?? e}`);
      throw new ServiceUnavailableException('No se pudo subir la imagen.');
    }
    return { url: `${this.baseUrl}/storage/v1/object/public/${BUCKET}/${path}` };
  }
}

@Controller('uploads')
@UseGuards(JwtAuthGuard)
class UploadsController {
  constructor(private readonly uploads: UploadsService) {}

  /** Foto de cancha: multipart field "file". Devuelve {url} pública. */
  @Post('court-image')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_BYTES } }))
  courtImage(@UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('Falta el archivo "file".');
    return this.uploads.upload('courts', file);
  }
}

@Module({
  controllers: [UploadsController],
  providers: [UploadsService],
})
export class UploadsModule {}
