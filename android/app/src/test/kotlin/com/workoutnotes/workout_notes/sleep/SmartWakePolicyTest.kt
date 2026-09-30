package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartWakePolicyTest {
    private val deadline = 3_600_000L
    private val windowStart = deadline - 30 * 60_000L

    private fun decision(p: Double, valid: Boolean = true) =
        SleepWakeFilter.Decision("quiet_audio", valid, p, 0.0, 0.0)

    private fun SmartWakePolicy.feed(window: Int, p: Double, valid: Boolean = true) =
        onWindow(decision(p, valid), 30, (window + 1) * 30_000L, windowStart, deadline)

    @Test
    fun `does not ring before the night has seen sleep`() {
        val policy = SmartWakePolicy(0.5)
        for (window in 60 until 80) assertNull(policy.feed(window, 0.1))
        assertFalse(policy.isArmed)
    }

    @Test
    fun `rings inside the window at the first restless moment`() {
        val policy = SmartWakePolicy(0.5)
        for (window in 0 until 20) assertNull(policy.feed(window, 0.95))
        assertTrue(policy.isArmed)
        // Before the window a restless moment is only remembered sleep.
        assertNull(policy.feed(30, 0.2))
        assertNull(policy.feed(90, 0.8))
        assertNull(policy.feed(91, 0.4, valid = false))
        assertEquals(SmartWakePolicy.TRIGGER_STIRRING, policy.feed(92, 0.4))
        assertEquals(SmartWakePolicy.TRIGGER_AWAKE, policy.feed(93, 0.2))
    }

    @Test
    fun `never rings at or after the deadline`() {
        val policy = SmartWakePolicy(0.7)
        for (window in 0 until 20) policy.feed(window, 0.95)
        assertNull(policy.feed(119, 0.1))
        assertNull(policy.feed(200, 0.1))
    }
}
