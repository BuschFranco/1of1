/** Construcción de rutas teniendo en cuenta el `base` del sitio y el idioma.
 *
 * El sitio se publica bajo `/1of1` (GitHub Pages), así que ninguna ruta puede
 * escribirse absoluta a mano. El español vive en la raíz y el inglés bajo
 * `/en`, igual que resuelve `getLang()` en `../i18n`.
 */

export type Lang = 'es' | 'en';

const BASE = import.meta.env.BASE_URL.replace(/\/$/, '');

/** `url('es')` → `/1of1/` · `url('en', 'terminos')` → `/1of1/en/terminos` */
export function url(lang: Lang, path = ''): string {
  const prefix = lang === 'en' ? `${BASE}/en` : BASE;
  return path ? `${prefix}/${path}` : `${prefix}/`;
}

/** Recurso estático de `public/`: `asset('hero-bg.png')` → `/1of1/hero-bg.png` */
export function asset(file: string): string {
  return `${BASE}/${file}`;
}
