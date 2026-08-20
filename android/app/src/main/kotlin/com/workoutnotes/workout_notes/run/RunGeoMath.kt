package com.workoutnotes.workout_notes.run

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** Pure geo helpers for distance / pace — unit-tested without Android APIs. */
object RunGeoMath {
    private const val EARTH_RADIUS_METERS = 6_371_000.0

    /** ~28.8 km/h — above typical running; rejects GPS teleports. */
    const val DEFAULT_MAX_SPEED_MPS = 8.0

    fun haversineMeters(
        lat1: Double,
        lng1: Double,
        lat2: Double,
        lng2: Double,
    ): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
            sin(dLng / 2) * sin(dLng / 2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return EARTH_RADIUS_METERS * c
    }

    /** Pace in seconds per km. Null when distance is too small. */
    fun paceSecPerKm(distanceMeters: Double, movingTimeSeconds: Int): Double? {
        if (distanceMeters < 1.0 || movingTimeSeconds <= 0) return null
        return movingTimeSeconds / (distanceMeters / 1000.0)
    }

    fun estimateCalories(distanceMeters: Double, bodyWeightKg: Double = 70.0): Int {
        val km = distanceMeters / 1000.0
        return (km * bodyWeightKg).toInt().coerceAtLeast(0)
    }

    /**
     * Accept a new GPS fix when accuracy is known and reasonable, the point
     * moved enough to avoid jitter inflation, and implied speed is plausible
     * for running (rejects teleports after signal gaps).
     */
    fun shouldAcceptPoint(
        accuracyMeters: Float?,
        distanceFromLastMeters: Double,
        timeDeltaSeconds: Double = 1.0,
        minDistanceMeters: Double = 3.0,
        maxAccuracyMeters: Float = 40f,
        maxSpeedMps: Double = DEFAULT_MAX_SPEED_MPS,
    ): Boolean {
        if (accuracyMeters == null || accuracyMeters > maxAccuracyMeters) return false
        if (distanceFromLastMeters < minDistanceMeters) return false
        val safeTime = timeDeltaSeconds.coerceAtLeast(0.1)
        val speedMps = distanceFromLastMeters / safeTime
        if (speedMps > maxSpeedMps) return false
        return true
    }
}
