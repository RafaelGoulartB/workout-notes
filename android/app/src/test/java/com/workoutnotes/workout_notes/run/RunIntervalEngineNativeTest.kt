package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RunIntervalEngineNativeTest {

    private fun kinds(events: List<RunIntervalEvent>) = events.map { it.kind }

    @Test
    fun distanceWorkThenTimeRestThenNextWork() {
        val engine = RunIntervalEngineNative(
            RunIntervalPreset(
                workMetric = RunIntervalMetric.distance,
                workValue = 400,
                restMetric = RunIntervalMetric.time,
                restValue = 60,
                repeats = 2,
            ),
        )
        assertEquals(listOf(RunIntervalEventKind.workStarted), kinds(engine.start()))
        assertEquals(1, engine.snapshot.workIndex)

        assertTrue(engine.tick(true, 200.0, 60).isEmpty())
        assertEquals(0.5, engine.snapshot.progress, 1e-6)

        assertEquals(listOf(RunIntervalEventKind.restStarted), kinds(engine.tick(true, 400.0, 120)))
        assertEquals(RunIntervalPhase.rest, engine.snapshot.phase)

        // Rest runs on time, not distance; a 60 s rest gets a 10 s heads-up.
        val restEnd = engine.tick(true, 420.0, 172)
        assertEquals(listOf(RunIntervalEventKind.timeRemainingCue), kinds(restEnd))
        assertEquals(10, restEnd.single().remainingSeconds)
        assertEquals(listOf(RunIntervalEventKind.workStarted), kinds(engine.tick(true, 430.0, 180)))
        assertEquals(2, engine.snapshot.workIndex)
    }

    @Test
    fun lastWorkSkipsTheTrailingRestAndCompletes() {
        val engine = RunIntervalEngineNative(
            RunIntervalPreset(RunIntervalMetric.distance, 400, RunIntervalMetric.time, 60, 1),
        )
        engine.start()
        assertEquals(listOf(RunIntervalEventKind.completed), kinds(engine.tick(true, 400.0, 100)))
        assertEquals(RunIntervalPhase.done, engine.snapshot.phase)
        assertEquals(1.0, engine.snapshot.progress, 1e-6)
    }

    @Test
    fun zeroRestJumpsStraightToTheNextWork() {
        val engine = RunIntervalEngineNative(
            RunIntervalPreset(RunIntervalMetric.distance, 200, RunIntervalMetric.time, 0, 2),
        )
        engine.start()
        assertEquals(listOf(RunIntervalEventKind.workStarted), kinds(engine.tick(true, 200.0, 50)))
        assertEquals(RunIntervalPhase.work, engine.snapshot.phase)
        assertEquals(2, engine.snapshot.workIndex)
    }

    @Test
    fun shortTimePhasesGetATenSecondHeadsUp() {
        val engine = RunIntervalEngineNative(
            RunIntervalPreset(RunIntervalMetric.time, 60, RunIntervalMetric.time, 30, 2),
        )
        engine.start()
        assertTrue(engine.tick(true, 100.0, 40).isEmpty())
        val cue = engine.tick(true, 140.0, 50)
        assertEquals(listOf(RunIntervalEventKind.timeRemainingCue), kinds(cue))
        assertEquals(10, cue.single().remainingSeconds)
    }

    @Test
    fun doesNotAdvanceWhileNotRecording() {
        val engine = RunIntervalEngineNative(
            RunIntervalPreset(RunIntervalMetric.distance, 400, RunIntervalMetric.time, 60, 2),
        )
        engine.start()
        assertTrue(engine.tick(false, 500.0, 100).isEmpty())
        assertEquals(RunIntervalPhase.work, engine.snapshot.phase)
    }

    @Test
    fun snapshotPreviewsWhatFollows() {
        val engine = RunIntervalEngineNative(
            RunIntervalPreset(RunIntervalMetric.distance, 400, RunIntervalMetric.time, 90, 2),
        )
        engine.start()
        var snap = engine.snapshot
        assertEquals(RunIntervalPhase.rest, snap.nextPhase)
        assertEquals(RunIntervalMetric.time, snap.nextMetric)
        assertEquals(90, snap.nextTarget)

        engine.skip()
        snap = engine.snapshot
        assertEquals(RunIntervalPhase.work, snap.nextPhase)
        assertEquals(RunIntervalMetric.distance, snap.nextMetric)
        assertEquals(400, snap.nextTarget)

        engine.skip() // second work
        engine.skip() // last work has no trailing rest -> done
        assertEquals(RunIntervalPhase.done, engine.snapshot.phase)
        assertNull(engine.snapshot.nextPhase)
    }

    @Test
    fun snapshotMapUsesTheWireNamesDartReads() {
        val engine = RunIntervalEngineNative(
            RunIntervalPreset(RunIntervalMetric.distance, 400, RunIntervalMetric.time, 90, 3),
        )
        engine.start()
        val map = engine.snapshot.toMap()
        assertEquals("work", map["phase"])
        assertEquals("distance", map["metric"])
        assertEquals(400, map["target"])
        assertEquals("rest", map["nextPhase"])
        assertEquals("time", map["nextMetric"])
        assertEquals(90, map["nextTarget"])
    }

    @Test
    fun skipIsANoOpWhileIdle() {
        val engine = RunIntervalEngineNative()
        assertTrue(engine.skip().isEmpty())
        assertEquals(RunIntervalPhase.idle, engine.snapshot.phase)
    }
}
