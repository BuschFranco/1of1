import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { CourtPost, courtPostWire, PostComment, postCommentWire } from '../domain/wire';
import { PrismaService } from '../prisma/prisma.module';

@Injectable()
export class PostsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Listar publicaciones de una cancha (con comentarios y likes), paginadas. */
  async listByCourt(
    courtId: string,
    userEmail?: string,
    limit = 20,
    cursor?: string,
  ): Promise<{ items: CourtPost[]; nextCursor: string | null }> {
    const email = userEmail?.trim().toLowerCase();
    const rows: any[] = await this.prisma.courtPost.findMany({
      where: {
        courtId,
        archived: false,
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: limit + 1,
      include: {
        _count: { select: { likes: true } },
        ...(email
          ? {
              likes: {
                where: { userEmail: email },
                select: { id: true },
              },
              comments: {
                where: { archived: false },
                orderBy: { createdAt: 'asc' },
                include: {
                  _count: { select: { likes: true } },
                  likes: {
                    where: { userEmail: email },
                    select: { id: true },
                  },
                },
              },
            }
          : {
              comments: {
                where: { archived: false },
                orderBy: { createdAt: 'asc' },
                include: { _count: { select: { likes: true } } },
              },
            }),
      },
    } as any);

    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return {
      items: items.map((r: any) => {
        const comments = (r.comments || []).map((c: any) =>
          postCommentWire(
            c,
            c._count?.likes ?? 0,
            Array.isArray(c.likes) && c.likes.length > 0,
          ),
        );
        return courtPostWire(
          r,
          r._count?.likes ?? 0,
          Array.isArray(r.likes) && r.likes.length > 0,
          comments,
        );
      }),
      nextCursor,
    };
  }

  /** Crear una publicación (1 por usuario por día por cancha). */
  async create(
    courtId: string,
    email: string,
    handle: string,
    content: string,
  ): Promise<CourtPost> {
    // Verificar límite: 1 publicación por usuario por día en esta cancha.
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const todayCount = await this.prisma.courtPost.count({
      where: {
        courtId,
        userEmail: email.trim().toLowerCase(),
        archived: false,
        createdAt: { gte: startOfDay },
      },
    });

    if (todayCount > 0) {
      throw new BadRequestException(
        'Ya publicaste hoy en esta cancha. Intentá mañana.',
      );
    }

    const row = await this.prisma.courtPost.create({
      data: {
        courtId,
        userEmail: email.trim().toLowerCase(),
        userHandle: handle,
        content: content.trim(),
        createdAt: new Date(),
      },
    });

    return courtPostWire(row, 0, false, []);
  }

  /** Agregar comentario a una publicación. */
  async addComment(
    postId: string,
    email: string,
    handle: string,
    content: string,
  ): Promise<PostComment> {
    // Verificar que la publicación existe.
    const post = await this.prisma.courtPost.findUnique({
      where: { id: postId },
    });
    if (!post || post.archived) {
      throw new NotFoundException('Publicación no encontrada.');
    }

    const row = await this.prisma.postComment.create({
      data: {
        postId,
        userEmail: email.trim().toLowerCase(),
        userHandle: handle,
        content: content.trim(),
        createdAt: new Date(),
      },
    });

    return postCommentWire(row, 0, false);
  }

  /** Like/unlike en una publicación (toggle). */
  async togglePostLike(postId: string, email: string): Promise<{ liked: boolean; likeCount: number }> {
    const post = await this.prisma.courtPost.findUnique({ where: { id: postId } });
    if (!post || post.archived) {
      throw new NotFoundException('Publicación no encontrada.');
    }

    const normalizedEmail = email.trim().toLowerCase();
    const existing = await this.prisma.postLike.findUnique({
      where: { postId_userEmail: { postId, userEmail: normalizedEmail } },
    });

    if (existing) {
      await this.prisma.postLike.delete({ where: { id: existing.id } });
    } else {
      await this.prisma.postLike.create({
        data: { postId, userEmail: normalizedEmail },
      });
    }

    const likeCount = await this.prisma.postLike.count({ where: { postId } });
    return { liked: !existing, likeCount };
  }

  /** Like/unlike en un comentario (toggle). */
  async toggleCommentLike(commentId: string, email: string): Promise<{ liked: boolean; likeCount: number }> {
    const comment = await this.prisma.postComment.findUnique({ where: { id: commentId } });
    if (!comment || comment.archived) {
      throw new NotFoundException('Comentario no encontrado.');
    }

    const normalizedEmail = email.trim().toLowerCase();
    const existing = await this.prisma.commentLike.findUnique({
      where: { commentId_userEmail: { commentId, userEmail: normalizedEmail } },
    });

    if (existing) {
      await this.prisma.commentLike.delete({ where: { id: existing.id } });
    } else {
      await this.prisma.commentLike.create({
        data: { commentId, userEmail: normalizedEmail },
      });
    }

    const likeCount = await this.prisma.commentLike.count({ where: { commentId } });
    return { liked: !existing, likeCount };
  }

  /** Eliminar publicación (solo el autor o admin). */
  async remove(postId: string): Promise<void> {
    const commentIds = (await this.prisma.postComment.findMany({
      where: { postId },
      select: { id: true },
    })).map(c => c.id);

    await this.prisma.$transaction([
      this.prisma.postLike.deleteMany({ where: { postId } }),
      ...(commentIds.length > 0
        ? [this.prisma.commentLike.deleteMany({ where: { commentId: { in: commentIds } } })]
        : []),
      this.prisma.postComment.deleteMany({ where: { postId } }),
      this.prisma.courtPost.updateMany({
        where: { id: postId },
        data: { archived: true },
      }),
    ]);
  }

  /** Eliminar comentario (solo el autor o admin). */
  async removeComment(commentId: string): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.commentLike.deleteMany({ where: { commentId } }),
      this.prisma.postComment.updateMany({
        where: { id: commentId },
        data: { archived: true },
      }),
    ]);
  }

  /** Obtener una publicación por id (para validar propiedad). */
  async getPost(postId: string) {
    const row = await this.prisma.courtPost.findUnique({
      where: { id: postId },
    });
    if (!row) throw new NotFoundException('Publicación no encontrada.');
    return row;
  }

  /** Obtener un comentario por id (para validar propiedad). */
  async getComment(commentId: string) {
    const row = await this.prisma.postComment.findUnique({
      where: { id: commentId },
    });
    if (!row) throw new NotFoundException('Comentario no encontrado.');
    return row;
  }
}
