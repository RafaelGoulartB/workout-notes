package com.workoutnotes.workout_notes.sleep

internal object SleepAlarmStatePolicy {
    fun canMarkRinging(
        state: String,
        alarmAtMillis: Long,
        expectedAlarmAtMillis: Long,
    ): Boolean = state == "scheduled" && alarmAtMillis == expectedAlarmAtMillis

    fun canResumeSnoozedMission(
        state: String,
        snoozeCount: Int,
        requiresMission: Boolean,
    ): Boolean = state == "scheduled" &&
        snoozeCount > 0 && requiresMission

    fun canDismissSnooze(
        state: String,
        snoozeCount: Int,
        requiresMission: Boolean,
    ): Boolean = state == "scheduled" &&
        snoozeCount > 0 && !requiresMission
}
