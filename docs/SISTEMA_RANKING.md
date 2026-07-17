# Sistema de Ranking / Puntos — 1of1

Explicación del sistema de puntos ("Ranking" en el perfil), niveles y ranking de amigos, tal como está implementado hoy.

**Código fuente:**
- Fórmula y acumulación: `app/lib/services/play_session_service.dart` (`resolvePending`, ~línea 1769)
- Curva de niveles: `app/lib/data/achievements.dart` (`pointsForLevel` / `levelForPoints`)
- UI (tarjeta de nivel, celda "Rating", hoja de ranking): `app/lib/screens/profile_screen.dart`
- Backend del ranking por período: `POST /matches` + `GET /ranking` (NestJS)

---

## 1. Qué es el "Rating"

Es un **contador acumulativo de puntos de por vida** (no un ELO: nunca baja). Se muestra en el perfil como "Rating" y alimenta:

1. El **nivel** del jugador (1..∞, curva creciente).
2. El **ranking entre amigos** (total y por período).
3. Los **logros por nivel** (`level_5/10/20/30`) y sus títulos.

Los puntos solo se ganan **jugando partidos detectados por la app** (sesión de juego en una cancha, GPS + cronómetro). Un partido suma puntos únicamente cuando el usuario **resuelve el resultado** (ganó / perdió / empató / entrenamiento). Si responde "no contó", no suma nada.

Requisito mínimo: el partido debe durar al menos **13 minutos** (`minMatch`); por debajo se asume cancelado y no suma puntos, tiempo, jugadas ni historial.

---

## 2. Fórmula de puntos por partido

```
puntos = puntosPorTiempo
       + bonusResultado      (% de puntosPorTiempo)
       + bonusRacha          (% de puntosPorTiempo)
       + bonusCanchaNueva    (+30 fijo)
       + bonusRecordCalorias (+25 fijo)
```

### 2.1 Puntos por tiempo (la base)

```
segundosPuntuables = min(segundosJugados, 2 horas)        // pointsTimeCap
puntosPorTiempo    = round(minutosPuntuables × multiplicador)
```

- **1 punto por minuto** como base.
- **Multiplicador por duración**: incentiva partidos largos. Crece **lineal** desde ×1.0 al empezar hasta **×1.8 a los 90 minutos** (`multiplierCap`) y se queda ahí. Solo afecta la base por tiempo, no los bonus fijos.
- **Cap de 2 horas** (`pointsTimeCap`): pasado ese tiempo neto el reloj deja de puntuar (cap silencioso, no se muestra en UI). Es el mismo umbral donde la app pregunta "¿Seguís jugando?"; con confirmación hay hasta 1 h extra de juego (que ya no puntúa) y a las 3 h netas se cierra solo.

Máximo teórico de la base: 120 min × 1.8 = **216 puntos por tiempo**.

### 2.2 Bonus por resultado (porcentaje de la base)

Es un **porcentaje de los puntos por tiempo**, no un valor fijo — así el peso del resultado escala con lo que jugaste:

| Resultado      | Bonus |
|----------------|-------|
| Victoria       | +30 % |
| Derrota        | +30 % |
| Empate         | +20 % |
| Entrenamiento  | +15 % |
| No contó       | 0 % (y el partido no suma nada) |

Victoria y derrota valen **igual** a propósito: el resultado es autorreportado y no queremos incentivo a mentir. Ganar sigue rindiendo por otro lado (racha, logros de victorias, títulos).

### 2.3 Bonus de racha (solo victorias)

- **+5 % de la base por cada victoria consecutiva**, con tope de **+25 %** (racha de 5).
- La racha puede seguir creciendo más allá de 5 (para logros como "Invencible"), pero el porcentaje queda clavado en 25 %.
- Una **derrota corta la racha** (y la archiva en el historial de rachas). Empate, entrenamiento y "no contó" **no la afectan**.

### 2.4 Bonus de cancha nueva

**+30 puntos fijos** la primera vez que jugás en una cancha (se detecta contra el mapa local de tiempo-por-cancha, antes de registrar el partido).

### 2.5 Bonus de salud (récord de calorías)

Solo si el usuario conectó Salud (Health Connect / HealthKit, opt-in):

- Se leen las calorías activas de la ventana del partido desde el store del OS.
- Si superan el **récord personal**, se suman **+25 puntos** (`calorieRecordBonus`) y el récord se actualiza.
- El **primer dato válido fija la base sin bonus** (récord inicial = 0 → primera medición no paga).
- Sin wearable / sin datos: no pasa nada, no penaliza.

### Ejemplo completo

Partido de 60 min, victoria, 3ra victoria seguida, cancha ya conocida, sin récord de calorías:

```
multiplicador  = 1.0 + 0.8 × (60/90)   = ×1.533
base           = round(60 × 1.533)      = 92 pts
resultado      = round(92 × 0.30)       = 28 pts   (mismo valor si hubiese perdido)
racha          = round(92 × 0.15)       = 14 pts   (3 victorias × 5 %)
total          = 92 + 28 + 14           = 134 pts
```

---

## 3. Niveles

Curva cuadrática infinita, definida en `achievements.dart`:

```dart
pointsForLevel(L) = 40 × L × (L − 1)     // nivel 1 = 0 pts
// subir de L a L+1 cuesta 80·L puntos
```

| Nivel | Puntos acumulados | Costo del salto |
|-------|-------------------|-----------------|
| 1     | 0                 | —               |
| 2     | 80                | 80              |
| 3     | 240               | 160             |
| 5     | 800               | 320             |
| 10    | 3.600             | 720             |
| 20    | 15.200            | 1.520           |
| 30    | 34.800            | 2.320           |

- La tarjeta del perfil muestra "Nivel N", la barra de progreso dentro del nivel y "Faltan X pts para el nivel N+1".
- Al subir de nivel se encola un `RewardEvent.levelUp` (banner in-app + notificación local).
- Los niveles 5/10/20/30 desbloquean logros ("En ascenso", "Subiendo fuerte", "Elite", "Cúspide") que a su vez desbloquean títulos ("Aspirante", "Figura", "Crack del barrio", "Hall of Fame").

---

## 4. Ranking de amigos

Se abre tocando la celda **"Rating"** del perfil (`_showRanking` → `_RankingSheet`). Compara al usuario con sus amigos en 4 períodos:

| Período   | Corte                            | Fuente de datos |
|-----------|----------------------------------|-----------------|
| Semana    | Lunes 00:00                      | Yo: log local · Amigos: backend |
| Mes       | Día 1 del mes, 00:00             | ídem |
| Temporada | Semestre calendario (1 ene / 1 jul) | ídem |
| Total     | Todo                             | Yo: puntos locales · Amigos: campo `points` del perfil (ProfilesProvider), **sin red** |

### Temporadas (el eje competitivo)

Las temporadas son **semestres de calendario** (1 ene–30 jun / 1 jul–31 dic; `PlaySessionService.seasonStart`/`seasonEnd`, backend `season.ts`). Son el eje de la competencia: al terminar una, **todo lo puntuable se reinicia**.

- **Se reinicia por temporada**: el ranking de jugadores y de clanes por período, y la **conquista de canchas** (usuario y clan). "Reiniciar" no borra nada: los partidos viven fechados en la DB Partidos y cada agregación de temporada **filtra por `EndedAt >= inicio de temporada`**. Una temporada nueva arranca sola en 0 y el histórico queda intacto para siempre.
- **Se conserva** (NO depende de la temporada): el nivel, los logros, los títulos y cualquier desbloqueable — todos derivan de `Profile.points` (total de por vida), que nunca se resetea. También el ranking "Total" del perfil (histórico).
- **UI**: pestaña "Temporada" propia en el Ranking global (con banner de fechas + días restantes + aviso de reset) y chip destacado con trofeo en el ranking del perfil. El detalle de cancha muestra "Puntos esta temporada" y "Puntos históricos" por separado, "Conquistada esta temporada por" (clan) y "Rey de la cancha esta temporada" (`GET /matches/court-king`, el jugador con más puntos ahí en la temporada).

### Ranking global (botón de trofeo en el mapa)

Pantalla propia (`RankingScreen`) accesible desde el botón flotante de trofeo del mapa. El ranking del perfil queda **scopeado a amigos**; el global vive acá:

- Dos pestañas: **Global** (toggle Jugadores/Clanes + filtro Semana/Mes) y **Temporada** (aparte, con su banner de fechas + toggle Jugadores/Clanes de la temporada). Top 50 cada uno.
- Navegación por **swipe** entre las 6 combinaciones; los chips reflejan la página.
- Abajo, una sección fija con **tu posición** como jugador y la de **tu clan** en el período, aunque estén fuera del top 50.
- El **ranking del perfil** (entre amigos) también se navega por swipe entre Semana/Mes/Total/Temporada, y el botón "Ranking" del perfil muestra **tu posición (#N) entre amigos** en vez de los puntos totales (con loader anti-doble-modal).
- El detalle de cancha y la miniatura del mapa muestran el **rey de la cancha** (jugador con más puntos esta temporada) además del clan que la conquistó.
- Un solo endpoint (`GET /rankings/global?since=`) resuelve todo server-side con una pasada por la DB Partidos desde el corte: agrega por jugador y por clan, ordena, corta a 50 y calcula tu puesto sobre el ranking completo. Las identidades (nombre/handle/clan por email) se cachean 60 s.
- **Un clan = la insignia de texto** (≤4 chars) que cada usuario escribe en su perfil, normalizada (`trim` + mayúsculas): "nba" y "NBA" son el mismo clan. Sin entidad Clan: cualquiera "se une" escribiendo la misma insignia. Empates: menos miembros primero, luego alfabético.
- **Cancha conquistada**: el detalle de cada cancha muestra el clan con más puntos históricos acumulados ahí (`GET /clans/court-owner?courtId=`). Sin jugadores con clan que hayan puntuado, la card no aparece; si el dueño es tu clan, la card se tinta con el acento.
- Existe también `GET /clans/ranking?since=` (agregado global de clanes con modo Total), hoy sin uso en la UI.

### Puntos por cancha (detalle de cancha)

El detalle de cada cancha muestra "Puntos acá" (total del usuario en esa cancha) y "Tus partidos acá" (historial):

- **Puntos**: se suman **server-side desde la DB Partidos** (`GET /matches/court-points?courtId=…`, email del token) — sobreviven reinstalaciones y no están capados. Mientras el backend no respondió, o si la suma local del log supera a la de la DB (partidos pendientes de subir), se muestra la suma local.
- **Historial**: sale del **log local** (últimos 100 partidos del dispositivo), filtrado por cancha, hasta 10 filas (resultado, duración, fecha, puntos).

**Cómo funciona el modo por período:**
1. Cada partido que sumó puntos se encola local (`pending_matches::$userKey`) y el `SyncCoordinator` lo sube en lote vía `POST /matches` (offline-first: si falla, reintenta en el próximo flush).
2. La hoja de ranking llama `GET /ranking?since=<ISO>&emails=…`; el backend agrupa y suma por email server-side.
3. Mis puntos del período salen del **log local** (`pointsThisWeek/Month/Season`), no del backend — por eso mi número puede diferir del que ven mis amigos si hay partidos aún no subidos.
4. Sin conexión, los amigos quedan en 0 para el período (fallo silencioso).

---

## 5. Persistencia y siembra

- Todo lo local se guarda en `SharedPreferences` **namespaced por usuario** (`clave::email`): puntos (`play_points`), log (últimos 100 partidos), racha, récord de calorías, badges.
- Los agregados (puntos, jugadas, racha…) se suben al perfil del backend cada ~2 min durante el juego (batch) y en el flush.
- Al loguearse en un dispositivo nuevo, los puntos se **siembran desde el perfil** (`seedPoints`): se toma el mayor entre el valor local y el remoto (`if (seedPoints > _points)`), así reinstalar no pierde progreso pero tampoco pisa un local más avanzado.
- El **historial de partidos y el detalle no se suben**: solo agregados. Por eso el ranking por período necesita la DB de Partidos en el backend.

---

## 6. Propiedades del diseño (resumen)

- **Nunca baja**: no hay penalizaciones; perder suma lo mismo que ganar (+30 % sobre la base). Mide *dedicación* más que *skill*.
- **El tiempo domina**: la base por tiempo es el 100 % de referencia; los bonus de resultado/racha son porcentajes de ella. Un partido largo perdido puede valer más que uno corto ganado.
- **Anti-farmeo**: mínimo 13 min para contar, cap de 2 h puntuables, pregunta de confirmación a las 2 h, multiplicador topado a los 90 min, cancha nueva paga una sola vez, récord de calorías solo al superarlo.
- **Autoreportado**: el resultado (ganó/perdió) lo declara el usuario sin verificación. Victoria y derrota pagan lo mismo en puntos, así que mentir no rinde en el rating; el único incentivo residual es el bonus de racha (hasta +25 % de la base) y los logros por victorias.
