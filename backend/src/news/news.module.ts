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

type League = 'nba' | 'wnba' | 'lnb' | '3x3';

const MAX_RSS_ITEMS = 20;

@Injectable()
class NewsService {
  private readonly log = new Logger(NewsService.name);
  private readonly newsdataKey = process.env.NEWSDATA_API_KEY ?? '';
  private readonly cache = new Map<League, { at: number; value: Article[] }>();

  async forLeague(league: League): Promise<Article[]> {
    const hit = this.cache.get(league);
    if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;

    const value =
      league === 'lnb'
        ? await this.fromNewsData()
        : league === '3x3'
          ? await this.fromGoogleNews()
          : await this.fromEspn(league);

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
      const base = articles.map((a) => ({
        title: a.headline ?? '',
        summary: a.description ?? '',
        url: a.links?.web?.href ?? '',
        imageUrl: a.images?.[0]?.url ?? '',
        source: 'ESPN',
        publishedAt: a.published ?? '',
      }));
      // ESPN viene en inglés: traducimos título y resumen. Por artículo (no
      // en batch) para que una traducción fallida no tire abajo las demás.
      return Promise.all(
        base.map(async (a) => ({
          ...a,
          title: await this.translateToEs(a.title),
          summary: await this.translateToEs(a.summary),
        })),
      );
    } catch (e) {
      this.log.error(`espn news (${league}) falló: ${(e as Error)?.message ?? e}`);
      return [];
    }
  }

  /// Traduce un texto EN→ES vía el endpoint no oficial de Google Translate
  /// (sin key, sin límite documentado — mismo criterio que ESPN: no es un
  /// contrato soportado, pero es lo que usa medio internet gratis). Nunca
  /// lanza: si falla, devuelve el texto original en inglés antes que romper
  /// el feed. El costo es bajo a propósito: esto corre una vez cada 30 min
  /// (el TTL del caché de la liga), no por cada request de cada usuario.
  private async translateToEs(text: string): Promise<string> {
    if (!text) return text;
    try {
      const res = await axios.get(
        'https://translate.googleapis.com/translate_a/single',
        {
          params: { client: 'gtx', sl: 'en', tl: 'es', dt: 't', q: text },
          timeout: 6000,
        },
      );
      const segments = (res.data?.[0] ?? []) as unknown[][];
      const joined = segments.map((s) => (s?.[0] as string) ?? '').join('');
      return joined || text;
    } catch (e) {
      this.log.warn(`traducción falló, queda en inglés: ${(e as Error)?.message ?? e}`);
      return text;
    }
  }

  /// 3x3: no hay API ni feed dedicado (ESPN no tiene liga 3x3 y la API de FIBA
  /// 3x3 es privada). Sale del RSS de búsqueda de Google News, sin key y sin
  /// cupo diario; no es un contrato documentado, pero es un feed público
  /// estándar. Nunca lanza: ante cualquier falla devuelve lista vacía.
  private async fromGoogleNews(): Promise<Article[]> {
    try {
      const res = await axios.get('https://news.google.com/rss/search', {
        params: {
          q: '"FIBA 3x3" OR "3x3 basketball" OR "básquet 3x3"',
          hl: 'es-419',
          gl: 'AR',
          ceid: 'AR:es-419',
        },
        timeout: 8000,
        responseType: 'text',
      });
      const xml = String(res.data ?? '');
      const tag = (block: string, name: string): string => {
        const m = block.match(
          new RegExp(`<${name}[^>]*>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?</${name}>`),
        );
        return this.decodeXml((m?.[1] ?? '').trim());
      };
      const items = (xml.match(/<item>[\s\S]*?<\/item>/g) ?? []).map((b) => {
        const source = tag(b, 'source');
        let title = tag(b, 'title');
        // Google agrega " - Fuente" al final del título.
        if (source && title.endsWith(` - ${source}`)) {
          title = title.slice(0, -(source.length + 3));
        }
        const pub = tag(b, 'pubDate');
        const ms = Date.parse(pub);
        return {
          ms: Number.isNaN(ms) ? 0 : ms,
          article: {
            title,
            summary: '',
            url: tag(b, 'link'),
            imageUrl: '',
            source: source || 'Google News',
            publishedAt: Number.isNaN(ms) ? '' : new Date(ms).toISOString(),
          } as Article,
        };
      });
      return items
        .filter((i) => i.article.title && i.article.url)
        .sort((a, b) => b.ms - a.ms)
        .slice(0, MAX_RSS_ITEMS)
        .map((i) => i.article);
    } catch (e) {
      this.log.error(`google news (3x3) falló: ${(e as Error)?.message ?? e}`);
      return [];
    }
  }

  private decodeXml(s: string): string {
    return s
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;|&#39;/g, "'")
      .replace(/&amp;/g, '&');
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
    const l = league === 'nba' || league === 'wnba' || league === 'lnb' || league === '3x3'
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
