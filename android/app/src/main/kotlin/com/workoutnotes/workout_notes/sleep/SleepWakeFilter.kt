package com.workoutnotes.workout_notes.sleep

import java.time.Instant
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

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
 * nights and `SleepWakeFilterParityTest` checks this class against them.
 */
class SleepWakeFilter(
    private val sessionId: String,
    startsAwake: Boolean = true,
    featureVersion: String? = CURRENT_FEATURE_VERSION,
) {
    companion object {
        const val CURRENT_FEATURE_VERSION = "audio-features-v5"
        private val BAND_LIMITED_BREATHING_VERSIONS = setOf("audio-features-v5")
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

    private val evidence = SleepAudioEvidenceExtractor(
        bandLimitedBreathing = featureVersion in BAND_LIMITED_BREATHING_VERSIONS,
    )
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

/** Mirror of `SleepAudioEvidenceExtractor` in Dart. */
internal class SleepAudioEvidenceExtractor(private val bandLimitedBreathing: Boolean) {
    companion object {
        private const val MINIMUM_VALID_FRACTION = 0.8
        private const val MAXIMUM_ZERO_SAMPLE_FRACTION = 0.98
        private val ACTIVITY_BIN_EDGES = doubleArrayOf(1.0, 3.0, 10.0, 20.0)
        private val ACTIVE_WAKE_ACTIVITY = doubleArrayOf(0.20, 0.12, 0.25, 0.20, 0.23)
        private val QUIET_WAKE_ACTIVITY = doubleArrayOf(0.785, 0.105, 0.08, 0.02, 0.01)
        private val SLEEP_ACTIVITY = doubleArrayOf(0.80, 0.10, 0.07, 0.02, 0.01)
        private val PERIODIC_BREATHING = doubleArrayOf(0.06, 0.12, 0.15)
        private const val PERIODIC_BASELINE = 0.12
        private val SNORING_LIKELIHOOD = doubleArrayOf(0.002, 0.002, 0.05)
        private const val MINIMUM_REGULARITY = 0.45
        private const val MINIMUM_RATE_HZ = 0.15
        private const val MAXIMUM_RATE_HZ = 0.65
        private const val MAXIMUM_FLATNESS = 0.65
        private const val LOUD_ACTIVITY_NOISE_DB = 10.0
        private const val STATIONARY_ACTIVE_FRACTION = 0.8
        private const val MINIMUM_VARIABLE_LEVEL_STDDEV_DB = 3.0
        private const val SNORING_LOW_SHARE = 0.6
        private const val ENVIRONMENTAL_LOW_BAND_FRACTION = 0.9
        private const val ENVIRONMENTAL_HIGH_BAND_FRACTION = 0.7
        private const val MAXIMUM_ENVIRONMENTAL_PROMINENCE_DB = 30.0
        private const val MAXIMUM_ENVIRONMENTAL_EXCESS_RATIO = 10.0
        private const val MAXIMUM_ENVIRONMENTAL_NOISE_DB = 15.0
        private const val MINIMUM_FOREGROUND_EXCESS_RATIO = 0.5
        private const val ENVIRONMENTAL_HIGH_EXCESS_SHARE = 0.8
        private const val ENVIRONMENTAL_RUMBLE_EXCESS_SHARE = 0.9
        private const val FLOOR_WINDOWS = 40
        private const val MINIMUM_FLOOR_WINDOWS = 10
        private const val FLOOR_PERCENTILE = 0.2

        private val INVALID = SleepAudioEvidence("invalid_capture", false, null)
    }

    private class Excess(val bands: DoubleArray, val total: Double, val ratio: Double)

    private val floorHistory = ArrayDeque<DoubleArray>()

    fun evaluate(segment: Map<String, Any?>, sessionId: String, seconds: Int): SleepAudioEvidence {
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
        if (!valid) return INVALID
        val energy = DoubleArray(5) { bands[it]!! / seconds }
        var total = 0.0
        for (v in energy) total += v
        if (!total.isFinite() || total <= 0.0) return INVALID

        val excess = excessOverFloor(energy)
        remember(energy)

        val activity = number(segment, "noise_active_seconds")
        if (activity == null || !activity.isFinite() || activity < 0.0) {
            return SleepAudioEvidence("no_activity_measure", true, null)
        }
        val active = activity.coerceIn(0.0, seconds.toDouble())
        val per30 = active * 30 / seconds
        val bin = bin(per30)
        val high = (energy[3] + energy[4]) / total
        val regularity = number(segment, "breathing_regularity")
        val rate = number(segment, "breathing_rate_hz")
        val flatness = number(segment, "spectral_flatness")
        val periodic = regularity != null &&
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

        if (bin == 0) {
            val quiet = groups(0)
            if (periodic && (bandLimitedBreathing || high < 0.4)) {
                return SleepAudioEvidence(
                    "periodic_breathing",
                    true,
                    DoubleArray(3) { quiet[it] * PERIODIC_BREATHING[it] / PERIODIC_BASELINE },
                )
            }
            return SleepAudioEvidence("quiet_audio", true, quiet)
        }

        if (isEnvironmental(segment, noise, energy, total, excess)) {
            return SleepAudioEvidence(
                "environmental_sound",
                true,
                groups(0).map { sqrt(it) }.toDoubleArray(),
                ambientSeconds = active,
            )
        }
        val levelStddev = number(segment, "audio_level_stddev_db")
        if (active / seconds >= STATIONARY_ACTIVE_FRACTION &&
            (levelStddev == null ||
                !levelStddev.isFinite() ||
                levelStddev < MINIMUM_VARIABLE_LEVEL_STDDEV_DB)
        ) {
            return SleepAudioEvidence("steady_background", true, null)
        }
        val lowShare = if (excess != null && excess.total > 0) {
            (excess.bands[0] + excess.bands[1]) / excess.total
        } else {
            (energy[0] + energy[1]) / total
        }
        if (periodic && noise >= LOUD_ACTIVITY_NOISE_DB && lowShare >= SNORING_LOW_SHARE) {
            return SleepAudioEvidence("snoring", true, SNORING_LIKELIHOOD)
        }
        val likelihoods = groups(bin)
        if (noise >= LOUD_ACTIVITY_NOISE_DB) {
            return SleepAudioEvidence(
                "audio_activity",
                true,
                likelihoods,
                movementSeconds = active,
            )
        }
        return SleepAudioEvidence(
            "soft_audio_activity",
            true,
            likelihoods.map { sqrt(it) }.toDoubleArray(),
            movementSeconds = active,
        )
    }

    private fun bin(activeSecondsPer30: Double): Int {
        for (i in ACTIVITY_BIN_EDGES.indices) {
            if (activeSecondsPer30 < ACTIVITY_BIN_EDGES[i]) return i
        }
        return ACTIVITY_BIN_EDGES.size
    }

    private fun groups(bin: Int) = doubleArrayOf(
        ACTIVE_WAKE_ACTIVITY[bin],
        QUIET_WAKE_ACTIVITY[bin],
        SLEEP_ACTIVITY[bin],
    )

    private fun isEnvironmental(
        segment: Map<String, Any?>,
        noise: Double,
        energy: DoubleArray,
        total: Double,
        excess: Excess?,
    ): Boolean {
        val peak = number(segment, "audio_peak_dbfs")
        val floor = number(segment, "audio_baseline_dbfs")
        if (peak != null &&
            floor != null &&
            peak.isFinite() &&
            floor.isFinite() &&
            peak - floor < MAXIMUM_ENVIRONMENTAL_PROMINENCE_DB &&
            (energy[0] / total >= ENVIRONMENTAL_LOW_BAND_FRACTION ||
                (energy[3] + energy[4]) / total >= ENVIRONMENTAL_HIGH_BAND_FRACTION)
        ) {
            return true
        }
        if (excess == null || noise >= MAXIMUM_ENVIRONMENTAL_NOISE_DB) return false
        if (excess.ratio < MINIMUM_FOREGROUND_EXCESS_RATIO) return true
        if (excess.ratio >= MAXIMUM_ENVIRONMENTAL_EXCESS_RATIO) return false
        return (excess.bands[3] + excess.bands[4]) / excess.total >=
            ENVIRONMENTAL_HIGH_EXCESS_SHARE ||
            excess.bands[0] / excess.total >= ENVIRONMENTAL_RUMBLE_EXCESS_SHARE
    }

    private fun excessOverFloor(energy: DoubleArray): Excess? {
        if (floorHistory.size < MINIMUM_FLOOR_WINDOWS) return null
        val floor = DoubleArray(5)
        for (band in 0 until 5) {
            val values = floorHistory.map { it[band] }.sorted()
            floor[band] = values[floor(values.size * FLOOR_PERCENTILE).toInt()]
        }
        var floorTotal = 0.0
        for (v in floor) floorTotal += v
        if (floorTotal <= 0.0) return null
        val bands = DoubleArray(5) { max(0.0, energy[it] - floor[it]) }
        var total = 0.0
        for (v in bands) total += v
        return Excess(bands, total, total / floorTotal)
    }

    private fun remember(energy: DoubleArray) {
        floorHistory.addLast(energy)
        if (floorHistory.size > FLOOR_WINDOWS) floorHistory.removeFirst()
    }

    private fun number(segment: Map<String, Any?>, key: String): Double? =
        (segment[key] as? Number)?.toDouble()
}
