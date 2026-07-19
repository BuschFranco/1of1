# Assets gráficos de Play Store — 1of1

## ✅ Listos

- **`icon-512.png`** — ícono de la ficha (512×512).
- **`feature-graphic-1024x500.png`** — banner de la ficha (1024×500).

Ambos generados a partir del branding real de la app (`assets/branding/icon_foreground.png`
+ tipografía Jost) con `generate-icon.ps1` / `generate-feature-graphic.ps1`. Si
cambia el logo o los colores de marca, corré esos scripts de nuevo.

## ⏳ Capturas de pantalla (pendiente — necesita el celu conectado)

Play Store pide mínimo 2, hasta 8. Preparé el plan de **5 capturas** con el
mensaje de marketing (headline + subtítulo) que mejor vende cada feature,
apuntado a las keywords de la ficha (canchas, ranking, pickup, clanes):

| # | Pantalla de la app | Headline | Subtítulo |
|---|---|---|---|
| 1 | Mapa (Home) con canchas visibles | ENCONTRÁ TU CANCHA | Canchas de básquet cerca tuyo, con toda la info |
| 2 | Detalle de cancha (rating + conquista + rey de la cancha) | CADA CANCHA TIENE SU REY | Descubrí quién domina tu cancha esta temporada |
| 3 | Ranking global (pestaña Jugadores o Clanes) | COMPETÍ DE VERDAD | Ranking real por temporada, con tus amigos o con todos |
| 4 | Chat de un pickup | ARMÁ TU PARTIDO | Invitá gente, organizá equipos y chateá |
| 5 | Perfil (nivel, logros, clan) | SUBÍ DE NIVEL | Puntos, logros, títulos y tu clan |

### Cómo tomarlas (cuando tengas el celu conectado)

1. Conectá el celu por USB con depuración habilitada (`adb devices` debe listarlo).
2. Abrí la app en la pantalla #1 de la tabla (el mapa con algunas canchas a la vista).
3. Desde PowerShell, en esta carpeta:
   ```powershell
   .\capture-screenshot.ps1 -Headline "ENCONTRA TU CANCHA" -Subtitle "Canchas de basquet cerca tuyo, con toda la info" -OutName "01-mapa"
   ```
   (sin tildes en los parámetros de PowerShell para evitar problemas de encoding
   de la terminal; el script las agrega bien en la imagen final si hace falta —
   avisame si preferís que las agregue por vos).
4. Repetí para las 4 pantallas restantes, cambiando `-OutName` (02, 03, 04, 05)
   y los textos de la tabla.
5. El resultado (1080×1920, formato retrato estándar de Play Store) queda en
   `screenshots/0X-nombre.png`, listo para subir a Play Console.

Si querés, cuando conectes el celu lo hacemos juntos en el momento — yo corro
los comandos, vos solo navegás la app a la pantalla indicada.
