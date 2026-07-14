# Sistema de detección de partidos

Documento de referencia del **núcleo de la app**: cómo 1of1 detecta que estás
jugando en una cancha, arranca el partido solo, lo cierra solo, y cómo logra
todo eso incluso con la app minimizada, cerrada o con el celu suspendido —
sin rastrear tu ubicación de forma continua.

> **Archivos involucrados**
>
> | Archivo | Rol |
> | --- | --- |
> | `lib/services/play_session_service.dart` | Cerebro: estados, dwell, gracia de salida, cronómetro, puntos. Corre en el isolate principal (app viva). |
> | `lib/services/session_alarms.dart` | Alarmas exactas del SO + callbacks en isolate de background (app muerta). |
> | `lib/services/geofence_service.dart` | Geofences del SO (native_geofence): despiertan la app al cruzar el radio de una cancha. |
> | `lib/services/sync_coordinator.dart` | Cablea todo: registra/quita geofences y radar según sesión + preferencia + permiso. |
> | `lib/services/app_permissions.dart` | Chequeo/pedido de permisos (ubicación, "Siempre", notifs, alarmas exactas, batería). |
> | `lib/widgets/permissions_modal.dart` | UI de permisos ("Detección automática" = background). |

---

## 1. La idea en una frase

Si permanecés **≥ 6 minutos** dentro de un radio de **110 m** de una cancha,
el partido **arranca solo**. Si salís del radio y seguís afuera **6 minutos**
continuos, el partido **se cierra solo**. Todo lo demás del sistema existe
para que esas dos frases sigan siendo ciertas con la app minimizada, cerrada,
el proceso muerto por el fabricante o el celu en Doze.

## 2. Constantes que gobiernan el sistema

Viven arriba de `play_session_service.dart`. **No dupliques estos números en
otro lado** — con una excepción deliberada, ver §8.1.

| Constante | Valor | Qué controla |
| --- | --- | --- |
| `radiusMeters` | 110 m | Radio de detección alrededor de cada cancha (igual al de las geofences, `kCourtGeofenceRadius`). |
| `dwellThreshold` | 6 min | Permanencia continua dentro del radio para arrancar el partido. |
| `exitGrace` | 6 min | Tiempo continuo fuera del radio para cerrar el partido. |
| `gpsJitterGrace` | 15 s | Tolerancia a saltos de GPS: una lectura suelta fuera (o dentro) del radio no resetea nada hasta sostenerse este tiempo. |
| `dwellSnooze` | 1 h | "No juego": silencia el detector de ESA cancha (también aplica al DETENER manual). |
| `snoozeExitClear` | 2 min | Lecturas continuas fuera del radio para limpiar el snooze solo (te fuiste de verdad). |
| `minMatch` | 13 min | Duración mínima para que un partido cuente (menos = cancelado, no suma nada). |
| `resumeGapMax` | 3 min | Si el "latido" del partido persistido es más viejo que esto al reabrir, el proceso estuvo muerto: se cierra con el tiempo del último latido en vez de resumir inflado. |
| `endNotifLeadTime` | 3 min | Cuánto antes del cierre automático se avisa "tu partido se cierra pronto". |
| `batteryEndPercent` | 5 % | Batería mínima (sin cargar) antes de cerrar el partido para proteger la info. |
| `pointsTimeCap` | 2 h | El tiempo deja de sumar puntos acá. Es TAMBIÉN el trigger de la pregunta de partido largo "¿Seguís jugando?" (§3.1): mismo número, un solo umbral. |
| `confirmTimeout` | 20 min | Ventana para responder la pregunta de las 2h. Sin respuesta → el partido se CANCELA por completo (sin puntos, sin historial, sin tiempo). |
| `overtimeMax` | 1 h | Yapa máxima tras responder "Sí": a las 3h netas (2h + 1h) el partido se cierra y GUARDA solo. |
| `_sampleEvery` | 10 s | Cadencia del muestreo GPS con la app abierta. |
| `_kRadarEvery` (session_alarms) | 15 min | Cadencia del radar de respaldo en background. Peor caso de demora de detección. |

Además el filtro de calidad: `_evaluate` **descarta** cualquier lectura con
`accuracy > radiusMeters * 1.5` (165 m) — una lectura peor que eso no sirve
para decidir sobre un radio de 110 m.

## 3. Máquina de estados

El servicio está siempre en uno de estos estados (por usuario, namespaced):

```
                 entra al radio                 6 min continuos adentro
   ┌─────────┐ ────────────────▶ ┌──────────┐ ─────────────────────▶ ┌──────────┐
   │  IDLE   │                   │  DWELL   │                        │ PLAYING  │
   │ (nada)  │ ◀──────────────── │ (cuenta  │                        │ (partido │
   └─────────┘   >15s afuera     │regresiva)│                        │ en curso)│
        ▲        (jitter grace)  └──────────┘                        └────┬─────┘
        │                                                                 │ sale del radio
        │                                                            ┌────▼─────┐
        │            vuelve al radio >15s continuos                  │  EXIT    │
        │          ◀───────────────────────────────────────────────  │  GRACE   │
        │                                                            │ (cuenta  │
        │        6 min continuos afuera                              │de cierre)│
        └──────────────────────────────────────────────────────────  └──────────┘
                 → partido queda PENDIENTE DE RESULTADO ("¿Cómo te fue?")
```

- **DWELL**: al entrar al radio, `_beginDwell()` arranca la cuenta regresiva,
  programa la **alarma exacta de arranque** a +6 min y prende el foreground
  service (ver §5.2) para que la cuenta siga aunque minimices.
- **PLAYING**: `_startSession()` es idempotente (si la alarma y el stream
  intentan arrancar el mismo partido, no se duplica). Cancela la alarma de
  arranque y programa la vigilancia periódica de batería.
- **EXIT GRACE**: `_beginExitGrace()` marca desde cuándo estás afuera,
  programa la **alarma exacta de cierre** a +6 min y una **alarma de aviso**
  a -3 min del cierre. Si volvés al radio (15 s continuos adentro), se cancela
  todo y la notif vuelve a "jugando".
- Al cerrar, el partido queda **pendiente de resultado**: la app pregunta
  "¿Cómo te fue?" y recién ahí `resolvePending()` computa puntos, logros,
  historial y lo encola para subir a Notion.

### 3.1 Partido largo: AWAITING CONFIRM (pregunta de las 2h)

A las **2 h de juego NETO** (`pointsTimeCap` — el mismo umbral donde el tiempo
deja de sumar puntos), PLAYING entra en un sub-estado de pausa forzada:

```
              2h de juego neto               ┌─ "SÍ, SIGO"  → reanuda con 1h de tope:
   ┌──────────┐ ─────────────▶ ┌──────────┐  │   a las 3h netas cierra y GUARDA solo
   │ PLAYING  │                │ AWAITING │──┤   (+ snooze 1h + botón manual)
   │          │                │ CONFIRM  │  ├─ "NO, TERMINÉ" → cierra normal (tiempo
   └──────────┘                │ (pausado)│  │   congelado en 2h) + snooze 1h
                               └──────────┘  └─ sin respuesta en 20 min → CANCELADO
                                                 (sin puntos/historial) + snooze 1h
```

- El cronómetro y la detección quedan **congelados** (reutiliza el mecanismo
  de pausa) hasta que el usuario responda — por notificación con botones
  SÍ/NO (`showContinueCheck`, canal con sonido) o por el banner del mapa.
- **"Sí, sigo"**: la espera no cuenta como tiempo jugado; hay **1 h más como
  máximo** (`overtimeMax`). A las 3 h netas el partido se cierra solo, se
  **guarda normal** (pendiente de resultado) y se avisa "llegaste al tiempo
  límite". No se vuelve a preguntar.
- **"No, terminé"**: cierre normal con el tiempo congelado en las 2 h — queda
  pendiente de "¿Cómo te fue?" y suma como cualquier partido.
- **Sin respuesta en 20 min** (`confirmTimeout`): el partido se **cancela por
  completo** — no queda pendiente, no suma puntos, ni tiempo, ni jugadas, ni
  historial.
- Los tres desenlaces (límite / No / timeout) aplican el **snooze de 1 h** de
  la cancha (mismo flujo que "No juego"): el celu sigue en el radio y sin eso
  arrancaría otra cuenta regresiva al instante. Queda el botón **"Iniciar
  partido"** manual en el mapa.
- No se pregunta si hay **gracia de salida** en curso (el partido ya se está
  cerrando) ni durante una **pausa manual** (el umbral es juego neto, la
  pausa lo corre). Todo el flujo funciona con la app cerrada vía las alarmas
  100016/100017/100018 (§5.4) y se reconcilia al reabrir.

Casos especiales:

- **"No juego"** (banner o notificación) y **DETENER manual**: silencian el
  detector de esa cancha por 1 h (`dwellSnooze`). El arranque queda manual
  ("Iniciar partido") mientras sigas ahí; si te vas 2 min continuos, el snooze
  se limpia solo.
- **Pausa manual**: congela el cronómetro Y la detección (no arranca gracia
  ni cierra nada mientras está pausado).
- **Batería crítica** (≤5 % sin cargar): cierra el partido en curso para no
  perder el registro antes de que el SO mate la app.

### 3.2 Línea de tiempo de un partido (todos los tiempos, de punta a punta)

| Momento | Qué pasa | Tiempo |
| --- | --- | --- |
| **0'** | Entrás al radio de **110 m** → arranca la cuenta regresiva (dwell) + alarma de arranque. | — |
| **0'–6'** | Cuenta regresiva. Un salto de GPS afuera se tolera hasta **15 s** continuos antes de resetearla. | `dwellThreshold` 6 min |
| **6'** | **El partido arranca solo** (ticker, stream, alarma o radar — el que llegue primero; es idempotente). | — |
| en curso | Cronómetro visible; "latido" persistido cada **30 s**; muestreo GPS cada **10 s** (app abierta o FGS); radar cada **15 min** (proceso muerto); chequeo de batería cada ~**20 s** en vivo y cada **15 min** por alarma. | — |
| < 13' | Si el partido termina antes de **13 min**, se descarta: no suma nada. | `minMatch` 13 min |
| salís del radio | Arranca la **gracia de salida**: **6 min** continuos afuera para cerrar. Aviso "se cierra pronto" cuando faltan **3 min**. Si volvés **15 s** continuos adentro, se cancela. La gracia CUENTA como tiempo jugado. | `exitGrace` 6 min · `endNotifLeadTime` 3 min |
| **1:30 h** | El multiplicador de puntos por duración llega a su tope (×1.8). | `multiplierCap` 90 min |
| **2 h netas** | El tiempo deja de sumar puntos Y salta la **pregunta "¿Seguís jugando?"**: el cronómetro se PAUSA hasta que respondas. | `pointsTimeCap` 2 h |
| +20' sin respuesta | Partido **CANCELADO por completo** (sin puntos/historial/tiempo) + snooze 1 h + botón manual. | `confirmTimeout` 20 min |
| respondés "No" | Cierre normal con el tiempo congelado en 2 h (pendiente de "¿Cómo te fue?") + snooze 1 h + botón manual. | — |
| respondés "Sí" | Reanuda (la espera no cuenta) con **1 h más** como máximo. | `overtimeMax` 1 h |
| **3 h netas** | **Tope duro**: cierra y GUARDA solo + "llegaste al tiempo límite" + snooze 1 h + botón manual. | 2 h + 1 h |
| tras cerrar/cancelar | La cancha queda silenciada **1 h** ("No juego"/DETENER/límite/timeout): arranque solo manual. El snooze se limpia si estás **2 min** continuos fuera del radio. | `dwellSnooze` 1 h · `snoozeExitClear` 2 min |
| al reabrir la app | Si el latido quedó > **3 min** viejo (proceso muerto), se guarda con el tiempo del último latido. Una sesión activa de > **6 h** se descarta por corrupta. | `resumeGapMax` 3 min · tope 6 h |
| batería ≤ **5 %** | (Sin cargar) el partido se cierra para proteger el registro. | `batteryEndPercent` |

## 4. Qué NO hace el sistema (decisión de diseño)

**No hay rastreo continuo de GPS en segundo plano.** Lejos de toda cancha y
con la app minimizada/cerrada, **no corre ningún código de la app** y no se
toma ningún fix. Esto es deliberado:

1. **Batería**: el copy del modal lo promete ("No gasta batería extra: solo
   se usa cuando estás en una cancha"). Un stream continuo 24/7 sería
   inaceptable.
2. **Privacidad / política de Google Play**: la divulgación destacada declara
   que solo guardamos *en qué cancha jugaste*, no tus coordenadas. No
   necesitamos el recorrido, solo los cruces de borde.

**Consecuencia visible (y esperada)**: al reabrir la app después de tenerla
minimizada, el puntito azul del mapa "salta" a tu ubicación actual. Eso es la
primera muestra del ticker al volver al frente — **no** es señal de que la
detección en background esté rota. La detección no depende de ese puntito.

## 5. Las cinco capas de detección

Ordenadas de más precisa a más resiliente. Cada capa cubre el modo de falla
de la anterior; la detección funciona si **al menos una** está viva.

### 5.1 Ticker en foreground (app abierta)

`Timer.periodic` de 1 s en el isolate principal. Cada 10 s (`_sampleEvery`)
llama `getCurrentPosition` y pasa el fix a `_evaluate()`. También refresca la
UI de cuentas regresivas y persiste el "latido" del partido cada 30 s. Solo
corre con la app viva; al minimizar, el SO suspende los timers de Flutter.

### 5.2 Foreground service con stream (app minimizada, EN una cancha)

`_startStream()` abre un `getPositionStream` de geolocator con
`ForegroundNotificationConfig`: Android eleva el proceso a **servicio en
primer plano** (con notificación persistente), lo que lo exime de la
suspensión. Config clave en Android: `distanceFilter: 0` +
`intervalDuration: 10s` — updates **por tiempo**, no por distancia, porque el
caso típico del dwell es estar **quieto** en la cancha (con filtro por
distancia no llegaría ningún update y la cuenta nunca se resolvería).

Se prende SOLO cuando tiene sentido (su notificación queda justificada):
- al empezar un dwell (`_beginDwell`), aunque la app esté abierta — así al
  minimizar la cuenta sigue;
- al entrar a la zona de una cancha por geofence (`enterCourtArea`), si la
  detección automática está activa;
- al adoptar un partido/dwell que una alarma arrancó en background.

Se apaga al salir de la zona sin partido en curso (`leaveCourtArea`), al
apagar la preferencia, al cerrar sesión, o cuando `_evaluate` te ve fuera de
toda cancha sin background habilitado. **Si hay partido en curso NO se corta
al salir del radio**: se queda vivo durante la gracia para poder cerrar el
partido de forma confiable.

Nunca pide permisos: si no hay al menos "mientras se usa", retorna sin hacer
nada (los permisos los pide el modal, ver §7).

### 5.3 Geofences del SO (app cerrada — vía rápida)

`GeofenceService.syncCourts()` registra cada cancha con coordenadas (máx 95,
margen bajo el límite de 100 de Android) como geofence en **Google Play
Services**. El SO vigila los bordes con su propio motor de bajo consumo, sin
mantener la app viva ni notificación persistente, y ejecuta
`geofenceTriggered` en un isolate al cruzar un borde
(`notificationResponsiveness: 1 min`).

El callback tiene dos caminos:
- **App viva**: reenvía el evento por `IsolateNameServer` al isolate
  principal → `enterCourtArea()` / `leaveCourtArea()` (prende el FGS o
  arranca la gracia).
- **App muerta**: en ENTER, notifica "Estás en una cancha — abrí 1of1 para
  registrar tu partido" y **cancela la alarma de cierre** si estabas en
  gracia de salida (volviste a tiempo y no hay isolate principal que la
  cancele). El resto lo cubre el radar (§5.5).

### 5.4 Alarmas exactas del SO (los momentos críticos, app en cualquier estado)

`android_alarm_manager_plus` con `exact + wakeup + allowWhileIdle +
rescheduleOnReboot` (y fallback a inexacta si el usuario revocó "Alarmas y
recordatorios" en Android 14+). Los callbacks son `@pragma('vm:entry-point')`
y corren en un **isolate de background** a la hora exacta, aunque la app esté
cerrada o el celu en Doze. Cada alarma persiste su "objetivo" en
SharedPreferences para que el callback sepa qué hacer sin memoria compartida.

| Alarma | ID | Cuándo se programa | Qué hace el callback |
| --- | --- | --- | --- |
| **Arranque** | 100011 | Al empezar un dwell, a +6 min | Verifica que sigas en la cancha (best-effort; sin fix arranca igual) → persiste la sesión activa, notifica "¡Arrancó tu partido!", escribe presencia en Notion, arranca vigilancia de batería. |
| **Cierre** | 100012 | Al empezar la gracia, a +6 min | Verifica que sigas afuera (sin fix, cierra: la salida ya se detectó hace 6 min) → mueve la sesión activa a "pendiente de resultado", notifica, limpia presencia. |
| **Aviso** | 100014 | Junto con la de cierre, a -3 min | "Tu partido se cierra en 3 minutos. Volvé a la cancha para seguir jugando." Solo si la gracia sigue vigente y seguís afuera. |
| **Batería** | 100013 | Al arrancar un partido, periódica 15 min | Si el partido sigue y la batería ≤5 % sin cargar, cierra para proteger el registro. |
| **Radar** | 100015 | Ver §5.5 | — |
| **Pregunta 2h** | 100016 | Al arrancar el partido, a +2 h (reprogramada al reanudar una pausa: el umbral es juego neto) | Si el partido sigue (sin gracia ni pregunta previa): estampa `confirmAskedAtMillis` en la sesión activa ("pausa" en background), muestra "¿Seguís jugando?" con SÍ/NO y programa el timeout. |
| **Timeout pregunta** | 100017 | Al preguntar, a +20 min | Si nadie respondió (el flag sigue en la sesión activa): descarta el partido POR COMPLETO (sin pendiente), snooze 1 h de la cancha, notifica "Partido cancelado". |
| **Cierre duro 3h** | 100018 | Al responder "Sí", a +1 h de juego neto | Cierra y GUARDA el partido (pendiente de resultado) con el tope como fin, snooze 1 h, notifica "Llegaste al tiempo límite". |

Detalle importante del arranque en background: la sesión que escribe la
alarma va **sin** `lastSeenMillis` a propósito. Su ausencia le dice a
`_restore()` que ese partido lo arrancó una alarma con el proceso muerto (no
hay latidos que exigir) y debe **resumirlo**, no cerrarlo por "gap".

### 5.5 Radar de respaldo (app muerta — red de seguridad, cada 15 min)

Los fabricantes (Samsung especialmente) matan procesos, estrangulan geofences
y foreground services. El radar es el plan Z: una alarma **periódica**
(`kAlarmRadarId`, cada 15 min, sobrevive reinicios con `rescheduleOnReboot`)
despierta un isolate que toma **UN solo fix** (timeout 12 s) y espeja lo que
haría `_evaluate`:

- **Sin partido ni dwell sembrado** → si estás dentro del radio de alguna
  cancha (usa el cache `courts_geo_cache` que escribe SyncCoordinator, porque
  el isolate no puede leer el catálogo en memoria), **siembra la
  permanencia**: programa la alarma de arranque a +6 min y muestra la
  notificación de cuenta regresiva. Respeta el snooze de "No juego".
- **Con partido en curso** → si estás fuera del radio y no hay gracia
  programada, **arranca la gracia de salida** (persiste `endsAtMillis` +
  alarma de cierre), igual que `_beginExitGrace`.
- En ambos casos deja el diagnóstico `last_bg_fix_millis` (ver §9) y hace
  ping al isolate principal por si está vivo.

Peor caso de demora de detección con todo lo demás muerto: **15 min** (la
cadencia del radar), + 6 min de dwell = el partido arranca como muy tarde
~21 min después de llegar. La gracia de salida, ídem: cierre como muy tarde
~21 min después de irte, pero el cierre usa `endsAtMillis` como tope así el
tiempo jugado no se infla.

## 6. Reconciliación: cómo se sincronizan los isolates

Los isolates de background **no comparten memoria** con el principal. El
contrato es: **SharedPreferences es la fuente de verdad persistida** (mismas
claves namespaced `base::$userKey` en ambos lados) + un ping best-effort por
`IsolateNameServer` (`oneofone_play_port`).

`reconcileFromPrefs()` corre en el isolate principal al **volver al frente**
(lifecycle `resumed`) y al recibir un ping, y adopta lo que las alarmas hayan
hecho mientras tanto:

1. **Alarma arrancó un partido** que no teníamos → adoptarlo (con su
   cronómetro corrido desde `startMillis`), re-armar el FGS, cancelar la
   alarma de arranque.
2. **Alarma cerró el partido** que creíamos en curso → cerrarlo en memoria.
3. **Quedó un pendiente de resultado** → adoptarlo (dispara "¿Cómo te fue?").
4. **El radar sembró un dwell** → adoptar la cuenta regresiva donde iba (no
   reiniciarla) y prender el FGS.

En sentido inverso, con la app viva el partido persiste un **latido**
(`_persistActive`) en cada evaluación y cada 30 s del ticker. Al reabrir, si
el latido quedó más viejo que `resumeGapMax` (3 min), `_restore()` asume que
el proceso estuvo muerto y **cierra el partido con el tiempo del último
latido** (no infla la duración con el tiempo que el celu pasó en el bolsillo).

### Claves persistidas relevantes

| Clave (base) | Namespaced | Quién la escribe | Qué guarda |
| --- | --- | --- | --- |
| `play_active_session` | sí | servicio + alarmas | Partido en curso: `courtId`, `courtName`, `startMillis`, `endsAtMillis` (si hay gracia), `lastSeenMillis` (latido). |
| `play_pending_result` | sí | servicio + alarmas | Partido cerrado esperando "¿Cómo te fue?". |
| `play_alarm_start/end/warn` | no | session_alarms | Objetivo de cada alarma (cancha, coordenadas, hora). |
| `play_background_enabled` | sí | setBackground | Preferencia "Detección automática" (default **true**). |
| `play_dwell_snooze` | sí | "No juego"/DETENER | `{courtId, untilMillis}`. |
| `play_bg_userkey` | no | SyncCoordinator | userKey activo, para que los isolates armen las claves namespaced. |
| `courts_geo_cache` | no | SyncCoordinator | Catálogo (id/nombre/lat/lng) para el radar. |
| `last_bg_fix_millis` | no | radar + stream | Diagnóstico: último fix obtenido en background (§9). |
| `play_mock_pos` | no | setMock (DEV) | Ubicación simulada; los isolates la respetan para testear sin ir a la cancha. |

## 7. Activación: permisos y gating

La cadena completa para que el background funcione la evalúa
`SyncCoordinator._syncGeofences()`, que registra (o quita) geofences + radar
**solo si se cumplen las cuatro**:

```
sesión iniciada  AND  backgroundEnabled  AND  canchas cargadas  AND  permiso == ALWAYS
```

Si falta cualquiera, se limpia todo — registrar geofences sin permiso
"Siempre" solo daría una falsa sensación de que funciona (Android no entrega
eventos de geofence ni GPS en background sin `always`).

- **"Detección automática"** (fila `AppPerm.background` del modal de
  permisos): encadena la **divulgación destacada** obligatoria de Google Play
  ("recolectamos tu ubicación… incluso con la app cerrada… solo guardamos en
  qué cancha jugaste") → ajustes del sistema → "Permitir todo el tiempo". Al
  volver con el permiso concedido, el modal llama `setBackground(true)` para
  que el coordinador registre geofences + radar **ya mismo**, sin reiniciar.
- La preferencia es **local por dispositivo** (default true) y también se
  puede apagar desde la tuerquita del perfil (corta el FGS y quita
  geofences + radar vía `onBackgroundChanged`).
- Permisos de soporte del modal: **Avisos de partido** (notifs), **Arranque
  puntual** (alarmas exactas, Android 14+ puede revocarlas — hay fallback a
  inexactas), **Detección estable** (exención de optimización de batería —
  crítico en Samsung, ver §8.2).
- Regla de producto: **no agregar auto-requests** de permisos fuera del modal
  y los puntos en-contexto documentados en `CLAUDE.md` §3.

## 8. Gotchas conocidos

### 8.1 Constantes gemelas (¡mantener en sync!)

Los isolates de background no pueden leer las constantes del servicio, así
que `session_alarms.dart` tiene **copias deliberadas**: `_kRadiusMeters`,
`_kDwellThreshold`, `_kExitGrace`, `_kMinMatchSeconds`, `_kEndNotifLead`,
`_kBatteryEndPercent`, `_kConfirmAfter` (= `pointsTimeCap`),
`_kConfirmTimeout` (= `confirmTimeout`) y `_kDwellSnooze` (= `dwellSnooze`).
Y `geofence_service.dart` tiene `kCourtGeofenceRadius` (= `radiusMeters`).
**Si cambiás una, cambiá su gemela.**

### 8.2 Fabricantes agresivos (Samsung y cía.)

Samsung mata el proceso Y el foreground service con la app en background
("optimización" propia, más allá de Doze). Por eso existen las capas 5.4 y
5.5: las alarmas exactas y el radar son lo único que Samsung respeta
razonablemente — y aún así, sin la exención de batería ("Detección estable")
pueden demorarse. Si un usuario reporta que "no detectó el partido", el
checklist es: ¿permiso Siempre? ¿Detección automática activa? ¿exención de
batería? ¿alarmas exactas permitidas?

### 8.3 Modo prueba (mock)

Con la ubicación simulada activa (`setMock`, controles DEV del mapa), **el
GPS real queda bloqueado en todos los caminos**: el stream lo ignora, los
geofences no interfieren (`enterCourtArea`/`leaveCourtArea` retornan) y los
isolates leen `play_mock_pos` antes de pedir un fix. Sin esto, una cancha
real cerca de tu casa arruinaría cualquier prueba simulada.

### 8.4 El radar es inexacto por naturaleza

`AndroidAlarmManager.periodic` usa alarmas inexactas: en Doze profundo los
15 min pueden estirarse. Es aceptable porque el radar es la ÚLTIMA red, no la
vía principal — pero no bajes la cadencia esperando precisión.

## 9. Cómo verificar que el background funciona (en la calle)

1. **Diagnóstico rápido** — controles DEV del mapa (`home_screen.dart`,
   `_lastBgFix`): muestra "último fix hace X" leyendo `last_bg_fix_millis`,
   que escriben el radar y el stream **solo con la app minimizada**. Test:
   minimizar la app (lejos de una cancha), esperar ~20 min, reabrir y mirar
   el indicador. ≤15-20 min = el radar está vivo. "Nunca" o un valor viejo =
   revisar el checklist de §8.2.
2. **Test real de llegada**: ir a una cancha con la app cerrada. Debería
   llegar la notificación de cuenta regresiva (geofence al instante, o radar
   en ≤15 min) y el partido arrancar solo a los 6 min.
3. **Test real de salida**: con partido en curso y app cerrada, alejarse.
   A los ~3 min de gracia llega "tu partido se cierra pronto"; a los 6, el
   cierre y el pendiente de "¿Cómo te fue?" al reabrir.
4. **Sin ir a la cancha**: modo prueba (pin simulado en el mapa) — las
   alarmas también respetan el mock, así que el ciclo completo
   dwell → arranque → gracia → cierre es testeable desde el sillón.

> **Nota**: que el puntito azul del mapa "salte" al reabrir la app **no es un
> síntoma de falla** — es la consecuencia esperada de que no hay rastreo
> continuo (§4). El indicador de §9.1 existe precisamente porque el mapa no
> sirve para verificar el background.
