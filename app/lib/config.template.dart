// CONFIGURACIÓN DE SECRETOS
//
// La app NO usa este archivo en runtime: las claves se inyectan en build-time
// vía --dart-define-from-file=dart_defines.json (gitignored). Este template
// solo documenta qué claves hacen falta.
//
// dart_defines.json:
// {
//   "MAPS_API_KEY": "<google maps key>",
//   "NOTION_TOKEN": "<internal integration secret de Notion, ntn_... o secret_...>"
// }
//
// Los IDs de las bases de Notion tienen default embebido en
// lib/notion/notion_config.dart (no son secretos); se pueden sobreescribir con
// --dart-define NOTION_DB_USERS / NOTION_DB_PROFILES / NOTION_DB_COURTS /
// NOTION_DB_REVIEWS / NOTION_DB_PICKUPS si fuera necesario.
//
// Para correr: flutter run --dart-define-from-file=dart_defines.json
const kMapsApiKey = 'TU_API_KEY_AQUI';
