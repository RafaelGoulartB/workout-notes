package com.workoutnotes.workout_notes.run

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.workoutnotes.workout_notes.MainActivity

object RunTrackingNotification {
    const val CHANNEL_ID = "run_tracking"
    const val NOTIFICATION_ID = 1201

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val pt = context.resources.configuration.locales[0].language == "pt"
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                if (pt) "Corrida" else "Running",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = if (pt) {
                    "Gravação de corrida com GPS"
                } else {
                    "GPS run recording"
                }
                setSound(null, null)
                enableVibration(false)
            },
        )
    }

    fun build(
        context: Context,
        startedAt: Long,
        distanceMeters: Double,
        durationSeconds: Int,
        status: String,
    ): Notification {
        ensureChannel(context)
        val openIntent = PendingIntent.getActivity(
            context,
            1202,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutable(),
        )
        val pt = context.resources.configuration.locales[0].language == "pt"
        val km = distanceMeters / 1000.0
        val distanceText = String.format("%.2f km", km)
        val timeText = formatDuration(durationSeconds)
        val title = when (status) {
            "paused" -> if (pt) "Corrida pausada" else "Run paused"
            else -> if (pt) "Corrida em andamento" else "Run in progress"
        }
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(title)
            .setContentText("$distanceText · $timeText")
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(startedAt)
            .setUsesChronometer(status != "paused")
            .build()
    }

    private fun formatDuration(totalSeconds: Int): String {
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }

    private fun pendingIntentImmutable(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
}
