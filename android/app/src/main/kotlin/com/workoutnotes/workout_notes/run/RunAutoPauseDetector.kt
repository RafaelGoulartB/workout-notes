package com.workoutnotes.workout_notes.run

import kotlin.math.cos
import kotlin.math.hypot

/**
 * Pure stillness detector behind auto-pause. It only looks at fixes, never at
 * Android APIs, so it is unit-tested with synthetic tracks.
 *
 * Hysteresis keeps GPS jitter from flapping the state:
 *  - moving -> paused needs the speed below [pauseSpeedMps] for [stillMillis];
 *  - paused -> moving needs the speed at or above [resumeSpeedMps] for
 *    [movingMillis] (a single noisy fix never resumes a run).
 *
 * Speed comes from the receiver's Doppler value when the fix is accurate.
 * Otherwise it is the *net* displacement across [windowMillis]: position noise
 * is a bounded random walk, so it barely moves the net displacement, while a
 * runner's steady progress does.
 */
class RunAutoPauseDetector(
    private val pauseSpeedMps: Double = 0.8,
    private val resumeSpeedMps: Double = 1.4,
    private val stillMillis: Long = 6_000L,
    private val movingMillis: Long = 2_000L,
    private val windowMillis: Long = 6_000L,
    private val minWindowMillis: Long = 3_000L,
    private val maxAccuracyMeters: Float = 35f,
) {
    enum class Event { NONE, PAUSE, RESUME }

    private class Sample(val timeMillis: Long, val x: Double, val y: Double)

    private val window = ArrayDeque<Sample>()
    private var originLat: Double? = null
    private var slowSinceMillis = -1L
    private var fastSinceMillis = -1L

    var paused: Boolean = false
        private set

    /** Forgets everything; optionally starts already paused (spool restore). */
    fun reset(startPaused: Boolean = false) {
        paused = startPaused
        window.clear()
        originLat = null
        slowSinceMillis = -1L
        fastSinceMillis = -1L
    }

    fun onFix(
        timeMillis: Long,
        latitude: Double,
        longitude: Double,
        speedMps: Double?,
        accuracyMeters: Float?,
    ): Event {
        if (accuracyMeters != null && accuracyMeters > maxAccuracyMeters) return Event.NONE
        val speed = estimateSpeed(timeMillis, latitude, longitude, speedMps) ?: return Event.NONE

        if (!paused) {
            if (speed < pauseSpeedMps) {
                if (slowSinceMillis < 0) slowSinceMillis = timeMillis
                if (timeMillis - slowSinceMillis >= stillMillis) {
                    paused = true
                    slowSinceMillis = -1L
                    fastSinceMillis = -1L
                    return Event.PAUSE
                }
            } else {
                slowSinceMillis = -1L
            }
        } else {
            if (speed >= resumeSpeedMps) {
                if (fastSinceMillis < 0) fastSinceMillis = timeMillis
                if (timeMillis - fastSinceMillis >= movingMillis) {
                    paused = false
                    slowSinceMillis = -1L
                    fastSinceMillis = -1L
                    window.clear()
                    return Event.RESUME
                }
            } else {
                fastSinceMillis = -1L
            }
        }
        return Event.NONE
    }

    private fun estimateSpeed(
        timeMillis: Long,
        latitude: Double,
        longitude: Double,
        speedMps: Double?,
    ): Double? {
        val originLatitude = originLat ?: latitude.also { originLat = it }
        val metersPerDegree = 111_320.0
        val x = longitude * metersPerDegree * cos(Math.toRadians(originLatitude))
        val y = latitude * metersPerDegree
        window.addLast(Sample(timeMillis, x, y))
        while (window.size > 1 && timeMillis - window.first().timeMillis > windowMillis) {
            window.removeFirst()
        }
        if (speedMps != null && speedMps >= 0.0 && speedMps.isFinite()) return speedMps
        val first = window.first()
        val elapsed = timeMillis - first.timeMillis
        if (elapsed < minWindowMillis) return null
        return hypot(x - first.x, y - first.y) / (elapsed / 1000.0)
    }
}
