package com.miagendaia.mi_agenda_ia

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class AlarmActivity : Activity() {
    private lateinit var alarmIntent: Intent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        alarmIntent = intent

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)

            val keyguard =
                getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguard.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.decorView.postDelayed(
            {
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                )
            },
            60_000L,
        )

        setContentView(buildContent())
    }

    @Deprecated("La alarma debe cerrarse con una acción explícita.")
    override fun onBackPressed() {
        // No cerrar con Atrás.
    }

    private fun buildContent(): ScrollView {
        val title =
            alarmIntent.getStringExtra("title") ?: "Actividad pendiente"
        val itemType =
            alarmIntent.getStringExtra("itemType") ?: "reminder"

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(48, 72, 48, 48)
            setBackgroundColor(Color.WHITE)
        }

        root.addView(
            TextView(this).apply {
                text = "Mi Agenda IA"
                textSize = 22f
                setTextColor(Color.rgb(7, 95, 228))
                gravity = Gravity.CENTER
            },
        )

        root.addView(
            TextView(this).apply {
                text = typeLabel(itemType)
                textSize = 16f
                setTextColor(Color.DKGRAY)
                gravity = Gravity.CENTER
                setPadding(0, 24, 0, 8)
            },
        )

        root.addView(
            TextView(this).apply {
                text = title
                textSize = 30f
                setTextColor(Color.BLACK)
                gravity = Gravity.CENTER
                setPadding(0, 20, 0, 30)
            },
        )

        root.addView(
            TextView(this).apply {
                text =
                    "Esta alerta seguirá pendiente hasta que elijas una acción."
                textSize = 16f
                gravity = Gravity.CENTER
                setTextColor(Color.DKGRAY)
                setPadding(0, 0, 0, 28)
            },
        )

        addActionButton(
            root,
            "OK · Terminar",
            AlarmActionReceiver.ACTION_OK,
        )

        if (itemType == "task") {
            addActionButton(
                root,
                "Completar tarea",
                AlarmActionReceiver.ACTION_COMPLETE,
            )
        }

        addActionButton(
            root,
            "Posponer 10 minutos",
            AlarmActionReceiver.ACTION_SNOOZE_10,
        )
        addActionButton(
            root,
            "Posponer 30 minutos",
            AlarmActionReceiver.ACTION_SNOOZE_30,
        )
        addActionButton(
            root,
            "Posponer 1 hora",
            AlarmActionReceiver.ACTION_SNOOZE_60,
        )
        addActionButton(
            root,
            "Reprogramar",
            AlarmActionReceiver.ACTION_REPROGRAM,
        )

        return ScrollView(this).apply {
            addView(
                root,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
    }

    private fun addActionButton(
        root: LinearLayout,
        label: String,
        actionName: String,
    ) {
        root.addView(
            Button(this).apply {
                text = label
                textSize = 17f
                isAllCaps = false
                setOnClickListener {
                    sendAction(actionName)
                }
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = 14
            },
        )
    }

    private fun sendAction(actionName: String) {
        val broadcast =
            Intent(this, AlarmActionReceiver::class.java).apply {
                action = actionName
                putExtras(alarmIntent)
            }

        sendBroadcast(broadcast)
        finishAndRemoveTask()
    }

    private fun typeLabel(itemType: String): String =
        when (itemType) {
            "task" -> "TAREA"
            "event" -> "CALENDARIO"
            else -> "RECORDATORIO"
        }
}
