package com.workoutnotes.workout_notes.sleep

import kotlin.math.PI
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BreathingAnalyzerTest {
    @Test
    fun detectsRegularBreathingEnvelope() {
        val analyzer = BreathingAnalyzer()
        val seconds = 30
        val samples = ShortArray(16_000 * seconds) { index ->
            val t = index.toDouble()
            val envelope = 0.5 + 0.4 * sin(2.0 * PI * 0.25 * t / 16_000.0)
            (envelope * sin(2.0 * PI * 100.0 * t / 16_000.0) * Short.MAX_VALUE * 0.5)
                .toInt()
                .toShort()
        }
        analyzer.add(samples, samples.size)
        val (regularity, rate) = analyzer.snapshot()
        assertTrue("expected a regular envelope, got $regularity", regularity >= 0.5)
        assertEquals("expected ~0.25 Hz breathing rate", 0.25, rate, 0.05)
    }

    @Test
    fun silenceYieldsNoRate() {
        val analyzer = BreathingAnalyzer()
        val samples = ShortArray(16_000 * 5) // all zeros
        analyzer.add(samples, samples.size)
        val (regularity, rate) = analyzer.snapshot()
        assertEquals(0.0, regularity, 0.0)
        assertEquals(0.0, rate, 0.0)
    }

    @Test
    fun slowDriftIsNotReportedAsFastBreathing() {
        // A monotonic loudness ramp (fan spinning up, distant traffic) has a
        // high autocorrelation at the shortest lag but no periodic peak.
        val analyzer = BreathingAnalyzer()
        val seconds = 30
        val samples = ShortArray(16_000 * seconds) { index ->
            val t = index.toDouble()
            val envelope = 0.05 + 0.4 * t / (16_000.0 * seconds)
            (envelope * sin(2.0 * PI * 100.0 * t / 16_000.0) * Short.MAX_VALUE)
                .toInt()
                .toShort()
        }
        analyzer.add(samples, samples.size)
        val (regularity, rate) = analyzer.snapshot()
        assertEquals(0.0, regularity, 0.0)
        assertEquals(0.0, rate, 0.0)
    }

    @Test
    fun oneLoudEventDoesNotSwampPeriodicBreathing() {
        val analyzer = BreathingAnalyzer()
        val seconds = 30
        val samples = ShortArray(16_000 * seconds) { index ->
            val t = index.toDouble()
            val breathing = 0.02 * (1.2 + sin(2.0 * PI * 0.25 * t / 16_000.0))
            val bump = if (t / 16_000.0 in 14.0..14.5) 0.8 else 0.0
            ((breathing + bump) * sin(2.0 * PI * 100.0 * t / 16_000.0) * Short.MAX_VALUE)
                .toInt()
                .toShort()
        }
        analyzer.add(samples, samples.size)
        val (regularity, rate) = analyzer.snapshot()
        assertTrue("expected periodic envelope, got $regularity", regularity >= 0.45)
        assertEquals(0.25, rate, 0.05)
    }
}
