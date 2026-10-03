package com.workoutnotes.workout_notes.common

import com.workoutnotes.workout_notes.medication.MedicationReminderPolicy
import java.util.TimeZone

/**
 * Keeps alarms defined by a local hour and minute at that local time when the
 * time zone or the clock changes (travel, manual clock change, network time).
 * An alarm stores both its definition (hour, minute, weekdays) and the
 * absolute instant it was armed for; only the definition survives a time zone
 * change, so the instant is derived from it again.
 */
internal object AlarmTimePolicy {
    /**
     * The instant an alarm stored as [storedAtMillis] should now fire.
     *
     * Left untouched: a snoozed alarm (its instant is "N minutes from then",
     * not a time of day) and an alarm already due, which the system fires
     * right away or the restore paths ring late. Otherwise it is the next
     * occurrence of [hour]:[minute] on [weekdays] (empty means every day) in
     * [timeZone].
     */
    fun refreshedAt(
        storedAtMillis: Long,
        nowMillis: Long,
        hour: Int,
        minute: Int,
        weekdays: Set<Int>,
        snoozed: Boolean,
        timeZone: TimeZone = TimeZone.getDefault(),
    ): Long {
        if (snoozed || storedAtMillis <= nowMillis) return storedAtMillis
        return MedicationReminderPolicy.nextOccurrence(hour, minute, weekdays, nowMillis, timeZone)
    }
}
