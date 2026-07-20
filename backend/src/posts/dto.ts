import { IsString, MaxLength } from 'class-validator';

export class CreatePostDto {
  @IsString()
  @MaxLength(300)
  content!: string;
}

export class CreateCommentDto {
  @IsString()
  @MaxLength(300)
  content!: string;
}
