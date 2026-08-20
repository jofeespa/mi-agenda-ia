package com.miagendaia.mi_agenda_ia

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.miagendaia/alarm"
    private val ringtoneRequestCode = 5102

    private var pendingRingtoneResult: MethodChannel.Result? = null
    private var previewRingtone: Ringtone? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine,
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    AlarmScheduler.schedule(
                        context = this,
                        id = call.argument<String>("id") ?: "",
                        title =
                            call.argument<String>("title") ?: "Recordatorio",
                        itemType =
                            call.argument<String>("itemType") ?: "reminder",
                        triggerAt =
                            call.argument<Number>("timestamp")?.toLong() ?: 0L,
                        alertMode =
                            call.argument<String>("alertMode")
                                ?: "soundAndVibration",
                        ringtoneUri =
                            call.argument<String>("ringtoneUri") ?: "",
                        alarmDurationSeconds =
                            call.argument<Number>(
                                "alarmDurationSeconds",
                            )?.toInt() ?: 30,
                        repeatMinutes =
                            call.argument<Number>(
                                "repeatMinutes",
                            )?.toInt() ?: 0,
                        occurrenceKey =
                            call.argument<String>("occurrenceKey") ?: "0",
                    )
                    result.success(null)
                }

                "cancelItem" -> {
                    AlarmScheduler.cancelItem(
                        this,
                        call.argument<String>("id") ?: "",
                    )
                    result.success(null)
                }

                "consumePendingAction" -> {
                    result.success(
                        PendingAlarmActions.consume(this),
                    )
                }

                "requestAlarmPermissions" -> {
                    requestAlarmPermissions()
                    result.success(null)
                }

                "pickRingtone" -> {
                    if (pendingRingtoneResult != null) {
                        result.error(
                            "picker_busy",
                            "Ya hay un selector abierto.",
                            null,
                        )
                    } else {
                        pendingRingtoneResult = result
                        openRingtonePicker(
                            call.argument<String>("currentUri"),
                        )
                    }
                }

                "previewRingtone" -> {
                    val uri = call.argument<String>("uri")
                    stopPreview()

                    if (uri.isNullOrBlank()) {
                        result.success(null)
                    } else {
                        previewRingtone =
                            RingtoneManager.getRingtone(
                                this,
                                Uri.parse(uri),
                            )
                        previewRingtone?.play()
                        result.success(null)
                    }
                }

                "stopRingtonePreview" -> {
                    stopPreview()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun openRingtonePicker(currentUri: String?) {
        val picker =
            Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_TYPE,
                    RingtoneManager.TYPE_ALL,
                )
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_TITLE,
                    "Elige el tono de Mi Agenda IA",
                )
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT,
                    true,
                )
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,
                    false,
                )
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                    Settings.System.DEFAULT_NOTIFICATION_URI,
                )

                if (!currentUri.isNullOrBlank()) {
                    putExtra(
                        RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                        Uri.parse(currentUri),
                    )
                }
            }

        @Suppress("DEPRECATION")
        startActivityForResult(
            picker,
            ringtoneRequestCode,
        )
    }

    @Deprecated("Compatibilidad con selector de tonos")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (requestCode == ringtoneRequestCode) {
            val pendingResult = pendingRingtoneResult
            pendingRingtoneResult = null

            if (resultCode != Activity.RESULT_OK) {
                pendingResult?.success(null)
                return
            }

            @Suppress("DEPRECATION")
            val uri =
                data?.getParcelableExtra<Uri>(
                    RingtoneManager.EXTRA_RINGTONE_PICKED_URI,
                )

            if (uri == null) {
                pendingResult?.success(null)
                return
            }

            val title = try {
                RingtoneManager.getRingtone(
                    this,
                    uri,
                )?.getTitle(this) ?: "Tono seleccionado"
            } catch (_: Exception) {
                "Tono seleccionado"
            }

            pendingResult?.success(
                mapOf(
                    "uri" to uri.toString(),
                    "title" to title,
                ),
            )
            return
        }

        super.onActivityResult(
            requestCode,
            resultCode,
            data,
        )
    }

    private fun stopPreview() {
        try {
            previewRingtone?.stop()
        } catch (_: Exception) {
        }
        previewRingtone = null
    }

    private fun requestAlarmPermissions() {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                2001,
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager =
                getSystemService(Context.ALARM_SERVICE) as AlarmManager

            if (!alarmManager.canScheduleExactAlarms()) {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:$packageName"),
                    ),
                )
            }
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        ) {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager

            if (!notificationManager.canUseFullScreenIntent()) {
                try {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                } catch (_: Exception) {
                }
            }
        }
    }

    override fun onDestroy() {
        stopPreview()
        super.onDestroy()
    }
}
