package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RunCueSchedulerTest {

    private fun cue(text: String, priority: RunCuePriority, kind: String = text, at: Long = 0L, ttl: Long? = null) =
        if (ttl == null) RunCue(text, priority, kind, at) else RunCue(text, priority, kind, at, ttlMillis = ttl)

    @Test
    fun criticalCuesAreMergedAndSpokenAtOnce() {
        val scheduler = RunCueScheduler()
        scheduler.offer(cue("1:28, on target.", RunCuePriority.critical, "a"))
        scheduler.offer(cue("Recover, 90 seconds.", RunCuePriority.critical, "b"))
        scheduler.offer(cue("Kilometer 3.", RunCuePriority.normal))
        assertEquals("1:28, on target. Recover, 90 seconds.", scheduler.next(0L)?.text)
        // The normal cue waits for a gap after the merged utterance.
        assertNull(scheduler.next(1_000L))
        assertEquals("Kilometer 3.", scheduler.next(20_000L)?.text)
    }

    @Test
    fun staleCuesAreDroppedNotSaidLate() {
        val scheduler = RunCueScheduler()
        scheduler.offer(cue("Pick it up.", RunCuePriority.high, at = 0L))
        assertNull(scheduler.next(9_000L))
    }

    @Test
    fun newerCueOfTheSameKindReplacesTheQueuedOne() {
        val scheduler = RunCueScheduler()
        scheduler.offer(cue("Go.", RunCuePriority.critical, "step"))
        scheduler.next(0L)
        scheduler.offer(cue("Kilometer 3.", RunCuePriority.normal, "km", at = 1_000L))
        scheduler.offer(cue("Kilometer 4.", RunCuePriority.normal, "km", at = 2_000L))
        assertEquals("Kilometer 4.", scheduler.next(20_000L)?.text)
        assertNull(scheduler.next(60_000L))
    }

    @Test
    fun progressCuesHoldBackRightBeforeAStepChange() {
        val scheduler = RunCueScheduler()
        scheduler.offer(cue("Kilometer 3.", RunCuePriority.normal, at = 0L))
        scheduler.offer(cue("200 meters left.", RunCuePriority.high, at = 0L))
        assertEquals("200 meters left.", scheduler.next(0L, secondsToTransition = 8.0)?.text)
        assertNull(scheduler.next(15_000L, secondsToTransition = 5.0))
        assertEquals("Kilometer 3.", scheduler.next(16_000L, secondsToTransition = null)?.text)
    }

    @Test
    fun lowerCuesAreCappedPerTwoMinutes() {
        val scheduler = RunCueScheduler(budgetPerWindow = 2)
        var spoken = 0
        var t = 0L
        repeat(5) { i ->
            scheduler.offer(cue("Cue $i.", RunCuePriority.normal, "k$i", at = t, ttl = 200_000))
        }
        while (t <= 110_000L) {
            if (scheduler.next(t) != null) spoken++
            t += 1_000L
        }
        assertEquals(2, spoken)
        // High-priority feedback is never held by the budget.
        scheduler.offer(cue("Ease off.", RunCuePriority.high, "pace", at = t))
        assertEquals("Ease off.", scheduler.next(t)?.text)
    }
}
