package com.workoutnotes.workout_notes.sleep

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import java.util.Calendar
import com.workoutnotes.workout_notes.common.AlarmRestorePolicy
import com.workoutnotes.workout_notes.common.AlarmTimePolicy
import com.workoutnotes.workout_notes.common.PendingIntentFlags

/** Durable, multi-alarm companion to the single sleep-monitor scheduler. */
object TraditionalAlarmScheduler {
    private const val TAG = "TraditionalAlarms"
    const val ACTION_FIRE = "com.workoutnotes.workout_notes.sleep.TRADITIONAL_ALARM_FIRE"
    const val EXTRA_ID = "traditional_alarm_id"
    const val EXTRA_ALARM_AT = "alarm_at_epoch_ms"
    private const val INDEX_PREFS = "traditional_alarm_index"
    private const val KEY_IDS = "ids"

    data class Snapshot(
        val id: String,
        val alarmAtMillis: Long,
        val hour: Int,
        val minute: Int,
        val weekdays: Set<Int>,
        val snoozeEnabled: Boolean,
        val snoozeMinutes: Int,
        val maxSnoozes: Int,
        val snoozeCount: Int,
        val requiresMission: Boolean,
        val missionHash: String?,
        val missionSalt: String?,
        val missionFormat: String?,
        val state: String,
        val enabled: Boolean,
        /** Starts soft and rises ([com.workoutnotes.workout_notes.common.AlarmWakePrefs]). */
        val gradualVolume: Boolean = false,
    )

    fun schedule(context: Context, snapshot: Snapshot) {
        require(snapshot.alarmAtMillis > System.currentTimeMillis()) { "Alarm must be in the future" }
        if (!SleepAlarmScheduler.canScheduleExact(context)) throw SecurityException("Exact alarm permission is required")
        persist(context, snapshot.copy(state = "scheduled", enabled = true))
        setSystemAlarm(context, snapshot)
    }

    fun cancel(context: Context, id: String) {
        read(context, id)?.let { snapshot ->
            context.getSystemService(AlarmManager::class.java).cancel(fireIntent(context, snapshot))
        }
        remove(context, id)
    }

    @Synchronized
    fun markRinging(context: Context, id: String, expectedAlarmAtMillis: Long? = null): Boolean {
        val snapshot = read(context, id) ?: return false
        if (!TraditionalAlarmStatePolicy.canMarkRinging(
                snapshot.state,
                snapshot.alarmAtMillis,
                expectedAlarmAtMillis,
            )
        ) return false
        persist(context, snapshot.copy(state = "ringing"))
        return true
    }

    fun dismiss(context: Context, id: String) = finish(context, id)

    fun snooze(context: Context, id: String): Snapshot? {
        val snapshot = read(context, id) ?: return null
        if (!snapshot.snoozeEnabled || snapshot.snoozeCount >= snapshot.maxSnoozes) return null
        val next = System.currentTimeMillis() + snapshot.snoozeMinutes.coerceIn(1, 60) * 60_000L
        val scheduled = snapshot.copy(alarmAtMillis = next, state = "scheduled", snoozeCount = snapshot.snoozeCount + 1)
        schedule(context, scheduled)
        return scheduled
    }

    @Synchronized
    fun resumeSnoozedMission(context: Context, id: String): Snapshot? {
        val snapshot = read(context, id) ?: return null
        if (!TraditionalAlarmStatePolicy.canOpenSnoozedMission(
                snapshot.enabled,
                snapshot.state,
                snapshot.snoozeCount,
                snapshot.requiresMission,
            )
        ) return null
        val ringing = snapshot.copy(state = "ringing")
        persist(context, ringing)
        context.getSystemService(AlarmManager::class.java).cancel(fireIntent(context, snapshot))
        return ringing
    }

    @Synchronized
    fun dismissSnooze(context: Context, id: String): Boolean {
        val snapshot = read(context, id) ?: return false
        if (!TraditionalAlarmStatePolicy.canDismissSnooze(
                snapshot.enabled,
                snapshot.state,
                snapshot.snoozeCount,
                snapshot.requiresMission,
            )
        ) return false
        finish(context, id)
        return true
    }

    fun verifyMission(context: Context, id: String, raw: String, format: String): Boolean {
        val snapshot = read(context, id) ?: return false
        if (!snapshot.requiresMission || snapshot.state != "ringing" ||
            snapshot.missionHash.isNullOrBlank() || snapshot.missionSalt.isNullOrBlank()) return false
        val actual = BarcodeMissionCrypto.hash(format, raw, snapshot.missionSalt)
        return BarcodeMissionCrypto.constantTimeEquals(actual, snapshot.missionHash)
    }

    @Synchronized
    fun finish(context: Context, id: String) {
        val snapshot = read(context, id) ?: return
        if (snapshot.weekdays.isEmpty()) {
            persist(context, snapshot.copy(state = "completed", enabled = false))
            context.getSystemService(AlarmManager::class.java).cancel(fireIntent(context, snapshot))
            return
        }
        val next = nextOccurrence(snapshot, System.currentTimeMillis())
        schedule(context, snapshot.copy(alarmAtMillis = next, state = "scheduled", enabled = true, snoozeCount = 0))
    }

    /**
     * Re-arms every alarm after a reboot, an update or an app launch. A due
     * alarm (ringing, or missed while the phone was off) rings again through
     * an exact alarm shortly after (30 s after a boot), never from the boot receiver
     * itself; one missed by more than
     * [AlarmRestorePolicy.MAX_LATE_RING_MILLIS] is closed (a repeating alarm
     * moves to its next day). One alarm failing never blocks the others.
     */
    fun restore(context: Context, fromBoot: Boolean = false) {
        ids(context).forEach { id ->
            try {
                val snapshot = read(context, id) ?: return@forEach
                if (!snapshot.enabled || snapshot.state == "completed") return@forEach
                val now = System.currentTimeMillis()
                if (snapshot.state == "ringing" && !fromBoot) {
                    // Ringing in this boot: the service start is idempotent.
                    startRinging(context, id)
                    return@forEach
                }
                if (snapshot.state != "ringing" && snapshot.alarmAtMillis > now) {
                    schedule(context, snapshot)
                    return@forEach
                }
                if (AlarmRestorePolicy.shouldRingLate(snapshot.alarmAtMillis, now)) {
                    rearmSoon(context, snapshot, afterBoot = fromBoot)
                } else {
                    finish(context, id)
                }
            } catch (error: Throwable) {
                Log.w(TAG, "Could not restore alarm $id", error)
            }
        }
    }

    /**
     * Arms the alarms again after a time zone or clock change, or when the
     * exact-alarm permission was granted. With [refreshLocalTimes] each
     * alarm's instant is derived again from its local hour and minute (see
     * [AlarmTimePolicy]), so a 07:00 alarm still rings at local 07:00 after
     * travel. Ringing, snoozed and already due alarms are left to the system
     * and [restore]; nothing is rung from here.
     */
    fun rearmPending(context: Context, refreshLocalTimes: Boolean) {
        val now = System.currentTimeMillis()
        ids(context).forEach { id ->
            try {
                val snapshot = read(context, id) ?: return@forEach
                if (!snapshot.enabled || snapshot.state != "scheduled" || snapshot.alarmAtMillis <= now) {
                    return@forEach
                }
                val alarmAt = if (refreshLocalTimes) {
                    AlarmTimePolicy.refreshedAt(
                        snapshot.alarmAtMillis,
                        now,
                        snapshot.hour,
                        snapshot.minute,
                        snapshot.weekdays,
                        snoozed = snapshot.snoozeCount > 0,
                    )
                } else {
                    snapshot.alarmAtMillis
                }
                schedule(context, snapshot.copy(alarmAtMillis = alarmAt))
            } catch (error: Throwable) {
                Log.w(TAG, "Could not re-arm alarm $id", error)
            }
        }
    }

    /**
     * Starts the ringing service of an alarm already marked ringing. If
     * Android refuses the start, the alarm is re-armed shortly ahead
     * instead of staying silently "ringing".
     */
    fun startRinging(context: Context, id: String) {
        try {
            TraditionalAlarmRingingService.start(context, id)
        } catch (error: Throwable) {
            Log.w(TAG, "Alarm ringing service refused to start", error)
            read(context, id)?.let { rearmSoon(context, it, afterBoot = true) }
        }
    }

    /**
     * The ringing service could not become a foreground service (Android
     * refused it, typically right after a boot): ring again once the refusal
     * no longer applies instead of crashing or staying silently "ringing".
     */
    fun recoverRefusedRing(context: Context, id: String) {
        read(context, id)?.let { rearmSoon(context, it, afterBoot = true) }
    }

    private fun rearmSoon(context: Context, snapshot: Snapshot, afterBoot: Boolean) {
        try {
            schedule(
                context,
                snapshot.copy(
                    alarmAtMillis = AlarmRestorePolicy.rearmAt(
                        System.currentTimeMillis(),
                        afterBoot,
                    ),
                    state = "scheduled",
                ),
            )
        } catch (error: Throwable) {
            // Exact alarms were revoked: the next launch or boot retries.
            Log.w(TAG, "Could not re-arm alarm ${snapshot.id}", error)
        }
    }

    fun states(context: Context): List<Map<String, Any>> = ids(context).mapNotNull { id ->
        read(context, id)?.let {
            mapOf(
                "id" to it.id,
                "enabled" to it.enabled,
                "alarm_at_epoch_ms" to it.alarmAtMillis,
                "state" to it.state,
                "snooze_count" to it.snoozeCount,
                "max_snoozes" to it.maxSnoozes,
                "requires_mission" to it.requiresMission,
            )
        }
    }

    fun read(context: Context, id: String): Snapshot? {
        val p = preferences(context, id)
        if (!p.getBoolean("exists", false)) return null
        return Snapshot(
            id, p.getLong("alarm_at", 0L), p.getInt("hour", 7), p.getInt("minute", 0),
            p.getStringSet("weekdays", mutableSetOf())?.mapNotNull { it.toIntOrNull() }?.toSet() ?: emptySet(),
            p.getBoolean("snooze_enabled", true), p.getInt("snooze_minutes", 5),
            p.getInt("max_snoozes", 3), p.getInt("snooze_count", 0),
            p.getBoolean("requires_mission", false), p.getString("mission_hash", null),
            p.getString("mission_salt", null), p.getString("mission_format", null),
            p.getString("state", "scheduled") ?: "scheduled", p.getBoolean("enabled", true),
            p.getBoolean("gradual_volume", false),
        )
    }

    private fun persist(context: Context, snapshot: Snapshot) {
        preferences(context, snapshot.id).edit()
            .putBoolean("exists", true).putLong("alarm_at", snapshot.alarmAtMillis)
            .putInt("hour", snapshot.hour).putInt("minute", snapshot.minute)
            .putStringSet("weekdays", snapshot.weekdays.map { it.toString() }.toMutableSet())
            .putBoolean("snooze_enabled", snapshot.snoozeEnabled).putInt("snooze_minutes", snapshot.snoozeMinutes)
            .putInt("max_snoozes", snapshot.maxSnoozes).putInt("snooze_count", snapshot.snoozeCount)
            .putBoolean("requires_mission", snapshot.requiresMission).putString("mission_hash", snapshot.missionHash)
            .putString("mission_salt", snapshot.missionSalt).putString("mission_format", snapshot.missionFormat)
            .putString("state", snapshot.state).putBoolean("enabled", snapshot.enabled)
            .putBoolean("gradual_volume", snapshot.gradualVolume).apply()
        index(context).edit().putStringSet(KEY_IDS, (ids(context) + snapshot.id).toMutableSet()).apply()
    }

    private fun remove(context: Context, id: String) {
        preferences(context, id).edit().clear().apply()
        index(context).edit().putStringSet(KEY_IDS, (ids(context) - id).toMutableSet()).apply()
    }

    private fun setSystemAlarm(context: Context, snapshot: Snapshot) {
        val showIntent = PendingIntent.getActivity(context, requestCode(snapshot.id), Intent(context, com.workoutnotes.workout_notes.MainActivity::class.java), PendingIntentFlags.UPDATE_IMMUTABLE)
        context.getSystemService(AlarmManager::class.java).setAlarmClock(AlarmManager.AlarmClockInfo(snapshot.alarmAtMillis, showIntent), fireIntent(context, snapshot))
    }

    private fun fireIntent(context: Context, snapshot: Snapshot) = PendingIntent.getBroadcast(
        context, requestCode(snapshot.id), Intent(context, TraditionalAlarmReceiver::class.java).apply {
            action = ACTION_FIRE; data = Uri.parse("traditional-alarm://${snapshot.id}")
            putExtra(EXTRA_ID, snapshot.id); putExtra(EXTRA_ALARM_AT, snapshot.alarmAtMillis)
        }, PendingIntentFlags.UPDATE_IMMUTABLE,
    )

    private fun nextOccurrence(snapshot: Snapshot, now: Long): Long {
        val calendar = Calendar.getInstance().apply { timeInMillis = now; set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        repeat(8) { offset ->
            val candidate = (calendar.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, offset); set(Calendar.HOUR_OF_DAY, snapshot.hour); set(Calendar.MINUTE, snapshot.minute)
            }
            val weekday = ((candidate.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if (candidate.timeInMillis > now && snapshot.weekdays.contains(weekday)) return candidate.timeInMillis
        }
        return now + 7 * 24 * 60 * 60_000L
    }

    private fun ids(context: Context): Set<String> = index(context).getStringSet(KEY_IDS, mutableSetOf()) ?: emptySet()
    private fun index(context: Context) = storage(context).getSharedPreferences(INDEX_PREFS, Context.MODE_PRIVATE)
    private fun preferences(context: Context, id: String) = storage(context).getSharedPreferences("traditional_alarm_$id", Context.MODE_PRIVATE)
    private fun storage(context: Context): Context = context.createDeviceProtectedStorageContext()
    private fun requestCode(id: String) = 20_000 + (id.hashCode() and 0x3fffffff)
}
