package com.workoutnotes.workout_notes.sleep

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.workoutnotes.workout_notes.MainActivity

object SleepMonitorNotification {
    const val CHANNEL_ID = "sleep_monitoring"
    const val NOTIFICATION_ID = 1101
    const val ACTION_STOP = "com.workoutnotes.workout_notes.sleep.STOP"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                if (context.resources.configuration.locales[0].language == "pt") {
                    "Monitoramento do sono"
                } else {
                    "Sleep monitoring"
                },
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = if (context.resources.configuration.locales[0].language == "pt") {
                    "Monitoramento local de sinais de áudio"
                } else {
                    "Local audio signal monitoring"
                }
                setSound(null, null)
                enableVibration(false)
            },
        )
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
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutable(),
        )
        val stopIntent = PendingIntent.getBroadcast(
            context,
            1103,
            Intent(context, StopSleepMonitoringReceiver::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutable(),
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

    private fun pendingIntentImmutable(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
}
