package com.workoutnotes.workout_notes.run

import kotlin.math.max

/** Pure recovery rules for timing and split baselines persisted in the spool. */
data class RunTrackingRecoveryState(
    val pausedAtMillis: Long,
    val totalPausedMillis: Long,
    val lastSplitMovingSeconds: Int,
    val nextSplitAtMeters: Double,
    /** Standing-still time already excluded from moving time. */
    val totalAutoPausedMillis: Long = 0L,
    /** Non-zero when the process died while auto-paused. */
    val autoPausedAtMillis: Long = 0L,
)

object RunTrackingRecovery {
    fun restore(
        session: Map<String, Any?>,
        completedSplits: List<Map<String, Any?>>,
        nowMillis: Long,
    ): RunTrackingRecoveryState {
        val storedDuration = (session["duration_seconds"] as? Number)?.toInt() ?: 0
        val storedMoving =
            (session["moving_time_seconds"] as? Number)?.toInt() ?: storedDuration
        val lastSplitMoving =
            (session["last_split_moving_seconds"] as? Number)?.toInt()
                ?: completedSplits.sumOf {
                    (it["duration_seconds"] as? Number)?.toInt() ?: 0
                }
        val totalAutoPaused = (session["total_auto_paused_millis"] as? Number)?.toLong() ?: 0L
        val totalPaused =
            (session["total_paused_millis"] as? Number)?.toLong()
                ?: max(0L, (storedDuration - storedMoving) * 1000L - totalAutoPaused)
        val pausedAt = if ((session["status"] as? String) == "paused") {
            (session["paused_at_millis"] as? Number)?.toLong() ?: nowMillis
        } else {
            0L
        }
        val nextSplit =
            (session["next_split_at_meters"] as? Number)?.toDouble()
                ?: (completedSplits.size + 1) * 1000.0
        val autoPausedAt = if ((session["status"] as? String) == "paused") {
            0L
        } else {
            (session["auto_paused_at_millis"] as? Number)?.toLong() ?: 0L
        }
        return RunTrackingRecoveryState(
            pausedAtMillis = pausedAt,
            totalPausedMillis = totalPaused,
            lastSplitMovingSeconds = lastSplitMoving,
            nextSplitAtMeters = nextSplit,
            totalAutoPausedMillis = totalAutoPaused,
            autoPausedAtMillis = autoPausedAt,
        )
    }
}
