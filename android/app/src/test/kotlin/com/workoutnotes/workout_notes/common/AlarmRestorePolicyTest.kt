package com.workoutnotes.workout_notes.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlarmRestorePolicyTest {
    @Test
    fun `an alarm missed briefly rings late, a stale one does not`() {
        val alarmAt = 1_000_000_000L
        assertTrue(AlarmRestorePolicy.shouldRingLate(alarmAt, alarmAt + 60_000L))
        assertTrue(
            AlarmRestorePolicy.shouldRingLate(
                alarmAt,
                alarmAt + AlarmRestorePolicy.MAX_LATE_RING_MILLIS,
            ),
        )
        assertFalse(
            AlarmRestorePolicy.shouldRingLate(
                alarmAt,
                alarmAt + AlarmRestorePolicy.MAX_LATE_RING_MILLIS + 1,
            ),
        )
    }

    @Test
    fun `a due alarm is re-armed past the boot allowlist window`() {
        assertEquals(10_003_000L, AlarmRestorePolicy.rearmAt(10_000_000L))
        // Inside the 20 s boot window a start still counts as from BOOT_COMPLETED.
        assertEquals(10_030_000L, AlarmRestorePolicy.rearmAt(10_000_000L, afterBoot = true))
    }
}
