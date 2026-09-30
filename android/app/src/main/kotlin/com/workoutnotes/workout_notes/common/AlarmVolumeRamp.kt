package com.workoutnotes.workout_notes.common

import kotlin.math.pow

/**
 * How an alarm sound starts: a gentle rise over [rampMillis] and, when
 * [boostToMax] is set, the system alarm volume raised to its maximum once the
 * rise ends (restored when the alarm stops).
 *
 * The rise is linear in decibels, from [START_DB] below the alarm volume up
 * to it, because loudness is perceived logarithmically: a linear gain ramp
 * sounds like near silence followed by a jump.
 */
data class AlarmVolumeRamp(val rampMillis: Long, val boostToMax: Boolean) {
    companion object {
        val NONE = AlarmVolumeRamp(0L, false)
        const val START_DB = -30.0

        /** A snoozed alarm rings again: the person is already half awake. */
        const val SNOOZE_RAMP_MILLIS = 20_000L
        const val TICK_MILLIS = 200L
    }

    val isGradual: Boolean get() = rampMillis > 0L

    /** Player gain (0..1, relative to the alarm stream volume). */
    fun gainAt(elapsedMillis: Long): Float {
        if (!isGradual || elapsedMillis >= rampMillis) return 1f
        val fraction = elapsedMillis.coerceAtLeast(0L).toDouble() / rampMillis
        return 10.0.pow((START_DB * (1.0 - fraction)) / 20.0).toFloat()
    }

    /** Vibration joins halfway: buzzing from the first second defeats a soft start. */
    val vibrationDelayMillis: Long get() = rampMillis / 2

    /** Same profile for a snoozed ring: a short rise, same boost. */
    fun forSnooze(): AlarmVolumeRamp =
        if (isGradual) copy(rampMillis = minOf(rampMillis, SNOOZE_RAMP_MILLIS)) else this
}
