package com.workoutnotes.workout_notes.sleep

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.workoutnotes.workout_notes.MainActivity
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.PendingIntentFlags

/** "Missed alarm" notice left when a standalone alarm rang for its whole timeout unanswered. */
object TraditionalAlarmMissedNotification {
    private const val CHANNEL_ID = "traditional_alarm_missed"

    fun show(context: Context, snapshot: TraditionalAlarmScheduler.Snapshot) {
        NotificationChannels.ensure(
            context,
            CHANNEL_ID,
            context.getString(R.string.traditional_alarm_missed_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ) {
            description = context.getString(R.string.traditional_alarm_missed_channel_description)
        }
        val open = PendingIntent.getActivity(
            context,
            notificationId(snapshot.id),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        val time = SleepSnoozeNotification.clock(context, snapshot.alarmAtMillis)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setColor(Color.rgb(91, 82, 171))
            .setContentTitle(context.getString(R.string.traditional_alarm_missed_title))
            .setContentText(context.getString(R.string.traditional_alarm_missed_body, time))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(notificationId(snapshot.id), notification)
        } catch (_: SecurityException) {
            // Notifications denied: nothing else to tell the user with.
        }
    }

    private fun notificationId(alarmId: String): Int = 50_000 + (alarmId.hashCode() and 0xfffff)
}
