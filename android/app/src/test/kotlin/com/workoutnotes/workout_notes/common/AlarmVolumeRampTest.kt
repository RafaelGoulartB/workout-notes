package com.workoutnotes.workout_notes.common

import kotlin.math.log10
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlarmVolumeRampTest {
    private fun db(gain: Float) = 20 * log10(gain.toDouble())

    @Test
    fun `rise is linear in decibels from -30 dB to full volume`() {
        val ramp = AlarmVolumeRamp(120_000L, boostToMax = true)
        assertEquals(-30.0, db(ramp.gainAt(0L)), 0.01)
        assertEquals(-15.0, db(ramp.gainAt(60_000L)), 0.01)
        assertEquals(-7.5, db(ramp.gainAt(90_000L)), 0.01)
        assertEquals(1f, ramp.gainAt(120_000L), 0f)
        assertEquals(1f, ramp.gainAt(500_000L), 0f)
        var previous = 0f
        for (t in 0L..120_000L step 200L) {
            val gain = ramp.gainAt(t)
            assertTrue("gain must never drop at $t", gain >= previous)
            previous = gain
        }
    }

    @Test
    fun `vibration joins halfway and no ramp rings at once`() {
        assertEquals(60_000L, AlarmVolumeRamp(120_000L, false).vibrationDelayMillis)
        assertFalse(AlarmVolumeRamp.NONE.isGradual)
        assertEquals(1f, AlarmVolumeRamp.NONE.gainAt(0L), 0f)
    }

    @Test
    fun `a snoozed ring rises briefly and keeps the boost`() {
        val snooze = AlarmVolumeRamp(180_000L, boostToMax = true).forSnooze()
        assertEquals(AlarmVolumeRamp.SNOOZE_RAMP_MILLIS, snooze.rampMillis)
        assertTrue(snooze.boostToMax)
        assertEquals(10_000L, AlarmVolumeRamp(10_000L, false).forSnooze().rampMillis)
        assertEquals(AlarmVolumeRamp.NONE, AlarmVolumeRamp.NONE.forSnooze())
    }
}
