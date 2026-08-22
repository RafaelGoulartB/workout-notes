package com.workoutnotes.workout_notes.run

import org.json.JSONArray
import org.json.JSONObject

enum class RunStepRole {
    warmup, work, recovery, steady, cooldown;

    /** Recovery/warmup/cooldown are "easy" — pace cues only fire on effort. */
    val isEffort: Boolean get() = this == work || this == steady

    companion object {
        fun fromString(raw: String?): RunStepRole = when (raw) {
            "warmup" -> warmup
            "recovery" -> recovery
            "steady" -> steady
            "cooldown" -> cooldown
            else -> work
        }
    }
}

/** One planned segment of a structured session. */
data class RunWorkoutStepNative(
    val role: RunStepRole = RunStepRole.work,
    val metric: RunIntervalMetric = RunIntervalMetric.distance,
    val value: Int = 0,
    val repeatGroup: Int? = null,
    val repeatCount: Int = 1,
    val targetPaceMinSecPerKm: Double? = null,
    val targetPaceMaxSecPerKm: Double? = null,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>?): RunWorkoutStepNative? {
            if (map == null) return null
            val value = (map["value"] as? Number)?.toInt() ?: 0
            if (value <= 0) return null
            return RunWorkoutStepNative(
                role = RunStepRole.fromString(map["role"] as? String),
                metric = if (map["metric"] == "time") RunIntervalMetric.time else RunIntervalMetric.distance,
                value = value,
                repeatGroup = (map["repeatGroup"] as? Number)?.toInt(),
                repeatCount = ((map["repeatCount"] as? Number)?.toInt() ?: 1).coerceIn(1, 99),
                targetPaceMinSecPerKm = (map["targetPaceMinSecPerKm"] as? Number)?.toDouble(),
                targetPaceMaxSecPerKm = (map["targetPaceMaxSecPerKm"] as? Number)?.toDouble(),
            )
        }

        fun fromJson(json: JSONObject?): RunWorkoutStepNative? {
            if (json == null) return null
            val value = json.optInt("value", 0)
            if (value <= 0) return null
            return RunWorkoutStepNative(
                role = RunStepRole.fromString(json.optString("role", "work")),
                metric = if (json.optString("metric") == "time") RunIntervalMetric.time else RunIntervalMetric.distance,
                value = value,
                repeatGroup = if (json.isNull("repeatGroup")) null else json.optInt("repeatGroup"),
                repeatCount = json.optInt("repeatCount", 1).coerceIn(1, 99),
                targetPaceMinSecPerKm = if (json.isNull("targetPaceMinSecPerKm")) null else json.optDouble("targetPaceMinSecPerKm").takeIf { !it.isNaN() },
                targetPaceMaxSecPerKm = if (json.isNull("targetPaceMaxSecPerKm")) null else json.optDouble("targetPaceMaxSecPerKm").takeIf { !it.isNaN() },
            )
        }

        /** Parses the `plan` argument coming over the MethodChannel. */
        fun listFromAny(raw: Any?): List<RunWorkoutStepNative> {
            if (raw is List<*>) {
                return raw.mapNotNull {
                    @Suppress("UNCHECKED_CAST")
                    fromMap(it as? Map<String, Any?>)
                }
            }
            if (raw is String && raw.isNotBlank()) return listFromJsonString(raw)
            return emptyList()
        }

        /** Parses the plan persisted in the run spool. */
        fun listFromJsonString(raw: String?): List<RunWorkoutStepNative> {
            if (raw.isNullOrBlank()) return emptyList()
            return try {
                val array = JSONArray(raw)
                (0 until array.length()).mapNotNull { fromJson(array.optJSONObject(it)) }
            } catch (_: Throwable) {
                emptyList()
            }
        }

        fun listToJsonString(steps: List<RunWorkoutStepNative>): String {
            val array = JSONArray()
            for (step in steps) array.put(step.toJson())
            return array.toString()
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("role", role.name)
        put("metric", metric.name)
        put("value", value)
        if (repeatGroup != null) put("repeatGroup", repeatGroup) else put("repeatGroup", JSONObject.NULL)
        put("repeatCount", repeatCount)
        if (targetPaceMinSecPerKm != null) put("targetPaceMinSecPerKm", targetPaceMinSecPerKm) else put("targetPaceMinSecPerKm", JSONObject.NULL)
        if (targetPaceMaxSecPerKm != null) put("targetPaceMaxSecPerKm", targetPaceMaxSecPerKm) else put("targetPaceMaxSecPerKm", JSONObject.NULL)
    }
}

/** A step after repeat expansion — what the engine actually executes. */
data class RunExpandedStepNative(
    val step: RunWorkoutStepNative,
    val repIndex: Int,
    val repTotal: Int,
    val sequence: Int,
)

enum class RunStepEnginePhase { idle, running, done }

enum class RunStepEventKind {
    stepStarted, stepCompleted, timeRemainingCue, paceTooSlow, paceTooFast, workoutCompleted
}

data class RunStepEventNative(
    val kind: RunStepEventKind,
    val stepIndex: Int,
    val totalSteps: Int,
    val role: RunStepRole,
    val repIndex: Int,
    val repTotal: Int,
    val metric: RunIntervalMetric,
    val target: Int,
    val remainingSeconds: Int? = null,
    val paceSecPerKm: Double? = null,
)

data class RunStepSnapshotNative(
    val phase: RunStepEnginePhase = RunStepEnginePhase.idle,
    val stepIndex: Int = 0,
    val totalSteps: Int = 0,
    val role: RunStepRole = RunStepRole.work,
    val repIndex: Int = 0,
    val repTotal: Int = 0,
    val metric: RunIntervalMetric = RunIntervalMetric.distance,
    val target: Int = 0,
    val progress: Double = 0.0,
    val remaining: Double = 0.0,
    val workRepsDone: Int = 0,
    val workRepsTotal: Int = 0,
) {
    val isActive: Boolean get() = phase == RunStepEnginePhase.running
    val isDone: Boolean get() = phase == RunStepEnginePhase.done
}

/** Planned-vs-actual outcome of one executed step. */
data class RunStepResultNative(
    val sequence: Int,
    val role: RunStepRole,
    val repIndex: Int,
    val plannedMetric: RunIntervalMetric,
    val plannedValue: Int,
    val plannedPaceSecPerKm: Double?,
    val distanceMeters: Double,
    val durationSeconds: Int,
) {
    val actualPaceSecPerKm: Double?
        get() = if (distanceMeters < 1 || durationSeconds <= 0) null
        else durationSeconds / (distanceMeters / 1000.0)

    fun toMap(): Map<String, Any?> = mapOf(
        "sequence" to sequence,
        "role" to role.name,
        "repIndex" to repIndex,
        "plannedMetric" to plannedMetric.name,
        "plannedValue" to plannedValue,
        "plannedPaceSecPerKm" to plannedPaceSecPerKm,
        "distanceMeters" to distanceMeters,
        "durationSeconds" to durationSeconds,
        "actualPaceSecPerKm" to actualPaceSecPerKm,
    )
}

/**
 * Pure FSM that walks a structured running session (warmup → N×(work/recovery)
 * → cooldown). Kotlin port of lib/services/run_workout_step_engine.dart —
 * keep both sides in sync; test/run_workout_step_engine_test.dart and
 * RunWorkoutStepEngineNativeTest cover the same scenarios.
 */
class RunWorkoutStepEngineNative {
    private var steps: List<RunExpandedStepNative> = emptyList()
    private var phase: RunStepEnginePhase = RunStepEnginePhase.idle
    private var index: Int = 0
    private var accum: Double = 0.0
    private var remainingCueSpoken: Boolean = false
    private var paceCueSpoken: Boolean = false
    private var lastDistance: Double = 0.0
    private var lastMovingSeconds: Int = 0
    private var stepDistance: Double = 0.0
    private var stepSeconds: Int = 0
    private val stepResults = mutableListOf<RunStepResultNative>()

    val totalSteps: Int get() = steps.size

    val hasPlan: Boolean get() = steps.isNotEmpty()

    val results: List<RunStepResultNative> get() = stepResults.toList()

    val workRepsTotal: Int get() = steps.count { it.step.role == RunStepRole.work }

    private val workRepsDone: Int
        get() = steps.take(index.coerceIn(0, steps.size)).count { it.step.role == RunStepRole.work }

    fun configure(rawSteps: List<RunWorkoutStepNative>) {
        steps = expand(rawSteps.filter { it.value > 0 })
        reset()
    }

    fun reset() {
        phase = RunStepEnginePhase.idle
        index = 0
        accum = 0.0
        remainingCueSpoken = false
        paceCueSpoken = false
        lastDistance = 0.0
        lastMovingSeconds = 0
        stepDistance = 0.0
        stepSeconds = 0
        stepResults.clear()
    }

    val snapshot: RunStepSnapshotNative
        get() {
            if (phase != RunStepEnginePhase.running || index < 0 || index >= steps.size) {
                return RunStepSnapshotNative(
                    phase = phase,
                    stepIndex = index,
                    totalSteps = steps.size,
                    progress = if (phase == RunStepEnginePhase.done) 1.0 else 0.0,
                    workRepsDone = if (phase == RunStepEnginePhase.done) workRepsTotal else workRepsDone,
                    workRepsTotal = workRepsTotal,
                )
            }
            val current = steps[index]
            val target = current.step.value.toDouble()
            return RunStepSnapshotNative(
                phase = phase,
                stepIndex = index,
                totalSteps = steps.size,
                role = current.step.role,
                repIndex = current.repIndex,
                repTotal = current.repTotal,
                metric = current.step.metric,
                target = current.step.value,
                progress = if (target <= 0) 1.0 else (accum / target).coerceIn(0.0, 1.0),
                remaining = (target - accum).coerceIn(0.0, target),
                workRepsDone = workRepsDone,
                workRepsTotal = workRepsTotal,
            )
        }

    fun start(): List<RunStepEventNative> {
        if (steps.isEmpty()) {
            phase = RunStepEnginePhase.done
            return emptyList()
        }
        index = 0
        accum = 0.0
        stepDistance = 0.0
        stepSeconds = 0
        remainingCueSpoken = false
        paceCueSpoken = false
        lastDistance = 0.0
        lastMovingSeconds = 0
        stepResults.clear()
        phase = RunStepEnginePhase.running
        return listOf(event(RunStepEventKind.stepStarted, steps[0]))
    }

    fun tick(recording: Boolean, distanceMeters: Double, movingTimeSeconds: Int): List<RunStepEventNative> {
        val distanceDelta = (distanceMeters - lastDistance).coerceAtLeast(0.0)
        val timeDelta = (movingTimeSeconds - lastMovingSeconds).coerceIn(0, 3600)
        lastDistance = distanceMeters
        lastMovingSeconds = movingTimeSeconds

        if (phase != RunStepEnginePhase.running || !recording) return emptyList()

        val events = mutableListOf<RunStepEventNative>()
        stepDistance += distanceDelta
        stepSeconds += timeDelta

        var current = steps[index]
        accum += if (current.step.metric == RunIntervalMetric.distance) distanceDelta else timeDelta.toDouble()

        val target = current.step.value.toDouble()
        if (current.step.metric == RunIntervalMetric.time && !remainingCueSpoken && target > 30) {
            val remaining = target - accum
            if (remaining <= 30 && remaining > 0) {
                remainingCueSpoken = true
                events.add(event(RunStepEventKind.timeRemainingCue, current, remainingSeconds = 30))
            }
        }

        if (!paceCueSpoken && current.step.role.isEffort) {
            val pace = currentStepPace()
            if (pace != null && stepSeconds >= 20) {
                val min = current.step.targetPaceMinSecPerKm
                val max = current.step.targetPaceMaxSecPerKm
                if (max != null && pace > max) {
                    paceCueSpoken = true
                    events.add(event(RunStepEventKind.paceTooSlow, current, paceSecPerKm = pace))
                } else if (min != null && pace < min) {
                    paceCueSpoken = true
                    events.add(event(RunStepEventKind.paceTooFast, current, paceSecPerKm = pace))
                }
            }
        }

        while (phase == RunStepEnginePhase.running &&
            (current.step.value <= 0 || accum + 1e-6 >= current.step.value)
        ) {
            val overflow = accum - current.step.value
            events.add(event(RunStepEventKind.stepCompleted, current))
            recordResult(current)
            if (index >= steps.size - 1) {
                phase = RunStepEnginePhase.done
                index = steps.size
                events.add(
                    RunStepEventNative(
                        kind = RunStepEventKind.workoutCompleted,
                        stepIndex = -1,
                        totalSteps = steps.size,
                        role = current.step.role,
                        repIndex = current.repIndex,
                        repTotal = current.repTotal,
                        metric = current.step.metric,
                        target = current.step.value,
                    )
                )
                break
            }
            val previousMetric = current.step.metric
            index++
            current = steps[index]
            accum = if (current.step.metric == previousMetric) overflow.coerceAtLeast(0.0) else 0.0
            stepDistance = 0.0
            stepSeconds = 0
            remainingCueSpoken = false
            paceCueSpoken = false
            events.add(event(RunStepEventKind.stepStarted, current))
        }
        return events
    }

    /** Closes a partial step when the run is stopped mid-session. */
    fun finish() {
        if (phase == RunStepEnginePhase.running &&
            index >= 0 && index < steps.size &&
            (stepDistance > 0 || stepSeconds > 0)
        ) {
            recordResult(steps[index])
        }
        phase = RunStepEnginePhase.done
    }

    private fun currentStepPace(): Double? {
        if (stepDistance < 50 || stepSeconds <= 0) return null
        return stepSeconds / (stepDistance / 1000.0)
    }

    private fun recordResult(expanded: RunExpandedStepNative) {
        stepResults.add(
            RunStepResultNative(
                sequence = stepResults.size,
                role = expanded.step.role,
                repIndex = expanded.repIndex,
                plannedMetric = expanded.step.metric,
                plannedValue = expanded.step.value,
                plannedPaceSecPerKm = expanded.step.targetPaceMinSecPerKm,
                distanceMeters = stepDistance,
                durationSeconds = stepSeconds,
            )
        )
    }

    private fun event(
        kind: RunStepEventKind,
        expanded: RunExpandedStepNative,
        remainingSeconds: Int? = null,
        paceSecPerKm: Double? = null,
    ) = RunStepEventNative(
        kind = kind,
        stepIndex = expanded.sequence,
        totalSteps = steps.size,
        role = expanded.step.role,
        repIndex = expanded.repIndex,
        repTotal = expanded.repTotal,
        metric = expanded.step.metric,
        target = expanded.step.value,
        remainingSeconds = remainingSeconds,
        paceSecPerKm = paceSecPerKm,
    )

    companion object {
        /**
         * Flattens steps into the execution sequence. Consecutive steps sharing
         * a `repeatGroup` form a block repeated `repeatCount` times.
         */
        fun expand(ordered: List<RunWorkoutStepNative>): List<RunExpandedStepNative> {
            val result = mutableListOf<RunExpandedStepNative>()
            var index = 0
            while (index < ordered.size) {
                val group = ordered[index].repeatGroup
                if (group == null) {
                    result.add(RunExpandedStepNative(ordered[index], 1, 1, result.size))
                    index++
                    continue
                }
                val block = mutableListOf<RunWorkoutStepNative>()
                var cursor = index
                while (cursor < ordered.size && ordered[cursor].repeatGroup == group) {
                    block.add(ordered[cursor])
                    cursor++
                }
                val repeats = block.maxOf { it.repeatCount }.coerceIn(1, 99)
                for (rep in 1..repeats) {
                    for (step in block) {
                        result.add(RunExpandedStepNative(step, rep, repeats, result.size))
                    }
                }
                index = cursor
            }
            return result
        }
    }
}
