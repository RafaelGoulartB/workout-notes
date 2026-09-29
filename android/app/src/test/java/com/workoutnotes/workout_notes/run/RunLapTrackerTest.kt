package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class RunLapTrackerTest {
    @Test
    fun marksLapsFromMovingTimeAndDistance() {
        val tracker = RunLapTracker()
        val first = tracker.mark(distanceMeters = 1_000.0, movingSeconds = 300)!!
        assertEquals(1, first["lap_index"])
        assertEquals(0.0, first["start_distance_meters"] as Double, 0.001)
        assertEquals(1_000.0, first["distance_meters"] as Double, 0.001)
        assertEquals(300, first["duration_seconds"])
        assertEquals(300.0, first["pace_sec_per_km"] as Double, 0.001)

        val second = tracker.mark(distanceMeters = 2_500.0, movingSeconds = 750)!!
        assertEquals(2, second["lap_index"])
        assertEquals(1_000.0, second["start_distance_meters"] as Double, 0.001)
        assertEquals(1_500.0, second["distance_meters"] as Double, 0.001)
        assertEquals(450, second["duration_seconds"])
        assertEquals(300.0, second["pace_sec_per_km"] as Double, 0.001)
        assertEquals(2, tracker.count)
    }

    @Test
    fun ignoresAccidentalDoubleTap() {
        val tracker = RunLapTracker()
        tracker.mark(500.0, 120)
        assertNull(tracker.mark(501.0, 121))
        assertEquals(1, tracker.count)
    }

    @Test
    fun currentLapTracksTheOpenLap() {
        val tracker = RunLapTracker()
        tracker.mark(1_000.0, 300)
        val current = tracker.current(1_400.0, 420)
        assertEquals(2, current["lap_index"])
        assertEquals(400.0, current["distance_meters"] as Double, 0.001)
        assertEquals(120, current["duration_seconds"])
        assertEquals(300.0, current["pace_sec_per_km"] as Double, 0.001)
    }

    @Test
    fun finalLapOnlyWhenLapsWereMarked() {
        val plain = RunLapTracker()
        assertNull(plain.closeFinal(5_000.0, 1_500))

        val tracker = RunLapTracker()
        tracker.mark(1_000.0, 300)
        val last = tracker.closeFinal(1_800.0, 540)
        assertNotNull(last)
        assertEquals(2, last!!["lap_index"])
        assertEquals(800.0, last["distance_meters"] as Double, 0.001)
        assertEquals(240, last["duration_seconds"])
        assertEquals(2, tracker.completedLaps().size)
        // Nothing left to close.
        assertNull(tracker.closeFinal(1_800.0, 540))
    }

    @Test
    fun restoreResumesTheOpenLap() {
        val tracker = RunLapTracker()
        tracker.restore(
            laps = listOf(mapOf("lap_index" to 1)),
            startDistanceMeters = 1_000.0,
            startMovingSeconds = 300,
        )
        val lap = tracker.mark(2_000.0, 600)!!
        assertEquals(2, lap["lap_index"])
        assertEquals(1_000.0, lap["distance_meters"] as Double, 0.001)
    }
}
