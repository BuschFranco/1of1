import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/** Protege endpoints REST: exige un Bearer JWT válido. */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
