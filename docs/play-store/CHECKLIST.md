# Checklist de lanzamiento a Play Store — 1of1

## ✅ Ya hecho (técnico)

- [x] Backend en producción con HTTPS (Render): `https://oneofone-backend.onrender.com`
- [x] App apuntando al backend de producción (`dart_defines.json`)
- [x] Sacado el parche de cleartext LAN (`network_security_config.xml` + atributo del manifest)
- [x] Keystore de release generada (`app/android/app/upload-keystore.jks` + `key.properties`, gitignored)
- [x] `build.gradle.kts` firma el release con la keystore de producción (ya no con la de debug)
- [x] Primer AAB firmado compilado: `app/build/app/outputs/bundle/release/app-release.aab`
- [x] Borrador de política de privacidad: [`docs/play-store/politica-privacidad.html`](politica-privacidad.html)
- [x] Guía para el formulario de Seguridad de Datos: [`docs/play-store/data-safety.md`](data-safety.md)
- [x] **Título y descripciones optimizados con ASO** (research de keywords, long-tail): [`docs/play-store/ficha-tienda.md`](ficha-tienda.md)
- [x] **Ícono 512×512** listo: [`assets/icon-512.png`](assets/icon-512.png)
- [x] **Feature graphic 1024×500** listo: [`assets/feature-graphic-1024x500.png`](assets/feature-graphic-1024x500.png)
- [x] Pipeline de capturas de pantalla listo para correr (headlines definidos, script automático): [`assets/README.md`](assets/README.md)

## 🧍 Solo vos podés hacer esto (cuenta, pagos, legal)

1. **Crear cuenta de Google Play Console** — [play.google.com/console](https://play.google.com/console),
   pago único de **US$25**. (No puedo pagarlo por vos.)
2. **Completar/revisar y publicar la política de privacidad**:
   - Abrí [`politica-privacidad.html`](politica-privacidad.html) (ya lo tenés abierto en el navegador) y completá los `[COMPLETAR ...]`: email de contacto y fecha.
   - Subila a una URL pública. La más simple sin costo: **GitHub Pages** de este mismo repo:
     - En GitHub → tu repo → Settings → Pages → Source: "Deploy from branch" → branch `main`, carpeta `/docs`.
     - Guardar. En unos minutos queda publicada en algo como `https://buschfranco.github.io/1of1/play-store/politica-privacidad.html`.
   - Guardá esa URL, la vas a pegar en Play Console (App content → Privacy policy).
3. **Revisar los textos de la ficha** en [`ficha-tienda.md`](ficha-tienda.md) (título, descripciones optimizados para ASO) — están listos para pegar tal cual, ajustalos si querés otra voz.
4. **Tomar las capturas de pantalla reales**: conectá el celu y seguí [`assets/README.md`](assets/README.md) (5 pantallas con headline ya definido, un comando por captura). El ícono y el feature graphic ya están listos, no hace falta tocarlos.
5. **Completar el cuestionario de Data Safety** en Play Console con la tabla de [`data-safety.md`](data-safety.md).
6. **Cuestionario de clasificación de contenido** (IARC) — lo completa Google con preguntas tipo (violencia, contenido generado por usuarios en el chat, etc.). Como hay chat entre usuarios, probablemente marque "interacción con usuarios" y "contenido generado por usuarios" — respondé con sinceridad, Play te guía con las preguntas.
7. **Target audience / público objetivo** — declarar que la app NO está dirigida a niños (13+ recomendado dado el registro por email/Google y el chat).
8. **Subir el AAB** (`app/build/app/outputs/bundle/release/app-release.aab`) a un track (te recomiendo arrancar por **Internal testing** o **Closed testing** antes de producción, así probás con vos y unos pocos usuarios antes del review público).
9. **App access**: si el reviewer de Google necesita loguearse para revisar la app, dejá un usuario de prueba (email/password) en el formulario correspondiente.
10. **Ads**: declarar que la app NO tiene publicidad (asumo que no la tiene).

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
