// CONFIGURACIÓN DE SECRETOS
//
// La app NO usa este archivo en runtime: las claves se inyectan en build-time
// vía --dart-define-from-file=dart_defines.json (gitignored). Este template
// solo documenta qué claves hacen falta.
//
// dart_defines.json:
// {
//   "MAPS_API_KEY": "<google maps key>",
//   "API_BASE_URL": "https://oneofone-backend.onrender.com"
// }
//
// API_BASE_URL apunta al backend NestJS (backend/). En beta corre en la PC del
// dev: usar la IP LAN (ipconfig → IPv4) y reservarla en el router (DHCP
// reservation) — la URL es const de compile-time, si la IP cambia hay que
// recompilar. El token de Notion vive SOLO en backend/.env (ya no en la app).
//
// Para correr: flutter run --dart-define-from-file=dart_defines.json
const kMapsApiKey = 'TU_API_KEY_AQUI';
