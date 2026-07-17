/**
 * Temporadas = semestres de calendario (1 ene–30 jun / 1 jul–31 dic), la misma
 * regla que la app (PlaySessionService.seasonStart). Todo lo puntuable se
 * "reinicia" por temporada FILTRANDO partidos por fecha — nunca borrando datos.
 */

/** Inicio de la temporada actual (1 de enero o 1 de julio). */
export function seasonStart(now: Date = new Date()): Date {
  return new Date(now.getFullYear(), now.getMonth() <= 5 ? 0 : 6, 1);
}

/** Fin exclusivo de la temporada actual (1 de julio o 1 de enero siguiente). */
export function seasonEnd(now: Date = new Date()): Date {
  const first = now.getMonth() <= 5;
  return new Date(now.getFullYear() + (first ? 0 : 1), first ? 6 : 0, 1);
}

/** Inicio de temporada en ISO local (sin milisegundos), para filtros Notion. */
export function seasonStartIso(now: Date = new Date()): string {
  const s = seasonStart(now);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${s.getFullYear()}-${pad(s.getMonth() + 1)}-${pad(s.getDate())}T00:00:00`;
}
