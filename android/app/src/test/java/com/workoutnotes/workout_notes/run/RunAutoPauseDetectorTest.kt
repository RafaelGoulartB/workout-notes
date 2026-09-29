package com.workoutnotes.workout_notes.run

import com.workoutnotes.workout_notes.run.RunAutoPauseDetector.Event
import java.util.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RunAutoPauseDetectorTest {
    private val baseLat = -23.5505
    private val baseLng = -46.6333
    private val metersPerDegree = 111_320.0

    /** Feeds one fix per second and returns the events with their second. */
    private class Feeder(val detector: RunAutoPauseDetector, val lat0: Double, val lng0: Double) {
        var t = 0L
        var northMeters = 0.0
        val events = mutableListOf<Pair<Long, Event>>()

        fun fix(speed: Double?, dNorth: Double = 0.0, jitter: Double = 0.0, accuracy: Float = 5f): Event {
            t += 1
            northMeters += dNorth
            val lat = lat0 + (northMeters + jitter) / 111_320.0
            val event = detector.onFix(t * 1000L, lat, lng0, speed, accuracy)
            if (event != Event.NONE) events += t to event
            return event
        }
    }

    private fun feeder() = Feeder(RunAutoPauseDetector(), baseLat, baseLng)

    @Test
    fun steadyRunningNeverPauses() {
        val f = feeder()
        repeat(120) { f.fix(speed = 3.0, dNorth = 3.0) }
        assertTrue(f.events.isEmpty())
        assertFalse(f.detector.paused)
    }

    @Test
    fun standingStillPausesAfterSixSeconds() {
        val f = feeder()
        repeat(20) { f.fix(speed = 3.0, dNorth = 3.0) }
        repeat(10) { f.fix(speed = 0.1) }
        assertEquals(1, f.events.size)
        assertEquals(Event.PAUSE, f.events[0].second)
        // 6 s of stillness measured from the first slow fix (t=21 -> t=27).
        assertEquals(27L, f.events[0].first)
        assertTrue(f.detector.paused)
    }

    @Test
    fun briefSlowdownDoesNotPause() {
        val f = feeder()
        repeat(10) { f.fix(speed = 3.0, dNorth = 3.0) }
        repeat(4) { f.fix(speed = 0.2) } // traffic light shorter than the delay
        repeat(10) { f.fix(speed = 3.0, dNorth = 3.0) }
        assertTrue(f.events.isEmpty())
    }

    @Test
    fun gpsJitterWithoutDopplerSpeedStillPauses() {
        val f = feeder()
        val random = Random(42)
        repeat(15) { f.fix(speed = null, dNorth = 3.0) }
        // Standing: position wanders +-1.5 m around a fixed spot.
        repeat(20) { f.fix(speed = null, jitter = (random.nextDouble() - 0.5) * 3.0) }
        assertEquals(listOf(Event.PAUSE), f.events.map { it.second })
    }

    @Test
    fun jitterWhilePausedDoesNotResume() {
        val f = feeder()
        val random = Random(7)
        repeat(10) { f.fix(speed = 0.0) }
        assertTrue(f.detector.paused)
        repeat(60) { f.fix(speed = null, jitter = (random.nextDouble() - 0.5) * 4.0) }
        assertEquals(listOf(Event.PAUSE), f.events.map { it.second })
    }

    @Test
    fun singleSpikeDoesNotResumeButSustainedMovementDoes() {
        val f = feeder()
        repeat(10) { f.fix(speed = 0.0) }
        assertTrue(f.detector.paused)
        f.fix(speed = 4.0) // one noisy fix
        f.fix(speed = 0.0)
        assertTrue(f.detector.paused)
        f.fix(speed = 2.5, dNorth = 2.5)
        f.fix(speed = 2.5, dNorth = 2.5)
        assertTrue(f.detector.paused)
        f.fix(speed = 2.5, dNorth = 2.5)
        assertFalse(f.detector.paused)
        assertEquals(listOf(Event.PAUSE, Event.RESUME), f.events.map { it.second })
    }

    @Test
    fun speedBetweenThresholdsKeepsCurrentState() {
        val f = feeder()
        repeat(10) { f.fix(speed = 0.0) }
        assertTrue(f.detector.paused)
        // Walking slowly (1.0 m/s) is above the pause threshold but below the
        // resume threshold: still paused.
        repeat(30) { f.fix(speed = 1.0, dNorth = 1.0) }
        assertTrue(f.detector.paused)

        val g = feeder()
        repeat(30) { g.fix(speed = 1.0, dNorth = 1.0) }
        assertFalse(g.detector.paused) // and a slow jog never pauses
    }

    @Test
    fun inaccurateFixesAreIgnored() {
        val f = feeder()
        repeat(20) { f.fix(speed = 0.0, accuracy = 80f) }
        assertTrue(f.events.isEmpty())
    }

    @Test
    fun resetForgetsPausedState() {
        val f = feeder()
        repeat(10) { f.fix(speed = 0.0) }
        assertTrue(f.detector.paused)
        f.detector.reset()
        assertFalse(f.detector.paused)
        val restored = RunAutoPauseDetector()
        restored.reset(startPaused = true)
        assertTrue(restored.paused)
    }

    @Test
    fun metersPerDegreeSanity() {
        // Guards the helper used above: 1.11 m north is ~1e-5 degrees.
        assertEquals(1e-5, 1.1132 / metersPerDegree, 1e-7)
    }
}
