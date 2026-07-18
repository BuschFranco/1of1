import { Injectable, NotFoundException } from '@nestjs/common';
import {
  ALLOWED_BADGES,
  Court,
  COURT_APPROVAL,
  courtWire,
  Review,
  reviewWire,
} from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';

@Injectable()
export class CourtsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Canchas aprobadas (las que ve la app en el mapa/lista). */
  async listApproved(): Promise<Court[]> {
    const rows = await this.prisma.court.findMany({
      where: { approval: COURT_APPROVAL.approved, archived: false },
    });
    return rows.map(courtWire);
  }

  /** Canchas propuestas por el usuario, en CUALQUIER estado de aprobación.
   * El cliente compara `approval` contra su último estado conocido para avisar
   * aprobaciones/rechazos (no hay push entre usuarios). */
  async listMine(email: string): Promise<Court[]> {
    const rows = await this.prisma.court.findMany({
      where: {
        proposedByEmail: email.trim().toLowerCase(),
        archived: false,
      },
    });
    return rows.map(courtWire);
  }

  /** Borra (archiva) una cancha y todas sus reseñas. */
  async remove(courtId: string): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.review.updateMany({
        where: { courtId, archived: false },
        data: { archived: true },
      }),
      this.prisma.court.updateMany({
        where: { id: courtId },
        data: { archived: true },
      }),
    ]);
  }

  /** Recupera una reseña por id (para validar propiedad antes de borrar). */
  async getReview(pageId: string): Promise<Review> {
    const row = await this.prisma.review.findUnique({ where: { id: pageId } });
    if (!row) throw new NotFoundException('Reseña no encontrada.');
    return reviewWire(row);
  }

  async removeReview(pageId: string): Promise<void> {
    await this.prisma.review.updateMany({
      where: { id: pageId },
      data: { archived: true },
    });
  }

  /** Propone una cancha nueva (queda pendiente de moderación). */
  async propose(
    court: Record<string, any>,
    meta: { createdBy: string; createdByClan: string; createdByEmail: string },
  ): Promise<Court> {
    const row = await this.prisma.court.create({
      data: {
        name: court.name ?? '',
        area: court.area ?? '',
        dist: court.dist ?? '',
        img: court.img ?? '',
        type: court.type ?? 'Exterior',
        free: court.free ?? false,
        lit: court.lit ?? false,
        hoops: court.hoops ?? 1,
        surface: court.surface ?? 'Asfalto',
        vibe: court.vibe ?? 'Casual',
        hours: court.hours ?? '',
        openTime: court.openTime ?? '',
        closeTime: court.closeTime ?? '',
        badges: (court.badges ?? []).filter((b: string) =>
          ALLOWED_BADGES.has(b),
        ),
        desc: court.desc ?? '',
        lat: court.lat ?? 0,
        lng: court.lng ?? 0,
        proposedBy: meta.createdBy,
        proposedByClan: meta.createdByClan,
        proposedByEmail: meta.createdByEmail,
        // Toda propuesta entra pendiente de moderación.
        approval: COURT_APPROVAL.pending,
      },
    });
    return courtWire(row);
  }

  async listReviews(courtId: string): Promise<Review[]> {
    const rows = await this.prisma.review.findMany({
      where: { courtId, archived: false },
    });
    return rows.map(reviewWire);
  }

  async addReview(
    courtId: string,
    userEmail: string,
    userHandle: string,
    rating: number,
    comment: string,
  ): Promise<Review> {
    const row = await this.prisma.review.create({
      data: {
        courtId,
        userEmail,
        userHandle,
        rating,
        comment,
        createdAt: new Date(),
      },
    });
    return reviewWire(row);
  }
}
