package com.workoutnotes.workout_notes.sleep

import com.workoutnotes.workout_notes.sleep.TraditionalAlarmTimeoutPolicy.Action
import org.junit.Assert.assertEquals
import org.junit.Test

class TraditionalAlarmTimeoutPolicyTest {
    @Test
    fun `the timeout is ten minutes like the stock clock`() {
        assertEquals(600_000L, TraditionalAlarmTimeoutPolicy.RING_TIMEOUT_MILLIS)
    }

    @Test
    fun `an unanswered alarm with a snooze left snoozes`() {
        assertEquals(
            Action.SNOOZE,
            TraditionalAlarmTimeoutPolicy.actionOnTimeout("ringing", true, 0, 3),
        )
        assertEquals(
            Action.SNOOZE,
            TraditionalAlarmTimeoutPolicy.actionOnTimeout("ringing", true, 2, 3),
        )
    }

    @Test
    fun `an unanswered alarm out of snoozes is missed`() {
        assertEquals(
            Action.MISSED,
            TraditionalAlarmTimeoutPolicy.actionOnTimeout("ringing", true, 3, 3),
        )
    }

    @Test
    fun `an unanswered alarm without snooze is missed`() {
        assertEquals(
            Action.MISSED,
            TraditionalAlarmTimeoutPolicy.actionOnTimeout("ringing", false, 0, 3),
        )
        assertEquals(
            Action.MISSED,
            TraditionalAlarmTimeoutPolicy.actionOnTimeout("ringing", true, 0, 0),
        )
    }

    @Test
    fun `nothing happens when the alarm is not ringing any more`() {
        for (state in listOf("scheduled", "completed")) {
            assertEquals(
                Action.NONE,
                TraditionalAlarmTimeoutPolicy.actionOnTimeout(state, true, 0, 3),
            )
        }
    }

    @Test
    fun `a mission alarm out of snoozes keeps ringing`() {
        assertEquals(
            Action.KEEP_RINGING,
            TraditionalAlarmTimeoutPolicy.actionOnTimeout("ringing", false, 0, 0, requiresMission = true),
        )
        assertEquals(
            Action.SNOOZE,
            TraditionalAlarmTimeoutPolicy.actionOnTimeout("ringing", true, 0, 3, requiresMission = true),
        )
    }
}
