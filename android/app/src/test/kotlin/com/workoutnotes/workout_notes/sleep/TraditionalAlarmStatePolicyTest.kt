package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TraditionalAlarmStatePolicyTest {
    @Test
    fun `alarm fires only for the current scheduled occurrence`() {
        assertTrue(
            TraditionalAlarmStatePolicy.canMarkRinging(
                state = "scheduled",
                alarmAtMillis = 200L,
                expectedAlarmAtMillis = 200L,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canMarkRinging(
                state = "scheduled",
                alarmAtMillis = 300L,
                expectedAlarmAtMillis = 200L,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canMarkRinging(
                state = "completed",
                alarmAtMillis = 200L,
                expectedAlarmAtMillis = 200L,
            ),
        )
    }

    @Test
    fun `ringing completion is idempotent and respects mission requirement`() {
        assertTrue(
            TraditionalAlarmStatePolicy.canFinishRinging(
                state = "ringing",
                requiresMission = false,
                missionCompleted = false,
            ),
        )
        assertTrue(
            TraditionalAlarmStatePolicy.canFinishRinging(
                state = "ringing",
                requiresMission = true,
                missionCompleted = true,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canFinishRinging(
                state = "scheduled",
                requiresMission = true,
                missionCompleted = true,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canFinishRinging(
                state = "ringing",
                requiresMission = true,
                missionCompleted = false,
            ),
        )
    }

    @Test
    fun `mission can be opened only from an active snooze that requires it`() {
        assertTrue(
            TraditionalAlarmStatePolicy.canOpenSnoozedMission(
                enabled = true,
                state = "scheduled",
                snoozeCount = 1,
                requiresMission = true,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canOpenSnoozedMission(
                enabled = true,
                state = "scheduled",
                snoozeCount = 0,
                requiresMission = true,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canOpenSnoozedMission(
                enabled = true,
                state = "ringing",
                snoozeCount = 1,
                requiresMission = true,
            ),
        )
    }

    @Test
    fun `snooze can be dismissed directly only when no mission is required`() {
        assertTrue(
            TraditionalAlarmStatePolicy.canDismissSnooze(
                enabled = true,
                state = "scheduled",
                snoozeCount = 2,
                requiresMission = false,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canDismissSnooze(
                enabled = true,
                state = "scheduled",
                snoozeCount = 2,
                requiresMission = true,
            ),
        )
        assertFalse(
            TraditionalAlarmStatePolicy.canDismissSnooze(
                enabled = false,
                state = "scheduled",
                snoozeCount = 2,
                requiresMission = false,
            ),
        )
    }
}
