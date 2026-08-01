package com.workoutnotes.workout_notes.sleep

/** Pure rules for the emergency challenge, kept separate for JVM testing. */
object EmergencyChallengePolicy {
    const val MAX_TAPS = 1000
    const val DURATION_MILLIS = 3 * 60 * 1000L

    fun nextTaps(current: Int): Int =
        (current + 1).coerceAtMost(MAX_TAPS)

    fun remainingMillis(deadlineMillis: Long, nowMillis: Long): Long =
        (deadlineMillis - nowMillis).coerceAtLeast(0L)

    fun isActive(deadlineMillis: Long, nowMillis: Long): Boolean =
        deadlineMillis > nowMillis

    fun progressPerMille(deadlineMillis: Long, nowMillis: Long): Int {
        val remaining = remainingMillis(deadlineMillis, nowMillis)
        return (
            remaining.toDouble() / DURATION_MILLIS * 1000
        ).toInt().coerceIn(0, 1000)
    }
}
