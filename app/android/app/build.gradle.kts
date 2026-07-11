import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProps = Properties()
val localPropsFile = rootProject.file("local.properties")
if (localPropsFile.exists()) localPropsFile.inputStream().use { localProps.load(it) }

// API key del mapa nativo. Fuente única: dart_defines.json (la misma que usa
// `--dart-define-from-file`). local.properties la puede sobreescribir por equipo.
fun resolveMapsApiKey(): String {
    val fromLocal = localProps.getProperty("MAPS_API_KEY")
    if (!fromLocal.isNullOrBlank()) return fromLocal
    // rootProject es app/android → probamos app/ (ubicación actual del archivo)
    // y el repo root (ubicación histórica) como fallback.
    for (path in listOf("../dart_defines.json", "../../dart_defines.json")) {
        val dartDefines = rootProject.file(path)
        if (dartDefines.exists()) {
            val m = Regex("\"MAPS_API_KEY\"\\s*:\\s*\"([^\"]+)\"").find(dartDefines.readText())
            if (m != null) return m.groupValues[1]
        }
    }
    return ""
}

android {
    namespace = "com.buschfranco.oneofone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requerido por flutter_local_notifications (usa APIs de java.time).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.buschfranco.oneofone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // native_geofence requiere minSdk 23+; Health Connect (paquete health)
        // requiere minSdk 26+.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = resolveMapsApiKey()
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
