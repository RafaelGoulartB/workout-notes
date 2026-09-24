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
    fun `snoozed mission can resume only from a scheduled snooze`() {
        assertTrue(
            SleepAlarmStatePolicy.canResumeSnoozedMission(
                state = "scheduled",
                snoozeCount = 1,
                requiresMission = true,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canResumeSnoozedMission(
                state = "scheduled",
                snoozeCount = 0,
                requiresMission = true,
            ),
        )
        assertFalse(
            SleepAlarmStatePolicy.canResumeSnoozedMission(
                state = "ringing",
                snoozeCount = 1,
                requiresMission = true,
            ),
        )
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
