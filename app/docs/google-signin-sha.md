# Google Sign-In — huellas SHA de firma (registro)

Login con Google usa el Web OAuth client como `serverClientId` en la app
(`lib/screens/auth_screen.dart`), pero en Android Google valida la app por
**paquete + huella SHA-1** contra un **cliente OAuth de tipo Android** en el mismo
proyecto de Google Cloud. Si la SHA-1 de la firma con la que está instalada la app
no está registrada, el login falla con:

```
Error con Google: PlatformException(sign_in_failed, ...: 10: , null, null)
```

El `10` es **DEVELOPER_ERROR** = SHA-1 no registrada (no es un bug de código).

> **La SHA-1 depende del KEYSTORE, no del build.** Se registra una sola vez por
> keystore; buildear de nuevo no cambia nada. Solo cambia si cambiás de keystore.

## Datos del proyecto

- **Proyecto Google Cloud / número:** `823840378752`
- **serverClientId (Web OAuth):** `823840378752-4rmlor8ivgmgkjsle7irmhu23cbtbabl.apps.googleusercontent.com`
- **Package name (applicationId):** `com.buschfranco.oneofone`
- Dónde se cargan: [Google Cloud Console → APIs y servicios → Credenciales](https://console.cloud.google.com/apis/credentials)
  → cliente OAuth de tipo **Android** (package + SHA-1). Se pueden tener varias
  SHA-1 registradas a la vez.

## Huellas por firma

| Firma | Cuándo se usa | SHA-1 | Registrada |
| --- | --- | --- | --- |
| **Debug** | `flutter run` / builds de debug | `4C:4F:F6:84:BE:0C:55:DE:F4:10:3A:DB:1F:D5:C9:4C:FE:8C:13:AD` | ✅ sí |
| **Upload (release)** | APK/AAB release firmado con `android/app/upload-keystore.jks` (alias `upload`) | `6B:BB:50:20:3B:60:B6:66:22:FD:EA:FA:04:3E:E1:0D:D2:79:BF:86` | ⬅️ cargar |
| **Play App Signing** | app instalada desde Play Store (Google re-firma con SU clave) | `78:09:3D:DE:2C:D2:5A:79:C4:C1:D8:12:26:98:2A:C9:E4:D4:C5:ED` | ⬅️ cargar |

> **Ojo con las dos huellas de Play Console.** La página de firma muestra el
> *certificado de la clave de subida* (= la fila "Upload" de acá) y el
> *certificado de la clave de firma de la app* (= la fila "Play App Signing").
> Son distintas y hay que registrar **las dos**: la de subida cubre los APK que
> compilás e instalás por adb, la de firma cubre todo lo que baje de Play.
> Si falta la segunda, la app instalada desde la tienda muestra el **mapa en
> blanco** y el login con Google falla con `DEVELOPER_ERROR`.
>
> En Play Console la huella de firma vive en **Protegida con Play → Protección
> de Play Store → Gestionar la firma de apps de Play** (Google sacó las
> herramientas de firma de los menús viejos de "Release"; la propia ayuda del
> cliente OAuth de Android cita esa ruta).
>
> **Un cliente OAuth de Android admite UNA sola huella.** Para cubrir varias
> firmas hay que crear **un cliente por huella**, todos con el mismo package
> `com.buschfranco.oneofone`. La restricción de la Maps API key, en cambio, sí
> acepta varios pares package + huella en la misma key.
>
> La huella de Play App Signing de arriba se obtuvo del device (agosto 2026),
> leyendo el error que imprime el propio SDK de Maps:
>
> ```bash
> "C:\Android\platform-tools\adb.exe" logcat -d | grep -A3 "Authorization failure"
> ```
>
> Imprime `Android Application (<cert_fingerprint>;<package_name>): <SHA-1>;com.buschfranco.oneofone`.
> Sirve para verificar con qué firma quedó instalada la app, sin depender de
> navegar Play Console.

SHA-256 (por si algún servicio la pide, ej. Firebase / App Links):

- Debug: `22:2A:8E:F6:91:63:98:58:DC:09:5B:BA:F5:C3:98:B1:40:AB:8D:08:5D:EC:AE:25:E9:32:16:60:1B:38:D4:C0`
- Upload (release): `32:D4:C4:AB:04:79:73:A3:98:CE:FE:C7:5F:DE:84:1F:95:13:E6:8D:9E:AA:9D:91:98:49:B9:60:F7:FE:5F:78`

> Las huellas SHA salen del certificado público de firma — **no son secretas**
> (por eso se pueden versionar). Lo que NO se commitea nunca es el keystore
> (`upload-keystore.jks`) ni `key.properties` (gitignored). **No pierdas el
> upload keystore:** si se pierde, cambia la huella y se complica subir updates.

## Cómo regenerar estas huellas

```bash
# Release (upload keystore) — pide las pass desde android/key.properties
cd app/android
keytool -list -v -keystore app/upload-keystore.jks -alias upload

# Debug
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android
```
