package com.buschfranco.oneofone

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (no FlutterActivity): el plugin `health` necesita las
// Activity Result APIs de androidx para lanzar el diálogo de permisos de Health
// Connect; con FlutterActivity la solicitud falla en silencio.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "oneofone/alarm_perm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // ¿Puede programar alarmas exactas? En Android < 12 siempre sí.
                    "canScheduleExact" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                            result.success(am.canScheduleExactAlarms())
                        } else {
                            result.success(true)
                        }
                    }
                    // Abre la pantalla del sistema para conceder alarmas exactas.
                    "openExactSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            }
                        } catch (e: Exception) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (_: Exception) {
                            }
                        }
                        result.success(null)
                    }
                    // ¿La app está exenta de la optimización de batería? Sin esta
                    // exención, Samsung/One UI congela o mata el proceso (y su
                    // foreground service) en pleno partido.
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    // Pide la exención (diálogo del sistema). Fallback: la lista
                    // general de optimización de batería.
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            } catch (_: Exception) {
                            }
                        }
                        result.success(null)
                    }
                    // Abre la pantalla de Health Connect (fallback manual para
                    // conceder los permisos de salud si el diálogo in-app falla).
                    "openHealthConnect" -> {
                        try {
                            startActivity(
                                Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS")
                            )
                        } catch (_: Exception) {
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
