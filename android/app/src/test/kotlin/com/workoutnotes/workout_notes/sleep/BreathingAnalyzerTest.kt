package com.workoutnotes.workout_notes.sleep

import com.workoutnotes.workout_notes.sleep.SyntheticSleepAudio.night
import com.workoutnotes.workout_notes.sleep.SyntheticSleepAudio.rate
import com.workoutnotes.workout_notes.sleep.SyntheticSleepAudio.regularity
import com.workoutnotes.workout_notes.sleep.SyntheticSleepAudio.snapshots
import kotlin.math.ln
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BreathingAnalyzerTest {
    private fun assertBreath(rateHz: Double, seconds: Double = 60.0, sampleRate: Int = 16_000) {
        val results = snapshots(night(sampleRate, seconds, breathHz = rateHz), sampleRate)
        assertTrue(results.isNotEmpty())
        for (result in results) {
            assertTrue("regularity ${regularity(result)} at $rateHz Hz", regularity(result) >= 0.6)
            assertEquals("rate at $rateHz Hz", rateHz, rate(result), 0.02)
        }
    }

    @Test
    fun detectsBreathingBuriedInHissAndHum() = assertBreath(0.25)

    @Test
    fun resolvesSlowAndFastBreathing() {
        assertBreath(0.2)
        assertBreath(0.4)
    }

    @Test
    fun worksAtTheFortyFourKilohertzFallbackRate() = assertBreath(0.25, seconds = 40.0, sampleRate = 44_100)

    @Test
    fun hissAndHumAloneAreNotBreathing() {
        // Chance autocorrelation peaks stay well below the 0.45 Dart threshold.
        for (humHz in listOf(50.0, 60.0)) {
            val results = snapshots(night(16_000, 90.0, breathHz = null, humHz = humHz), 16_000)
            assertEquals(3, results.size)
            for (result in results) {
                assertTrue("regularity ${regularity(result)} with $humHz Hz hum", regularity(result) < 0.4)
            }
        }
    }

    @Test
    fun shallowBreathingStillReads() {
        val results = snapshots(night(16_000, 60.0, breathHz = 0.25, depth = 0.4), 16_000)
        assertTrue(regularity(results.last()) >= 0.5)
        assertEquals(0.25, rate(results.last()), 0.02)
    }

    @Test
    fun historySpansSnapshotsAndNeedsTwentySeconds() {
        val analyzer = BreathingAnalyzer()
        val period = analyzer.framePeriodSeconds
        assertEquals(0.125, period, 1e-9)
        fun feed(seconds: Double, offsetSeconds: Double = 0.0) {
            val frames = (seconds / period).toInt()
            for (i in 0 until frames) {
                val t = offsetSeconds + i * period
                analyzer.addFrame(1e-8 * (1.0 + 0.6 * kotlin.math.sin(2 * Math.PI * 0.25 * t)))
            }
        }
        feed(15.0)
        assertEquals(0.0 to 0.0, analyzer.snapshot())
        feed(15.0, 15.0)
        val first = analyzer.snapshot()
        assertEquals(0.25, first.second, 0.01)
        // The history is not cleared by a snapshot: a second one right away
        // still has the same data.
        assertEquals(first.second, analyzer.snapshot().second, 1e-9)
    }

    @Test
    fun silenceYieldsNoRate() {
        val analyzer = BreathingAnalyzer()
        repeat(30 * 8) { analyzer.addFrame(0.0) }
        assertEquals(0.0 to 0.0, analyzer.snapshot())
    }

    @Test
    fun silentFramesStillAdvanceTime() {
        // All-zero frames skip the FFT but must still reach the analyzer.
        val frames = mutableListOf<Double>()
        val spectral = SpectralAnalyzer(16_000) { frames += it }
        val silence = ShortArray(16_000 * 3)
        spectral.add(silence, silence.size)
        assertEquals(24, frames.size)
        assertTrue(frames.all { it == 0.0 })
    }

    @Test
    fun slowDriftIsNotReportedAsBreathing() {
        // A loudness ramp (fan spinning up, distant traffic) decays
        // monotonically in the autocorrelation and has no periodic peak.
        val analyzer = BreathingAnalyzer()
        val frames = 60 * 8
        for (i in 0 until frames) {
            analyzer.addFrame(1e-9 * (1.0 + 9.0 * i / frames))
        }
        val (regularity, rate) = analyzer.snapshot()
        assertEquals(0.0, regularity, 0.0)
        assertEquals(0.0, rate, 0.0)
    }

    @Test
    fun oneLoudEventDoesNotSwampPeriodicBreathing() {
        val analyzer = BreathingAnalyzer()
        val period = analyzer.framePeriodSeconds
        val frames = (60 / period).toInt()
        for (i in 0 until frames) {
            val t = i * period
            val breathing = 1e-9 * (1.2 + kotlin.math.sin(2 * Math.PI * 0.25 * t))
            val bump = if (t in 30.0..30.5) 1e-3 else 0.0
            analyzer.addFrame(breathing + bump)
        }
        val (regularity, rate) = analyzer.snapshot()
        assertTrue("expected periodic envelope, got $regularity", regularity >= 0.45)
        assertEquals(0.25, rate, 0.02)
        assertTrue(ln(1e-3 / 1e-9) > 10) // the bump really is a huge outlier
    }
}
