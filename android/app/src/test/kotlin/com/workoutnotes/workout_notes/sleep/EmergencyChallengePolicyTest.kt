package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmergencyChallengePolicyTest {
    @Test
    fun capsTapsAtFiveHundred() {
        assertEquals(1, EmergencyChallengePolicy.nextTaps(0))
        assertEquals(500, EmergencyChallengePolicy.nextTaps(499))
        assertEquals(500, EmergencyChallengePolicy.nextTaps(500))
        assertEquals(500, EmergencyChallengePolicy.nextTaps(1200))
    }

    @Test
    fun pausesBarcodeOnlyForFirstFiveAttempts() {
        assertTrue(EmergencyChallengePolicy.shouldPauseBarcodeAttempt(0))
        assertTrue(EmergencyChallengePolicy.shouldPauseBarcodeAttempt(4))
        assertFalse(EmergencyChallengePolicy.shouldPauseBarcodeAttempt(5))
        assertEquals(5, EmergencyChallengePolicy.nextBarcodePauseAttempts(4))
        assertEquals(5, EmergencyChallengePolicy.nextBarcodePauseAttempts(5))
    }

    @Test
    fun countsDownForExactlyThreeMinutes() {
        val start = 10_000L
        val deadline = start + EmergencyChallengePolicy.DURATION_MILLIS

        assertEquals(
            EmergencyChallengePolicy.DURATION_MILLIS,
            EmergencyChallengePolicy.remainingMillis(deadline, start),
        )
        assertEquals(
            EmergencyChallengePolicy.DURATION_MILLIS - 30_000L,
            EmergencyChallengePolicy.remainingMillis(deadline, start + 30_000L),
        )
        assertEquals(0L, EmergencyChallengePolicy.remainingMillis(deadline, deadline))
        assertTrue(EmergencyChallengePolicy.isActive(deadline, deadline - 1L))
        assertFalse(EmergencyChallengePolicy.isActive(deadline, deadline))
    }

    @Test
    fun progressFallsFromFullToEmpty() {
        val start = 20_000L
        val deadline = start + EmergencyChallengePolicy.DURATION_MILLIS

        assertEquals(1000, EmergencyChallengePolicy.progressPerMille(deadline, start))
        assertEquals(500, EmergencyChallengePolicy.progressPerMille(
            deadline,
            start + EmergencyChallengePolicy.DURATION_MILLIS / 2,
        ))
        assertEquals(0, EmergencyChallengePolicy.progressPerMille(deadline, deadline))
    }
}
