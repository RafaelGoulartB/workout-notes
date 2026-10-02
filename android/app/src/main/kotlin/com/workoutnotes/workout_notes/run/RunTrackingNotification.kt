package com.workoutnotes.workout_notes.run

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.workoutnotes.workout_notes.MainActivity
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.PendingIntentFlags
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.NotificationChannels.silent

object RunTrackingNotification {
    const val CHANNEL_ID = "run_tracking"
    const val NOTIFICATION_ID = 1201
    const val RECOVERY_CHANNEL_ID = "run_recovery"
    const val RECOVERY_NOTIFICATION_ID = 1205

    private const val REQUEST_OPEN = 1202
    private const val REQUEST_TOGGLE_PAUSE = 1203
    private const val REQUEST_LAP = 1204
    private const val REQUEST_RECOVERY = 1206

    fun ensureChannel(context: Context) {
        val pt = isPortuguese(context)
        NotificationChannels.ensure(
            context,
            CHANNEL_ID,
            if (pt) "Corrida" else "Running",
            NotificationManager.IMPORTANCE_LOW,
        ) {
            description = if (pt) {
                "Gravação de corrida com GPS"
            } else {
                "GPS run recording"
            }
            silent()
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
    }

    /**
     * Minimal notification that satisfies `startForeground` when a
     * `startForegroundService` start has nothing to record and stops at once.
     */
    fun buildPlaceholder(context: Context): Notification {
        ensureChannel(context)
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(context.getString(R.string.run_placeholder_title))
            .setContentText(context.getString(R.string.run_placeholder_text))
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    /**
     * "Run paused, tap to resume": posted when the system restarts the service
     * from the background and Android refuses a location foreground service.
     * The spool stays intact; opening the app takes the recoverActive path.
     */
    fun buildRecoveryNotice(context: Context): Notification {
        NotificationChannels.ensure(
            context,
            RECOVERY_CHANNEL_ID,
            context.getString(R.string.run_recovery_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        val openIntent = PendingIntent.getActivity(
            context,
            REQUEST_RECOVERY,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        return NotificationCompat.Builder(context, RECOVERY_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(context.getString(R.string.run_recovery_title))
            .setContentText(context.getString(R.string.run_recovery_text))
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(context.getString(R.string.run_recovery_text)),
            )
            .setContentIntent(openIntent)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .build()
    }

    /** Best effort: the notification permission may be denied. */
    fun postRecoveryNotice(context: Context) {
        try {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.notify(RECOVERY_NOTIFICATION_ID, buildRecoveryNotice(context))
        } catch (_: Throwable) {
            // No permission or no manager: the spool is intact and the app
            // recovers the run the next time it opens.
        }
    }

    fun cancelRecoveryNotice(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)
                .cancel(RECOVERY_NOTIFICATION_ID)
        } catch (_: Throwable) {
            // Nothing to cancel.
        }
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
            PendingIntentFlags.UPDATE_IMMUTABLE,
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
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
    }

    private fun isPortuguese(context: Context): Boolean =
        context.resources.configuration.locales[0].language == "pt"
}
