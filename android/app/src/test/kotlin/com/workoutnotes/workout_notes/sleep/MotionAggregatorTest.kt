package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class MotionAggregatorTest {
    @Test
    fun staysUnavailableWhenNoSensorExists() {
        val aggregator = MotionAggregator(null)
        aggregator.register()
        assertFalse(aggregator.available)
        assertEquals(emptyMap<String, Double>(), aggregator.snapshotAndReset())
        aggregator.unregister()
    }
}
