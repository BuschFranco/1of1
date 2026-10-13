# Noticias: fuentes y licencias

Estado de las fuentes de la sección Noticias (Social → Noticias) y qué riesgo
de licencia tiene cada una. Código: `backend/src/news/news.module.ts`. La app
nunca llama a las fuentes directo: va por `GET /news?league=...` del backend,
que cachea 30 min por liga.

> Última revisión: 2026-10-13. No es asesoría legal. Si la app se monetiza o
> hay un reclamo, revisar esto con alguien legal.

## Resumen

| Liga (`league`) | Fuente | Key | Licencia comercial | Riesgo |
| --- | --- | --- | --- | --- |
| `nba`, `wnba` | API no oficial de ESPN (`site.api.espn.com`) | no | **No hay contrato**: endpoint no documentado | Medio |
| `lnb` (Liga Nacional) | NewsData.io, búsqueda por palabra clave | `NEWSDATA_API_KEY` (Render) | **Sí**, en su plan gratis (200 créditos/día, 12 h de delay, solo snippets) | Bajo |
| `3x3` | RSS de búsqueda de Google News | no | **No**: ver abajo | **Alto** |

## 3x3 — Google News RSS (el punto débil)

- No hay fuente gratis dedicada: ESPN no tiene liga 3x3 y la API de FIBA 3x3 es
  privada (solo broadcasters, acceso por mail a FIBA).
- Los [términos de Google News](https://www.google.com/intl/en_us/terms_google_news.html)
  limitan el contenido a uso personal y no comercial. Cada feed trae el aviso de
  que es "para mostrar resultados en un lector de feeds personal, para uso
  personal".
- **Que la app sea gratis no lo resuelve**: el backend toma el feed y se lo
  sirve a todos los usuarios, o sea redistribuye. Eso choca con "uso personal"
  aunque no se cobre nada.
- Riesgo realista: más técnico que legal. Google puede limitar o bloquear las
  llamadas desde la IP de Render y el chip 3x3 quedaría en "Sin noticias por
  ahora" (el código ya degrada a lista vacía, no rompe nada).
- Se eligió igual por ser lo único verificable gratis al momento de
  implementarlo. De la nota solo se guardan título, fuente, fecha y link: sin
  texto ni imagen.

### Plan de salida (si hay un reclamo, un bloqueo o se monetiza la app)

1. **Opción rápida**: sacar el chip `3x3` de `app/lib/screens/news_screen.dart`
   y el branch `'3x3'` de `news.module.ts` (`fromGoogleNews`, `League`, el
   whitelist del controller). No hay migraciones ni datos que limpiar.
2. **Opción con licencia**: pasar `3x3` a NewsData.io, igual que `lnb` (método
   `fromNewsData`, que hoy tiene el query de Liga Nacional fijo y habría que
   parametrizar). Keywords candidatas: `"FIBA 3x3" OR "3x3 basketball" OR
   "básquet 3x3"`. **Pendiente de verificar con la key real** que traiga notas
   útiles y no ruido de otros deportes.

## NBA / WNBA — ESPN no oficial

Es la API que alimenta la app de ESPN, de uso muy extendido, sin límite
publicado, pero **no es un contrato documentado** ni trae licencia comercial.
Si ESPN la cierra o reclama, el feed degrada a vacío. Alternativa de salida:
NewsData.io con keywords de NBA/WNBA (los textos de ESPN además vienen en
inglés y el backend los traduce EN→ES con el endpoint no oficial de Google
Translate, que tiene la misma salvedad).

## Liga Nacional — NewsData.io

Única fuente con uso comercial permitido en su plan gratis. El cupo diario es
compartido entre todos los usuarios, por eso el caché de 30 min en el backend.
Sin `NEWSDATA_API_KEY` en el entorno, la liga devuelve vacío.

## Relacionado

- [`MONETIZACION.md`](MONETIZACION.md): si se activa monetización, revisar este
  documento antes (sube el riesgo de las fuentes sin licencia).
- [`../app/docs/cache.md`](../app/docs/cache.md): caché de noticias en la app.
