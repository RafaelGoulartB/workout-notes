package com.workoutnotes.workout_notes.sleep

import java.time.Instant
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Native copy of the Dart bedside sleep/wake model
 * (`lib/services/sleep_audio_evidence.dart`, `sleep_wake_model.dart` and the
 * causal `SleepWakeCursor` in `sleep_wake_engine.dart`).
 *
 * It exists only so the smart alarm can decide, with the app closed, whether
 * the person is stirring. The stored stage labels still come from the Dart
 * engine, which smooths the whole night. Every constant and every arithmetic
 * step mirrors the Dart code in the same order: `test/fixtures/
 * sleep_wake_parity.json` holds the Dart probabilities of the real fixture
 * nights and of a synthetic night that reaches every rule, and
 * `SleepWakeFilterParityTest` checks this class against them.
 */
class SleepWakeFilter(
    private val sessionId: String,
    startsAwake: Boolean = true,
) {
    companion object {
        private const val ALIGNMENT_TOLERANCE_MILLIS = 1_000L
    }

    data class Decision(
        val reason: String,
        val validSignal: Boolean,
        /** Probability of being asleep after this window. */
        val sleepProbability: Double,
        val movementSeconds: Double,
        val ambientSeconds: Double,
    )

    private val evidence = SleepAudioEvidenceExtractor()
    private val startProbabilities =
        if (startsAwake) SleepWakeModel.START_AWAKE else SleepWakeModel.START_UNKNOWN
    private var probabilities: DoubleArray? = null
    private var expectedStartMillis: Long? = null

    /** Current probability of being asleep; null before the first window. */
    val sleepProbability: Double?
        get() = probabilities?.let { SleepWakeModel.sleepProbability(it) }

    /** Feeds one native segment (the map spooled by [AudioSignalProcessor]). */
    fun add(segment: Map<String, Any?>): Decision {
        val startMillis = Instant.parse(segment["started_at"].toString()).toEpochMilli()
        val seconds = (segment["duration_seconds"] as? Number)?.toInt() ?: 0
        val expected = expectedStartMillis
        if (expected != null) {
            val gapMillis = startMillis - expected
            if (gapMillis > ALIGNMENT_TOLERANCE_MILLIS) {
                // Windows that never arrived: let the model drift through them.
                val steps = (gapMillis / 30_000.0).roundToInt().coerceIn(1, 480)
                repeat(steps) { step(null) }
                evidence.interrupt()
            }
        }
        expectedStartMillis = startMillis + seconds * 1_000L
        val result = evidence.evaluate(segment, sessionId, seconds)
        step(result.likelihoods)
        return Decision(
            reason = result.reason,
            validSignal = result.validSignal,
            sleepProbability = SleepWakeModel.sleepProbability(probabilities!!),
            movementSeconds = result.movementSeconds,
            ambientSeconds = result.ambientSeconds,
        )
    }

    private fun step(likelihoods: DoubleArray?) {
        val current = probabilities
        val prior = if (current == null) startProbabilities else SleepWakeModel.predict(current)
        probabilities = SleepWakeModel.update(prior, likelihoods)
    }
}

/** Mirror of `SleepWakeModel` in Dart: a 5-state HMM, one step per window. */
internal object SleepWakeModel {
    private const val STATE_COUNT = 5
    private const val ASLEEP = 4

    /** Emission group of each state: 0 active wake, 1 quiet wake, 2 sleep. */
    private val EMISSION_GROUP = intArrayOf(0, 1, 0, 1, 2)

    private val TRANSITIONS = arrayOf(
        doubleArrayOf(0.85, 0.14, 0.0, 0.0, 0.01),
        doubleArrayOf(0.02, 0.95, 0.0, 0.0, 0.03),
        doubleArrayOf(0.0, 0.0, 0.85, 0.13, 0.02),
        doubleArrayOf(0.0, 0.0, 0.04, 0.86, 0.10),
        doubleArrayOf(0.0, 0.0, 0.010, 0.004, 0.986),
    )

    val START_AWAKE = doubleArrayOf(0.7, 0.3, 0.0, 0.0, 0.0)
    val START_UNKNOWN = doubleArrayOf(0.15, 0.15, 0.1, 0.1, 0.5)

    fun predict(p: DoubleArray): DoubleArray {
        val out = DoubleArray(STATE_COUNT)
        for (i in 0 until STATE_COUNT) {
            if (p[i] == 0.0) continue
            val row = TRANSITIONS[i]
            for (j in 0 until STATE_COUNT) {
                out[j] += p[i] * row[j]
            }
        }
        return out
    }

    fun update(predicted: DoubleArray, groups: DoubleArray?): DoubleArray {
        val out = DoubleArray(STATE_COUNT) { i ->
            predicted[i] * (groups?.get(EMISSION_GROUP[i]) ?: 1.0)
        }
        return normalize(out)
    }

    private fun normalize(p: DoubleArray): DoubleArray {
        var total = 0.0
        for (v in p) total += v
        if (!total.isFinite() || total <= 0.0) {
            return DoubleArray(STATE_COUNT) { 1.0 / STATE_COUNT }
        }
        return DoubleArray(STATE_COUNT) { p[it] / total }
    }

    fun sleepProbability(p: DoubleArray): Double = p[ASLEEP]
}

/** Mirror of `SleepAudioEvidence` in Dart. */
internal class SleepAudioEvidence(
    val reason: String,
    val validSignal: Boolean,
    val likelihoods: DoubleArray?,
    val movementSeconds: Double = 0.0,
    val ambientSeconds: Double = 0.0,
)

/**
 * Mirror of `SleepAudioEvidenceExtractor` in Dart: a person next to the phone
 * raises every frequency band at once, the room (birds, traffic, rain) only
 * some. Each band is compared in dB with its own recent quiet level and the
 * window is scored by its second-smallest band excess.
 */
internal class SleepAudioEvidenceExtractor {
    companion object {
        private const val MINIMUM_VALID_FRACTION = 0.8
        private const val MAXIMUM_ZERO_SAMPLE_FRACTION = 0.98
        private val SCORE_BIN_EDGES = doubleArrayOf(4.0, 8.0, 14.0)
        private val ACTIVE_WAKE_SCORE = doubleArrayOf(0.42, 0.10, 0.15, 0.33)
        private val QUIET_WAKE_SCORE = doubleArrayOf(0.84, 0.10, 0.045, 0.015)
        private val SLEEP_SCORE = doubleArrayOf(0.86, 0.10, 0.03, 0.01)
        private val SNORING_LIKELIHOOD = doubleArrayOf(0.02, 0.04, 0.10)
        private const val FLOOR_WINDOWS = 40
        private const val MINIMUM_FLOOR_WINDOWS = 3
        private const val FLOOR_PERCENTILE = 0.2
        private const val RECENT_FLOOR_WINDOWS = 10
        private const val MINIMUM_BAND_ENERGY = 1e-18
        private const val MINIMUM_SCORED_BANDS = 4
        private const val MINIMUM_BURST_SECONDS = 1.0
        private const val RUMBLE_HIGH_SHARE = 0.02
        private const val STATIONARY_ACTIVE_FRACTION = 0.8
        private const val MINIMUM_VARIABLE_LEVEL_STDDEV_DB = 3.0
        private const val MINIMUM_REGULARITY = 0.45
        private const val MINIMUM_RATE_HZ = 0.15
        private const val MAXIMUM_RATE_HZ = 0.5
        private const val MAXIMUM_FLATNESS = 0.65
        private const val SNORING_NOISE_DB = 10.0
        private const val SNORING_LOW_SHARE = 0.6

        private val INVALID = SleepAudioEvidence("invalid_capture", false, null)
    }

    /** Recent band levels in dB, oldest first. */
    private val levels = ArrayDeque<DoubleArray>()
    private var previousSnoreLike = false

    /** Windows are missing before the next one: a snoring run does not continue. */
    fun interrupt() {
        previousSnoreLike = false
    }

    fun evaluate(segment: Map<String, Any?>, sessionId: String, seconds: Int): SleepAudioEvidence {
        val level = bandLevels(segment, sessionId, seconds)
        if (level == null) {
            previousSnoreLike = false
            return INVALID
        }
        val floor = floor()
        levels.addLast(level)
        if (levels.size > FLOOR_WINDOWS) levels.removeFirst()
        val snoreLikeBefore = previousSnoreLike
        previousSnoreLike = false

        val activity = number(segment, "noise_active_seconds")
        if (activity == null || !activity.isFinite() || activity < 0.0) {
            return SleepAudioEvidence("no_activity_measure", true, null)
        }
        val active = activity.coerceIn(0.0, seconds.toDouble())
        if (floor == null) return SleepAudioEvidence("calibrating", true, null)
        val levelStddev = number(segment, "audio_level_stddev_db")
        if (active / seconds >= STATIONARY_ACTIVE_FRACTION &&
            (levelStddev == null ||
                !levelStddev.isFinite() ||
                levelStddev < MINIMUM_VARIABLE_LEVEL_STDDEV_DB)
        ) {
            return SleepAudioEvidence("steady_background", true, null)
        }

        val silent = decibels(0.0)
        // A band whose floor is digitally silent has no level to rise from.
        val excess = (0 until 5)
            .filter { floor[it] > silent }
            .map { level[it] - floor[it] }
            .sorted()
        if (excess.size < MINIMUM_SCORED_BANDS) {
            return SleepAudioEvidence("silent_bands", true, null)
        }
        val burst = active >= MINIMUM_BURST_SECONDS
        // Judged before the score: loud snoring next to the phone reaches every band.
        val snoreLike = burst &&
            number(segment, "noise_score")!! >= SNORING_NOISE_DB &&
            periodic(segment) &&
            lowShare(level) >= SNORING_LOW_SHARE
        previousSnoreLike = snoreLike
        if (snoreLike && snoreLikeBefore) {
            return SleepAudioEvidence("snoring", true, SNORING_LIKELIHOOD)
        }
        val bin = bin(excess[1])
        if (bin < 2) {
            return SleepAudioEvidence(
                if (bin == 1) "faint_sound" else if (burst) "environmental_sound" else "quiet_audio",
                true,
                groups(bin),
                ambientSeconds = if (burst) active else 0.0,
            )
        }
        // Every band rose, but not the way a person next to the phone does it.
        if (!burst) return SleepAudioEvidence("sustained_sound", true, groups(1))
        if (addedHighShare(level, floor) < RUMBLE_HIGH_SHARE) {
            return SleepAudioEvidence("low_rumble", true, groups(1), ambientSeconds = active)
        }
        return SleepAudioEvidence(
            if (bin == 2) "movement" else "strong_movement",
            true,
            groups(bin),
            movementSeconds = active,
        )
    }

    private fun decibels(energy: Double): Double =
        10 * ln(max(energy, MINIMUM_BAND_ENERGY)) / ln(10.0)

    private fun bin(score: Double): Int {
        for (i in SCORE_BIN_EDGES.indices) {
            if (score < SCORE_BIN_EDGES[i]) return i
        }
        return SCORE_BIN_EDGES.size
    }

    private fun groups(bin: Int) = doubleArrayOf(
        ACTIVE_WAKE_SCORE[bin],
        QUIET_WAKE_SCORE[bin],
        SLEEP_SCORE[bin],
    )

    private fun periodic(segment: Map<String, Any?>): Boolean {
        val regularity = number(segment, "breathing_regularity")
        val rate = number(segment, "breathing_rate_hz")
        val flatness = number(segment, "spectral_flatness")
        return regularity != null &&
            regularity.isFinite() &&
            regularity >= MINIMUM_REGULARITY &&
            regularity <= 1.0 &&
            rate != null &&
            rate.isFinite() &&
            rate >= MINIMUM_RATE_HZ &&
            rate <= MAXIMUM_RATE_HZ &&
            flatness != null &&
            flatness.isFinite() &&
            flatness >= 0.0 &&
            flatness < MAXIMUM_FLATNESS
    }

    /** Share of the energy above the room floor that lies above 1.5 kHz. */
    private fun addedHighShare(level: DoubleArray, floor: DoubleArray): Double {
        var high = 0.0
        var all = 0.0
        for (band in 0 until 5) {
            val added = max(0.0, 10.0.pow(level[band] / 10) - 10.0.pow(floor[band] / 10))
            all += added
            if (band >= 3) high += added
        }
        return if (all > 0) high / all else 1.0
    }

    /** Share of the window's energy below 600 Hz. */
    private fun lowShare(level: DoubleArray): Double {
        val energy = DoubleArray(5) { 10.0.pow(level[it] / 10) }
        var total = 0.0
        for (v in energy) total += v
        return if (total > 0) (energy[0] + energy[1]) / total else 0.0
    }

    /** Band levels in dB of a usable window, null for a capture failure. */
    private fun bandLevels(segment: Map<String, Any?>, sessionId: String, seconds: Int): DoubleArray? {
        val noise = number(segment, "noise_score")
        val bands = Array(5) { number(segment, "spectral_band_energy_$it") }
        val zeros = number(segment, "digital_silence_fraction")
        val validFraction = number(segment, "valid_fraction")
        val calibrated = segment["audio_calibrated"] as? Boolean
        val valid = segment["session_id"]?.toString() == sessionId &&
            seconds > 0 &&
            seconds <= 60 &&
            segment["classification"]?.toString() != "invalid" &&
            validFraction != null &&
            validFraction.isFinite() &&
            validFraction >= MINIMUM_VALID_FRACTION &&
            validFraction <= 1.0 &&
            calibrated != false &&
            (zeros == null ||
                (zeros.isFinite() && zeros >= 0.0 && zeros < MAXIMUM_ZERO_SAMPLE_FRACTION)) &&
            noise != null &&
            noise.isFinite() &&
            noise >= 0.0 &&
            bands.all { it != null && it.isFinite() && it >= 0.0 }
        if (!valid) return null
        val energy = DoubleArray(5) { bands[it]!! / seconds }
        var total = 0.0
        for (v in energy) total += v
        if (!total.isFinite() || total <= 0.0) return null
        return DoubleArray(5) { decibels(energy[it]) }
    }

    /**
     * The room's quiet level per band, from the windows before this one: a low
     * percentile of the last 20 minutes, or the lowest level of the last five
     * when that is higher (a room sound that has just started).
     */
    private fun floor(): DoubleArray? {
        val count = levels.size
        if (count < MINIMUM_FLOOR_WINDOWS) return null
        val index = floor(count * FLOOR_PERCENTILE).toInt()
        return DoubleArray(5) { band ->
            val percentile = levels.map { it[band] }.sorted()[index]
            if (count < RECENT_FLOOR_WINDOWS) {
                percentile
            } else {
                var lowest = Double.POSITIVE_INFINITY
                for (i in count - RECENT_FLOOR_WINDOWS until count) {
                    lowest = min(lowest, levels[i][band])
                }
                max(percentile, lowest)
            }
        }
    }

    private fun number(segment: Map<String, Any?>, key: String): Double? =
        (segment[key] as? Number)?.toDouble()
}
