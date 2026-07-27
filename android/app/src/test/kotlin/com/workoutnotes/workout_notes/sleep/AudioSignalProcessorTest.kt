package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioSignalProcessorTest {
    @Test
    fun calculatesRmsAndDbfs() {
        val samples = shortArrayOf(0, 16_383, -16_383, 16_383)
        val rms = AudioSignalProcessor.rms(samples)
        assertEquals(-7.27, AudioSignalProcessor.dbfs(rms), 0.15)
        assertEquals(-6.02, AudioSignalProcessor.peakDbfs(samples), 0.15)
    }

    @Test
    fun classifiesInvalidAndRelativeNoise() {
        assertEquals("invalid", AudioSignalProcessor.classify(0.49, 20.0))
        assertEquals("quiet", AudioSignalProcessor.classify(1.0, 9.9))
        assertEquals("noise", AudioSignalProcessor.classify(1.0, 10.0))
    }

    @Test
    fun aggregatesThirtySecondWindowsAndGroupsEvents() {
        assertEquals(30, AudioSignalProcessor.WINDOW_SECONDS)
        assertEquals(
            2,
            AudioSignalProcessor.countEvents(
                listOf("quiet", "noise", "noise", "quiet", "noise"),
            ),
        )
        assertTrue(AudioSignalProcessor.MAX_SESSION_SECONDS >= 16 * 60 * 60)
        assertTrue(AudioSignalProcessor.MAX_CONSECUTIVE_READ_ERRORS <= 3)
        assertTrue(AudioSignalProcessor.NO_DATA_TIMEOUT_MILLIS <= 5_000)
    }

    @Test
    fun calibratesAgainstDeviceNoiseFloorInsteadOfFixedDbfs() {
        val baseline = AdaptiveNoiseBaseline(calibrationSampleCount = 4)
        listOf(-30.0, -31.0, -29.0, -5.0).forEach(baseline::observe)

        assertTrue(baseline.isCalibrated)
        assertEquals(-31.0, baseline.value, 0.01)
        assertEquals("quiet", AudioSignalProcessor.classify(1.0, baseline.noiseScore(-30.0)))
        assertEquals("noise", AudioSignalProcessor.classify(1.0, baseline.noiseScore(-20.0)))
    }
}
