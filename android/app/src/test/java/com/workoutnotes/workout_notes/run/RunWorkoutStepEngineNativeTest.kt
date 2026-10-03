package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Behaviour of the structured-session engine. Its repeat expansion must match
 * `RunPlanWorkout.expand` in Dart (test/run_workout_steps_test.dart) — a
 * divergence would show one plan on screen and cue another through the
 * headphones.
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
    fun emitsOneMinuteCueOnLongTimeSteps() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.steady, 300, RunIntervalMetric.time)))
        engine.start()
        assertTrue(engine.tick(true, 500.0, 200).isEmpty())
        val events = engine.tick(true, 800.0, 245)
        assertEquals(listOf(RunStepEventKind.timeRemainingCue), events.map { it.kind })
        assertEquals(60, events[0].remainingSeconds)
        assertTrue(engine.tick(true, 820.0, 250).isEmpty())
    }

    @Test
    fun timedStepsCountDownTheirLastThreeSeconds() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.work, 30, RunIntervalMetric.time), step(RunStepRole.recovery, 60, RunIntervalMetric.time)))
        engine.start()
        val ticks = (1..30).map { second -> engine.tick(true, second * 4.0, second) }
        val countdown = ticks.flatten().filter { it.kind == RunStepEventKind.countdown }
        assertEquals(listOf(3, 2, 1), countdown.map { it.remainingSeconds })
        // The last tick both completes the step and starts the next one.
        assertEquals(RunStepEventKind.stepStarted, ticks.last().last().kind)
    }

    @Test
    fun longEffortsGetAHalfwayCall() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.steady, 2000)))
        engine.start()
        assertTrue(engine.tick(true, 900.0, 270).none { it.kind == RunStepEventKind.halfway })
        assertEquals(1, engine.tick(true, 1000.0, 300).count { it.kind == RunStepEventKind.halfway })
        assertTrue(engine.tick(true, 1100.0, 330).none { it.kind == RunStepEventKind.halfway })
    }

    /** Ticks once per second at [pace] from [from] to [to]. */
    private fun RunWorkoutStepEngineNative.runAt(
        pace: Double,
        from: Int,
        to: Int,
        startMeters: Double,
    ): Pair<Double, List<RunStepEventNative>> {
        var meters = startMeters
        val events = mutableListOf<RunStepEventNative>()
        for (second in from + 1..to) {
            meters += 1000.0 / pace
            events.addAll(tick(true, meters, second))
        }
        return meters to events
    }

    @Test
    fun paceWarningUsesARollingWindowAndReArms() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.steady, 1200, RunIntervalMetric.time, paceMin = 290.0, paceMax = 310.0)))
        engine.start()
        var (meters, events) = engine.runAt(340.0, 0, 120, 0.0)
        val slow = events.filter { it.kind == RunStepEventKind.paceTooSlow }
        assertEquals(1, slow.size)
        assertEquals(340.0, slow.single().paceSecPerKm!!, 5.0)

        val back = engine.runAt(300.0, 120, 160, meters)
        meters = back.first
        assertEquals(1, back.second.count { it.kind == RunStepEventKind.paceBackInRange })

        val again = engine.runAt(340.0, 160, 300, meters)
        assertEquals(1, again.second.count { it.kind == RunStepEventKind.paceTooSlow })
    }

    @Test
    fun noPaceWarningDuringTheAccelerationOfARep() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.work, 400, repeatGroup = 1, repeatCount = 4, paceMin = 230.0, paceMax = 250.0)))
        engine.start()
        // A slow first 20 s, then on pace: the window forgets the start.
        val (meters, start) = engine.runAt(400.0, 0, 20, 0.0)
        val (_, rest) = engine.runAt(240.0, 20, 95, meters)
        assertTrue((start + rest).none { it.kind == RunStepEventKind.paceTooSlow })
    }

    @Test
    fun easyEffortStepsOnlyWarnWhenTooFast() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.steady, 6000, paceMin = 330.0, paceMax = 360.0)), easyEffort = true)
        engine.start()
        val (meters, slow) = engine.runAt(450.0, 0, 300, 0.0)
        assertTrue(slow.none { it.kind == RunStepEventKind.paceTooSlow })
        val (_, fast) = engine.runAt(290.0, 300, 400, meters)
        assertEquals(1, fast.count { it.kind == RunStepEventKind.paceTooFast })
    }

    @Test
    fun completedStepCarriesWhatWasRun() {
        val engine = RunWorkoutStepEngineNative()
        engine.configure(listOf(step(RunStepRole.work, 400), step(RunStepRole.cooldown, 400)))
        engine.start()
        val events = engine.tick(true, 400.0, 92)
        val done = events.first { it.kind == RunStepEventKind.stepCompleted }
        assertEquals(92, done.stepDurationSeconds)
        assertEquals(400.0, done.stepDistanceMeters!!, 0.001)
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
    fun executionSnapshotResumesCurrentStepAndCompletedResults() {
        val plan = listOf(
            step(RunStepRole.warmup, 1000),
            step(RunStepRole.work, 400, repeatGroup = 1, repeatCount = 2),
            step(RunStepRole.recovery, 60, RunIntervalMetric.time, repeatGroup = 1, repeatCount = 2),
        )
        val original = RunWorkoutStepEngineNative()
        original.configure(plan)
        original.start()
        original.tick(true, 1000.0, 300)
        original.tick(true, 1200.0, 350)

        val restored = RunWorkoutStepEngineNative()
        restored.configure(plan)
        assertTrue(restored.restoreStateJson(original.stateJson()))

        assertEquals(RunStepRole.work, restored.snapshot.role)
        assertEquals(0.5, restored.snapshot.progress, 0.001)
        assertEquals(1, restored.results.size)
        assertEquals(1000.0, restored.results.first().distanceMeters, 0.001)

        restored.tick(true, 1400.0, 400)
        assertEquals(RunStepRole.recovery, restored.snapshot.role)
        assertEquals(2, restored.results.size)
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
