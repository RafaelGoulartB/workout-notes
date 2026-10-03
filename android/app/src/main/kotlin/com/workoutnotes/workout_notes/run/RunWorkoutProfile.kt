package com.workoutnotes.workout_notes.run

import org.json.JSONObject

/** Kind of the planned workout; mirrors `RunWorkoutKind` in Dart. */
enum class RunWorkoutKindNative {
    none, easy, long, tempo, interval, fartlek, hills, progression, recovery, race, test;

    /** Easy-effort days: only "too fast" is worth a warning. */
    val isEasy: Boolean get() = this == easy || this == long || this == recovery

    companion object {
        fun from(raw: Any?): RunWorkoutKindNative =
            values().firstOrNull { it.name == raw?.toString() } ?: none
    }
}

/** How a pace target is enforced. */
enum class RunPaceMode {
    /** Warn on both sides of the band. */
    band,

    /** Easy days: warn only when running faster than the band. */
    ceiling,
}

/**
 * The planned workout behind a session (kind and headline targets), sent by
 * Dart next to the step list. It shapes the coach: a step-less planned run gets
 * an implicit goal and pace target, the kind picks the vocabulary ("Hill 3",
 * "Surge 3") and which cues are worth saying.
 */
data class RunWorkoutProfile(
    val kind: RunWorkoutKindNative = RunWorkoutKindNative.none,
    val targetDistanceMeters: Int? = null,
    val targetDurationSeconds: Int? = null,
    val targetPaceSecPerKm: Double? = null,
) {
    val isPlanned: Boolean get() = kind != RunWorkoutKindNative.none

    /** A planned distance or duration that can stand in for a session goal. */
    fun implicitGoal(): RunSessionGoal? = when {
        targetDistanceMeters != null && targetDistanceMeters > 0 ->
            RunSessionGoal(enabled = true, metric = RunIntervalMetric.distance, value = targetDistanceMeters)
        targetDurationSeconds != null && targetDurationSeconds > 0 ->
            RunSessionGoal(enabled = true, metric = RunIntervalMetric.time, value = targetDurationSeconds)
        else -> null
    }

    /**
     * Pace enforcement for a run without steps, or null when the workout should
     * be run by feel (time trials, hills, no target).
     */
    fun implicitPace(): RunPaceTarget? {
        val pace = targetPaceSecPerKm?.takeIf { it > 0 && it.isFinite() } ?: return null
        return when {
            kind.isEasy -> RunPaceTarget(pace, tolerancePercent = 6, mode = RunPaceMode.ceiling)
            kind == RunWorkoutKindNative.race -> RunPaceTarget(pace, tolerancePercent = 3, mode = RunPaceMode.band)
            kind == RunWorkoutKindNative.test || kind == RunWorkoutKindNative.hills -> null
            else -> RunPaceTarget(pace, tolerancePercent = 5, mode = RunPaceMode.band)
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("kind", kind.name)
        put("targetDistanceMeters", targetDistanceMeters ?: JSONObject.NULL)
        put("targetDurationSeconds", targetDurationSeconds ?: JSONObject.NULL)
        put("targetPaceSecPerKm", targetPaceSecPerKm ?: JSONObject.NULL)
    }

    companion object {
        fun none() = RunWorkoutProfile()

        fun fromMap(map: Map<String, Any?>?): RunWorkoutProfile {
            if (map == null) return none()
            return RunWorkoutProfile(
                kind = RunWorkoutKindNative.from(map["kind"]),
                targetDistanceMeters = (map["targetDistanceMeters"] as? Number)?.toInt()?.takeIf { it > 0 },
                targetDurationSeconds = (map["targetDurationSeconds"] as? Number)?.toInt()?.takeIf { it > 0 },
                targetPaceSecPerKm = (map["targetPaceSecPerKm"] as? Number)?.toDouble()?.takeIf { it > 0 },
            )
        }

        fun fromJsonString(raw: String?): RunWorkoutProfile {
            if (raw.isNullOrBlank()) return none()
            return try {
                val json = JSONObject(raw)
                RunWorkoutProfile(
                    kind = RunWorkoutKindNative.from(json.optString("kind")),
                    targetDistanceMeters = if (json.isNull("targetDistanceMeters")) null
                    else json.optInt("targetDistanceMeters").takeIf { it > 0 },
                    targetDurationSeconds = if (json.isNull("targetDurationSeconds")) null
                    else json.optInt("targetDurationSeconds").takeIf { it > 0 },
                    targetPaceSecPerKm = if (json.isNull("targetPaceSecPerKm")) null
                    else json.optDouble("targetPaceSecPerKm").takeIf { it > 0 && !it.isNaN() },
                )
            } catch (_: Throwable) {
                none()
            }
        }
    }
}

/** A single pace target with its tolerance. */
data class RunPaceTarget(
    val paceSecPerKm: Double,
    val tolerancePercent: Int,
    val mode: RunPaceMode = RunPaceMode.band,
) {
    /** -1 too fast, 1 too slow, 0 fine. */
    fun direction(pace: Double): Int {
        val tolerance = tolerancePercent / 100.0
        return when {
            pace < paceSecPerKm * (1 - tolerance) -> -1
            mode == RunPaceMode.band && pace > paceSecPerKm * (1 + tolerance) -> 1
            else -> 0
        }
    }
}
