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
import android.util.Log
import com.workoutnotes.workout_notes.MainActivity
import com.workoutnotes.workout_notes.common.AlarmRestorePolicy
import com.workoutnotes.workout_notes.common.PendingIntentFlags

object SleepAlarmScheduler {
    private const val TAG = "SleepAlarmScheduler"
    const val ACTION_FIRE = "com.workoutnotes.workout_notes.sleep.ALARM_FIRE"
    const val ACTION_DISMISS_SNOOZE = "com.workoutnotes.workout_notes.sleep.ALARM_DISMISS_SNOOZE"
    const val EXTRA_ALARM_AT = "alarm_at_epoch_ms"
    const val EXTRA_SESSION_ID = "session_id"
    const val EXTRA_MONITOR_MODE = "monitor_mode"
    const val EXTRA_MISSION_TYPE = "mission_type"
    const val EXTRA_MISSION_HASH = "mission_hash"
    const val EXTRA_MISSION_SALT = "mission_salt"
    const val EXTRA_MISSION_FORMAT = "mission_format"
    const val EXTRA_MAX_SNOOZES = "max_snoozes"
    const val EXTRA_SMART_WINDOW_MINUTES = "smart_window_minutes"
    const val EXTRA_SMART_THRESHOLD = "smart_threshold"
    const val EXTRA_TRIGGER = "alarm_trigger"
    const val MAX_SMART_WINDOW_MINUTES = 90

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
    private const val KEY_SMART_WINDOW_MINUTES = "smart_window_minutes"
    private const val KEY_SMART_THRESHOLD = "smart_threshold"
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
        /** Minutes before [alarmAtMillis] in which a smart alarm may ring; 0 = off. */
        val smartWindowMinutes: Int = 0,
        /** Probability of sleep under which the smart alarm rings. */
        val smartThreshold: Double = 0.5,
    ) {
        val hasSmartWindow: Boolean get() = smartWindowMinutes > 0
        val smartWindowStartMillis: Long
            get() = alarmAtMillis - smartWindowMinutes * 60_000L

        val requiresMission: Boolean get() = monitorMode == "alarm_with_mission"
        val isSnoozed: Boolean get() = SleepAlarmStatePolicy.isSnoozed(state, snoozeCount)
        val canRunMission: Boolean
            get() = SleepAlarmStatePolicy.canRunMission(state, snoozeCount, requiresMission)
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
        smartWindowMinutes: Int = 0,
        smartThreshold: Double = 0.5,
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
            PendingIntentFlags.UPDATE_IMMUTABLE,
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
            .putInt(
                KEY_SMART_WINDOW_MINUTES,
                smartWindowMinutes.coerceIn(0, MAX_SMART_WINDOW_MINUTES),
            )
            .putFloat(KEY_SMART_THRESHOLD, smartThreshold.coerceIn(0.05, 0.95).toFloat())
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
        SleepSnoozeNotification.cancel(context)
        clear(context)
    }

    @Synchronized
    fun markFired(context: Context, expectedAlarmAtMillis: Long): Boolean {
        val snapshot = read(context) ?: return false
        if (!SleepAlarmStatePolicy.canMarkRinging(
                snapshot.state,
                snapshot.alarmAtMillis,
                expectedAlarmAtMillis,
            )
        ) return false
        val editor = preferences(context).edit().putString(KEY_STATE, STATE_RINGING)
        // A mission started during the snooze keeps going when the snooze
        // rings: the ringing service stays paused until its deadline.
        if (!isEmergencyChallengeActive(context)) {
            editor.putInt(KEY_EMERGENCY_TAPS, 0).remove(KEY_EMERGENCY_DEADLINE)
        }
        if (!isBarcodeChallengeActive(context)) {
            editor.remove(KEY_BARCODE_DEADLINE)
                .remove(KEY_BARCODE_PAUSE_ATTEMPTS)
                .remove(KEY_BARCODE_PAUSE_ACTIVE)
        }
        editor.apply()
        SleepSnoozeNotification.cancel(context)
        return true
    }

    @Synchronized
    fun complete(context: Context) {
        val stored = read(context)
        if (stored != null && stored.state == STATE_SCHEDULED) {
            // Finished during a snooze: the next ring must not fire.
            context.getSystemService(AlarmManager::class.java).cancel(
                fireIntent(context, stored.alarmAtMillis, stored.sessionId,
                    stored.monitorMode, stored.missionType, stored.missionHash,
                    stored.missionSalt, stored.missionFormat),
            )
        }
        SleepSnoozeNotification.cancel(context)
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
            snapshot.smartWindowMinutes,
            snapshot.smartThreshold,
        )
        read(context)?.let { SleepSnoozeNotification.show(context, it) }
        return true
    }

    @Synchronized
    fun dismissSnooze(context: Context): Snapshot? {
        val snapshot = read(context) ?: return null
        if (!SleepAlarmStatePolicy.canDismissSnooze(
                snapshot.state,
                snapshot.snoozeCount,
                snapshot.requiresMission,
            )
        ) return null
        complete(context)
        return snapshot
    }

    /**
     * Rings the first alarm of the night now, before its deadline (smart
     * wake). Only a scheduled, never-snoozed alarm still aimed at
     * [expectedAlarmAtMillis] qualifies. The pending deadline is cancelled
     * only once the ringing service has started; if it cannot start, the
     * deadline stays armed and rings as usual. Must run on the main thread:
     * it stops the monitoring service, whose capture thread may be the
     * caller's.
     */
    fun fireEarly(context: Context, expectedAlarmAtMillis: Long, trigger: String): Boolean {
        val snapshot = synchronized(this) {
            read(context)?.takeIf {
                it.state == STATE_SCHEDULED &&
                    it.snoozeCount == 0 &&
                    it.alarmAtMillis == expectedAlarmAtMillis &&
                    it.alarmAtMillis > System.currentTimeMillis()
            }
        } ?: return false
        if (!ring(context, expectedAlarmAtMillis, trigger, rearmOnFailure = false)) {
            return false
        }
        context.getSystemService(AlarmManager::class.java).cancel(
            fireIntent(context, snapshot.alarmAtMillis, snapshot.sessionId,
                snapshot.monitorMode, snapshot.missionType, snapshot.missionHash,
                snapshot.missionSalt, snapshot.missionFormat),
        )
        return true
    }

    /**
     * Marks the alarm ringing and starts the ringing service; only once it
     * started does it record when and why on the night and end the
     * monitoring (whose foreground service is what lets a smart ring start
     * from the background). If Android refuses the start, the alarm goes back
     * to scheduled and, with [rearmOnFailure], is re-armed as an exact alarm
     * shortly after. Shared by the exact alarm (the deadline), a smart
     * early ring and the re-armed restores.
     */
    fun ring(
        context: Context,
        alarmAtMillis: Long,
        trigger: String,
        rearmOnFailure: Boolean = true,
    ): Boolean {
        val before = read(context)
        if (!markFired(context, alarmAtMillis)) return false
        val snapshot = read(context)
        val ringing = Intent(context, SleepAlarmRingingService::class.java).apply {
            action = SleepAlarmRingingService.ACTION_START
            putExtra(EXTRA_ALARM_AT, alarmAtMillis)
            putExtra(EXTRA_SESSION_ID, snapshot?.sessionId)
            putExtra(EXTRA_MONITOR_MODE, snapshot?.monitorMode)
            putExtra(EXTRA_MISSION_TYPE, snapshot?.missionType)
            putExtra(EXTRA_MISSION_HASH, snapshot?.missionHash)
            putExtra(EXTRA_MISSION_SALT, snapshot?.missionSalt)
            putExtra(EXTRA_MISSION_FORMAT, snapshot?.missionFormat)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(ringing)
            } else {
                context.startService(ringing)
            }
        } catch (error: Throwable) {
            Log.w(TAG, "Alarm ringing service refused to start", error)
            unmarkFired(context, alarmAtMillis)
            if (rearmOnFailure) read(context)?.let { rearmSoon(context, it, afterBoot = true) }
            return false
        }
        // A snooze ringing again is not the moment the night's alarm went off.
        if ((before?.snoozeCount ?: 0) == 0) {
            SleepMonitoringService.recordAlarmFired(context, trigger, System.currentTimeMillis())
        }
        SleepMonitoringService.stopCurrent("alarm")
        return true
    }

    /**
     * The ringing service could not become a foreground service (Android
     * refused it, typically right after a boot): put the alarm back to
     * scheduled and ring it again once the refusal no longer applies.
     */
    fun recoverRefusedRing(context: Context) {
        val snapshot = read(context) ?: return
        if (snapshot.state != STATE_RINGING) return
        rearmSoon(context, snapshot, afterBoot = true)
    }

    /** Undoes [markFired] when the ring could not start. */
    @Synchronized
    private fun unmarkFired(context: Context, alarmAtMillis: Long) {
        val snapshot = read(context) ?: return
        if (snapshot.state != STATE_RINGING || snapshot.alarmAtMillis != alarmAtMillis) return
        preferences(context).edit().putString(KEY_STATE, STATE_SCHEDULED).apply()
    }

    /**
     * Re-arms [snapshot] as an exact alarm shortly ahead (past the boot window
     * when [afterBoot]), keeping its
     * snoozes, mission and smart window. The alarm's receiver may start the
     * ringing service where a boot receiver may not.
     */
    private fun rearmSoon(context: Context, snapshot: Snapshot, afterBoot: Boolean) {
        try {
            schedule(
                context,
                AlarmRestorePolicy.rearmAt(System.currentTimeMillis(), afterBoot),
                snapshot.sessionId,
                snapshot.monitorMode,
                snapshot.missionType,
                snapshot.missionHash,
                snapshot.missionSalt,
                snapshot.missionFormat,
                snapshot.maxSnoozes,
                snapshot.snoozeCount,
                snapshot.smartWindowMinutes,
                snapshot.smartThreshold,
            )
        } catch (error: Throwable) {
            // Exact alarms were revoked: the next launch or boot retries.
            Log.w(TAG, "Could not re-arm the sleep alarm", error)
        }
    }

    fun emergencyTaps(context: Context): Int =
        preferences(context).getInt(KEY_EMERGENCY_TAPS, 0)

    /** Starts a fresh emergency attempt or continues one surviving recreation. */
    fun beginEmergencyChallenge(context: Context): Boolean {
        val snapshot = read(context) ?: return false
        if (!snapshot.canRunMission) return false

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
        if (!snapshot.canRunMission) return false

        val now = System.currentTimeMillis()
        val deadline = barcodeDeadline(context)
        if (deadline > now) return true

        if (snapshot.isSnoozed) {
            // Nothing is ringing, so an early scan spends no pause attempt;
            // if the snooze rings mid-scan it stays quiet until the deadline.
            preferences(context).edit()
                .putBoolean(KEY_BARCODE_PAUSE_ACTIVE, true)
                .putLong(KEY_BARCODE_DEADLINE, now + BARCODE_CHALLENGE_DURATION_MILLIS)
                .apply()
            return true
        }

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

    /**
     * Re-arms the stored alarm after a reboot or an update. One that was
     * ringing, or came due while the phone was off, rings again a few
     * seconds later through an exact alarm (never started from the boot
     * receiver itself); one missed by more than
     * [AlarmRestorePolicy.MAX_LATE_RING_MILLIS] is closed instead.
     */
    fun restore(context: Context) {
        val stored = read(context) ?: return
        if (stored.state == STATE_COMPLETED) return
        val now = System.currentTimeMillis()
        if (stored.state == STATE_RINGING || stored.alarmAtMillis <= now) {
            if (AlarmRestorePolicy.shouldRingLate(stored.alarmAtMillis, now)) {
                rearmSoon(context, stored, afterBoot = true)
            } else {
                complete(context)
            }
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
                stored.smartWindowMinutes,
                stored.smartThreshold,
            )
            read(context)?.takeIf { it.isSnoozed }?.let {
                SleepSnoozeNotification.show(context, it)
            }
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
                prefs.getInt(KEY_SMART_WINDOW_MINUTES, 0),
                prefs.getFloat(KEY_SMART_THRESHOLD, 0.5f).toDouble(),
            )
        } else {
            null
        }
    }

    private fun clear(context: Context) {
        preferences(context).edit().clear().apply()
    }

    private fun preferences(context: Context) =
        context.createDeviceProtectedStorageContext()
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

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
        PendingIntentFlags.UPDATE_IMMUTABLE,
    )
}
