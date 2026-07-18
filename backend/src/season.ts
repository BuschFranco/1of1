/**
 * Temporadas = semestres de calendario (1 ene–30 jun / 1 jul–31 dic), la misma
 * regla que la app (PlaySessionService.seasonStart). Todo lo puntuable se
 * "reinicia" por temporada FILTRANDO partidos por fecha — nunca borrando datos.
 *
 * En UTC: la regla heredada del gateway es que las fechas naive de la app se
 * interpretan como UTC, así que los cortes también se generan en UTC para que
 * la comparación sea consistente (mismo reloj de pared en ambos lados).
 */

/** Inicio de la temporada actual (1 de enero o 1 de julio, 00:00 UTC). */
export function seasonStart(now: Date = new Date()): Date {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() <= 5 ? 0 : 6, 1),
  );
}

/** Fin exclusivo de la temporada actual (1 de julio o 1 de enero siguiente). */
export function seasonEnd(now: Date = new Date()): Date {
  const first = now.getUTCMonth() <= 5;
  return new Date(
    Date.UTC(now.getUTCFullYear() + (first ? 0 : 1), first ? 6 : 0, 1),
  );
}
