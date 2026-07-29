# Checklist de lanzamiento a Play Store — 1of1

## ✅ Ya hecho (técnico)

- [x] Backend en producción con HTTPS (Render): `https://oneofone-backend.onrender.com`
- [x] App apuntando al backend de producción (`dart_defines.json`)
- [x] Sacado el parche de cleartext LAN (`network_security_config.xml` + atributo del manifest)
- [x] Keystore de release generada (`app/android/app/upload-keystore.jks` + `key.properties`, gitignored)
- [x] `build.gradle.kts` firma el release con la keystore de producción (ya no con la de debug)
- [x] Primer AAB firmado compilado: `app/build/app/outputs/bundle/release/app-release.aab`
- [x] Política de privacidad y Términos publicados y auditados contra el código real: `web/src/pages/privacidad.astro` / `terminos.astro` (el borrador viejo `politica-privacidad.html` de esta carpeta se eliminó por duplicado — ver paso 3 de abajo)
- [x] Guía para el formulario de Seguridad de Datos: [`docs/play-store/data-safety.md`](data-safety.md)
- [x] **Título y descripciones optimizados con ASO** (research de keywords, long-tail): [`docs/play-store/ficha-tienda.md`](ficha-tienda.md)
- [x] **Ícono 512×512** listo: [`assets/icon-512.png`](assets/icon-512.png)
- [x] **Feature graphic 1024×500** listo: [`assets/feature-graphic-1024x500.png`](assets/feature-graphic-1024x500.png)
- [x] Pipeline de capturas de pantalla listo para correr (headlines definidos, script automático): [`assets/README.md`](assets/README.md)
- [x] **Página web de eliminación de cuenta** (exigida desde nov-2023, aparte del botón in-app): `web/src/pages/eliminar-cuenta.astro` (+ `en/eliminar-cuenta.astro`). Explica el borrado in-app instantáneo y una vía por email para quien no tenga la app instalada, y detalla qué se borra (perfil, partidos, reseñas, amistades, pickups/chats, mensajes) basado en lo que realmente hace `ProfilesService.deleteAccount` en el backend. Enlazada desde el footer del sitio. URL para pegar en Play Console → App content → Delete account: **`https://buschfranco.github.io/1of1/eliminar-cuenta`**

## 🧍 Solo vos podés hacer esto (cuenta, pagos, legal)

1. **Crear cuenta de Google Play Console** — [play.google.com/console](https://play.google.com/console),
   pago único de **US$25**. (No puedo pagarlo por vos.)
2. **Publicar la URL de eliminación de cuenta**: Play Console → App content → "Delete account" pide una URL pública además de que el borrado exista in-app. Pegá `https://buschfranco.github.io/1of1/eliminar-cuenta` (o `.../en/eliminar-cuenta` si piden la versión en inglés).
3. **Política de privacidad — ya está publicada, solo falta pegar la URL**:
   - El borrador viejo `politica-privacidad.html` (con placeholders
     `[COMPLETAR ...]` sin completar) se eliminó por ser un duplicado
     desactualizado. La versión real y ya auditada vive en
     `web/src/pages/privacidad.astro` (fuente: `app/lib/data/legal_content.dart`)
     y se publica solo con cada push a `main` vía
     [`.github/workflows/astro.yml`](../../.github/workflows/astro.yml).
   - URL para pegar en Play Console (App content → Privacy policy):
     `https://buschfranco.github.io/1of1/privacidad`
   - Mientras estás ahí, completá también `kPrivacyPolicyUrl`/`kTermsUrl` en
     `app/lib/data/legal_content.dart` (hoy vacías) con esta URL y con
     `https://buschfranco.github.io/1of1/terminos`, así la app también puede
     linkear a la versión web.
4. **Revisar los textos de la ficha** en [`ficha-tienda.md`](ficha-tienda.md) (título, descripciones optimizados para ASO) — están listos para pegar tal cual, ajustalos si querés otra voz.
5. **Tomar las capturas de pantalla reales**: conectá el celu y seguí [`assets/README.md`](assets/README.md) (5 pantallas con headline ya definido, un comando por captura). El ícono y el feature graphic ya están listos, no hace falta tocarlos.
6. **Completar el cuestionario de Data Safety** en Play Console con la tabla de [`data-safety.md`](data-safety.md).
7. **Cuestionario de clasificación de contenido** (IARC) — lo completa Google con preguntas tipo (violencia, contenido generado por usuarios en el chat, etc.). Como hay chat entre usuarios, probablemente marque "interacción con usuarios" y "contenido generado por usuarios" — respondé con sinceridad, Play te guía con las preguntas.
8. **Target audience / público objetivo** — declarar que la app NO está dirigida a niños (13+ recomendado dado el registro por email/Google y el chat).
9. **Subir el AAB** (`app/build/app/outputs/bundle/release/app-release.aab`) a un track (te recomiendo arrancar por **Internal testing** o **Closed testing** antes de producción, así probás con vos y unos pocos usuarios antes del review público).
10. **App access**: si el reviewer de Google necesita loguearse para revisar la app, dejá un usuario de prueba (email/password) en el formulario correspondiente.
11. **Ads**: declarar que la app NO tiene publicidad (asumo que no la tiene).
12. **Google Sign-In tras publicar**: cuando actives Play App Signing, agregá la
    SHA-1 de la *app signing key* (Play Console → Configuración → Firma de la app)
    al cliente OAuth de Android en Google Cloud, o el login con Google falla para
    quien instale desde la tienda. Registro de todas las huellas SHA en
    [`app/docs/google-signin-sha.md`](../../app/docs/google-signin-sha.md).

## 🤝 Lo que puedo seguir preparando cuando me digas

- Tomar las capturas de pantalla reales con vos apenas conectes el celu (ya está el script listo, solo falta el dispositivo).
- Ajustar textos si querés otro tono o probar variantes A/B del título.
- Si Google pide el video de justificación de ubicación en background, armar el guión y grabarlo con vos.
- Subir una nueva versión (`versionCode`/`versionName` en `pubspec.yaml`) cuando haya cambios, y regenerar el AAB firmado.

## Cómo regenerar el AAB en el futuro

```bash
cd app
flutter build appbundle --release --dart-define-from-file=dart_defines.json
```

El archivo sale en `app/build/app/outputs/bundle/release/app-release.aab`, ya
firmado automáticamente con la keystore de `key.properties` (mientras ese
archivo exista en `app/android/`). **Recordá subir la versión en `pubspec.yaml`**
(`version: X.Y.Z+N`, el `+N` es el `versionCode` que debe ser mayor cada vez)
antes de cada subida a Play Store.
