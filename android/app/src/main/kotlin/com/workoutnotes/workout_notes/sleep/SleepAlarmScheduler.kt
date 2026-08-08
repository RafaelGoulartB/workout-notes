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
    const val EXTRA_MONITOR_MODE = "monitor_mode"
    const val EXTRA_MISSION_TYPE = "mission_type"
    const val EXTRA_MISSION_HASH = "mission_hash"
    const val EXTRA_MISSION_SALT = "mission_salt"
    const val EXTRA_MISSION_FORMAT = "mission_format"
    const val EXTRA_MAX_SNOOZES = "max_snoozes"

    private const val PREFS_NAME = "sleep_alarm_schedule"
    private const val KEY_ALARM_AT = "alarm_at_epoch_ms"
    private const val KEY_SESSION_ID = "session_id"
    private const val KEY_MONITOR_MODE = "monitor_mode"
    private const val KEY_MISSION_TYPE = "mission_type"
    private const val KEY_MISSION_HASH = "mission_hash"
    private const val KEY_MISSION_SALT = "mission_salt"
    private const val KEY_MISSION_FORMAT = "mission_format"
    private const val KEY_MAX_SNOOZES = "max_snoozes"
    private const val KEY_SNOOZE_COUNT = "snooze_count"
    private const val KEY_STATE = "state"
    private const val KEY_EMERGENCY_TAPS = "emergency_taps"
    private const val KEY_EMERGENCY_DEADLINE = "emergency_deadline_epoch_ms"
    private const val KEY_BARCODE_DEADLINE = "barcode_deadline_epoch_ms"
    private const val KEY_BARCODE_PAUSE_ATTEMPTS = "barcode_pause_attempts"
    private const val KEY_BARCODE_PAUSE_ACTIVE = "barcode_pause_active"
    const val STATE_SCHEDULED = "scheduled"
    const val STATE_RINGING = "ringing"
    const val STATE_COMPLETED = "completed"
    const val MAX_EMERGENCY_TAPS = EmergencyChallengePolicy.MAX_TAPS
    const val EMERGENCY_CHALLENGE_DURATION_MILLIS = EmergencyChallengePolicy.DURATION_MILLIS
    const val BARCODE_CHALLENGE_DURATION_MILLIS = 60_000L
    const val MAX_BARCODE_PAUSE_ATTEMPTS = EmergencyChallengePolicy.MAX_BARCODE_PAUSE_ATTEMPTS
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

    data class Snapshot(
        val alarmAtMillis: Long,
        val sessionId: String,
        val monitorMode: String,
        val missionType: String?,
        val missionHash: String?,
        val missionSalt: String?,
        val missionFormat: String?,
        val state: String,
        val maxSnoozes: Int,
        val snoozeCount: Int,
    ) {
        val requiresMission: Boolean get() = monitorMode == "alarm_with_mission"
    }

    fun schedule(
        context: Context,
        alarmAtMillis: Long,
        sessionId: String,
        monitorMode: String = "alarm_without_mission",
        missionType: String? = null,
        missionHash: String? = null,
        missionSalt: String? = null,
        missionFormat: String? = null,
        maxSnoozes: Int = 3,
        snoozeCount: Int = 0,
    ) {
        require(alarmAtMillis > System.currentTimeMillis()) { "Alarm must be in the future" }
        if (!canScheduleExact(context)) {
            throw SecurityException("Exact alarm permission is required")
        }
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation = fireIntent(
            context,
            alarmAtMillis,
            sessionId,
            monitorMode,
            missionType,
            missionHash,
            missionSalt,
            missionFormat,
        )
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
            .putString(KEY_MONITOR_MODE, monitorMode)
            .putString(KEY_MISSION_TYPE, missionType)
            .putString(KEY_MISSION_HASH, missionHash)
            .putString(KEY_MISSION_SALT, missionSalt)
            .putString(KEY_MISSION_FORMAT, missionFormat)
            .putInt(KEY_MAX_SNOOZES, maxSnoozes.coerceIn(0, 10))
            .putInt(KEY_SNOOZE_COUNT, snoozeCount.coerceAtLeast(0))
            .putString(KEY_STATE, STATE_SCHEDULED)
            .putInt(KEY_EMERGENCY_TAPS, 0)
            .remove(KEY_EMERGENCY_DEADLINE)
            .remove(KEY_BARCODE_DEADLINE)
            .remove(KEY_BARCODE_PAUSE_ATTEMPTS)
            .remove(KEY_BARCODE_PAUSE_ACTIVE)
            .apply()
    }

    fun cancel(context: Context) {
        val stored = read(context)
        if (stored != null && stored.state == STATE_SCHEDULED) {
            context.getSystemService(AlarmManager::class.java).cancel(
                fireIntent(context, stored.alarmAtMillis, stored.sessionId,
                    stored.monitorMode, stored.missionType, stored.missionHash,
                    stored.missionSalt, stored.missionFormat),
            )
        }
        clear(context)
    }

    fun markFired(context: Context) {
        preferences(context).edit()
            .putString(KEY_STATE, STATE_RINGING)
            .putInt(KEY_EMERGENCY_TAPS, 0)
            .remove(KEY_EMERGENCY_DEADLINE)
            .remove(KEY_BARCODE_DEADLINE)
            .remove(KEY_BARCODE_PAUSE_ATTEMPTS)
            .remove(KEY_BARCODE_PAUSE_ACTIVE)
            .apply()
    }

    fun complete(context: Context) {
        // Keep the immutable snapshot long enough for Flutter to import the
        // dismissal metadata after a cold start. A later session overwrites it
        // when it schedules its own alarm.
        preferences(context).edit()
            .putString(KEY_STATE, STATE_COMPLETED)
            .putInt(KEY_EMERGENCY_TAPS, 0)
            .remove(KEY_EMERGENCY_DEADLINE)
            .remove(KEY_BARCODE_DEADLINE)
            .remove(KEY_BARCODE_PAUSE_ATTEMPTS)
            .remove(KEY_BARCODE_PAUSE_ACTIVE)
            .apply()
    }

    fun canSnooze(context: Context): Boolean {
        val snapshot = read(context) ?: return false
        return snapshot.state == STATE_RINGING && snapshot.snoozeCount < snapshot.maxSnoozes
    }

    fun snooze(context: Context): Boolean {
        val snapshot = read(context) ?: return false
        if (!canSnooze(context)) return false
        schedule(
            context,
            System.currentTimeMillis() + 5 * 60_000L,
            snapshot.sessionId,
            snapshot.monitorMode,
            snapshot.missionType,
            snapshot.missionHash,
            snapshot.missionSalt,
            snapshot.missionFormat,
            snapshot.maxSnoozes,
            snapshot.snoozeCount + 1,
        )
        return true
    }

    fun emergencyTaps(context: Context): Int =
        preferences(context).getInt(KEY_EMERGENCY_TAPS, 0)

    /** Starts a fresh emergency attempt or continues one surviving recreation. */
    fun beginEmergencyChallenge(context: Context): Boolean {
        val snapshot = read(context) ?: return false
        if (snapshot.state != STATE_RINGING || !snapshot.requiresMission) return false

        val now = System.currentTimeMillis()
        val deadline = emergencyDeadline(context)
        if (deadline <= now) {
            preferences(context).edit()
                .putInt(KEY_EMERGENCY_TAPS, 0)
                .putLong(
                    KEY_EMERGENCY_DEADLINE,
                    now + EmergencyChallengePolicy.DURATION_MILLIS,
                )
                .apply()
        }
        return true
    }

    fun emergencyDeadline(context: Context): Long =
        preferences(context).getLong(KEY_EMERGENCY_DEADLINE, 0L)

    fun emergencyRemainingMillis(context: Context): Long =
        EmergencyChallengePolicy.remainingMillis(
            emergencyDeadline(context),
            System.currentTimeMillis(),
        )

    fun isEmergencyChallengeActive(context: Context): Boolean =
        EmergencyChallengePolicy.isActive(emergencyDeadline(context), System.currentTimeMillis())

    fun resetEmergencyChallenge(context: Context) {
        preferences(context).edit()
            .putInt(KEY_EMERGENCY_TAPS, 0)
            .remove(KEY_EMERGENCY_DEADLINE)
            .apply()
    }

    fun beginBarcodeChallenge(context: Context): Boolean {
        val snapshot = read(context) ?: return false
        if (snapshot.state != STATE_RINGING || !snapshot.requiresMission) return false

        val now = System.currentTimeMillis()
        val deadline = barcodeDeadline(context)
        if (deadline > now) return true

        val previousAttempts = barcodePauseAttempts(context)
        preferences(context).edit()
            .putInt(
                KEY_BARCODE_PAUSE_ATTEMPTS,
                EmergencyChallengePolicy.nextBarcodePauseAttempts(previousAttempts),
            )
            .putBoolean(
                KEY_BARCODE_PAUSE_ACTIVE,
                EmergencyChallengePolicy.shouldPauseBarcodeAttempt(previousAttempts),
            )
            .putLong(KEY_BARCODE_DEADLINE, now + BARCODE_CHALLENGE_DURATION_MILLIS)
            .apply()
        return true
    }

    fun barcodeDeadline(context: Context): Long =
        preferences(context).getLong(KEY_BARCODE_DEADLINE, 0L)

    fun barcodePauseAttempts(context: Context): Int =
        preferences(context).getInt(KEY_BARCODE_PAUSE_ATTEMPTS, 0)

    fun isBarcodePauseActive(context: Context): Boolean =
        preferences(context).getBoolean(KEY_BARCODE_PAUSE_ACTIVE, false)

    fun barcodeRemainingMillis(context: Context): Long =
        (barcodeDeadline(context) - System.currentTimeMillis()).coerceAtLeast(0L)

    fun isBarcodeChallengeActive(context: Context): Boolean =
        barcodeDeadline(context) > System.currentTimeMillis()

    fun resetBarcodeChallenge(context: Context) {
        preferences(context).edit()
            .remove(KEY_BARCODE_DEADLINE)
            .remove(KEY_BARCODE_PAUSE_ACTIVE)
            .apply()
    }

    fun incrementEmergencyTaps(context: Context): Int {
        if (!isEmergencyChallengeActive(context)) return 0
        val next = EmergencyChallengePolicy.nextTaps(emergencyTaps(context))
        preferences(context).edit().putInt(KEY_EMERGENCY_TAPS, next).apply()
        return next
    }

    fun restore(context: Context) {
        val stored = read(context) ?: return
        if (stored.state == STATE_COMPLETED) return
        if (stored.state == STATE_RINGING) {
            SleepAlarmRingingService.start(context, stored.alarmAtMillis)
            return
        }
        if (stored.alarmAtMillis <= System.currentTimeMillis()) {
            markFired(context)
            SleepAlarmRingingService.start(context, stored.alarmAtMillis)
            return
        }
        try {
            schedule(
                context,
                stored.alarmAtMillis,
                stored.sessionId,
                stored.monitorMode,
                stored.missionType,
                stored.missionHash,
                stored.missionSalt,
                stored.missionFormat,
                stored.maxSnoozes,
                stored.snoozeCount,
            )
        } catch (_: Throwable) {
            // Keep the durable schedule so a later boot or permission grant can retry.
        }
    }

    fun read(context: Context): Snapshot? {
        val prefs = preferences(context)
        val alarmAt = prefs.getLong(KEY_ALARM_AT, 0L)
        val sessionId = prefs.getString(KEY_SESSION_ID, null)
        return if (alarmAt > 0L && !sessionId.isNullOrBlank()) {
            Snapshot(
                alarmAt,
                sessionId,
                prefs.getString(KEY_MONITOR_MODE, "alarm_without_mission")
                    ?: "alarm_without_mission",
                prefs.getString(KEY_MISSION_TYPE, null),
                prefs.getString(KEY_MISSION_HASH, null),
                prefs.getString(KEY_MISSION_SALT, null),
                prefs.getString(KEY_MISSION_FORMAT, null),
                prefs.getString(KEY_STATE, STATE_SCHEDULED) ?: STATE_SCHEDULED,
                prefs.getInt(KEY_MAX_SNOOZES, 3),
                prefs.getInt(KEY_SNOOZE_COUNT, 0),
            )
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
        monitorMode: String,
        missionType: String?,
        missionHash: String?,
        missionSalt: String?,
        missionFormat: String?,
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_FIRE,
        Intent(context, SleepAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_ALARM_AT, alarmAtMillis)
            putExtra(EXTRA_SESSION_ID, sessionId)
            putExtra(EXTRA_MONITOR_MODE, monitorMode)
            putExtra(EXTRA_MISSION_TYPE, missionType)
            putExtra(EXTRA_MISSION_HASH, missionHash)
            putExtra(EXTRA_MISSION_SALT, missionSalt)
            putExtra(EXTRA_MISSION_FORMAT, missionFormat)
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
