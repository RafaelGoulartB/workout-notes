package com.workoutnotes.workout_notes.medication

import java.util.Calendar
import java.util.TimeZone

/**
 * Pure scheduling rules for medication reminders, kept free of Android types
 * so they can be unit tested. Weekdays use Monday = 1 through Sunday = 7 (the
 * Dart [DateTime.weekday] convention); an empty set means every day.
 */
internal object MedicationReminderPolicy {
    const val STATE_SCHEDULED = "scheduled"
    const val STATE_AWAITING = "awaiting"
    const val STATE_RINGING = "ringing"

    /** Next reminder strictly after [now] for the slot's time and days. */
    fun nextOccurrence(
        hour: Int,
        minute: Int,
        weekdays: Set<Int>,
        now: Long,
        timeZone: TimeZone = TimeZone.getDefault(),
    ): Long {
        val base = Calendar.getInstance(timeZone).apply {
            timeInMillis = now
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        for (offset in 0..7) {
            val candidate = (base.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, offset)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
            }
            if (candidate.timeInMillis <= now) continue
            if (weekdays.isEmpty() || weekdays.contains(weekdayOf(candidate))) {
                return candidate.timeInMillis
            }
        }
        return now + 7 * DAY_MILLIS
    }

    /**
     * Identifies one scheduled dose ("2026-09-29T08:00", local time). Dart
     * builds the same key, so confirmations made on either side match.
     */
    fun doseKey(dueAt: Long, timeZone: TimeZone = TimeZone.getDefault()): String {
        val calendar = Calendar.getInstance(timeZone).apply { timeInMillis = dueAt }
        return String.format(
            java.util.Locale.US,
            "%04d-%02d-%02dT%02d:%02d",
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.DAY_OF_MONTH),
            calendar.get(Calendar.HOUR_OF_DAY),
            calendar.get(Calendar.MINUTE),
        )
    }

    /** Minutes without a confirmation before the sound alarm, kept sane. */
    fun escalationDelayMillis(minutes: Int): Long = minutes.coerceIn(1, 24 * 60) * 60_000L

    /** A reminder notification is shown unless the dose was already logged. */
    fun shouldRemind(doseKey: String, confirmedKeys: Set<String>): Boolean =
        !confirmedKeys.contains(doseKey)

    /** The escalation only rings for the dose it was armed for, if unconfirmed. */
    fun shouldEscalate(
        state: String,
        pendingDoseKey: String?,
        firedDoseKey: String?,
        confirmedKeys: Set<String>,
    ): Boolean = state == STATE_AWAITING &&
        pendingDoseKey != null &&
        pendingDoseKey == firedDoseKey &&
        !confirmedKeys.contains(pendingDoseKey)

    /** Keeps only the most recent confirmation keys (they sort by time). */
    fun pruneConfirmed(keys: Set<String>, keep: Int = 40): Set<String> =
        if (keys.size <= keep) keys else keys.sorted().takeLast(keep).toSet()

    private fun weekdayOf(calendar: Calendar): Int =
        ((calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1

    private const val DAY_MILLIS = 24 * 60 * 60_000L
}
