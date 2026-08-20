package com.miagendaia.mi_agenda_ia

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val title = intent.getStringExtra("title") ?: "Recordatorio"
        val itemType = intent.getStringExtra("itemType") ?: "reminder"
        val alertMode =
            intent.getStringExtra("alertMode") ?: "soundAndVibration"
        val ringtoneUri = intent.getStringExtra("ringtoneUri") ?: ""
        val duration = intent.getIntExtra("alarmDurationSeconds", 30)
        val repeatMinutes = intent.getIntExtra("repeatMinutes", 0)

        AlarmService.stopAlarm(context)

        when (intent.action) {
            ACTION_OK -> PendingAlarmActions.set(context, "ok", id)

            ACTION_COMPLETE -> PendingAlarmActions.set(
                context,
                "complete",
                id,
            )

            ACTION_REPROGRAM -> {
                PendingAlarmActions.set(context, "reprogram", id)
                launchApp(context)
            }

            ACTION_SNOOZE_10 -> scheduleSnooze(
                context,
                id,
                title,
                itemType,
                alertMode,
                ringtoneUri,
                duration,
                repeatMinutes,
                10,
            )

            ACTION_SNOOZE_30 -> scheduleSnooze(
                context,
                id,
                title,
                itemType,
                alertMode,
                ringtoneUri,
                duration,
                repeatMinutes,
                30,
            )

            ACTION_SNOOZE_60 -> scheduleSnooze(
                context,
                id,
                title,
                itemType,
                alertMode,
                ringtoneUri,
                duration,
                repeatMinutes,
                60,
            )
        }
    }

    private fun scheduleSnooze(
        context: Context,
        id: String,
        title: String,
        itemType: String,
        alertMode: String,
        ringtoneUri: String,
        duration: Int,
        repeatMinutes: Int,
        minutes: Int,
    ) {
        AlarmScheduler.schedule(
            context = context,
            id = id,
            title = title,
            itemType = itemType,
            triggerAt =
                System.currentTimeMillis() + minutes * 60 * 1000L,
            alertMode = alertMode,
            ringtoneUri = ringtoneUri,
            alarmDurationSeconds = duration,
            repeatMinutes = repeatMinutes,
            occurrenceKey =
                "snooze-$minutes-${System.currentTimeMillis()}",
        )
    }

    private fun launchApp(context: Context) {
        val launch =
            context.packageManager.getLaunchIntentForPackage(
                context.packageName,
            )?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP,
                )
            }

        if (launch != null) {
            context.startActivity(launch)
        }
    }

    companion object {
        const val ACTION_OK = "com.miagendaia.action.OK"
        const val ACTION_COMPLETE = "com.miagendaia.action.COMPLETE"
        const val ACTION_SNOOZE_10 = "com.miagendaia.action.SNOOZE_10"
        const val ACTION_SNOOZE_30 = "com.miagendaia.action.SNOOZE_30"
        const val ACTION_SNOOZE_60 = "com.miagendaia.action.SNOOZE_60"
        const val ACTION_REPROGRAM = "com.miagendaia.action.REPROGRAM"
    }
}
