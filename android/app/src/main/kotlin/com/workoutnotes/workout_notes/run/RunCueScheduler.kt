package com.workoutnotes.workout_notes.run

/**
 * Priority of a spoken cue.
 *
 * - [critical]: what to do now (step changes, last rep, goal or workout done).
 *   Spoken at once; several in the same tick are merged into one utterance.
 * - [high]: actionable feedback (pace corrections, time left, next rep).
 * - [normal]: progress (distance/time cues, rep results, goal progress).
 * - [low]: status (GPS, auto-pause in voice).
 */
enum class RunCuePriority { critical, high, normal, low }

/** Short tones played instead of (or before) words. */
enum class RunEarcon {
    /** One tick of the 3-2-1 countdown before a step change. */
    countdown,

    /** Into an effort: run now. */
    go,

    /** Into an easy part: recover, cool down. */
    ease,

    /** Workout or goal complete. */
    done,

    /** Auto-pause began. */
    pause,

    /** Auto-pause ended. */
    resume,
}

/** Vibration patterns that mirror the earcons. */
enum class RunHapticPattern { tick, go, ease, done }

data class RunCue(
    val text: String,
    val priority: RunCuePriority,
    /** Same-kind cues replace each other while queued (a newer split wins). */
    val kind: String,
    val createdAtMillis: Long,
    /** A cue older than this is dropped instead of being said late. */
    val ttlMillis: Long = defaultTtl(priority),
    val earcon: RunEarcon? = null,
    val haptic: RunHapticPattern? = null,
) {
    fun expired(now: Long): Boolean = now - createdAtMillis > ttlMillis

    companion object {
        fun defaultTtl(priority: RunCuePriority): Long = when (priority) {
            RunCuePriority.critical -> 15_000
            RunCuePriority.high -> 8_000
            RunCuePriority.normal -> 25_000
            RunCuePriority.low -> 30_000
        }
    }
}

/**
 * Decides which queued cue is spoken and when, so the coach never floods the
 * runner (or their music) with talk:
 *
 * - critical cues go out immediately, merged when several arrive together;
 * - other cues wait for a gap after the previous utterance, and lower ones are
 *   capped to a few per two minutes ([budgetPerWindow]);
 * - normal/low cues are held back while a step change is imminent, so a split
 *   never talks over "Rep 4, go";
 * - a cue waits instead of being lost when it collides with another, but is
 *   dropped once stale.
 *
 * Pure and clock-driven, so it is unit tested without Android.
 */
class RunCueScheduler(var budgetPerWindow: Int = 4) {

    private val queue = mutableListOf<RunCue>()
    private var lastSpokenEndsAt = NEVER
    private val spokenNonCritical = ArrayDeque<Long>()

    /** Speech rate multiplier used to estimate how long an utterance lasts. */
    var speechRate: Float = 1.0f

    fun reset() {
        queue.clear()
        lastSpokenEndsAt = NEVER
        spokenNonCritical.clear()
    }

    val pending: List<RunCue> get() = queue.toList()

    fun offer(cue: RunCue) {
        if (cue.text.isBlank()) return
        queue.removeAll { it.kind == cue.kind && it.priority != RunCuePriority.critical }
        queue.add(cue)
    }

    /** Drops queued cues of [kind] (e.g. a pace warning that no longer applies). */
    fun cancel(kind: String) {
        queue.removeAll { it.kind == kind }
    }

    /**
     * The next cue to speak now, or null. [secondsToTransition] is how soon the
     * current step ends (null when unknown or not in a structured session).
     */
    fun next(now: Long, secondsToTransition: Double? = null): RunCue? {
        queue.removeAll { it.expired(now) }
        if (queue.isEmpty()) return null

        val critical = queue.filter { it.priority == RunCuePriority.critical }
        if (critical.isNotEmpty()) {
            queue.removeAll(critical)
            val merged = if (critical.size == 1) critical.first() else critical.first().copy(
                text = critical.joinToString(" ") { it.text },
                earcon = critical.firstNotNullOfOrNull { it.earcon },
                haptic = critical.firstNotNullOfOrNull { it.haptic },
            )
            markSpoken(merged, now)
            return merged
        }

        while (spokenNonCritical.isNotEmpty() && now - spokenNonCritical.first() > BUDGET_WINDOW_MS) {
            spokenNonCritical.removeFirst()
        }
        val imminent = secondsToTransition != null && secondsToTransition <= QUIET_BEFORE_TRANSITION_S
        val candidate = queue
            .sortedWith(compareBy<RunCue> { it.priority.ordinal }.thenBy { it.createdAtMillis })
            .firstOrNull { cue ->
                val gap = when (cue.priority) {
                    RunCuePriority.high -> HIGH_GAP_MS
                    RunCuePriority.normal -> NORMAL_GAP_MS
                    else -> LOW_GAP_MS
                }
                val quietOk = !(imminent && cue.priority >= RunCuePriority.normal)
                val budgetOk = cue.priority == RunCuePriority.high ||
                    spokenNonCritical.size < budgetPerWindow
                quietOk && budgetOk && now - lastSpokenEndsAt >= gap
            } ?: return null
        queue.remove(candidate)
        markSpoken(candidate, now)
        if (candidate.priority != RunCuePriority.high) spokenNonCritical.addLast(now)
        return candidate
    }

    private fun markSpoken(cue: RunCue, now: Long) {
        lastSpokenEndsAt = now + estimatedDurationMillis(cue.text, speechRate)
    }

    companion object {
        const val HIGH_GAP_MS = 3_000L
        const val NORMAL_GAP_MS = 12_000L
        const val LOW_GAP_MS = 20_000L
        const val BUDGET_WINDOW_MS = 120_000L
        const val QUIET_BEFORE_TRANSITION_S = 12.0
        private const val NEVER = Long.MIN_VALUE / 4

        /** About 2.7 words per second at rate 1.0, plus engine start-up. */
        fun estimatedDurationMillis(text: String, rate: Float = 1.0f): Long {
            val words = text.trim().split(Regex("\\s+")).count { it.isNotEmpty() }
            val safeRate = rate.coerceIn(0.5f, 2.0f)
            return (words * 370 / safeRate).toLong() + 300L
        }
    }
}
