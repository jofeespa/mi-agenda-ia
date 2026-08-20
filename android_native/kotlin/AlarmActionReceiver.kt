package com.miagendaia.mi_agenda_ia

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val id = intent.getStringExtra("id") ?: return
        val title =
            intent.getStringExtra("title") ?: "Recordatorio"
        val alertMode =
            intent.getStringExtra("alertMode")
                ?: "soundAndVibration"
        val ringtoneUri =
            intent.getStringExtra("ringtoneUri") ?: ""

        AlarmService.stopAlarm(context)

        when (intent.action) {
            ACTION_OK -> {
                PendingAlarmActions.set(
                    context,
                    "ok",
                    id,
                )
            }

            ACTION_SNOOZE -> {
                AlarmScheduler.schedule(
                    context = context,
                    id = id,
                    title = title,
                    triggerAt =
                        System.currentTimeMillis() +
                            10 * 60 * 1000L,
                    alertMode = alertMode,
                    ringtoneUri = ringtoneUri,
                    occurrenceKey =
                        "snooze-${System.currentTimeMillis()}",
                )
            }

            ACTION_REPROGRAM -> {
                PendingAlarmActions.set(
                    context,
                    "reprogram",
                    id,
                )

                val launchIntent =
                    context.packageManager
                        .getLaunchIntentForPackage(
                            context.packageName,
                        )
                        ?.apply {
                            addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
                            )
                        }

                if (launchIntent != null) {
                    context.startActivity(launchIntent)
                }
            }
        }
    }

    companion object {
        const val ACTION_OK =
            "com.miagendaia.action.OK"
        const val ACTION_SNOOZE =
            "com.miagendaia.action.SNOOZE"
        const val ACTION_REPROGRAM =
            "com.miagendaia.action.REPROGRAM"
    }
}
