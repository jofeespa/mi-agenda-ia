package com.miagendaia.mi_agenda_ia

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object AlarmScheduler {
    private const val PREFS = "agenda_alarm_requests"

    fun schedule(
        context: Context,
        id: String,
        title: String,
        itemType: String,
        triggerAt: Long,
        alertMode: String,
        ringtoneUri: String,
        alarmDurationSeconds: Int,
        repeatMinutes: Int,
        occurrenceKey: String,
    ) {
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val requestCode =
            ("$id|$occurrenceKey".hashCode() and 0x7fffffff)

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("itemType", itemType)
            putExtra("alertMode", alertMode)
            putExtra("ringtoneUri", ringtoneUri)
            putExtra("alarmDurationSeconds", alarmDurationSeconds)
            putExtra("repeatMinutes", repeatMinutes)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE,
        )

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAt,
                pendingIntent,
            )
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAt,
                pendingIntent,
            )
        }

        val prefs =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val requests =
            prefs.getStringSet(id, emptySet())?.toMutableSet()
                ?: mutableSetOf()

        requests.add(requestCode.toString())
        prefs.edit().putStringSet(id, requests).apply()
    }

    fun cancelItem(context: Context, id: String) {
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val prefs =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val requests =
            prefs.getStringSet(id, emptySet()) ?: emptySet()

        for (raw in requests) {
            val requestCode = raw.toIntOrNull() ?: continue

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, AlarmReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or
                    PendingIntent.FLAG_IMMUTABLE,
            )

            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        }

        prefs.edit().remove(id).apply()
        AlarmService.stopAlarm(context)
    }
}
