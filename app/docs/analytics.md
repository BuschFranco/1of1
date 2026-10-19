# Analytics (Firebase / GA4)

Wrapper único: `lib/services/analytics_service.dart`. Solo Android por ahora
(iOS no tiene `GoogleService-Info.plist`). Si Firebase no inicializa, todo es
no-op: nunca rompe la app.

## Reglas para agregar un evento

- Se manda cuando la acción **se completó** (después del `await` que escribe
  al servidor), no al tocar el botón.
- **Nada de datos personales** en los parámetros: ni email, ni handle, ni
  textos que escribió el usuario, ni la insignia de clan. Solo ids de
  cancha/pickup, tipos, cantidades y booleanos (los bool viajan como 0/1).
- snake_case; nombre ≤ 40 caracteres, valores de texto ≤ 100 (el wrapper corta).
- Si GA4 tiene un evento recomendado, usar ese (`login`, `sign_up`, `share`,
  `join_group`): aparece en sus informes estándar.
- El isolate de segundo plano (`session_alarms.dart`) **no** puede loguear: lo
  que pasa ahí se cuenta cuando el isolate principal lo adopta.

## Pantallas

`screen_view` desde `MainShell._logScreen`: `mapa`, `canchas`, `crear`,
`social`, `perfil`, `cancha_detalle`, `filtros`.

## Eventos

| Evento | Dónde | Parámetros |
| --- | --- | --- |
| `share` | `match_detail_screen.dart` `_captureAndShare` | `content_type: session_result`, `status` (success/dismissed/unavailable), `has_photo`, `result`, `games` |
| `post_create` / `post_comment` / `post_like` | `detail_screen.dart` | `court_id` (+ `liked` en el like) |
| `review_create` / `review_delete` | `court_rating_service.dart` | `court_id` (+ `rating`, `has_comment`) |
| `pickup_create` | `pickups_provider.dart` `create` | `court_id`, `team_size`, `is_public`, `has_rewards`, `invited`, `hours_ahead` |
| `join_group` | `pickups_provider.dart` `joinByCode` / `joinPublic` | `group_id`, `method` (code/public), `court_id`, `team_size` |
| `pickup_leave` / `pickup_delete` / `pickup_reschedule` | `pickups_provider.dart` | `court_id` |
| `chat_message` | `pickup_chat_screen.dart` `_sendMessage` | — |
| `court_propose` | `courts_provider.dart` `addCourt` | `type`, `surface`, `free`, `has_hours` |
| `play_session_start` | `sync_coordinator.dart` (`trigger: app`) y `PlaySessionService.reconcileFromPrefs` (`trigger: background`) | `court_id`, `trigger` |
| `play_session_close` | `PlaySessionService.resolvePending` | `result` (`notCounted` = cerró sin cargar), `games`, `wins`, `trainings`, `minutes`, `exp`, `new_court`, `had_health` |
| `play_session_discard` | `sync_coordinator.dart` (`too_short`) y `discardOnTimeout` (`confirm_timeout`) | `minutes`, `reason` |
| `login` / `sign_up` | `session.dart` | `method` (email/google) |
| `logout` | `session.dart` `logout` | `reason` (user/expired) |
| `profile_edit` | `session.dart` `setHandle` / `setClanBadge` / `setTitle` | `field` (handle/badge/title), `first_time` en handle |
| `friend_add` / `friend_remove` | `profile_screen.dart` `_FriendsTab` | `reason` (remove/block) |
| `favorite_toggle` | `favorites_provider.dart` `toggle` | `court_id`, `action` (add/remove) |
| `route_start` | `home_screen.dart` `_setWaypoint` (no en los recálculos) | `court_id`, `mode`, `straight_line` |
| `map_filter` | `home_screen.dart` `_toggleFilter` | `filter`, `active`, `results` |
| `news_open` | `news_screen.dart` `_openArticle` | `league`, `source` |
| `onboarding_complete` | `main.dart` `_leaveOnboarding` | `next` (login/signup) |
| `tour_complete` / `tour_skip` | `app_tour.dart` `runAppTour` | `tour` (`main` o pestaña), `step`, `total`, `via` (skip/back) |
| `permission_result` | `permissions_modal.dart` (modal y primer arranque), `home_screen.dart` `_goToMyLocation`, `PlaySessionService.enableHealth` | `perm` (notifications/location/background/alarm/battery/health), `granted`, `source` (first_run/modal/map/settings/disclosure_declined) |

"Permitir todo el tiempo" se concede en los Ajustes del sistema: se registra
cuando la app vuelve a primer plano con el permiso ya dado (`source: settings`).

## Declaración

Analytics está declarado en la política de privacidad (app:
`lib/data/legal_content.dart`; web: `web/src/i18n/*.json`, clave `privacy`) y
en `docs/play-store/data-safety.md`. Si se suma un SDK o un dato nuevo, se
actualizan los tres.

## Probar

```bash
adb shell setprop debug.firebase.analytics.app com.buschfranco.oneofone
```

y abrir **Firebase → Analytics → DebugView**: los eventos aparecen al instante.
Para apagarlo: `adb shell setprop debug.firebase.analytics.app .none.`
