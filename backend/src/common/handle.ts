/** Normaliza un handle: minúsculas y con '@' adelante (igual que la app). */
export function normalizeHandle(raw: string): string {
  let h = (raw ?? '').trim().toLowerCase();
  if (!h) return h;
  if (!h.startsWith('@')) h = `@${h}`;
  return h;
}

/** Valida el formato del handle. Devuelve un mensaje de error o null si es OK. */
export function validateHandleFormat(raw: string): string | null {
  const h = normalizeHandle(raw);
  const body = h.startsWith('@') ? h.slice(1) : h;
  if (!body) return 'Ingresá un handle.';
  if (body.length < 3) return 'El handle debe tener al menos 3 caracteres.';
  if (body.length > 20) return 'El handle no puede superar los 20 caracteres.';
  if (!/^[a-z0-9._]+$/.test(body)) {
    return 'Solo letras, números, punto (.) o guion bajo (_).';
  }
  return null;
}
