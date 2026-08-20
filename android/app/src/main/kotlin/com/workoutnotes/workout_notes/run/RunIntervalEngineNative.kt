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
) {
    val isActive: Boolean get() = phase == RunIntervalPhase.work || phase == RunIntervalPhase.rest
}

enum class RunIntervalEventKind { workStarted, restStarted, completed, timeRemainingCue }

data class RunIntervalEvent(
    val kind: RunIntervalEventKind,
    val workIndex: Int,
    val totalWorks: Int,
    val remainingSeconds: Int? = null,
)

/**
 * Pure work/rest FSM — Kotlin port of lib/services/run_interval_engine.dart.
 */
class RunIntervalEngineNative(
    private var preset: RunIntervalPreset = RunIntervalPreset(),
) {
    private var phase: RunIntervalPhase = RunIntervalPhase.idle
    private var workIndex: Int = 0
    private var phaseAccum: Double = 0.0
    private var remainingCueSpoken: Boolean = false
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
            )
        }

    fun start(): List<RunIntervalEvent> {
        resetAccumulators()
        workIndex = 1
        phase = RunIntervalPhase.work
        phaseAccum = 0.0
        remainingCueSpoken = false
        return listOf(RunIntervalEvent(RunIntervalEventKind.workStarted, workIndex, preset.repeats))
    }

    fun reset() {
        phase = RunIntervalPhase.idle
        workIndex = 0
        phaseAccum = 0.0
        remainingCueSpoken = false
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

        if (metric == RunIntervalMetric.distance) {
            phaseAccum += distanceDelta
        } else {
            phaseAccum += timeDelta.toDouble()
        }

        if (metric == RunIntervalMetric.time && !remainingCueSpoken && target > 30) {
            val remaining = target - phaseAccum
            if (remaining <= 30 && remaining > 0) {
                remainingCueSpoken = true
                events.add(RunIntervalEvent(RunIntervalEventKind.timeRemainingCue, workIndex, preset.repeats, 30))
            }
        }

        if (target <= 0 || phaseAccum + 1e-6 >= target) {
            events.addAll(advancePhase())
        }
        return events
    }

    private fun advancePhase(): List<RunIntervalEvent> {
        val events = mutableListOf<RunIntervalEvent>()
        if (phase == RunIntervalPhase.work) {
            if (workIndex >= preset.repeats) {
                phase = RunIntervalPhase.done
                phaseAccum = 0.0
                events.add(RunIntervalEvent(RunIntervalEventKind.completed, workIndex, preset.repeats))
                return events
            }
            if (preset.restValue <= 0) {
                workIndex += 1
                phase = RunIntervalPhase.work
                phaseAccum = 0.0
                remainingCueSpoken = false
                events.add(RunIntervalEvent(RunIntervalEventKind.workStarted, workIndex, preset.repeats))
                return events
            }
            phase = RunIntervalPhase.rest
            phaseAccum = 0.0
            remainingCueSpoken = false
            events.add(RunIntervalEvent(RunIntervalEventKind.restStarted, workIndex, preset.repeats))
            return events
        }
        // rest finished
        if (workIndex >= preset.repeats) {
            phase = RunIntervalPhase.done
            phaseAccum = 0.0
            events.add(RunIntervalEvent(RunIntervalEventKind.completed, workIndex, preset.repeats))
            return events
        }
        workIndex += 1
        phase = RunIntervalPhase.work
        phaseAccum = 0.0
        remainingCueSpoken = false
        events.add(RunIntervalEvent(RunIntervalEventKind.workStarted, workIndex, preset.repeats))
        return events
    }

    private fun resetAccumulators() {
        phaseAccum = 0.0
        remainingCueSpoken = false
        lastDistance = 0.0
        lastMovingSeconds = 0
    }
}
