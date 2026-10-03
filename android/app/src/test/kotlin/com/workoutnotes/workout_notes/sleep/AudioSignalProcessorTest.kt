package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioSignalProcessorTest {
    @Test
    fun calculatesRmsAndDbfs() {
        val samples = shortArrayOf(0, 16_383, -16_383, 16_383)
        val rms = AudioSignalProcessor.rms(samples)
        assertEquals(-7.27, AudioSignalProcessor.dbfs(rms), 0.15)
    }

    @Test
    fun classifiesInvalidAndRelativeNoise() {
        assertEquals("invalid", AudioSignalProcessor.classify(0.49, 20.0))
        assertEquals("quiet", AudioSignalProcessor.classify(1.0, 9.9))
        assertEquals("noise", AudioSignalProcessor.classify(1.0, 10.0))
    }

    @Test
    fun usesThirtySecondWindowsAndBoundedReadRetries() {
        assertEquals(30, AudioSignalProcessor.WINDOW_SECONDS)
        assertTrue(AudioSignalProcessor.MAX_CONSECUTIVE_READ_ERRORS <= 3)
        assertTrue(AudioSignalProcessor.NO_DATA_TIMEOUT_MILLIS <= 5_000)
    }

    // One block is 125 ms; a deterministic +-1 dB jitter around [level].
    private val jitter = java.util.Random(11)

    private fun AdaptiveNoiseBaseline.feed(seconds: Double, level: Double) {
        repeat((seconds * 8).toInt()) { observe(level + (jitter.nextDouble() * 2.0 - 1.0)) }
    }

    @Test
    fun calibratesAgainstDeviceNoiseFloorInsteadOfFixedDbfs() {
        val baseline = AdaptiveNoiseBaseline(calibrationBlocks = 4)
        listOf(-30.0, -31.0, -29.0, -5.0).forEach(baseline::observe)

        assertTrue(baseline.isCalibrated)
        assertEquals(-31.0, baseline.value, 0.5)
        assertEquals("quiet", AudioSignalProcessor.classify(1.0, baseline.noiseScore(-30.0)))
        assertEquals("noise", AudioSignalProcessor.classify(1.0, baseline.noiseScore(-20.0)))
    }

    @Test
    fun baselineNeedsTenSecondsAndIgnoresDigitalSilence() {
        val baseline = AdaptiveNoiseBaseline()
        repeat(1_000) { baseline.observe(-120.0) }
        assertFalse(baseline.isCalibrated)
        repeat(79) { baseline.observe(-78.0) }
        assertFalse(baseline.isCalibrated)
        assertEquals(-55.0, baseline.value, 0.0)
        assertEquals(0.0, baseline.noiseScore(-10.0), 0.0)
        baseline.observe(-78.0)
        assertTrue(baseline.isCalibrated)
        assertEquals(-78.0, baseline.value, 0.5)
        assertEquals(30.0, baseline.noiseScore(-48.0), 0.5)
    }

    @Test
    fun shortLoudBurstDoesNotMoveTheBaseline() {
        val baseline = AdaptiveNoiseBaseline()
        baseline.feed(120.0, -78.0)
        var worst = 0.0
        repeat(80) {
            baseline.observe(-48.0)
            worst = maxOf(worst, baseline.value + 78.0)
        }
        for (block in 0 until 8 * 120) {
            baseline.observe(-78.0 + (jitter.nextDouble() * 2.0 - 1.0))
            worst = maxOf(worst, baseline.value + 78.0)
        }
        assertTrue("baseline moved by $worst dB", worst < 1.0)
    }

    @Test
    fun talkingWithNearFloorPausesKeepsTheFloor() {
        val baseline = AdaptiveNoiseBaseline()
        baseline.feed(60.0, -78.0)
        var worst = 0.0
        repeat(120) { // 5 min of 1 s pause / 1.5 s speech
            baseline.feed(1.0, -78.0)
            repeat(12) { baseline.observe(-60.0 + jitter.nextDouble() * 12.0) }
            worst = maxOf(worst, baseline.value + 78.0)
        }
        assertTrue("baseline moved by $worst dB", worst < 1.5)
    }

    @Test
    fun quietDipDoesNotInstantlyDragTheBaselineDown() {
        val baseline = AdaptiveNoiseBaseline()
        baseline.feed(300.0, -70.0)
        val before = baseline.value
        baseline.feed(10.0, -90.0)
        assertTrue("baseline fell to ${baseline.value}", baseline.value > before - 1.0)
    }

    @Test
    fun sustainedStepIsAbsorbedWithinFiveMinutes() {
        val baseline = AdaptiveNoiseBaseline()
        baseline.feed(300.0, -78.0)
        // A fan turns on: +10 dB. It first reads as activity...
        baseline.feed(60.0, -68.0)
        assertTrue(baseline.noiseScore(-68.0) > 8.0)
        // ...and is part of the room within ~5 minutes of the step.
        baseline.feed(240.0, -68.0)
        assertTrue("noiseScore ${baseline.noiseScore(-68.0)}", baseline.noiseScore(-68.0) < 3.0)
        // The fan stopping is followed within a minute.
        baseline.feed(60.0, -78.0)
        assertEquals(-78.0, baseline.value, 1.5)
    }
}
