package com.workoutnotes.workout_notes.sleep

/**
 * What a standalone alarm does when nobody answers it, like the stock clock:
 * after [RING_TIMEOUT_MILLIS] of ringing it snoozes if the alarm still has a
 * snooze to give, and otherwise gives up and reports a missed alarm. A mission
 * alarm out of snoozes keeps ringing: giving up would defeat the mission. (The
 * monitored sleep alarm and medication alarms keep ringing until answered.)
 */
internal object TraditionalAlarmTimeoutPolicy {
    const val RING_TIMEOUT_MILLIS = 10L * 60L * 1_000L

    enum class Action { NONE, SNOOZE, MISSED, KEEP_RINGING }

    fun actionOnTimeout(
        state: String,
        snoozeEnabled: Boolean,
        snoozeCount: Int,
        maxSnoozes: Int,
        requiresMission: Boolean = false,
    ): Action = when {
        state != "ringing" -> Action.NONE
        snoozeEnabled && snoozeCount < maxSnoozes -> Action.SNOOZE
        requiresMission -> Action.KEEP_RINGING
        else -> Action.MISSED
    }
}
