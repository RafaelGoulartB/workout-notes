package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirror of test/run_workout_step_engine_test.dart. The Dart and Kotlin engines
 * must produce the same sequence for the same steps — a divergence would make
 * the app cue one thing on screen and another through the headphones.
 */
class RunWorkoutStepEngineNativeTest {

    private fun step(
        role: RunStepRole,
        value: Int,
        metric: RunIntervalMetric = RunIntervalMetric.distance,
        repeatGroup: Int? = null,
        repeatCount: Int = 1,
        paceMin: Double? = null,
        paceMax: Double? = null,
    ) = RunWorkoutStepNative(role, metric, value, repeatGroup, repeatCount, paceMin, paceMax)

    /** 2 km warmup + 6×(800 m / 2 min) + 1 km cooldown. */
    private fun intervalSession() = listOf(
        step(RunStepRole.warmup, 2000),
        step(RunStepRole.work, 800, repeatGroup = 1, repeatCount = 6, paceMin = 230.0, paceMax = 245.0),
        step(RunStepRole.recovery, 120, RunIntervalMetric.time, repeatGroup = 1, repeatCount = 6),
        step(RunStepRole.cooldown, 1000),
    )

    @Test
    fun expandsRepeatBlocks() {
        val expanded = RunWorkoutStepEngineNative.expand(intervalSession())
        assertEquals(14, expanded.size)
        assertEquals(RunStepRole.warmup, expanded.first().step.role)
        assertEquals(RunStepRole.cooldown, expanded.last().step.role)
        assertEquals(1, expanded[1].repIndex)
        assertEquals(2, expanded[3].repIndex)
        assertEquals(6, expanded[11].repIndex)
        assertEquals(6, expanded[1].repTotal)
        assertEquals(6, expanded.count { it.step.role == RunStepRole.work })
    }

    @Test
    fun stepsWithoutRepeatGroupRunOnce() {
        val expanded = RunWorkoutStepEngineNative.expand(
            listOf(step(RunStepRole.warmup, 1000), step(RunStepRole.steady, 5000)),
        )
        assertEquals(2, expanded.size)
    }

    @Test
    fun distinctRepeatGroupsExpandIndependently() {
        val expanded = RunWorkoutStepEngineNative.expand(
            listOf(
                step(RunStepRole.work, 400, repeatGroup = 1, repeatCount = 4),
                step(RunStepRole.work, 200, repeatGroup = 2, repeatCount = 3),
            ),
        )
        assertEquals(7, expanded.size)
    }

    @Test
    fun walksDistanceOnlySession() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(
            listOf(
                step(RunStepRole.warmup, 1000),
                step(RunStepRole.work, 400),
                step(RunStepRole.cooldown, 500),
            ),
        )
        val start = engine.start()
        assertEquals(1, start.size)
        assertEquals(RunStepEventKind.stepStarted, start[0].kind)
        assertEquals(RunStepRole.warmup, engine.snapshot.role)

        var events = engine.tick(true, 500.0, 150)
        assertTrue(events.isEmpty())
        assertEquals(0.5, engine.snapshot.progress, 0.001)

        events = engine.tick(true, 1000.0, 300)
        assertEquals(
            listOf(RunStepEventKind.stepCompleted, RunStepEventKind.stepStarted),
            events.map { it.kind },
        )
        assertEquals(RunStepRole.work, engine.snapshot.role)

        engine.tick(true, 1400.0, 390)
        assertEquals(RunStepRole.cooldown, engine.snapshot.role)

        events = engine.tick(true, 1900.0, 540)
        assertEquals(RunStepEventKind.workoutCompleted, events.last().kind)
        assertTrue(engine.snapshot.isDone)
        assertEquals(3, engine.results.size)
    }

    @Test
    fun mixesDistanceWorkWithTimeRecovery() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(
            listOf(
                step(RunStepRole.work, 400, repeatGroup = 1, repeatCount = 2),
                step(RunStepRole.recovery, 60, RunIntervalMetric.time, repeatGroup = 1, repeatCount = 2),
            ),
        )
        engine.start()

        engine.tick(true, 400.0, 90)
        assertEquals(RunStepRole.recovery, engine.snapshot.role)
        assertEquals(RunIntervalMetric.time, engine.snapshot.metric)

        // Distance keeps moving during recovery but must not advance a time step.
        engine.tick(true, 500.0, 120)
        assertEquals(RunStepRole.recovery, engine.snapshot.role)
        engine.tick(true, 560.0, 150)
        assertEquals(RunStepRole.work, engine.snapshot.role)
        assertEquals(2, engine.snapshot.repIndex)
    }

    @Test
    fun emitsThirtySecondCueOnLongTimeSteps() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.steady, 300, RunIntervalMetric.time)))
        engine.start()
        assertTrue(engine.tick(true, 500.0, 200).isEmpty())
        val events = engine.tick(true, 800.0, 280)
        assertEquals(1, events.size)
        assertEquals(RunStepEventKind.timeRemainingCue, events[0].kind)
        assertEquals(30, events[0].remainingSeconds)
        assertTrue(engine.tick(true, 820.0, 285).isEmpty())
    }

    @Test
    fun warnsOnceWhenSlowerThanTargetPace() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.work, 1000, paceMin = 230.0, paceMax = 250.0)))
        engine.start()
        // 200 m in 60 s → 300 s/km, slower than the 250 s/km ceiling.
        val events = engine.tick(true, 200.0, 60)
        assertEquals(1, events.size)
        assertEquals(RunStepEventKind.paceTooSlow, events[0].kind)
        assertEquals(300.0, events[0].paceSecPerKm!!, 1.0)
        assertTrue(engine.tick(true, 260.0, 80).none { it.kind == RunStepEventKind.paceTooSlow })
    }

    @Test
    fun doesNotAdvanceWhilePaused() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.work, 400)))
        engine.start()
        assertTrue(engine.tick(false, 500.0, 120).isEmpty())
        assertTrue(engine.snapshot.isActive)
        engine.tick(true, 600.0, 140)
        assertEquals(100.0 / 400.0, engine.snapshot.progress, 0.001)
    }

    @Test
    fun countsEffortRepsAsTheyComplete() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.work, 400, repeatGroup = 1, repeatCount = 3)))
        engine.start()
        assertEquals(3, engine.workRepsTotal)
        assertEquals(0, engine.snapshot.workRepsDone)
        engine.tick(true, 400.0, 90)
        assertEquals(1, engine.snapshot.workRepsDone)
        engine.tick(true, 800.0, 180)
        assertEquals(2, engine.snapshot.workRepsDone)
    }

    @Test
    fun finishClosesPartialStep() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.work, 5000)))
        engine.start()
        engine.tick(true, 1200.0, 300)
        engine.finish()
        assertEquals(1, engine.results.size)
        assertEquals(1200.0, engine.results[0].distanceMeters, 0.001)
        assertEquals(250.0, engine.results[0].actualPaceSecPerKm!!, 1.0)
    }

    @Test
    fun emptySessionCompletesImmediately() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(emptyList())
        assertTrue(engine.start().isEmpty())
        assertTrue(engine.snapshot.isDone)
        assertTrue(!engine.hasPlan)
    }

    @Test
    fun zeroValueStepsAreDropped() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.warmup, 0), step(RunStepRole.work, 400)))
        assertEquals(1, engine.totalSteps)
    }

    @Test
    fun planSurvivesSpoolRoundTrip() {
        val original = intervalSession()
        val raw = RunWorkoutStepNative.listToJsonString(original)
        val restored = RunWorkoutStepNative.listFromJsonString(raw)

        assertEquals(original.size, restored.size)
        assertEquals(original, restored)
        // Restoring into an engine yields the same expanded sequence.
        assertEquals(
            RunWorkoutStepEngineNative.expand(original).size,
            RunWorkoutStepEngineNative.expand(restored).size,
        )
    }

    @Test
    fun parsesPlanComingFromTheMethodChannel() {
        val raw = listOf(
            mapOf(
                "role" to "warmup",
                "metric" to "distance",
                "value" to 2000,
                "repeatGroup" to null,
                "repeatCount" to 1,
            ),
            mapOf(
                "role" to "work",
                "metric" to "distance",
                "value" to 800,
                "repeatGroup" to 1,
                "repeatCount" to 6,
                "targetPaceMinSecPerKm" to 230.0,
            ),
            // Dropped: a zero-length step is not executable.
            mapOf("role" to "work", "metric" to "distance", "value" to 0),
        )
        val parsed = RunWorkoutStepNative.listFromAny(raw)
        assertEquals(2, parsed.size)
        assertEquals(RunStepRole.warmup, parsed[0].role)
        assertEquals(6, parsed[1].repeatCount)
        assertNotNull(parsed[1].targetPaceMinSecPerKm)
        assertNull(parsed[0].targetPaceMinSecPerKm)
    }

    @Test
    fun malformedPlanFallsBackToEmpty() {
        assertTrue(RunWorkoutStepNative.listFromJsonString("not json").isEmpty())
        assertTrue(RunWorkoutStepNative.listFromAny(null).isEmpty())
        assertTrue(RunWorkoutStepNative.listFromAny(42).isEmpty())
    }
}
