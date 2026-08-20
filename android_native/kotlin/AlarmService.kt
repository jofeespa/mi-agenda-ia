package com.miagendaia.mi_agenda_ia

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import java.util.Locale

class AlarmService : Service() {
    private val handler = Handler(Looper.getMainLooper())

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    private var active = false
    private var currentTitle = ""
    private var currentMode = "soundAndVibration"
    private var currentRingtoneUri = ""
    private var currentDurationSeconds = 30
    private var currentRepeatMinutes = 0

    private val silenceRunnable = Runnable {
        silencePlayback()
        scheduleRepeatIfNeeded()
    }

    private val repeatRunnable = Runnable {
        if (active) {
            startPlaybackCycle()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()

        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                tts?.language = Locale("es")
                tts?.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SPEECH,
                        )
                        .build(),
                )
            }
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopEverything()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                active = true

                val id = intent.getStringExtra("id") ?: ""
                currentTitle =
                    intent.getStringExtra("title") ?: "Recordatorio"
                val itemType =
                    intent.getStringExtra("itemType") ?: "reminder"
                currentMode =
                    intent.getStringExtra("alertMode") ?: "soundAndVibration"
                currentRingtoneUri =
                    intent.getStringExtra("ringtoneUri") ?: ""
                currentDurationSeconds =
                    intent.getIntExtra("alarmDurationSeconds", 30)
                currentRepeatMinutes =
                    intent.getIntExtra("repeatMinutes", 0)

                startForeground(
                    notificationId(id),
                    buildNotification(
                        id = id,
                        title = currentTitle,
                        itemType = itemType,
                        alertMode = currentMode,
                        ringtoneUri = currentRingtoneUri,
                        duration = currentDurationSeconds,
                        repeatMinutes = currentRepeatMinutes,
                    ),
                )

                startPlaybackCycle()
            }
        }

        return START_NOT_STICKY
    }

    private fun startPlaybackCycle() {
        handler.removeCallbacks(silenceRunnable)
        handler.removeCallbacks(repeatRunnable)
        silencePlayback()

        if (!active) return

        acquireWakeLock()

        val playTone =
            currentMode == "soundAndVibration" ||
                currentMode == "strong" ||
                currentMode == "soundOnly" ||
                currentMode == "toneAndVoice"

        val speak =
            currentMode == "voice" ||
                currentMode == "toneAndVoice"

        val vibrate =
            currentMode == "soundAndVibration" ||
                currentMode == "strong" ||
                currentMode == "vibrationOnly"

        if (playTone) {
            player = buildPlayer(
                currentRingtoneUri,
                currentMode == "toneAndVoice",
            )
            player?.start()
        }

        if (speak) {
            speakTitle()
        }

        if (vibrate) {
            startVibration(currentMode == "strong")
        }

        if (currentDurationSeconds > 0) {
            handler.postDelayed(
                silenceRunnable,
                currentDurationSeconds * 1000L,
            )
        }
    }

    private fun speakTitle() {
        if (!ttsReady) {
            handler.postDelayed(
                {
                    if (
                        active &&
                        (
                            currentMode == "voice" ||
                                currentMode == "toneAndVoice"
                            )
                    ) {
                        speakTitle()
                    }
                },
                700L,
            )
            return
        }

        tts?.speak(
            currentTitle,
            TextToSpeech.QUEUE_FLUSH,
            null,
            "agenda-alarm",
        )
    }

    private fun scheduleRepeatIfNeeded() {
        if (active && currentRepeatMinutes > 0) {
            handler.postDelayed(
                repeatRunnable,
                currentRepeatMinutes * 60 * 1000L,
            )
        }
    }

    private fun buildPlayer(
        selectedUri: String,
        quiet: Boolean,
    ): MediaPlayer? {
        val attributes =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(
                    AudioAttributes.CONTENT_TYPE_SONIFICATION,
                )
                .build()

        fun fromUri(uri: Uri): MediaPlayer? {
            return try {
                MediaPlayer().apply {
                    setAudioAttributes(attributes)
                    setDataSource(this@AlarmService, uri)
                    isLooping = true
                    setVolume(
                        if (quiet) 0.35f else 1.0f,
                        if (quiet) 0.35f else 1.0f,
                    )
                    prepare()
                }
            } catch (_: Exception) {
                null
            }
        }

        if (selectedUri.isNotBlank()) {
            fromUri(Uri.parse(selectedUri))?.let { return it }
        }

        fromUri(Settings.System.DEFAULT_ALARM_ALERT_URI)
            ?.let { return it }

        return try {
            val afd =
                resources.openRawResourceFd(R.raw.alarm_tone)

            MediaPlayer().apply {
                setAudioAttributes(attributes)
                setDataSource(
                    afd.fileDescriptor,
                    afd.startOffset,
                    afd.length,
                )
                afd.close()
                isLooping = true
                prepare()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun startVibration(strong: Boolean) {
        vibrator =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager =
                    getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                        as VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

        val pattern =
            if (strong) {
                longArrayOf(0, 1200, 250, 1200, 250)
            } else {
                longArrayOf(0, 800, 400, 800, 400)
            }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(
                VibrationEffect.createWaveform(pattern, 0),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return

        val powerManager =
            getSystemService(Context.POWER_SERVICE) as PowerManager

        wakeLock =
            powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "MiAgendaIA:AlarmWakeLock",
            ).apply {
                acquire(65_000L)
            }
    }

    private fun silencePlayback() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        player?.release()
        player = null

        vibrator?.cancel()
        vibrator = null

        try {
            tts?.stop()
        } catch (_: Exception) {
        }

        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null
    }

    private fun stopEverything() {
        active = false
        handler.removeCallbacksAndMessages(null)
        silencePlayback()
    }

    private fun buildNotification(
        id: String,
        title: String,
        itemType: String,
        alertMode: String,
        ringtoneUri: String,
        duration: Int,
        repeatMinutes: Int,
    ): Notification {
        val alarmIntent =
            Intent(this, AlarmActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra("id", id)
                putExtra("title", title)
                putExtra("itemType", itemType)
                putExtra("alertMode", alertMode)
                putExtra("ringtoneUri", ringtoneUri)
                putExtra("alarmDurationSeconds", duration)
                putExtra("repeatMinutes", repeatMinutes)
            }

        val fullScreenIntent =
            PendingIntent.getActivity(
                this,
                notificationId(id),
                alarmIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE,
            )

        fun actionPending(
            actionName: String,
            requestCode: Int,
        ): PendingIntent {
            val actionIntent =
                Intent(this, AlarmActionReceiver::class.java).apply {
                    action = actionName
                    putExtra("id", id)
                    putExtra("title", title)
                    putExtra("itemType", itemType)
                    putExtra("alertMode", alertMode)
                    putExtra("ringtoneUri", ringtoneUri)
                    putExtra("alarmDurationSeconds", duration)
                    putExtra("repeatMinutes", repeatMinutes)
                }

            return PendingIntent.getBroadcast(
                this,
                requestCode,
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
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(title),
            )
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setColor(Color.rgb(0, 95, 228))
            .setContentIntent(fullScreenIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(
                0,
                "OK",
                actionPending(
                    AlarmActionReceiver.ACTION_OK,
                    base + 1,
                ),
            )
            .addAction(
                0,
                "Posponer 10 min",
                actionPending(
                    AlarmActionReceiver.ACTION_SNOOZE_10,
                    base + 2,
                ),
            )
            .addAction(
                0,
                "Reprogramar",
                actionPending(
                    AlarmActionReceiver.ACTION_REPROGRAM,
                    base + 3,
                ),
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
                description = "Alarmas tipo despertador"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
    }

    override fun onDestroy() {
        stopEverything()
        try {
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL = "agenda_alarm_runtime_v4"
        const val ACTION_START = "com.miagendaia.alarm.START"
        const val ACTION_STOP = "com.miagendaia.alarm.STOP"

        fun stopAlarm(context: Context) {
            context.startService(
                Intent(context, AlarmService::class.java).apply {
                    action = ACTION_STOP
                },
            )
        }

        private fun notificationId(id: String): Int =
            (id.hashCode() and 0x7fffffff).coerceAtLeast(1)
    }
}
