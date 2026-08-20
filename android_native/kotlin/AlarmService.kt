package com.miagendaia.mi_agenda_ia

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.*
import android.provider.Settings
import androidx.core.app.NotificationCompat

class AlarmService : Service() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wake: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopPlayback()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                val id = intent.getStringExtra("id") ?: ""
                val title = intent.getStringExtra("title") ?: "Recordatorio"
                val mode =
                    intent.getStringExtra("alertMode") ?: "soundAndVibration"
                val ringtoneUri = intent.getStringExtra("ringtoneUri") ?: ""

                startForeground(
                    notificationId(id),
                    notification(id, title, mode, ringtoneUri),
                )
                startPlayback(mode, ringtoneUri)
            }
        }

        return START_NOT_STICKY
    }

    private fun startPlayback(mode: String, ringtoneUri: String) {
        stopPlayback()

        val powerManager =
            getSystemService(Context.POWER_SERVICE) as PowerManager
        wake = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MiAgendaIA:AlarmWakeLock",
        ).apply {
            acquire(30 * 60 * 1000L)
        }

        val sound = mode == "soundAndVibration" ||
            mode == "strong" ||
            mode == "soundOnly"
        val vib = mode == "soundAndVibration" ||
            mode == "strong" ||
            mode == "vibrationOnly"

        if (sound) {
            player = buildPlayer(ringtoneUri)
            player?.start()
        }

        if (vib) {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                    as VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            val pattern = if (mode == "strong") {
                longArrayOf(0, 1200, 250, 1200, 250)
            } else {
                longArrayOf(0, 800, 400, 800, 400)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        }
    }

    private fun buildPlayer(selectedUri: String): MediaPlayer? {
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        fun fromUri(uri: Uri): MediaPlayer? {
            return try {
                MediaPlayer().apply {
                    setAudioAttributes(attributes)
                    setDataSource(this@AlarmService, uri)
                    isLooping = true
                    prepare()
                }
            } catch (_: Exception) {
                null
            }
        }

        if (selectedUri.isNotBlank()) {
            fromUri(Uri.parse(selectedUri))?.let { return it }
        }

        fromUri(Settings.System.DEFAULT_ALARM_ALERT_URI)?.let { return it }

        return try {
            val afd = resources.openRawResourceFd(R.raw.alarm_tone)
            MediaPlayer().apply {
                setAudioAttributes(attributes)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                isLooping = true
                prepare()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun stopPlayback() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        player?.release()
        player = null

        vibrator?.cancel()
        vibrator = null

        if (wake?.isHeld == true) {
            wake?.release()
        }
        wake = null
    }

    private fun notification(
        id: String,
        title: String,
        mode: String,
        ringtoneUri: String,
    ): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)

        val open = PendingIntent.getActivity(
            this,
            notificationId(id),
            launch.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP,
                )
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun action(actionName: String, code: Int): PendingIntent {
            val actionIntent =
                Intent(this, AlarmActionReceiver::class.java).apply {
                    action = actionName
                    putExtra("id", id)
                    putExtra("title", title)
                    putExtra("alertMode", mode)
                    putExtra("ringtoneUri", ringtoneUri)
                }
            return PendingIntent.getBroadcast(
                this,
                code,
                actionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val base = notificationId(id) * 10

        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Mi Agenda IA")
            .setContentText(title)
            .setStyle(NotificationCompat.BigTextStyle().bigText(title))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setColor(Color.rgb(0, 95, 228))
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .addAction(
                0,
                "OK",
                action(AlarmActionReceiver.ACTION_OK, base + 1),
            )
            .addAction(
                0,
                "Posponer 10 min",
                action(AlarmActionReceiver.ACTION_SNOOZE, base + 2),
            )
            .addAction(
                0,
                "Reprogramar",
                action(AlarmActionReceiver.ACTION_REPROGRAM, base + 3),
            )
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                "Alarmas de Mi Agenda IA",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Alarmas persistentes"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
    }

    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null

    companion object {
        const val CHANNEL = "agenda_alarm_runtime_v3"
        const val ACTION_START = "com.miagendaia.alarm.START"
        const val ACTION_STOP = "com.miagendaia.alarm.STOP"

        fun stopAlarm(context: Context) {
            context.startService(
                Intent(context, AlarmService::class.java).apply {
                    action = ACTION_STOP
                },
            )
        }

        private fun notificationId(id: String) =
            (id.hashCode() and 0x7fffffff).coerceAtLeast(1)
    }
}
