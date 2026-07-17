import { HttpException, Injectable, Logger } from '@nestjs/common';
import axios, { AxiosInstance } from 'axios';
import { notionConfig } from './notion.config';

type Props = Record<string, any>;

/**
 * Cliente de la API REST de Notion (portado del NotionService de la app Dart).
 * Query/create/update/retrieve sobre databases + helpers para construir y
 * parsear propiedades (title, rich_text, number, checkbox, select,
 * multi_select, url, phone_number, date).
 *
 * Es el ÚNICO punto que habla con Notion: el token vive acá (server-side).
 */
@Injectable()
export class NotionService {
  private readonly log = new Logger(NotionService.name);
  private readonly http: AxiosInstance;
  readonly cfg = notionConfig();

  constructor() {
    this.http = axios.create({
      baseURL: 'https://api.notion.com/v1',
      headers: {
        Authorization: `Bearer ${this.cfg.token}`,
        'Notion-Version': this.cfg.apiVersion,
        'Content-Type': 'application/json',
      },
      timeout: 15000,
    });
  }

  get isConfigured(): boolean {
    return this.cfg.token.length > 0;
  }

  private fail(op: string, e: any): never {
    const status = e?.response?.status ?? 502;
    const body = e?.response?.data ?? e?.message ?? 'unknown';
    this.log.error(`Notion ${op} falló (HTTP ${status}): ${JSON.stringify(body)}`);
    throw new HttpException(`Notion ${op} error`, status >= 400 && status < 600 ? status : 502);
  }

  // ── Operaciones ────────────────────────────────────────────────────────

  async queryDatabase(
    databaseId: string,
    opts: { filter?: any; sorts?: any[]; pageSize?: number } = {},
  ): Promise<any[]> {
    try {
      const body: Props = { page_size: opts.pageSize ?? 100 };
      if (opts.filter) body.filter = opts.filter;
      if (opts.sorts) body.sorts = opts.sorts;
      const res = await this.http.post(`/databases/${databaseId}/query`, body);
      return (res.data.results ?? []) as any[];
    } catch (e) {
      this.fail('queryDatabase', e);
    }
  }

  /** Como queryDatabase pero sigue la paginación (`next_cursor`) hasta agotar
   * la base o llegar a [maxPages]. Necesario cuando el resultado puede superar
   * las 100 filas (pickups del usuario, ranking, borrado de cuenta). */
  async queryDatabaseAll(
    databaseId: string,
    opts: { filter?: any; sorts?: any[]; maxPages?: number } = {},
  ): Promise<any[]> {
    const out: any[] = [];
    let cursor: string | undefined;
    const maxPages = opts.maxPages ?? 20;
    try {
      for (let i = 0; i < maxPages; i++) {
        const body: Props = { page_size: 100 };
        if (opts.filter) body.filter = opts.filter;
        if (opts.sorts) body.sorts = opts.sorts;
        if (cursor) body.start_cursor = cursor;
        const res = await this.http.post(
          `/databases/${databaseId}/query`,
          body,
        );
        out.push(...((res.data.results ?? []) as any[]));
        if (!res.data.has_more) break;
        cursor = res.data.next_cursor as string | undefined;
        if (!cursor) break;
      }
      return out;
    } catch (e) {
      this.fail('queryDatabaseAll', e);
    }
  }

  async createPage(databaseId: string, properties: Props): Promise<any> {
    try {
      const res = await this.http.post('/pages', {
        parent: { database_id: databaseId },
        properties,
      });
      return res.data;
    } catch (e) {
      this.fail('createPage', e);
    }
  }

  async updatePage(pageId: string, properties: Props): Promise<any> {
    try {
      const res = await this.http.patch(`/pages/${pageId}`, { properties });
      return res.data;
    } catch (e) {
      this.fail('updatePage', e);
    }
  }

  async retrievePage(pageId: string): Promise<any> {
    try {
      const res = await this.http.get(`/pages/${pageId}`);
      return res.data;
    } catch (e) {
      this.fail('retrievePage', e);
    }
  }

  async archivePage(pageId: string): Promise<void> {
    try {
      await this.http.patch(`/pages/${pageId}`, { archived: true });
    } catch (e) {
      this.fail('archivePage', e);
    }
  }

  /** Asegura columnas (nombre -> tipo). Idempotente; Notion fusiona el schema. */
  async ensureProperties(
    databaseId: string,
    nameToType: Record<string, string>,
  ): Promise<void> {
    if (Object.keys(nameToType).length === 0) return;
    try {
      const properties: Props = {};
      for (const [name, type] of Object.entries(nameToType)) {
        properties[name] = { [type]: {} };
      }
      await this.http.patch(`/databases/${databaseId}`, { properties });
    } catch (e) {
      // best-effort: si falla por permisos, se puede crear a mano en Notion.
      this.log.warn(`ensureProperties: ${e?.message ?? e}`);
    }
  }

  // ── Builders: valor -> propiedad Notion ─────────────────────────────────

  static title = (v: string): Props => ({ title: [{ text: { content: v } }] });
  static richText = (v: string): Props => ({
    rich_text: [{ text: { content: v } }],
  });
  static number = (v: number | null): Props => ({ number: v });
  static checkbox = (v: boolean): Props => ({ checkbox: v });
  static select = (v: string | null): Props => ({
    select: !v ? null : { name: v },
  });
  static multiSelect = (vs: string[]): Props => ({
    multi_select: vs.map((name) => ({ name })),
  });
  static url = (v: string | null): Props => ({ url: !v ? null : v });
  static phone = (v: string | null): Props => ({ phone_number: !v ? null : v });
  static date = (isoStart: string | null): Props => ({
    date: isoStart ? { start: isoStart } : null,
  });

  // ── Parsers: página Notion -> valor (reciben el mapa `properties`) ───────

  static readTitle(p: Props, name: string): string {
    const list = p?.[name]?.title as any[] | undefined;
    if (!list?.length) return '';
    return list.map((e) => e.plain_text ?? '').join('');
  }
  static readText(p: Props, name: string): string {
    const list = p?.[name]?.rich_text as any[] | undefined;
    if (!list?.length) return '';
    return list.map((e) => e.plain_text ?? '').join('');
  }
  static readNumber(p: Props, name: string, fallback = 0): number {
    const v = p?.[name]?.number;
    return typeof v === 'number' ? v : fallback;
  }
  static readInt(p: Props, name: string, fallback = 0): number {
    const v = p?.[name]?.number;
    return typeof v === 'number' ? Math.trunc(v) : fallback;
  }
  static readCheckbox(p: Props, name: string): boolean {
    return p?.[name]?.checkbox === true;
  }
  static readSelect(p: Props, name: string, fallback = ''): string {
    return p?.[name]?.select?.name ?? fallback;
  }
  static readMultiSelect(p: Props, name: string): string[] {
    const list = p?.[name]?.multi_select as any[] | undefined;
    if (!list) return [];
    return list.map((e) => (e.name ?? '').toString());
  }
  static readUrl(p: Props, name: string, fallback = ''): string {
    return p?.[name]?.url ?? fallback;
  }
  static readPhone(p: Props, name: string, fallback = ''): string {
    return p?.[name]?.phone_number ?? fallback;
  }
  static readDate(p: Props, name: string): string | null {
    return p?.[name]?.date?.start ?? null;
  }

  // ── Filtros ─────────────────────────────────────────────────────────────

  static filterText = (property: string, value: string) => ({
    property,
    rich_text: { equals: value },
  });
  static filterTitle = (property: string, value: string) => ({
    property,
    title: { equals: value },
  });
  static filterCheckbox = (property: string, value: boolean) => ({
    property,
    checkbox: { equals: value },
  });
  static filterSelect = (property: string, value: string) => ({
    property,
    select: { equals: value },
  });
  static filterTextNotEmpty = (property: string) => ({
    property,
    rich_text: { is_not_empty: true },
  });
  static filterTextContains = (property: string, value: string) => ({
    property,
    rich_text: { contains: value },
  });
  static filterDateOnOrAfter = (property: string, isoDate: string) => ({
    property,
    date: { on_or_after: isoDate },
  });
  static filterOr = (filters: any[]) => ({ or: filters });
  static filterAnd = (filters: any[]) => ({ and: filters });
}
