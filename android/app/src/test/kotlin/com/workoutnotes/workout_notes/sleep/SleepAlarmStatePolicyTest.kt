package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepAlarmStatePolicyTest {
    @Test
    fun `alarm fires only for the current scheduled snapshot`() {
        assertTrue(
            SleepAlarmStatePolicy.canMarkRinging(
                state = "scheduled",
                alarmAtMillis = 200L,
                expectedAlarmAtMillis = 200L,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canMarkRinging(
                state = "scheduled",
                alarmAtMillis = 300L,
                expectedAlarmAtMillis = 200L,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canMarkRinging(
                state = "completed",
                alarmAtMillis = 200L,
                expectedAlarmAtMillis = 200L,
            ),
        )
    }

    @Test
    fun `mission runs while ringing and at any time during a snooze`() {
        assertTrue(
            SleepAlarmStatePolicy.canRunMission(
                state = "ringing",
                snoozeCount = 0,
                requiresMission = true,
            ),
        )
        assertTrue(
            SleepAlarmStatePolicy.canRunMission(
                state = "scheduled",
                snoozeCount = 1,
                requiresMission = true,
            ),
        )
        // Before the first ring there is nothing to wake up from yet.
        assertFalse(
            SleepAlarmStatePolicy.canRunMission(
                state = "scheduled",
                snoozeCount = 0,
                requiresMission = true,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canRunMission(
                state = "completed",
                snoozeCount = 1,
                requiresMission = true,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canRunMission(
                state = "ringing",
                snoozeCount = 0,
                requiresMission = false,
            ),
        )
    }

    @Test
    fun `only a scheduled alarm after a snooze counts as snoozed`() {
        assertTrue(SleepAlarmStatePolicy.isSnoozed(state = "scheduled", snoozeCount = 2))
        assertFalse(SleepAlarmStatePolicy.isSnoozed(state = "scheduled", snoozeCount = 0))
        assertFalse(SleepAlarmStatePolicy.isSnoozed(state = "ringing", snoozeCount = 2))
    }

    @Test
    fun `snooze can be dismissed directly only without a mission`() {
        assertTrue(
            SleepAlarmStatePolicy.canDismissSnooze(
                state = "scheduled",
                snoozeCount = 2,
                requiresMission = false,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canDismissSnooze(
                state = "scheduled",
                snoozeCount = 2,
                requiresMission = true,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canDismissSnooze(
                state = "completed",
                snoozeCount = 2,
                requiresMission = false,
            ),
        )
    }
}
