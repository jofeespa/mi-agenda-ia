package com.miagendaia.mi_agenda_ia

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val serviceIntent =
            Intent(context, AlarmService::class.java).apply {
                action = AlarmService.ACTION_START
                putExtra(
                    "id",
                    intent.getStringExtra("id") ?: "",
                )
                putExtra(
                    "title",
                    intent.getStringExtra("title")
                        ?: "Recordatorio",
                )
                putExtra(
                    "alertMode",
                    intent.getStringExtra("alertMode")
                        ?: "soundAndVibration",
                )
                putExtra(
                    "ringtoneUri",
                    intent.getStringExtra("ringtoneUri") ?: "",
                )
            }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
