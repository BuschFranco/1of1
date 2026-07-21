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
| **Play App Signing** | app instalada desde Play Store (Google re-firma con SU clave) | la da **Play Console → Configuración → Firma de la app** al publicar | pendiente |

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
