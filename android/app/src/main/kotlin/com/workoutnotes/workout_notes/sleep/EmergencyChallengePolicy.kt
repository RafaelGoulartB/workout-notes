package com.workoutnotes.workout_notes.sleep

/** Pure rules for the emergency challenge, kept separate for JVM testing. */
object EmergencyChallengePolicy {
    const val MAX_TAPS = 500
    const val DURATION_MILLIS = 3 * 60 * 1000L
    const val MAX_BARCODE_PAUSE_ATTEMPTS = 5

    fun nextTaps(current: Int): Int =
        (current + 1).coerceAtMost(MAX_TAPS)

    fun nextBarcodePauseAttempts(previousAttempts: Int): Int =
        (previousAttempts + 1).coerceAtMost(MAX_BARCODE_PAUSE_ATTEMPTS)

    fun shouldPauseBarcodeAttempt(previousAttempts: Int): Boolean =
        previousAttempts < MAX_BARCODE_PAUSE_ATTEMPTS

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
