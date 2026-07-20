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

    // Los modelos de posts/comentarios/likes se relacionan solo por IDs
    // escalares (postId, commentId) — no hay `@relation` en el schema, así que
    // no se puede usar `include`. Traemos los posts y después resolvemos likes y
    // comentarios con consultas separadas por ID (mismo patrón que `remove`).
    const rows = await this.prisma.courtPost.findMany({
      where: {
        courtId,
        archived: false,
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: limit + 1,
    });

    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    if (items.length === 0) {
      return { items: [], nextCursor };
    }

    const postIds = items.map((p) => p.id);

    // Likes de los posts: conteo por post + cuáles likeó el usuario actual.
    const postLikeGroups = await this.prisma.postLike.groupBy({
      by: ['postId'],
      where: { postId: { in: postIds } },
      _count: true,
    });
    const postLikeCount = new Map<string, number>(
      postLikeGroups.map((g) => [g.postId, g._count]),
    );
    const myPostLikes = email
      ? new Set(
          (
            await this.prisma.postLike.findMany({
              where: { postId: { in: postIds }, userEmail: email },
              select: { postId: true },
            })
          ).map((l) => l.postId),
        )
      : new Set<string>();

    // Comentarios (no archivados) de todos los posts de esta página.
    const commentRows = await this.prisma.postComment.findMany({
      where: { postId: { in: postIds }, archived: false },
      orderBy: { createdAt: 'asc' },
    });

    // Likes de esos comentarios: conteo + cuáles likeó el usuario actual.
    const commentIds = commentRows.map((c) => c.id);
    const commentLikeCount = new Map<string, number>();
    let myCommentLikes = new Set<string>();
    if (commentIds.length > 0) {
      const commentLikeGroups = await this.prisma.commentLike.groupBy({
        by: ['commentId'],
        where: { commentId: { in: commentIds } },
        _count: true,
      });
      for (const g of commentLikeGroups) {
        commentLikeCount.set(g.commentId, g._count);
      }
      if (email) {
        myCommentLikes = new Set(
          (
            await this.prisma.commentLike.findMany({
              where: { commentId: { in: commentIds }, userEmail: email },
              select: { commentId: true },
            })
          ).map((l) => l.commentId),
        );
      }
    }

    // Agrupar comentarios por post (ya vienen ordenados por createdAt asc).
    const commentsByPost = new Map<string, PostComment[]>();
    for (const c of commentRows) {
      const wire = postCommentWire(
        c,
        commentLikeCount.get(c.id) ?? 0,
        myCommentLikes.has(c.id),
      );
      const list = commentsByPost.get(c.postId);
      if (list) {
        list.push(wire);
      } else {
        commentsByPost.set(c.postId, [wire]);
      }
    }

    return {
      items: items.map((r) =>
        courtPostWire(
          r,
          postLikeCount.get(r.id) ?? 0,
          myPostLikes.has(r.id),
          commentsByPost.get(r.id) ?? [],
        ),
      ),
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
