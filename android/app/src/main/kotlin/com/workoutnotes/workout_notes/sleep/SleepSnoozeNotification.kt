package com.workoutnotes.workout_notes.sleep

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.PendingIntentFlags
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Quiet, ongoing notification while a monitored alarm is snoozed. It counts
 * down to the next ring and opens the alarm screen, so the mission (or the
 * dismissal) is always one tap away instead of waiting for the next ring.
 */
object SleepSnoozeNotification {
    private const val CHANNEL_ID = "sleep_alarm_snooze"
    private const val NOTIFICATION_ID = 1207
    private const val REQUEST_OPEN = 1208
    private const val REQUEST_DISMISS = 1209

    fun show(context: Context, snapshot: SleepAlarmScheduler.Snapshot) {
        if (!snapshot.isSnoozed) return
        NotificationChannels.ensure(
            context,
            CHANNEL_ID,
            context.getString(R.string.sleep_alarm_snooze_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ) {
            description = context.getString(R.string.sleep_alarm_snooze_channel_description)
            setShowBadge(false)
        }
        val open = PendingIntent.getActivity(
            context,
            REQUEST_OPEN,
            alarmScreenIntent(context, snapshot.alarmAtMillis),
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        val time = clock(context, snapshot.alarmAtMillis)
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setColor(Color.rgb(91, 82, 171))
            .setContentTitle(context.getString(R.string.sleep_alarm_snooze_notification_title, time))
            .setContentText(
                context.getString(
                    if (snapshot.requiresMission) {
                        R.string.sleep_alarm_snooze_notification_mission
                    } else {
                        R.string.sleep_alarm_snooze_notification_plain
                    },
                ),
            )
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(snapshot.alarmAtMillis)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setContentIntent(open)
        if (snapshot.requiresMission) {
            builder.addAction(
                android.R.drawable.ic_menu_camera,
                context.getString(R.string.sleep_alarm_complete_mission_now),
                open,
            )
        } else {
            val dismiss = PendingIntent.getBroadcast(
                context,
                REQUEST_DISMISS,
                Intent(context, SleepAlarmReceiver::class.java).apply {
                    action = SleepAlarmScheduler.ACTION_DISMISS_SNOOZE
                },
                PendingIntentFlags.UPDATE_IMMUTABLE,
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                context.getString(R.string.sleep_alarm_dismiss_now),
                dismiss,
            )
        }
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // Notifications denied: the snooze still rings; the app shows it too.
        }
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Opens the alarm screen on top of whatever is visible (or the lock screen). */
    fun alarmScreenIntent(context: Context, alarmAtMillis: Long): Intent =
        Intent(context, SleepAlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(SleepAlarmScheduler.EXTRA_ALARM_AT, alarmAtMillis)
        }

    /** Wall-clock time in the user's format; [big] drops the AM/PM marker. */
    fun clock(context: Context, millis: Long, big: Boolean = false): String {
        val locale = context.resources.configuration.locales[0] ?: Locale.getDefault()
        val is24Hour = android.text.format.DateFormat.is24HourFormat(context)
        val pattern = if (big) {
            bigClockPattern(context, is24Hour)
        } else {
            android.text.format.DateFormat.getBestDateTimePattern(locale, if (is24Hour) "Hm" else "hm")
        }
        return SimpleDateFormat(pattern, locale).format(Date(millis))
    }

    /** Hours and minutes only, for the large clock of the alarm screen. */
    fun bigClockPattern(context: Context, is24Hour: Boolean): String {
        if (is24Hour) {
            val locale = context.resources.configuration.locales[0] ?: Locale.getDefault()
            return android.text.format.DateFormat.getBestDateTimePattern(locale, "Hm")
        }
        return "h:mm"
    }
}
