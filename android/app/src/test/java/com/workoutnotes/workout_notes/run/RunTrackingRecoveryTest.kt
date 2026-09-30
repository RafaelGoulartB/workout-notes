package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Test

class RunTrackingRecoveryTest {
    @Test
    fun restoresPausedClockAndPartialSplitBaseline() {
        val restored = RunTrackingRecovery.restore(
            session = mapOf(
                "status" to "paused",
                "duration_seconds" to 740,
                "moving_time_seconds" to 615,
                "paused_at_millis" to 1_700_000_000_000L,
                "total_paused_millis" to 120_000L,
                "last_split_moving_seconds" to 572,
                "next_split_at_meters" to 3_000.0,
            ),
            completedSplits = listOf(
                mapOf("duration_seconds" to 286),
                mapOf("duration_seconds" to 286),
            ),
            nowMillis = 1_700_000_005_000L,
        )

        assertEquals(1_700_000_000_000L, restored.pausedAtMillis)
        assertEquals(120_000L, restored.totalPausedMillis)
        assertEquals(572, restored.lastSplitMovingSeconds)
        assertEquals(3_000.0, restored.nextSplitAtMeters, 0.001)
    }

    @Test
    fun derivesSafeBaselinesForLegacySpool() {
        val restored = RunTrackingRecovery.restore(
            session = mapOf(
                "status" to "paused",
                "duration_seconds" to 500,
                "moving_time_seconds" to 450,
            ),
            completedSplits = listOf(mapOf("duration_seconds" to 280)),
            nowMillis = 99_000L,
        )

        assertEquals(99_000L, restored.pausedAtMillis)
        assertEquals(50_000L, restored.totalPausedMillis)
        assertEquals(280, restored.lastSplitMovingSeconds)
        assertEquals(2_000.0, restored.nextSplitAtMeters, 0.001)
    }

    @Test
    fun restoresAutoPausedTimeAndOpenAutoPause() {
        val restored = RunTrackingRecovery.restore(
            session = mapOf(
                "status" to "recording",
                "duration_seconds" to 900,
                "moving_time_seconds" to 800,
                "total_paused_millis" to 40_000L,
                "total_auto_paused_millis" to 60_000L,
                "auto_paused_at_millis" to 1_700_000_000_000L,
            ),
            completedSplits = emptyList(),
            nowMillis = 1_700_000_010_000L,
        )
        assertEquals(40_000L, restored.totalPausedMillis)
        assertEquals(60_000L, restored.totalAutoPausedMillis)
        assertEquals(1_700_000_000_000L, restored.autoPausedAtMillis)
    }

    @Test
    fun manualPauseWinsOverStaleAutoPause() {
        val restored = RunTrackingRecovery.restore(
            session = mapOf(
                "status" to "paused",
                "duration_seconds" to 900,
                "moving_time_seconds" to 800,
                "auto_paused_at_millis" to 1_700_000_000_000L,
            ),
            completedSplits = emptyList(),
            nowMillis = 1_700_000_010_000L,
        )
        assertEquals(0L, restored.autoPausedAtMillis)
    }

    @Test
    fun legacyDerivationExcludesAutoPausedShare() {
        val restored = RunTrackingRecovery.restore(
            session = mapOf(
                "status" to "recording",
                "duration_seconds" to 1000,
                "moving_time_seconds" to 850,
                "total_auto_paused_millis" to 100_000L,
            ),
            completedSplits = emptyList(),
            nowMillis = 1L,
        )
        assertEquals(50_000L, restored.totalPausedMillis)
    }
}
