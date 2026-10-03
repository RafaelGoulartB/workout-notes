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
    stepStarted,
    stepCompleted,
    halfway,
    timeRemainingCue,
    distanceRemainingCue,

    /** One tick of the 3-2-1 countdown before a timed step ends. */
    countdown,
    paceTooSlow,
    paceTooFast,

    /** Pace is back inside the band after a warning. */
    paceBackInRange,
    workoutCompleted,
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
    val remainingMeters: Int? = null,
    val paceSecPerKm: Double? = null,
    /** What was actually run in the step ([RunStepEventKind.stepCompleted]). */
    val stepDistanceMeters: Double? = null,
    val stepDurationSeconds: Int? = null,
    val targetPaceMinSecPerKm: Double? = null,
    val targetPaceMaxSecPerKm: Double? = null,
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

    fun toJson(): JSONObject = JSONObject(toMap())

    companion object {
        fun fromJson(value: JSONObject): RunStepResultNative = RunStepResultNative(
            sequence = value.optInt("sequence", 0),
            role = RunStepRole.fromString(value.optString("role", "work")),
            repIndex = value.optInt("repIndex", 1),
            plannedMetric = if (value.optString("plannedMetric") == "time") {
                RunIntervalMetric.time
            } else {
                RunIntervalMetric.distance
            },
            plannedValue = value.optInt("plannedValue", 0),
            plannedPaceSecPerKm = if (value.isNull("plannedPaceSecPerKm")) {
                null
            } else {
                value.optDouble("plannedPaceSecPerKm").takeIf { !it.isNaN() }
            },
            distanceMeters = value.optDouble("distanceMeters", 0.0),
            durationSeconds = value.optInt("durationSeconds", 0),
        )
    }
}

/**
 * Pure FSM that walks a structured running session (warmup → N×(work/recovery)
 * → cooldown). It is the only step engine: Dart reads its `snapshotMap()` from
 * the tracking state. [expand] mirrors `RunPlanWorkout.expand` in Dart, which
 * the plan screens use for the same repeat blocks — keep both in sync
 * (test/run_workout_steps_test.dart and RunWorkoutStepEngineNativeTest).
 *
 * Besides step changes it emits the in-step cues the coach may speak: halfway,
 * time/distance left, the 3-2-1 countdown of timed steps, and pace warnings
 * measured over a rolling window (never the step average, which still holds
 * the acceleration of the first seconds).
 */
class RunWorkoutStepEngineNative {
    private var steps: List<RunExpandedStepNative> = emptyList()
    private var phase: RunStepEnginePhase = RunStepEnginePhase.idle
    private var index: Int = 0
    private var accum: Double = 0.0
    private var lastDistance: Double = 0.0
    private var lastMovingSeconds: Int = 0
    private var stepDistance: Double = 0.0
    private var stepSeconds: Int = 0
    private val stepResults = mutableListOf<RunStepResultNative>()

    /** Easy-effort workout: continuous steps only warn when too fast. */
    private var easyEffort: Boolean = false

    // Per-step cue state.
    private val firedCues = mutableSetOf<Int>()
    private val samples = ArrayDeque<Pair<Int, Double>>()
    private var paceAlerts: Int = 0
    private var lastAlertAt: Int = -1
    private var outSince: Int = -1
    private var outDirection: Int = 0
    private var alertedDirection: Int = 0

    val totalSteps: Int get() = steps.size

    val hasPlan: Boolean get() = steps.isNotEmpty()

    val results: List<RunStepResultNative> get() = stepResults.toList()

    /** Full durable execution state, excluding the plan definition itself. */
    fun stateJson(): String = JSONObject().apply {
        put("version", 2)
        put("phase", phase.name)
        put("index", index)
        put("accum", accum)
        put("lastDistance", lastDistance)
        put("lastMovingSeconds", lastMovingSeconds)
        put("stepDistance", stepDistance)
        put("stepSeconds", stepSeconds)
        put("firedCues", JSONArray().apply { for (cue in firedCues) put(cue) })
        put("paceAlerts", paceAlerts)
        put("lastAlertAt", lastAlertAt)
        put("alertedDirection", alertedDirection)
        put("results", JSONArray().apply {
            for (result in stepResults) put(result.toJson())
        })
    }.toString()

    /** Restores a snapshot after [configure] has loaded the same plan steps. */
    fun restoreStateJson(raw: String?): Boolean {
        if (raw.isNullOrBlank() || steps.isEmpty()) return false
        return try {
            val json = JSONObject(raw)
            val restoredPhase = when (json.optString("phase")) {
                "running" -> RunStepEnginePhase.running
                "done" -> RunStepEnginePhase.done
                else -> RunStepEnginePhase.idle
            }
            val restoredIndex = json.optInt("index", 0)
            if (restoredPhase == RunStepEnginePhase.running &&
                restoredIndex !in steps.indices
            ) {
                return false
            }
            phase = restoredPhase
            index = when (restoredPhase) {
                RunStepEnginePhase.done -> steps.size
                else -> restoredIndex.coerceIn(0, steps.lastIndex)
            }
            accum = json.optDouble("accum", 0.0).coerceAtLeast(0.0)
            lastDistance = json.optDouble("lastDistance", 0.0).coerceAtLeast(0.0)
            lastMovingSeconds = json.optInt("lastMovingSeconds", 0).coerceAtLeast(0)
            stepDistance = json.optDouble("stepDistance", 0.0).coerceAtLeast(0.0)
            stepSeconds = json.optInt("stepSeconds", 0).coerceAtLeast(0)
            resetStepCues()
            json.optJSONArray("firedCues")?.let { fired ->
                for (i in 0 until fired.length()) firedCues.add(fired.optInt(i))
            }
            paceAlerts = json.optInt("paceAlerts", 0)
            lastAlertAt = json.optInt("lastAlertAt", -1)
            alertedDirection = json.optInt("alertedDirection", 0)
            stepResults.clear()
            val results = json.optJSONArray("results") ?: JSONArray()
            for (i in 0 until results.length()) {
                results.optJSONObject(i)?.let {
                    stepResults.add(RunStepResultNative.fromJson(it))
                }
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Method-channel friendly live view used after Flutter reattaches. */
    fun snapshotMap(): Map<String, Any?> {
        val snap = snapshot
        val current = steps.getOrNull(snap.stepIndex)?.step
        return mapOf(
            "phase" to snap.phase.name,
            "stepIndex" to snap.stepIndex,
            "totalSteps" to snap.totalSteps,
            "role" to snap.role.name,
            "repIndex" to snap.repIndex,
            "repTotal" to snap.repTotal,
            "metric" to snap.metric.name,
            "target" to snap.target,
            "progress" to snap.progress,
            "remaining" to snap.remaining,
            "targetPaceMinSecPerKm" to current?.targetPaceMinSecPerKm,
            "targetPaceMaxSecPerKm" to current?.targetPaceMaxSecPerKm,
            "workRepsDone" to snap.workRepsDone,
            "workRepsTotal" to snap.workRepsTotal,
        ) + nextStepMap()
    }

    /** What comes after the running step, for the "up next" preview. */
    private fun nextStepMap(): Map<String, Any?> {
        val next = upcoming()
        return mapOf(
            "nextRole" to next?.step?.role?.name,
            "nextMetric" to next?.step?.metric?.name,
            "nextTarget" to next?.step?.value,
            "nextRepIndex" to next?.repIndex,
            "nextRepTotal" to next?.repTotal,
        )
    }

    /** The step being run, or null outside a running session. */
    fun current(): RunExpandedStepNative? =
        if (phase == RunStepEnginePhase.running) steps.getOrNull(index) else null

    /** The step after the running one, or null at the end. */
    fun upcoming(): RunExpandedStepNative? =
        if (phase == RunStepEnginePhase.running) steps.getOrNull(index + 1) else null

    /** The executed step at [sequence] (the event's stepIndex). */
    fun stepAt(sequence: Int): RunExpandedStepNative? = steps.getOrNull(sequence)

    /** The steps after [sequence], in order. */
    fun stepsAfter(sequence: Int): List<RunExpandedStepNative> =
        if (sequence + 1 >= steps.size) emptyList() else steps.subList(sequence + 1, steps.size)

    /**
     * How soon the running step ends: exact for timed steps, estimated from the
     * recent speed for distance steps. Null when unknown.
     */
    fun secondsToTransition(): Double? {
        val current = current() ?: return null
        val remaining = (current.step.value - accum).coerceAtLeast(0.0)
        if (current.step.metric == RunIntervalMetric.time) return remaining
        val first = samples.firstOrNull() ?: return null
        val span = stepSeconds - first.first
        val distance = stepDistance - first.second
        if (span < 5 || distance < 10) return null
        return remaining / (distance / span)
    }

    val workRepsTotal: Int get() = steps.count { it.step.role == RunStepRole.work }

    private val workRepsDone: Int
        get() = steps.take(index.coerceIn(0, steps.size)).count { it.step.role == RunStepRole.work }

    /**
     * Loads the plan. [easyEffort] marks an easy-day workout (easy, long,
     * recovery): its continuous steps only warn when the runner goes too fast.
     */
    fun configure(rawSteps: List<RunWorkoutStepNative>, easyEffort: Boolean = false) {
        steps = expand(rawSteps.filter { it.value > 0 })
        this.easyEffort = easyEffort
        reset()
    }

    fun reset() {
        phase = RunStepEnginePhase.idle
        index = 0
        accum = 0.0
        lastDistance = 0.0
        lastMovingSeconds = 0
        stepDistance = 0.0
        stepSeconds = 0
        resetStepCues()
        stepResults.clear()
    }

    private fun resetStepCues() {
        firedCues.clear()
        samples.clear()
        paceAlerts = 0
        lastAlertAt = -1
        outSince = -1
        outDirection = 0
        alertedDirection = 0
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
        lastDistance = 0.0
        lastMovingSeconds = 0
        resetStepCues()
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

        samples.addLast(stepSeconds to stepDistance)
        while (samples.size > 1 && stepSeconds - samples.first().first > PACE_WINDOW_S) samples.removeFirst()

        val remaining = current.step.value - accum
        if (remaining > 1e-6) {
            events.addAll(progressCues(current, remaining))
            paceCue(current)?.let { events.add(it) }
        }

        while (phase == RunStepEnginePhase.running &&
            (current.step.value <= 0 || accum + 1e-6 >= current.step.value)
        ) {
            val overflow = accum - current.step.value
            events.add(completedEvent(current))
            recordResult(current)
            if (index >= steps.size - 1) {
                phase = RunStepEnginePhase.done
                index = steps.size
                events.add(workoutCompletedEvent(current))
                break
            }
            val previousMetric = current.step.metric
            index++
            current = steps[index]
            accum = if (current.step.metric == previousMetric) overflow.coerceAtLeast(0.0) else 0.0
            stepDistance = 0.0
            stepSeconds = 0
            resetStepCues()
            events.add(event(RunStepEventKind.stepStarted, current))
        }
        return events
    }

    /**
     * Moves on to the next step now ("skip step"). The skipped step keeps what
     * was actually run in the results, exactly like a step that timed out.
     */
    fun skip(): List<RunStepEventNative> {
        if (phase != RunStepEnginePhase.running || index !in steps.indices) return emptyList()
        val events = mutableListOf<RunStepEventNative>()
        val current = steps[index]
        events.add(completedEvent(current))
        recordResult(current)
        if (index >= steps.size - 1) {
            phase = RunStepEnginePhase.done
            index = steps.size
            events.add(workoutCompletedEvent(current))
            return events
        }
        index++
        val next = steps[index]
        accum = 0.0
        stepDistance = 0.0
        stepSeconds = 0
        resetStepCues()
        events.add(event(RunStepEventKind.stepStarted, next))
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

    /** Halfway, "N left" and the 3-2-1 countdown, each at most once per step. */
    private fun progressCues(current: RunExpandedStepNative, remaining: Double): List<RunStepEventNative> {
        val out = mutableListOf<RunStepEventNative>()
        val step = current.step
        val target = step.value
        if (halfwayEligible(step) && accum * 2 >= target && firedCues.add(CUE_HALFWAY)) {
            out.add(event(RunStepEventKind.halfway, current))
        }
        val crossed = remainingThresholds(step).filter { remaining <= it && firedCues.add(it) }
        crossed.minOrNull()?.let { threshold ->
            out.add(
                if (step.metric == RunIntervalMetric.time) {
                    event(RunStepEventKind.timeRemainingCue, current, remainingSeconds = threshold)
                } else {
                    event(RunStepEventKind.distanceRemainingCue, current, remainingMeters = threshold)
                },
            )
        }
        if (step.metric == RunIntervalMetric.time && target >= COUNTDOWN_MIN_STEP_S) {
            var tick: Int? = null
            for (k in 3 downTo 1) {
                if (remaining <= k && firedCues.add(CUE_COUNTDOWN + k)) tick = k
            }
            tick?.let { out.add(event(RunStepEventKind.countdown, current, remainingSeconds = it)) }
        }
        return out
    }

    /**
     * Pace warning over the last [PACE_WINDOW_S] seconds. Only for effort steps
     * long enough for GPS pace to mean something, after a grace period, when
     * the drift lasts a few seconds; re-armed after a cooldown, capped per step,
     * and followed by "back on pace" once the runner corrects.
     */
    private fun paceCue(current: RunExpandedStepNative): RunStepEventNative? {
        val step = current.step
        if (!step.role.isEffort) return null
        val (fast, slow) = paceBand(step) ?: return null
        val longEnough = if (step.metric == RunIntervalMetric.time) step.value >= 60 else step.value >= 300
        if (!longEnough) return null
        val graceOver = if (step.metric == RunIntervalMetric.time) {
            stepSeconds >= (step.value * 0.25).coerceIn(20.0, 60.0)
        } else {
            stepSeconds >= 20 && stepDistance >= (step.value * 0.25).coerceIn(100.0, 400.0)
        }
        if (!graceOver) return null
        val first = samples.first()
        val span = stepSeconds - first.first
        val distance = stepDistance - first.second
        if (span < 12 || distance < 30) return null
        val pace = span / (distance / 1000.0)

        val ceilingOnly = easyEffort && step.role == RunStepRole.steady
        val direction = when {
            pace < fast -> -1
            pace > slow && !ceilingOnly -> 1
            else -> 0
        }
        if (direction == 0) {
            outSince = -1
            outDirection = 0
            if (alertedDirection != 0) {
                alertedDirection = 0
                return event(RunStepEventKind.paceBackInRange, current, paceSecPerKm = pace)
            }
            return null
        }
        if (direction != outDirection) {
            outDirection = direction
            outSince = stepSeconds
            return null
        }
        if (stepSeconds - outSince < PACE_PERSIST_S) return null
        val repeated = current.repTotal > 1
        if (paceAlerts >= (if (repeated) 2 else 5)) return null
        // Still off since the last warning (never back in range): wait longer.
        val cooldown = (if (repeated) 40 else 75) * (if (alertedDirection == direction) 2 else 1)
        if (lastAlertAt >= 0 && stepSeconds - lastAlertAt < cooldown) return null
        paceAlerts++
        lastAlertAt = stepSeconds
        alertedDirection = direction
        return event(
            if (direction > 0) RunStepEventKind.paceTooSlow else RunStepEventKind.paceTooFast,
            current,
            paceSecPerKm = pace,
        )
    }

    private fun completedEvent(current: RunExpandedStepNative) = event(
        RunStepEventKind.stepCompleted,
        current,
        stepDistanceMeters = stepDistance,
        stepDurationSeconds = stepSeconds,
    )

    private fun workoutCompletedEvent(current: RunExpandedStepNative) = RunStepEventNative(
        kind = RunStepEventKind.workoutCompleted,
        stepIndex = -1,
        totalSteps = steps.size,
        role = current.step.role,
        repIndex = current.repIndex,
        repTotal = current.repTotal,
        metric = current.step.metric,
        target = current.step.value,
    )

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
        remainingMeters: Int? = null,
        paceSecPerKm: Double? = null,
        stepDistanceMeters: Double? = null,
        stepDurationSeconds: Int? = null,
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
        remainingMeters = remainingMeters,
        paceSecPerKm = paceSecPerKm,
        stepDistanceMeters = stepDistanceMeters,
        stepDurationSeconds = stepDurationSeconds,
        targetPaceMinSecPerKm = expanded.step.targetPaceMinSecPerKm,
        targetPaceMaxSecPerKm = expanded.step.targetPaceMaxSecPerKm,
    )

    companion object {
        const val PACE_WINDOW_S = 20
        const val PACE_PERSIST_S = 6
        const val COUNTDOWN_MIN_STEP_S = 15
        private const val CUE_HALFWAY = 1_000_000
        private const val CUE_COUNTDOWN = 2_000_000

        /** Slack around a band so GPS jitter at the edge does not nag. */
        private const val BAND_SLACK = 0.015

        /**
         * The (fastest, slowest) acceptable pace of a step. A single bound is a
         * target point and gets a ±3% band.
         */
        fun paceBand(step: RunWorkoutStepNative): Pair<Double, Double>? {
            val min = step.targetPaceMinSecPerKm?.takeIf { it > 0 }
            val max = step.targetPaceMaxSecPerKm?.takeIf { it > 0 }
            val (fast, slow) = when {
                min != null && max != null -> minOf(min, max) to maxOf(min, max)
                min != null -> min * 0.97 to min * 1.03
                max != null -> max * 0.97 to max * 1.03
                else -> return null
            }
            return fast * (1 - BAND_SLACK) to slow * (1 + BAND_SLACK)
        }

        /** "N left" thresholds of a step (seconds or meters). */
        fun remainingThresholds(step: RunWorkoutStepNative): List<Int> {
            val value = step.value
            return if (step.metric == RunIntervalMetric.time) {
                when {
                    value >= 1200 -> listOf(300, 60)
                    value >= 240 -> listOf(60)
                    value > 90 -> listOf(30)
                    value >= 40 -> listOf(10)
                    else -> emptyList()
                }
            } else {
                when {
                    value >= 3000 -> listOf(1000, 200)
                    value >= 1000 -> listOf(200)
                    value >= 300 -> listOf(100)
                    else -> emptyList()
                }
            }
        }

        /** Long efforts get a "halfway" call. */
        fun halfwayEligible(step: RunWorkoutStepNative): Boolean =
            step.role.isEffort && if (step.metric == RunIntervalMetric.time) {
                step.value >= 480
            } else {
                step.value >= 1600
            }

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
