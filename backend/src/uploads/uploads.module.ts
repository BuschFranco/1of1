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
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import axios from 'axios';
import { randomUUID } from 'crypto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Subida de imágenes. La app comprime a WebP ANTES de mandar
// (flutter_image_compress); acá solo se valida tipo/tamaño y se sube. La URL
// pública resultante se guarda como texto (courts.img) — la DB nunca ve bytes.
//
// Destino: Cloudflare R2 si están las R2_* (VPS, img.buschfranco.com); si no,
// Supabase Storage (bucket público "media", con la service key) como antes.
// Las dos conviven mientras Render siga activo (ver README → "VPS").

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

  private readonly r2Bucket = process.env.R2_BUCKET ?? '';
  private readonly r2PublicUrl = (process.env.R2_PUBLIC_URL ?? '').replace(/\/$/, '');
  private readonly r2: S3Client | null =
    process.env.R2_ACCOUNT_ID &&
    process.env.R2_ACCESS_KEY_ID &&
    process.env.R2_SECRET_ACCESS_KEY &&
    this.r2Bucket &&
    this.r2PublicUrl
      ? new S3Client({
          region: 'auto',
          endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
          credentials: {
            accessKeyId: process.env.R2_ACCESS_KEY_ID,
            secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
          },
        })
      : null;

  get isConfigured(): boolean {
    return (
      this.r2 !== null ||
      (this.baseUrl.length > 0 && this.serviceKey.length > 0)
    );
  }

  /** Sube el buffer a `media/<folder>/<uuid>.<ext>` y devuelve la URL pública. */
  async upload(
    folder: string,
    file: { buffer: Buffer; mimetype: string; size: number },
  ): Promise<{ url: string }> {
    if (!this.isConfigured) {
      throw new ServiceUnavailableException(
        'Storage no configurado (R2_* o SUPABASE_URL / SUPABASE_SERVICE_KEY).',
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
    if (this.r2) {
      try {
        await this.r2.send(
          new PutObjectCommand({
            Bucket: this.r2Bucket,
            Key: path,
            Body: file.buffer,
            ContentType: file.mimetype,
            // El nombre es un uuid: el archivo nunca cambia.
            CacheControl: 'public, max-age=31536000, immutable',
          }),
        );
      } catch (e) {
        this.log.error(`upload a R2 falló: ${(e as Error)?.message ?? e}`);
        throw new ServiceUnavailableException('No se pudo subir la imagen.');
      }
      return { url: `${this.r2PublicUrl}/${path}` };
    }
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
