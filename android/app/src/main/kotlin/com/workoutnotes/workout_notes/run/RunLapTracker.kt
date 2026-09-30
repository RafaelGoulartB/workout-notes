package com.workoutnotes.workout_notes.run

/**
 * Manual laps. A lap is measured on moving time so auto/manual pauses never
 * inflate its pace. Pure and Android-free for unit tests; the service owns the
 * live totals and passes them in.
 */
class RunLapTracker {
    private val completed = mutableListOf<Map<String, Any?>>()
    private var lapStartDistance = 0.0
    private var lapStartMoving = 0

    val count: Int get() = completed.size
    val startDistanceMeters: Double get() = lapStartDistance
    val startMovingSeconds: Int get() = lapStartMoving

    fun reset() {
        completed.clear()
        lapStartDistance = 0.0
        lapStartMoving = 0
    }

    fun restore(
        laps: List<Map<String, Any?>>,
        startDistanceMeters: Double,
        startMovingSeconds: Int,
    ) {
        completed.clear()
        completed.addAll(laps)
        lapStartDistance = startDistanceMeters
        lapStartMoving = startMovingSeconds
    }

    fun completedLaps(): List<Map<String, Any?>> = completed.toList()

    /** Live "current lap" numbers, index is the lap being run (1-based). */
    fun current(distanceMeters: Double, movingSeconds: Int): Map<String, Any?> =
        lapMap(completed.size + 1, lapStartDistance, distanceMeters, movingSeconds)

    /**
     * Closes the current lap. Returns null (and changes nothing) for an
     * accidental double tap: under [MIN_LAP_SECONDS] of moving time.
     */
    fun mark(distanceMeters: Double, movingSeconds: Int): Map<String, Any?>? {
        if (movingSeconds - lapStartMoving < MIN_LAP_SECONDS) return null
        val lap = current(distanceMeters, movingSeconds)
        completed.add(lap)
        lapStartDistance = distanceMeters
        lapStartMoving = movingSeconds
        return lap
    }

    /**
     * When the run ends after at least one manual lap, the remainder becomes
     * the last lap so the laps add up to the whole activity.
     */
    fun closeFinal(distanceMeters: Double, movingSeconds: Int): Map<String, Any?>? {
        if (completed.isEmpty()) return null
        val remainingDistance = distanceMeters - lapStartDistance
        val remainingSeconds = movingSeconds - lapStartMoving
        if (remainingSeconds < 1 && remainingDistance < 1.0) return null
        val lap = current(distanceMeters, movingSeconds)
        completed.add(lap)
        lapStartDistance = distanceMeters
        lapStartMoving = movingSeconds
        return lap
    }

    private fun lapMap(
        index: Int,
        startDistance: Double,
        distanceMeters: Double,
        movingSeconds: Int,
    ): Map<String, Any?> {
        val distance = (distanceMeters - startDistance).coerceAtLeast(0.0)
        val duration = (movingSeconds - lapStartMoving).coerceAtLeast(0)
        return mapOf(
            "lap_index" to index,
            "start_distance_meters" to startDistance,
            "distance_meters" to distance,
            "duration_seconds" to duration,
            "pace_sec_per_km" to RunGeoMath.paceSecPerKm(distance, duration),
        )
    }

    companion object {
        const val MIN_LAP_SECONDS = 2
    }
}
