package com.workoutnotes.workout_notes.sleep

internal object TraditionalAlarmStatePolicy {
    fun canMarkRinging(
        state: String,
        alarmAtMillis: Long,
        expectedAlarmAtMillis: Long?,
    ): Boolean = state == "scheduled" &&
        (expectedAlarmAtMillis == null || alarmAtMillis == expectedAlarmAtMillis)

    fun canFinishRinging(
        state: String,
        requiresMission: Boolean,
        missionCompleted: Boolean,
    ): Boolean = state == "ringing" && requiresMission == missionCompleted

    fun canOpenSnoozedMission(
        enabled: Boolean,
        state: String,
        snoozeCount: Int,
        requiresMission: Boolean,
    ): Boolean = enabled && state == "scheduled" && snoozeCount > 0 && requiresMission

    fun canDismissSnooze(
        enabled: Boolean,
        state: String,
        snoozeCount: Int,
        requiresMission: Boolean,
    ): Boolean = enabled && state == "scheduled" && snoozeCount > 0 && !requiresMission
}
