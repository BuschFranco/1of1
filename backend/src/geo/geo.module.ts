import {
  Controller,
  Get,
  Injectable,
  Logger,
  Module,
  Query,
  ServiceUnavailableException,
  UseGuards,
} from '@nestjs/common';
import axios from 'axios';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Reverse geocoding (lat/lng → barrio y ciudad) por cuenta del backend.
//
// La app NO puede llamar a la Geocoding API directamente: su MAPS_API_KEY está
// restringida a la app Android (package + firma), restricción que vale para el
// Maps SDK pero NO para los web services — una llamada REST llega con IP y sin
// firma, así que Google la rechaza con REQUEST_DENIED. Eso hacía que la zona no
// se autocompletara nunca al dar de alta una cancha.
//
// Acá la key vive server-side (MAPS_API_KEY del entorno), donde puede estar sin
// restricción de app sin quedar expuesta en el APK.

/// Redondeo del cacheo: ~110 m, del orden del radio de una cancha. El pin
/// dispara un lookup cada vez que se asienta, así que sin esto se gasta cuota
/// en repetir la misma esquina.
const CACHE_PRECISION = 3;
const CACHE_MAX = 500;
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

type Place = { city: string; area: string };
type Component = { long_name?: string; types?: string[] };

@Injectable()
class GeoService {
  private readonly log = new Logger(GeoService.name);
  private readonly key = process.env.MAPS_API_KEY ?? '';
  private readonly cache = new Map<string, { at: number; value: Place }>();

  get isConfigured(): boolean {
    return this.key.length > 0;
  }

  /** Primer componente cuyo `types` incluya alguno de [types]. */
  private first(comps: Component[], types: string[]): string {
    for (const t of types) {
      for (const c of comps) {
        if ((c.types ?? []).includes(t) && c.long_name) return c.long_name;
      }
    }
    return '';
  }

  async reverse(lat: number, lng: number): Promise<Place> {
    if (!this.isConfigured) {
      throw new ServiceUnavailableException(
        'Geocoding no configurado (falta MAPS_API_KEY).',
      );
    }
    const cacheKey = `${lat.toFixed(CACHE_PRECISION)},${lng.toFixed(CACHE_PRECISION)}`;
    const hit = this.cache.get(cacheKey);
    if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;

    let comps: Component[] = [];
    try {
      const res = await axios.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        {
          params: { latlng: `${lat},${lng}`, language: 'es', key: this.key },
          timeout: 8000,
        },
      );
      const data = res.data as {
        status?: string;
        error_message?: string;
        results?: { address_components?: Component[] }[];
      };
      // Google devuelve HTTP 200 igual cuando rechaza: el estado real viene en
      // el body. Logueamos el error_message porque es lo único que distingue
      // "key mal configurada" de "acá no hay nada que geocodificar".
      if (data.status !== 'OK' || !data.results?.length) {
        if (data.status !== 'ZERO_RESULTS') {
          this.log.warn(
            `geocode ${data.status}: ${data.error_message ?? 'sin detalle'}`,
          );
        }
        return { city: '', area: '' };
      }
      comps = data.results[0].address_components ?? [];
    } catch (e) {
      this.log.error(`geocode falló: ${(e as Error)?.message ?? e}`);
      return { city: '', area: '' };
    }

    // Mismas reglas que tenía la app antes de mover esto al backend.
    const city = this.first(comps, ['locality', 'administrative_area_level_2']);
    const hood = this.first(comps, [
      'neighborhood',
      'sublocality',
      'sublocality_level_1',
    ]);
    const value: Place = {
      city: city || this.first(comps, ['administrative_area_level_1']),
      // "Palermo, Buenos Aires" cuando hay barrio Y ciudad y no son lo mismo.
      area: hood && city && hood !== city ? `${hood}, ${city}` : hood || city,
    };

    // Cache acotado: se descarta la entrada más vieja al llenarse (los Map de
    // JS preservan orden de inserción, así que la primera clave es la más
    // antigua). No hace falta LRU real para un caso de este tamaño.
    if (this.cache.size >= CACHE_MAX) {
      const oldest = this.cache.keys().next().value;
      if (oldest !== undefined) this.cache.delete(oldest);
    }
    this.cache.set(cacheKey, { at: Date.now(), value });
    return value;
  }

  /// Ruta caminando/en auto entre dos puntos, vía la Directions API. Misma
  /// razón que `reverse`: la key de la app está restringida al Maps SDK, no
  /// sirve para web services. Sin caché: la clave incluiría el origen, que
  /// cambia todo el tiempo mientras el usuario camina o maneja — el hit rate
  /// sería ~0. El cliente ya throttlea el refetch cada ~35 m de movimiento.
  async directions(
    originLat: number,
    originLng: number,
    destLat: number,
    destLng: number,
    mode: 'walking' | 'driving',
  ): Promise<{ points: string; durationText: string; distText: string }> {
    const empty = { points: '', durationText: '', distText: '' };
    if (!this.isConfigured) return empty;
    try {
      const res = await axios.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        {
          params: {
            origin: `${originLat},${originLng}`,
            destination: `${destLat},${destLng}`,
            mode,
            language: 'es',
            key: this.key,
          },
          timeout: 8000,
        },
      );
      const data = res.data as {
        status?: string;
        error_message?: string;
        routes?: {
          overview_polyline?: { points?: string };
          legs?: {
            duration?: { text?: string };
            distance?: { text?: string };
          }[];
        }[];
      };
      if (data.status !== 'OK' || !data.routes?.length) {
        if (data.status !== 'ZERO_RESULTS') {
          this.log.warn(
            `directions ${data.status}: ${data.error_message ?? 'sin detalle'}`,
          );
        }
        return empty;
      }
      const route = data.routes[0];
      const leg = route.legs?.[0];
      return {
        points: route.overview_polyline?.points ?? '',
        durationText: leg?.duration?.text ?? '',
        distText: leg?.distance?.text ?? '',
      };
    } catch (e) {
      this.log.error(`directions falló: ${(e as Error)?.message ?? e}`);
      return empty;
    }
  }
}

@Controller('geo')
@UseGuards(JwtAuthGuard)
class GeoController {
  constructor(private readonly geo: GeoService) {}

  /// Barrio y ciudad de un punto. Devuelve strings vacíos si no se pudo
  /// resolver: para quien llama es "no autocompletar", no un error.
  @Get('reverse')
  reverse(@Query('lat') lat: string, @Query('lng') lng: string) {
    const nLat = Number(lat);
    const nLng = Number(lng);
    if (!Number.isFinite(nLat) || !Number.isFinite(nLng)) {
      return { city: '', area: '' };
    }
    return this.geo.reverse(nLat, nLng);
  }

  /// Ruta caminando/en auto: polyline codificada + duración/distancia.
  /// Objeto vacío si no se pudo resolver: quien llama cae a línea recta.
  @Get('directions')
  directions(
    @Query('originLat') originLat: string,
    @Query('originLng') originLng: string,
    @Query('destLat') destLat: string,
    @Query('destLng') destLng: string,
    @Query('mode') mode: string,
  ) {
    const oLat = Number(originLat);
    const oLng = Number(originLng);
    const dLat = Number(destLat);
    const dLng = Number(destLng);
    const m = mode === 'walking' || mode === 'driving' ? mode : null;
    if (![oLat, oLng, dLat, dLng].every(Number.isFinite) || !m) {
      return { points: '', durationText: '', distText: '' };
    }
    return this.geo.directions(oLat, oLng, dLat, dLng, m);
  }
}

@Module({
  controllers: [GeoController],
  providers: [GeoService],
})
export class GeoModule {}
