package com.workoutnotes.workout_notes.medication

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.workoutnotes.workout_notes.MainActivity
import com.workoutnotes.workout_notes.sleep.SleepAlarmScheduler
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import com.workoutnotes.workout_notes.common.PendingIntentFlags

/**
 * Durable medication reminders. Each slot is one medication at one time of
 * day. At the reminder time a notification asks the user to confirm the dose;
 * if nothing is confirmed within the slot's escalation delay, a sound alarm
 * rings until the dose is confirmed or skipped.
 *
 * Confirmations made natively (notification screen or ringing alarm) are
 * appended to a spool that Dart imports into SQLite when the app opens, the
 * same one-way flow used by the sleep monitor.
 */
object MedicationReminderScheduler {
    const val ACTION_REMIND = "com.workoutnotes.workout_notes.medication.REMIND"
    const val ACTION_ESCALATE = "com.workoutnotes.workout_notes.medication.ESCALATE"
    const val EXTRA_SLOT_ID = "medication_slot_id"
    const val EXTRA_DUE_AT = "medication_due_at"
    const val EXTRA_DOSE_KEY = "medication_dose_key"
    const val STATUS_TAKEN = "taken"
    const val STATUS_SKIPPED = "skipped"

    private const val INDEX_PREFS = "medication_reminder_index"
    private const val SPOOL_PREFS = "medication_dose_spool"
    private const val KEY_IDS = "ids"
    private const val KEY_ENTRIES = "entries"

    data class Slot(
        val id: String,
        val medicationId: String,
        val name: String,
        val dosage: String?,
        val hour: Int,
        val minute: Int,
        val weekdays: Set<Int>,
        val escalationMinutes: Int,
        val nextAt: Long,
        val state: String,
        val pendingDoseKey: String?,
        val pendingDueAt: Long,
        val escalationAt: Long,
        val confirmedKeys: Set<String>,
    )

    /** Creates or updates a slot definition, keeping any dose in progress. */
    @Synchronized
    fun schedule(
        context: Context,
        id: String,
        medicationId: String,
        name: String,
        dosage: String?,
        hour: Int,
        minute: Int,
        weekdays: Set<Int>,
        escalationMinutes: Int,
    ) {
        val now = System.currentTimeMillis()
        val existing = read(context, id)
        val slot = Slot(
            id = id,
            medicationId = medicationId,
            name = name,
            dosage = dosage?.takeIf { it.isNotBlank() },
            hour = hour,
            minute = minute,
            weekdays = weekdays,
            escalationMinutes = escalationMinutes.coerceIn(1, 24 * 60),
            nextAt = MedicationReminderPolicy.nextOccurrence(hour, minute, weekdays, now),
            state = existing?.state ?: MedicationReminderPolicy.STATE_SCHEDULED,
            pendingDoseKey = existing?.pendingDoseKey,
            pendingDueAt = existing?.pendingDueAt ?: 0L,
            escalationAt = existing?.escalationAt ?: 0L,
            confirmedKeys = existing?.confirmedKeys ?: emptySet(),
        )
        persist(context, slot)
        setReminderAlarm(context, slot)
    }

    /** Removes a slot and everything it may have armed or shown. */
    @Synchronized
    fun cancel(context: Context, id: String) {
        val slot = read(context, id)
        val alarms = context.getSystemService(AlarmManager::class.java)
        alarms.cancel(reminderIntent(context, id, slot?.nextAt ?: 0L))
        alarms.cancel(escalationIntent(context, id, slot?.pendingDoseKey))
        notifications(context).cancel(notificationId(id))
        if (slot?.state == MedicationReminderPolicy.STATE_RINGING) {
            MedicationAlarmService.stop(context, id)
        }
        preferences(context, id).edit().clear().apply()
        index(context).edit().putStringSet(KEY_IDS, (ids(context) - id).toMutableSet()).apply()
    }

    /** Reminder time reached: notify, arm the escalation and plan the next day. */
    @Synchronized
    fun onReminder(context: Context, id: String, dueAt: Long) {
        val slot = read(context, id) ?: return
        val now = System.currentTimeMillis()
        val due = if (dueAt > 0L) dueAt else slot.nextAt
        val key = MedicationReminderPolicy.doseKey(due)
        val next = MedicationReminderPolicy.nextOccurrence(
            slot.hour, slot.minute, slot.weekdays, maxOf(now, due),
        )
        if (!MedicationReminderPolicy.shouldRemind(key, slot.confirmedKeys)) {
            val updated = slot.copy(nextAt = next)
            persist(context, updated)
            setReminderAlarm(context, updated)
            return
        }
        if (slot.state == MedicationReminderPolicy.STATE_RINGING) {
            // A newer dose supersedes one that was never confirmed.
            MedicationAlarmService.stop(context, id)
        }
        val updated = slot.copy(
            nextAt = next,
            state = MedicationReminderPolicy.STATE_AWAITING,
            pendingDoseKey = key,
            pendingDueAt = due,
            escalationAt = now + MedicationReminderPolicy.escalationDelayMillis(slot.escalationMinutes),
        )
        persist(context, updated)
        setReminderAlarm(context, updated)
        setEscalationAlarm(context, updated)
        MedicationNotifications.showReminder(context, updated)
    }

    /** Escalation time reached: ring if the dose is still unconfirmed. */
    @Synchronized
    fun onEscalate(context: Context, id: String, doseKey: String?) {
        val slot = read(context, id) ?: return
        if (!MedicationReminderPolicy.shouldEscalate(
                slot.state, slot.pendingDoseKey, doseKey, slot.confirmedKeys,
            )
        ) return
        persist(context, slot.copy(state = MedicationReminderPolicy.STATE_RINGING))
        notifications(context).cancel(notificationId(id))
        MedicationAlarmService.start(context, id)
    }

    /**
     * Logs a dose as taken or skipped. [fromNative] confirmations are spooled
     * for Dart; confirmations coming from Dart are already in SQLite.
     */
    @Synchronized
    fun confirm(
        context: Context,
        id: String,
        doseKey: String,
        status: String,
        fromNative: Boolean,
    ): Boolean {
        val slot = read(context, id) ?: return false
        val wasRinging = slot.state == MedicationReminderPolicy.STATE_RINGING &&
            slot.pendingDoseKey == doseKey
        var updated = slot.copy(
            confirmedKeys = MedicationReminderPolicy.pruneConfirmed(slot.confirmedKeys + doseKey),
        )
        if (slot.pendingDoseKey == doseKey) {
            context.getSystemService(AlarmManager::class.java)
                .cancel(escalationIntent(context, id, doseKey))
            notifications(context).cancel(notificationId(id))
            updated = updated.copy(
                state = MedicationReminderPolicy.STATE_SCHEDULED,
                pendingDoseKey = null,
                pendingDueAt = 0L,
                escalationAt = 0L,
            )
        }
        persist(context, updated)
        if (wasRinging) MedicationAlarmService.stop(context, id)
        if (fromNative) appendSpool(context, slot, doseKey, status)
        return true
    }

    /** Re-arms everything after a reboot, an update or an app launch. */
    @Synchronized
    fun restore(context: Context) {
        val now = System.currentTimeMillis()
        ids(context).forEach { id ->
            val slot = read(context, id) ?: return@forEach
            val next = if (slot.nextAt > now) slot.nextAt
            else MedicationReminderPolicy.nextOccurrence(slot.hour, slot.minute, slot.weekdays, now)
            var updated = slot.copy(nextAt = next)
            if (slot.state == MedicationReminderPolicy.STATE_AWAITING && slot.escalationAt <= now) {
                updated = updated.copy(state = MedicationReminderPolicy.STATE_RINGING)
            }
            persist(context, updated)
            try {
                setReminderAlarm(context, updated)
            } catch (_: Throwable) { }
            when (updated.state) {
                MedicationReminderPolicy.STATE_AWAITING -> {
                    try {
                        setEscalationAlarm(context, updated)
                    } catch (_: Throwable) { }
                }
                MedicationReminderPolicy.STATE_RINGING -> MedicationAlarmService.start(context, id)
            }
        }
    }

    fun states(context: Context): List<Map<String, Any?>> = ids(context).mapNotNull { id ->
        read(context, id)?.let {
            mapOf(
                "slot_id" to it.id,
                "medication_id" to it.medicationId,
                "state" to it.state,
                "pending_dose_key" to it.pendingDoseKey,
                "escalation_at_epoch_ms" to it.escalationAt,
                "next_at_epoch_ms" to it.nextAt,
            )
        }
    }

    // ---------------------------------------------------------------- spool

    @Synchronized
    fun spool(context: Context): List<Map<String, Any?>> {
        val entries = spoolEntries(context)
        return (0 until entries.length()).map { index ->
            val entry = entries.getJSONObject(index)
            mapOf(
                "id" to entry.getString("id"),
                "slot_id" to entry.getString("slot_id"),
                "medication_id" to entry.getString("medication_id"),
                "dose_key" to entry.getString("dose_key"),
                "status" to entry.getString("status"),
                "recorded_at_epoch_ms" to entry.getLong("recorded_at"),
            )
        }
    }

    @Synchronized
    fun ackSpool(context: Context, ids: Set<String>) {
        val entries = spoolEntries(context)
        val kept = JSONArray()
        for (index in 0 until entries.length()) {
            val entry = entries.getJSONObject(index)
            if (!ids.contains(entry.getString("id"))) kept.put(entry)
        }
        storage(context).getSharedPreferences(SPOOL_PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ENTRIES, kept.toString()).apply()
    }

    private fun appendSpool(context: Context, slot: Slot, doseKey: String, status: String) {
        val entries = spoolEntries(context)
        entries.put(
            JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("slot_id", slot.id)
                .put("medication_id", slot.medicationId)
                .put("dose_key", doseKey)
                .put("status", status)
                .put("recorded_at", System.currentTimeMillis()),
        )
        storage(context).getSharedPreferences(SPOOL_PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ENTRIES, entries.toString()).commit()
    }

    private fun spoolEntries(context: Context): JSONArray = try {
        JSONArray(
            storage(context).getSharedPreferences(SPOOL_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_ENTRIES, "[]") ?: "[]",
        )
    } catch (_: Throwable) {
        JSONArray()
    }

    // -------------------------------------------------------------- storage

    fun read(context: Context, id: String): Slot? {
        val p = preferences(context, id)
        if (!p.getBoolean("exists", false)) return null
        return Slot(
            id = id,
            medicationId = p.getString("medication_id", "") ?: "",
            name = p.getString("name", "") ?: "",
            dosage = p.getString("dosage", null),
            hour = p.getInt("hour", 8),
            minute = p.getInt("minute", 0),
            weekdays = p.getStringSet("weekdays", mutableSetOf())
                ?.mapNotNull { it.toIntOrNull() }?.toSet() ?: emptySet(),
            escalationMinutes = p.getInt("escalation_minutes", 30),
            nextAt = p.getLong("next_at", 0L),
            state = p.getString("state", MedicationReminderPolicy.STATE_SCHEDULED)
                ?: MedicationReminderPolicy.STATE_SCHEDULED,
            pendingDoseKey = p.getString("pending_dose_key", null),
            pendingDueAt = p.getLong("pending_due_at", 0L),
            escalationAt = p.getLong("escalation_at", 0L),
            confirmedKeys = p.getStringSet("confirmed_keys", mutableSetOf())?.toSet() ?: emptySet(),
        )
    }

    private fun persist(context: Context, slot: Slot) {
        preferences(context, slot.id).edit()
            .putBoolean("exists", true)
            .putString("medication_id", slot.medicationId)
            .putString("name", slot.name)
            .putString("dosage", slot.dosage)
            .putInt("hour", slot.hour)
            .putInt("minute", slot.minute)
            .putStringSet("weekdays", slot.weekdays.map { it.toString() }.toMutableSet())
            .putInt("escalation_minutes", slot.escalationMinutes)
            .putLong("next_at", slot.nextAt)
            .putString("state", slot.state)
            .putString("pending_dose_key", slot.pendingDoseKey)
            .putLong("pending_due_at", slot.pendingDueAt)
            .putLong("escalation_at", slot.escalationAt)
            .putStringSet("confirmed_keys", slot.confirmedKeys.toMutableSet())
            .commit()
        index(context).edit().putStringSet(KEY_IDS, (ids(context) + slot.id).toMutableSet()).apply()
    }

    // --------------------------------------------------------------- alarms

    private fun setReminderAlarm(context: Context, slot: Slot) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation = reminderIntent(context, slot.id, slot.nextAt)
        if (SleepAlarmScheduler.canScheduleExact(context)) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, slot.nextAt, operation)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, slot.nextAt, operation)
        }
    }

    private fun setEscalationAlarm(context: Context, slot: Slot) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation = escalationIntent(context, slot.id, slot.pendingDoseKey)
        if (SleepAlarmScheduler.canScheduleExact(context)) {
            // The escalation is a real alarm: an alarm-clock entry is never
            // deferred by Doze.
            val show = PendingIntent.getActivity(
                context,
                requestCode(slot.id, 3),
                Intent(context, MainActivity::class.java),
                PendingIntentFlags.UPDATE_IMMUTABLE,
            )
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(slot.escalationAt, show), operation)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, slot.escalationAt, operation)
        }
    }

    private fun reminderIntent(context: Context, id: String, dueAt: Long) = PendingIntent.getBroadcast(
        context,
        requestCode(id, 1),
        Intent(context, MedicationReminderReceiver::class.java).apply {
            action = ACTION_REMIND
            data = Uri.parse("medication-reminder://$id")
            putExtra(EXTRA_SLOT_ID, id)
            putExtra(EXTRA_DUE_AT, dueAt)
        },
        PendingIntentFlags.UPDATE_IMMUTABLE,
    )

    private fun escalationIntent(context: Context, id: String, doseKey: String?) = PendingIntent.getBroadcast(
        context,
        requestCode(id, 2),
        Intent(context, MedicationReminderReceiver::class.java).apply {
            action = ACTION_ESCALATE
            data = Uri.parse("medication-escalate://$id")
            putExtra(EXTRA_SLOT_ID, id)
            putExtra(EXTRA_DOSE_KEY, doseKey)
        },
        PendingIntentFlags.UPDATE_IMMUTABLE,
    )

    fun notificationId(id: String): Int = requestCode(id, 4)

    private fun requestCode(id: String, kind: Int) = 40_000 + kind * 1_000_000 + (id.hashCode() and 0x0fffff)
    private fun notifications(context: Context) = context.getSystemService(NotificationManager::class.java)
    private fun ids(context: Context): Set<String> = index(context).getStringSet(KEY_IDS, mutableSetOf()) ?: emptySet()
    private fun index(context: Context) = storage(context).getSharedPreferences(INDEX_PREFS, Context.MODE_PRIVATE)
    private fun preferences(context: Context, id: String) =
        storage(context).getSharedPreferences("medication_slot_${id.replace(Regex("[^A-Za-z0-9_-]"), "_")}", Context.MODE_PRIVATE)
    private fun storage(context: Context): Context = context.createDeviceProtectedStorageContext()
}
