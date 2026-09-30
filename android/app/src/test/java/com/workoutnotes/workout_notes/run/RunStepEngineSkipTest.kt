package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RunStepEngineSkipTest {
    private fun session() = listOf(
        RunWorkoutStepNative(RunStepRole.warmup, RunIntervalMetric.distance, 1000),
        RunWorkoutStepNative(RunStepRole.work, RunIntervalMetric.distance, 400, 1, 2),
        RunWorkoutStepNative(RunStepRole.recovery, RunIntervalMetric.time, 90, 1, 2),
        RunWorkoutStepNative(RunStepRole.cooldown, RunIntervalMetric.distance, 500),
    )

    @Test
    fun skipMovesToNextStepAndKeepsPartialResult() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(session())
        engine.start()
        engine.tick(recording = true, distanceMeters = 300.0, movingTimeSeconds = 90)

        val events = engine.skip()

        assertEquals(
            listOf(RunStepEventKind.stepCompleted, RunStepEventKind.stepStarted),
            events.map { it.kind },
        )
        assertEquals(RunStepRole.work, events.last().role)
        assertEquals(1, engine.snapshot.stepIndex)
        assertEquals(1, engine.results.size)
        assertEquals(300.0, engine.results[0].distanceMeters, 0.001)
        assertEquals(90, engine.results[0].durationSeconds)
    }

    @Test
    fun skippingTheLastStepCompletesTheWorkout() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(RunWorkoutStepNative(RunStepRole.steady, RunIntervalMetric.distance, 5000)))
        engine.start()
        val events = engine.skip()
        assertTrue(events.any { it.kind == RunStepEventKind.workoutCompleted })
        assertTrue(engine.snapshot.isDone)
        assertTrue(engine.skip().isEmpty())
    }

    @Test
    fun skipDoesNothingBeforeStart() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(session())
        assertTrue(engine.skip().isEmpty())
    }

    @Test
    fun snapshotExposesTheNextStep() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(session())
        engine.start()
        var map = engine.snapshotMap()
        assertEquals("work", map["nextRole"])
        assertEquals(400, map["nextTarget"])
        assertEquals("distance", map["nextMetric"])
        assertEquals(1, map["nextRepIndex"])
        assertEquals(2, map["nextRepTotal"])

        engine.skip() // work 1/2
        map = engine.snapshotMap()
        assertEquals("recovery", map["nextRole"])
        assertEquals("time", map["nextMetric"])
        assertEquals(90, map["nextTarget"])

        engine.skip(); engine.skip(); engine.skip() // recovery, work 2, recovery 2 -> cooldown
        engine.skip()
        assertNull(engine.snapshotMap()["nextRole"])
    }

    @Test
    fun intervalEngineSkipAdvancesThePhase() {
        val engine = RunIntervalEngineNative()
        engine.configure(RunIntervalPreset(repeats = 2))
        engine.start()
        assertEquals(RunIntervalPhase.work, engine.snapshot.phase)
        val toRest = engine.skip()
        assertEquals(RunIntervalEventKind.restStarted, toRest.first().kind)
        assertEquals(RunIntervalPhase.rest, engine.snapshot.phase)
        val toWork = engine.skip()
        assertEquals(RunIntervalEventKind.workStarted, toWork.first().kind)
        assertEquals(2, engine.snapshot.workIndex)
        engine.skip() // work 2 -> done (last rep has no rest)
        assertEquals(RunIntervalPhase.done, engine.snapshot.phase)
        assertTrue(engine.skip().isEmpty())
    }
}
