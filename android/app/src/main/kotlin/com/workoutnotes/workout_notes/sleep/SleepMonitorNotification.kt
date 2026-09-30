package com.workoutnotes.workout_notes.sleep

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.workoutnotes.workout_notes.MainActivity
import com.workoutnotes.workout_notes.common.PendingIntentFlags
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.NotificationChannels.silent

object SleepMonitorNotification {
    const val CHANNEL_ID = "sleep_monitoring"
    const val NOTIFICATION_ID = 1101
    const val ACTION_STOP = "com.workoutnotes.workout_notes.sleep.STOP"

    fun ensureChannel(context: Context) {
        val pt = context.resources.configuration.locales[0].language == "pt"
        NotificationChannels.ensure(
            context,
            CHANNEL_ID,
            if (pt) "Monitoramento do sono" else "Sleep monitoring",
            NotificationManager.IMPORTANCE_LOW,
        ) {
            description = if (pt) {
                "Monitoramento local de sinais de áudio"
            } else {
                "Local audio signal monitoring"
            }
            silent()
        }
    }

    fun build(
        context: Context,
        startedAt: Long,
        monitorMode: String = "alarm_without_mission",
    ): Notification {
        ensureChannel(context)
        val openIntent = PendingIntent.getActivity(
            context,
            1102,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getBroadcast(
            context,
            1103,
            Intent(context, StopSleepMonitoringReceiver::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        val pt = context.resources.configuration.locales[0].language == "pt"
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(if (pt) "Monitorando sono" else "Monitoring sleep")
            .setContentText(
                if (pt) "O microfone analisa sinais localmente" else "The microphone analyzes signals locally",
            )
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(startedAt)
            .setUsesChronometer(true)
        if (monitorMode != "alarm_with_mission") {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                if (pt) "Parar" else "Stop",
                stopIntent,
            )
        }
        return builder.build()
    }
}
