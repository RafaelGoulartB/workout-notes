package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RunStartCommandPolicyTest {
    @Test
    fun startRestoreAndStickyRestartOweAForegroundCall() {
        assertTrue(RunStartCommandPolicy.requiresForeground(RunTrackingService.ACTION_START))
        assertTrue(RunStartCommandPolicy.requiresForeground(RunTrackingService.ACTION_RESTORE))
        assertTrue(RunStartCommandPolicy.requiresForeground(null))
        assertTrue(RunStartCommandPolicy.requiresForeground("unknown"))
    }

    @Test
    fun notificationActionsDoNotOweAForegroundCall() {
        listOf(
            RunTrackingService.ACTION_PAUSE,
            RunTrackingService.ACTION_RESUME,
            RunTrackingService.ACTION_LAP,
            RunTrackingService.ACTION_STOP,
            RunTrackingService.ACTION_DISCARD,
        ).forEach { assertFalse(it, RunStartCommandPolicy.requiresForeground(it)) }
    }

    @Test
    fun idleServiceDoesNotStayAlive() {
        assertTrue(RunStartCommandPolicy.shouldStayAlive(true))
        assertFalse(RunStartCommandPolicy.shouldStayAlive(false))
    }
}
