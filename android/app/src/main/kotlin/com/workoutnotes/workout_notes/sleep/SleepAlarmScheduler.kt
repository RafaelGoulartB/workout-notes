package com.workoutnotes.workout_notes.sleep

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.workoutnotes.workout_notes.MainActivity

object SleepAlarmScheduler {
    const val ACTION_FIRE = "com.workoutnotes.workout_notes.sleep.ALARM_FIRE"
    const val EXTRA_ALARM_AT = "alarm_at_epoch_ms"
    const val EXTRA_SESSION_ID = "session_id"

    private const val PREFS_NAME = "sleep_alarm_schedule"
    private const val KEY_ALARM_AT = "alarm_at_epoch_ms"
    private const val KEY_SESSION_ID = "session_id"
    private const val REQUEST_FIRE = 1201
    private const val REQUEST_SHOW = 1202

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val manager = context.getSystemService(AlarmManager::class.java)
        return manager.canScheduleExactAlarms()
    }

    fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return context.getSystemService(NotificationManager::class.java)
            .canUseFullScreenIntent()
    }

    fun openExactAlarmSettings(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || canScheduleExact(activity)) return
        activity.startActivity(
            Intent(
                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Uri.parse("package:${activity.packageName}"),
            ),
        )
    }

    fun openFullScreenIntentSettings(activity: Activity) {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            canUseFullScreenIntent(activity)
        ) return
        activity.startActivity(
            Intent(
                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                Uri.parse("package:${activity.packageName}"),
            ),
        )
    }

    @Throws(SecurityException::class, IllegalArgumentException::class)
    fun schedule(context: Context, alarmAtMillis: Long, sessionId: String) {
        require(alarmAtMillis > System.currentTimeMillis()) { "Alarm must be in the future" }
        if (!canScheduleExact(context)) {
            throw SecurityException("Exact alarm permission is required")
        }
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation = fireIntent(context, alarmAtMillis, sessionId)
        val showIntent = PendingIntent.getActivity(
            context,
            REQUEST_SHOW,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        manager.setAlarmClock(
            AlarmManager.AlarmClockInfo(alarmAtMillis, showIntent),
            operation,
        )
        preferences(context).edit()
            .putLong(KEY_ALARM_AT, alarmAtMillis)
            .putString(KEY_SESSION_ID, sessionId)
            .apply()
    }

    fun cancel(context: Context) {
        val stored = read(context)
        if (stored != null) {
            context.getSystemService(AlarmManager::class.java).cancel(
                fireIntent(context, stored.first, stored.second),
            )
        }
        clear(context)
    }

    fun markFired(context: Context) {
        clear(context)
    }

    fun restore(context: Context) {
        val stored = read(context) ?: return
        if (stored.first <= System.currentTimeMillis()) {
            clear(context)
            return
        }
        try {
            schedule(context, stored.first, stored.second)
        } catch (_: Throwable) {
            // Keep the durable schedule so a later boot or permission grant can retry.
        }
    }

    private fun read(context: Context): Pair<Long, String>? {
        val prefs = preferences(context)
        val alarmAt = prefs.getLong(KEY_ALARM_AT, 0L)
        val sessionId = prefs.getString(KEY_SESSION_ID, null)
        return if (alarmAt > 0L && !sessionId.isNullOrBlank()) {
            alarmAt to sessionId
        } else {
            null
        }
    }

    private fun clear(context: Context) {
        preferences(context).edit().clear().apply()
    }

    private fun preferences(context: Context) =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        } else {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

    private fun fireIntent(
        context: Context,
        alarmAtMillis: Long,
        sessionId: String,
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_FIRE,
        Intent(context, SleepAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_ALARM_AT, alarmAtMillis)
            putExtra(EXTRA_SESSION_ID, sessionId)
        },
        PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
    )

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
}
