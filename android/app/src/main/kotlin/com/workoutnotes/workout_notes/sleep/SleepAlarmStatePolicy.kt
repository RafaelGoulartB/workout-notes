package com.workoutnotes.workout_notes.sleep

internal object SleepAlarmStatePolicy {
    fun canMarkRinging(
        state: String,
        alarmAtMillis: Long,
        expectedAlarmAtMillis: Long,
    ): Boolean = state == "scheduled" && alarmAtMillis == expectedAlarmAtMillis

    /** The next ring is a snooze: scheduled again after at least one snooze. */
    fun isSnoozed(state: String, snoozeCount: Int): Boolean =
        state == "scheduled" && snoozeCount > 0

    /**
     * A mission can be completed while the alarm rings and at any time during
     * a snooze, so an awake user never has to wait for the next ring.
     */
    fun canRunMission(
        state: String,
        snoozeCount: Int,
        requiresMission: Boolean,
    ): Boolean = requiresMission &&
        (state == "ringing" || isSnoozed(state, snoozeCount))

    fun canDismissSnooze(
        state: String,
        snoozeCount: Int,
        requiresMission: Boolean,
    ): Boolean = isSnoozed(state, snoozeCount) && !requiresMission
}
