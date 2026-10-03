package com.workoutnotes.workout_notes.run

enum class RunIntervalPhase { idle, work, rest, done }

data class RunIntervalSnapshot(
    val phase: RunIntervalPhase = RunIntervalPhase.idle,
    val workIndex: Int = 0,
    val totalWorks: Int = 0,
    val progress: Double = 0.0,
    val remaining: Double = 0.0,
    val currentMetric: RunIntervalMetric = RunIntervalMetric.distance,
    val currentTarget: Int = 0,
    /** What follows the running phase ("up next" preview); null when the set ends here. */
    val nextPhase: RunIntervalPhase? = null,
    val nextMetric: RunIntervalMetric? = null,
    val nextTarget: Int? = null,
) {
    val isActive: Boolean get() = phase == RunIntervalPhase.work || phase == RunIntervalPhase.rest

    /** Wire shape read by `RunIntervalSnapshot.fromMap` in Dart. */
    fun toMap(): Map<String, Any?> = mapOf(
        "phase" to phase.name,
        "workIndex" to workIndex,
        "totalWorks" to totalWorks,
        "progress" to progress,
        "remaining" to remaining,
        "metric" to currentMetric.name,
        "target" to currentTarget,
        "nextPhase" to nextPhase?.name,
        "nextMetric" to nextMetric?.name,
        "nextTarget" to nextTarget,
    )
}

enum class RunIntervalEventKind {
    workStarted,
    restStarted,
    completed,
    timeRemainingCue,
    distanceRemainingCue,

    /** One tick of the 3-2-1 countdown before a timed phase ends. */
    countdown,
}

data class RunIntervalEvent(
    val kind: RunIntervalEventKind,
    val workIndex: Int,
    val totalWorks: Int,
    val remainingSeconds: Int? = null,
    val remainingMeters: Int? = null,
    /** The work phase that just ended ([RunIntervalEventKind.restStarted], next work, completed). */
    val lastWorkSeconds: Int? = null,
    val lastWorkMeters: Double? = null,
)

/**
 * Pure work/rest FSM behind the quick "intervals" toggle. Its snapshot reaches
 * Dart as `interval_snapshot` in the tracking state.
 */
class RunIntervalEngineNative(
    private var preset: RunIntervalPreset = RunIntervalPreset(),
) {
    private companion object {
        const val COUNTDOWN = 2_000_000
    }

    /** Seconds until the running phase ends, when it is timed. */
    fun secondsToTransition(): Double? {
        if (phase != RunIntervalPhase.work && phase != RunIntervalPhase.rest) return null
        val metric = if (phase == RunIntervalPhase.work) preset.workMetric else preset.restMetric
        if (metric != RunIntervalMetric.time) return null
        val target = if (phase == RunIntervalPhase.work) preset.workValue else preset.restValue
        return (target - phaseAccum).coerceAtLeast(0.0)
    }

    val currentPreset: RunIntervalPreset get() = preset

    private var phase: RunIntervalPhase = RunIntervalPhase.idle
    private var workIndex: Int = 0
    private var phaseAccum: Double = 0.0
    private val firedCues = mutableSetOf<Int>()
    private var phaseSeconds: Int = 0
    private var phaseMeters: Double = 0.0
    private var lastDistance: Double = 0.0
    private var lastMovingSeconds: Int = 0

    fun configure(preset: RunIntervalPreset) {
        this.preset = preset
    }

    val snapshot: RunIntervalSnapshot
        get() {
            if (phase == RunIntervalPhase.idle || phase == RunIntervalPhase.done) {
                return RunIntervalSnapshot(
                    phase = phase,
                    workIndex = workIndex,
                    totalWorks = preset.repeats,
                    progress = if (phase == RunIntervalPhase.done) 1.0 else 0.0,
                    remaining = 0.0,
                    currentMetric = RunIntervalMetric.distance,
                    currentTarget = 0,
                )
            }
            val metric = if (phase == RunIntervalPhase.work) preset.workMetric else preset.restMetric
            val target = (if (phase == RunIntervalPhase.work) preset.workValue else preset.restValue).toDouble()
            val progress = if (target <= 0) 1.0 else (phaseAccum / target).coerceIn(0.0, 1.0)
            return RunIntervalSnapshot(
                phase = phase,
                workIndex = workIndex,
                totalWorks = preset.repeats,
                progress = progress,
                remaining = (target - phaseAccum).coerceIn(0.0, target),
                currentMetric = metric,
                currentTarget = target.toInt(),
                nextPhase = nextPhase(),
                nextMetric = nextPhase()?.let { if (it == RunIntervalPhase.work) preset.workMetric else preset.restMetric },
                nextTarget = nextPhase()?.let { if (it == RunIntervalPhase.work) preset.workValue else preset.restValue },
            )
        }

    private fun nextPhase(): RunIntervalPhase? = when (phase) {
        RunIntervalPhase.work -> when {
            workIndex >= preset.repeats -> null
            preset.restValue > 0 -> RunIntervalPhase.rest
            else -> RunIntervalPhase.work
        }
        RunIntervalPhase.rest -> if (workIndex >= preset.repeats) null else RunIntervalPhase.work
        else -> null
    }

    fun start(): List<RunIntervalEvent> {
        resetAccumulators()
        workIndex = 1
        phase = RunIntervalPhase.work
        phaseAccum = 0.0
        resetPhase()
        return listOf(RunIntervalEvent(RunIntervalEventKind.workStarted, workIndex, preset.repeats))
    }

    fun reset() {
        phase = RunIntervalPhase.idle
        workIndex = 0
        phaseAccum = 0.0
        resetPhase()
        lastDistance = 0.0
        lastMovingSeconds = 0
    }

    fun tick(recording: Boolean, distanceMeters: Double, movingTimeSeconds: Int): List<RunIntervalEvent> {
        if (phase == RunIntervalPhase.idle || phase == RunIntervalPhase.done) {
            lastDistance = distanceMeters
            lastMovingSeconds = movingTimeSeconds
            return emptyList()
        }
        val distanceDelta = (distanceMeters - lastDistance).coerceAtLeast(0.0)
        val timeDelta = (movingTimeSeconds - lastMovingSeconds).coerceIn(0, 3600)
        lastDistance = distanceMeters
        lastMovingSeconds = movingTimeSeconds
        if (!recording) return emptyList()

        val events = mutableListOf<RunIntervalEvent>()
        val metric = if (phase == RunIntervalPhase.work) preset.workMetric else preset.restMetric
        val target = (if (phase == RunIntervalPhase.work) preset.workValue else preset.restValue).toDouble()

        phaseSeconds += timeDelta
        phaseMeters += distanceDelta
        if (metric == RunIntervalMetric.distance) {
            phaseAccum += distanceDelta
        } else {
            phaseAccum += timeDelta.toDouble()
        }

        val remaining = target - phaseAccum
        if (remaining > 1e-6) {
            val step = RunWorkoutStepNative(
                role = if (phase == RunIntervalPhase.work) RunStepRole.work else RunStepRole.recovery,
                metric = metric,
                value = target.toInt(),
            )
            val crossed = RunWorkoutStepEngineNative.remainingThresholds(step)
                .filter { remaining <= it && firedCues.add(it) }
            crossed.minOrNull()?.let { threshold ->
                events.add(
                    if (metric == RunIntervalMetric.time) {
                        RunIntervalEvent(RunIntervalEventKind.timeRemainingCue, workIndex, preset.repeats, remainingSeconds = threshold)
                    } else {
                        RunIntervalEvent(RunIntervalEventKind.distanceRemainingCue, workIndex, preset.repeats, remainingMeters = threshold)
                    },
                )
            }
            if (metric == RunIntervalMetric.time && target >= RunWorkoutStepEngineNative.COUNTDOWN_MIN_STEP_S) {
                var tick: Int? = null
                for (k in 3 downTo 1) {
                    if (remaining <= k && firedCues.add(COUNTDOWN + k)) tick = k
                }
                tick?.let {
                    events.add(RunIntervalEvent(RunIntervalEventKind.countdown, workIndex, preset.repeats, remainingSeconds = it))
                }
            }
        }

        if (target <= 0 || phaseAccum + 1e-6 >= target) {
            events.addAll(advancePhase())
        }
        return events
    }

    /** Ends the current work/rest phase now ("skip step"). */
    fun skip(): List<RunIntervalEvent> {
        if (phase != RunIntervalPhase.work && phase != RunIntervalPhase.rest) return emptyList()
        return advancePhase()
    }

    private fun advancePhase(): List<RunIntervalEvent> {
        val events = mutableListOf<RunIntervalEvent>()
        if (phase == RunIntervalPhase.work) {
            val workSeconds = phaseSeconds
            val workMeters = phaseMeters
            fun withResult(kind: RunIntervalEventKind) = RunIntervalEvent(
                kind,
                workIndex,
                preset.repeats,
                lastWorkSeconds = workSeconds,
                lastWorkMeters = workMeters,
            )
            if (workIndex >= preset.repeats) {
                phase = RunIntervalPhase.done
                phaseAccum = 0.0
                resetPhase()
                events.add(withResult(RunIntervalEventKind.completed))
                return events
            }
            if (preset.restValue <= 0) {
                workIndex += 1
                phase = RunIntervalPhase.work
                phaseAccum = 0.0
                resetPhase()
                events.add(withResult(RunIntervalEventKind.workStarted).copy(workIndex = workIndex))
                return events
            }
            phase = RunIntervalPhase.rest
            phaseAccum = 0.0
            resetPhase()
            events.add(withResult(RunIntervalEventKind.restStarted))
            return events
        }
        // rest finished
        if (workIndex >= preset.repeats) {
            phase = RunIntervalPhase.done
            phaseAccum = 0.0
            resetPhase()
            events.add(RunIntervalEvent(RunIntervalEventKind.completed, workIndex, preset.repeats))
            return events
        }
        workIndex += 1
        phase = RunIntervalPhase.work
        phaseAccum = 0.0
        resetPhase()
        events.add(RunIntervalEvent(RunIntervalEventKind.workStarted, workIndex, preset.repeats))
        return events
    }

    private fun resetPhase() {
        firedCues.clear()
        phaseSeconds = 0
        phaseMeters = 0.0
    }

    private fun resetAccumulators() {
        phaseAccum = 0.0
        resetPhase()
        lastDistance = 0.0
        lastMovingSeconds = 0
    }
}
