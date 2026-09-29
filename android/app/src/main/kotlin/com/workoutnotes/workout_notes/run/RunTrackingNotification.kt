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

    private const val REQUEST_OPEN = 1202
    private const val REQUEST_TOGGLE_PAUSE = 1203
    private const val REQUEST_LAP = 1204

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val pt = isPortuguese(context)
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
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
    }

    /**
     * Ongoing notification: `time · distance · pace` plus Pause/Resume and Lap
     * actions, readable on the lock screen. [movingSeconds] is the moving
     * clock, so it also freezes while paused or auto-paused.
     */
    fun build(
        context: Context,
        startedAt: Long,
        distanceMeters: Double,
        movingSeconds: Int,
        paceSecPerKm: Double?,
        status: String,
        autoPaused: Boolean = false,
    ): Notification {
        ensureChannel(context)
        val pt = isPortuguese(context)
        val openIntent = PendingIntent.getActivity(
            context,
            REQUEST_OPEN,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutable(),
        )
        val paused = status == "paused"
        val title = when {
            paused -> if (pt) "Corrida pausada" else "Run paused"
            autoPaused -> if (pt) "Pausa automática" else "Auto-paused"
            else -> if (pt) "Corrida em andamento" else "Run in progress"
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(title)
            .setContentText(summaryText(distanceMeters, movingSeconds, paceSecPerKm, pt))
            .setContentIntent(openIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setWhen(startedAt)
            .setUsesChronometer(false)
        builder.addAction(
            0,
            if (paused) {
                if (pt) "Retomar" else "Resume"
            } else {
                if (pt) "Pausar" else "Pause"
            },
            servicePendingIntent(
                context,
                REQUEST_TOGGLE_PAUSE,
                if (paused) RunTrackingService.ACTION_RESUME else RunTrackingService.ACTION_PAUSE,
            ),
        )
        if (!paused) {
            builder.addAction(
                0,
                if (pt) "Volta" else "Lap",
                servicePendingIntent(context, REQUEST_LAP, RunTrackingService.ACTION_LAP),
            )
        }
        return builder.build()
    }

    /** `00:12:34 · 2.35 km · 5:32 /km`, localized decimal separator aside. */
    fun summaryText(
        distanceMeters: Double,
        movingSeconds: Int,
        paceSecPerKm: Double?,
        portuguese: Boolean,
    ): String {
        val locale = if (portuguese) java.util.Locale("pt", "BR") else java.util.Locale.US
        val distance = String.format(locale, "%.2f km", distanceMeters / 1000.0)
        val time = formatDuration(movingSeconds)
        val pace = formatPace(paceSecPerKm)
        return "$time · $distance · $pace"
    }

    fun formatDuration(totalSeconds: Int): String {
        val safe = totalSeconds.coerceAtLeast(0)
        val hours = safe / 3600
        val minutes = (safe % 3600) / 60
        val seconds = safe % 60
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }

    fun formatPace(secPerKm: Double?): String {
        if (secPerKm == null || !secPerKm.isFinite() || secPerKm <= 0 || secPerKm > 99 * 60) {
            return "--:-- /km"
        }
        val total = Math.round(secPerKm).toInt()
        return String.format("%d:%02d /km", total / 60, total % 60)
    }

    private fun servicePendingIntent(context: Context, requestCode: Int, action: String): PendingIntent {
        val intent = Intent(context, RunTrackingService::class.java).apply { this.action = action }
        return PendingIntent.getService(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutable(),
        )
    }

    private fun isPortuguese(context: Context): Boolean =
        context.resources.configuration.locales[0].language == "pt"

    private fun pendingIntentImmutable(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
}
