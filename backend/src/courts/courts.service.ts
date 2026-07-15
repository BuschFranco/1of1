import { Injectable } from '@nestjs/common';
import {
  Court,
  courtFromNotion,
  courtToNotionProps,
  COURT_APPROVAL,
  Review,
  reviewFromNotion,
  reviewToNotionProps,
} from '../notion/entities';
import { NotionService } from '../notion/notion.service';

@Injectable()
export class CourtsService {
  constructor(private readonly notion: NotionService) {}

  /** Canchas aprobadas (las que ve la app en el mapa/lista). */
  async listApproved(): Promise<Court[]> {
    const rows = await this.notion.queryDatabase(this.notion.cfg.db.courts, {
      filter: NotionService.filterSelect('Aprobacion', COURT_APPROVAL.approved),
    });
    return rows.map(courtFromNotion);
  }

  /** Canchas propuestas por el usuario, en CUALQUIER estado de aprobación.
   * El cliente compara `approval` contra su último estado conocido para avisar
   * aprobaciones/rechazos (no hay push entre usuarios). */
  async listMine(email: string): Promise<Court[]> {
    const rows = await this.notion.queryDatabaseAll(this.notion.cfg.db.courts, {
      filter: NotionService.filterText('CreatedByEmail', email.trim().toLowerCase()),
    });
    return rows.map(courtFromNotion);
  }

  /** Borra (archiva) una cancha y todas sus reseñas. Calca deleteCourt de la app. */
  async remove(courtId: string): Promise<void> {
    try {
      const reviews = await this.notion.queryDatabaseAll(
        this.notion.cfg.db.reviews,
        { filter: NotionService.filterText('CourtId', courtId) },
      );
      for (const r of reviews) {
        const id = r.id?.toString();
        if (id) await this.notion.archivePage(id);
      }
    } catch {
      // best-effort: igual archivamos la cancha.
    }
    await this.notion.archivePage(courtId);
  }

  async removeReview(pageId: string): Promise<void> {
    await this.notion.archivePage(pageId);
  }

  /** Propone una cancha nueva (queda pendiente de moderación). */
  async propose(
    court: Partial<Court>,
    meta: { createdBy: string; createdByClan: string; createdByEmail: string },
  ): Promise<Court> {
    const page = await this.notion.createPage(
      this.notion.cfg.db.courts,
      courtToNotionProps(court, meta),
    );
    return courtFromNotion(page);
  }

  async listReviews(courtId: string): Promise<Review[]> {
    const rows = await this.notion.queryDatabase(this.notion.cfg.db.reviews, {
      filter: NotionService.filterText('CourtId', courtId),
    });
    return rows.map(reviewFromNotion);
  }

  async addReview(
    courtId: string,
    userEmail: string,
    userHandle: string,
    rating: number,
    comment: string,
  ): Promise<Review> {
    const page = await this.notion.createPage(
      this.notion.cfg.db.reviews,
      reviewToNotionProps({
        courtId,
        userEmail,
        userHandle,
        rating,
        comment,
        createdAt: new Date().toISOString(),
      }),
    );
    return reviewFromNotion(page);
  }
}
