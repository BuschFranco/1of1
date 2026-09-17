import {
  Controller,
  Get,
  Injectable,
  Logger,
  Module,
  Query,
  UseGuards,
} from '@nestjs/common';
import axios from 'axios';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Noticias de básquet (NBA / WNBA / Liga Nacional) por cuenta del backend.
//
// Dos fuentes gratis, ninguna llamada directo desde la app — mismo motivo que
// GeoModule: si alguna necesitara key, quedaría expuesta en el APK; y acá
// además el cupo diario de NewsData.io es compartido entre TODOS los
// usuarios, así que hay que cachear server-side o se funde entre pocos.
//
// - NBA/WNBA: API no oficial de ESPN (site.api.espn.com), sin key, con
//   endpoint de noticias dedicado por liga. No es un contrato documentado por
//   ESPN, pero es la misma API que alimenta su propia app — ampliamente usada
//   así, sin límite publicado.
// - Liga Nacional (Argentina): no existe API ni RSS dedicado para la LNB (se
//   confirmó: el sitio oficial es una SPA sin feed). Sale de NewsData.io,
//   filtrando por palabra clave — es la única capa gratis que permite uso
//   comercial (NEWSDATA_API_KEY del entorno, análoga a MAPS_API_KEY).

const CACHE_TTL_MS = 30 * 60 * 1000; // 30 min: no hace falta frescura al segundo

/// Forma común a la que se mapean las dos fuentes, para que el lado app tenga
/// un solo modelo (NewsArticle) sin saber de dónde vino cada nota.
type Article = {
  title: string;
  summary: string;
  url: string;
  imageUrl: string;
  source: string;
  publishedAt: string;
};

type League = 'nba' | 'wnba' | 'lnb';

@Injectable()
class NewsService {
  private readonly log = new Logger(NewsService.name);
  private readonly newsdataKey = process.env.NEWSDATA_API_KEY ?? '';
  private readonly cache = new Map<League, { at: number; value: Article[] }>();

  async forLeague(league: League): Promise<Article[]> {
    const hit = this.cache.get(league);
    if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;

    const value =
      league === 'lnb' ? await this.fromNewsData() : await this.fromEspn(league);

    this.cache.set(league, { at: Date.now(), value });
    return value;
  }

  /// NBA/WNBA: endpoint de noticias de ESPN. Nunca lanza: ante cualquier falla
  /// (timeout, shape inesperado) degrada a lista vacía.
  private async fromEspn(league: 'nba' | 'wnba'): Promise<Article[]> {
    try {
      const res = await axios.get(
        `http://site.api.espn.com/apis/site/v2/sports/basketball/${league}/news`,
        { timeout: 8000 },
      );
      const articles = (res.data?.articles ?? []) as {
        headline?: string;
        description?: string;
        links?: { web?: { href?: string } };
        images?: { url?: string }[];
        published?: string;
      }[];
      return articles.map((a) => ({
        title: a.headline ?? '',
        summary: a.description ?? '',
        url: a.links?.web?.href ?? '',
        imageUrl: a.images?.[0]?.url ?? '',
        source: 'ESPN',
        publishedAt: a.published ?? '',
      }));
    } catch (e) {
      this.log.error(`espn news (${league}) falló: ${(e as Error)?.message ?? e}`);
      return [];
    }
  }

  /// Liga Nacional: NewsData.io por palabra clave — no hay endpoint dedicado
  /// para la LNB en ningún lado. `category=sports&language=es` acota el ruido
  /// del keyword search; igual puede traer alguna nota de otro deporte.
  private async fromNewsData(): Promise<Article[]> {
    if (!this.newsdataKey) return [];
    try {
      const res = await axios.get('https://newsdata.io/api/1/latest', {
        params: {
          apikey: this.newsdataKey,
          q: '"Liga Nacional de Básquet" OR "básquet argentino" OR "La Liga Argentina"',
          category: 'sports',
          language: 'es',
        },
        timeout: 8000,
      });
      const data = res.data as {
        status?: string;
        results?: {
          title?: string;
          description?: string;
          link?: string;
          image_url?: string;
          source_id?: string;
          pubDate?: string;
        }[];
      };
      if (data.status !== 'success' || !data.results?.length) return [];
      return data.results.map((r) => ({
        title: r.title ?? '',
        summary: r.description ?? '',
        url: r.link ?? '',
        imageUrl: r.image_url ?? '',
        source: r.source_id ?? 'NewsData',
        publishedAt: r.pubDate ?? '',
      }));
    } catch (e) {
      this.log.error(`newsdata (lnb) falló: ${(e as Error)?.message ?? e}`);
      return [];
    }
  }
}

@Controller('news')
@UseGuards(JwtAuthGuard)
class NewsController {
  constructor(private readonly svc: NewsService) {}

  /// Feed de noticias por liga. Lista vacía si la liga no es válida o si la
  /// fuente falló — quien llama degrada a "sin noticias", no a un error.
  @Get()
  news(@Query('league') league: string) {
    const l = league === 'nba' || league === 'wnba' || league === 'lnb'
      ? league
      : null;
    if (!l) return [];
    return this.svc.forLeague(l);
  }
}

@Module({
  controllers: [NewsController],
  providers: [NewsService],
})
export class NewsModule {}
