package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RunGeoMathTest {
    @Test
    fun haversine_knownShortDistance() {
        // ~111 meters north of equator at lng 0
        val meters = RunGeoMath.haversineMeters(0.0, 0.0, 0.001, 0.0)
        assertTrue(meters in 100.0..130.0)
    }

    @Test
    fun pace_and_calories() {
        val pace = RunGeoMath.paceSecPerKm(5000.0, 1500)
        assertEquals(300.0, pace!!, 0.01)
        assertEquals(350, RunGeoMath.estimateCalories(5000.0))
    }

    @Test
    fun shouldAcceptPoint_filtersJitterAndBadAccuracy() {
        assertFalse(RunGeoMath.shouldAcceptPoint(50f, 10.0, timeDeltaSeconds = 2.0))
        assertFalse(RunGeoMath.shouldAcceptPoint(10f, 1.0, timeDeltaSeconds = 2.0))
        assertTrue(RunGeoMath.shouldAcceptPoint(10f, 5.0, timeDeltaSeconds = 2.0))
    }

    @Test
    fun shouldAcceptPoint_rejectsNullAccuracy() {
        assertFalse(RunGeoMath.shouldAcceptPoint(null, 10.0, timeDeltaSeconds = 2.0))
    }

    @Test
    fun shouldAcceptPoint_rejectsTeleportSpeed() {
        // 80 m in 1 s ≈ 288 km/h
        assertFalse(RunGeoMath.shouldAcceptPoint(10f, 80.0, timeDeltaSeconds = 1.0))
        // 20 m in 4 s = 5 m/s ≈ 18 km/h — plausible jogging
        assertTrue(RunGeoMath.shouldAcceptPoint(10f, 20.0, timeDeltaSeconds = 4.0))
    }
}
