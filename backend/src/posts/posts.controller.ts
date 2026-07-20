import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/jwt.strategy';
import { ProfilesService } from '../profiles/profiles.service';
import { CreateCommentDto, CreatePostDto } from './dto';
import { PostsService } from './posts.service';

@Controller()
@UseGuards(JwtAuthGuard)
export class PostsController {
  constructor(
    private readonly posts: PostsService,
    private readonly profiles: ProfilesService,
  ) {}

  /** Listar publicaciones de una cancha (con likes del usuario), con paginación. */
  @Get('courts/:courtId/posts')
  list(
    @CurrentUser() user: AuthUser,
    @Param('courtId') courtId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    const take = Math.min(Math.max(parseInt(limit ?? '20', 10) || 20, 1), 50);
    return this.posts.listByCourt(courtId, user.email, take, cursor);
  }

  /** Crear publicación en una cancha. */
  @Post('courts/:courtId/posts')
  async create(
    @CurrentUser() user: AuthUser,
    @Param('courtId') courtId: string,
    @Body() dto: CreatePostDto,
  ) {
    const me = await this.profiles.getById(user.profileId);
    return this.posts.create(courtId, user.email, me.handle, dto.content);
  }

  /** Eliminar publicación (autor o admin). */
  @Delete('posts/:postId')
  async remove(
    @CurrentUser() user: AuthUser,
    @Param('postId') postId: string,
  ) {
    const post = await this.posts.getPost(postId);
    if (!user.isAdmin && post.userEmail.trim().toLowerCase() !== user.email.trim().toLowerCase()) {
      throw new ForbiddenException('Solo podés eliminar tus propias publicaciones.');
    }
    await this.posts.remove(postId);
    return { ok: true };
  }

  /** Like/unlike en una publicación (toggle). */
  @Post('posts/:postId/like')
  async togglePostLike(
    @CurrentUser() user: AuthUser,
    @Param('postId') postId: string,
  ) {
    return this.posts.togglePostLike(postId, user.email);
  }

  /** Agregar comentario a una publicación. */
  @Post('posts/:postId/comments')
  async addComment(
    @CurrentUser() user: AuthUser,
    @Param('postId') postId: string,
    @Body() dto: CreateCommentDto,
  ) {
    const me = await this.profiles.getById(user.profileId);
    return this.posts.addComment(postId, user.email, me.handle, dto.content);
  }

  /** Like/unlike en un comentario (toggle). */
  @Post('comments/:commentId/like')
  async toggleCommentLike(
    @CurrentUser() user: AuthUser,
    @Param('commentId') commentId: string,
  ) {
    return this.posts.toggleCommentLike(commentId, user.email);
  }

  /** Eliminar comentario (autor o admin). */
  @Delete('comments/:commentId')
  async removeComment(
    @CurrentUser() user: AuthUser,
    @Param('commentId') commentId: string,
  ) {
    const comment = await this.posts.getComment(commentId);
    if (!user.isAdmin && comment.userEmail.trim().toLowerCase() !== user.email.trim().toLowerCase()) {
      throw new ForbiddenException('Solo podés eliminar tus propios comentarios.');
    }
    await this.posts.removeComment(commentId);
    return { ok: true };
  }
}
