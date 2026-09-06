package com.workoutnotes.workout_notes.sleep

import kotlin.math.abs

/**
 * Estimates breathing regularity and rate from the slow amplitude envelope.
 *
 * A 0.5-second hop boxcar mean low-passes the audio to ~1 Hz, isolating the
 * breathing/snore amplitude modulation (0.15-1.0 Hz) from speech energy. The
 * normalized autocorrelation peak over plausible breath-period lags yields the
 * regularity score; its argmax maps to breaths per second.
 */
class BreathingAnalyzer(private val sampleRate: Int = 16_000) {
    companion object {
        const val HOP_SAMPLES = 8_000 // 0.5 s at 16 kHz
        const val MIN_LAG = 2 // 1.0 s -> 1.0 Hz ceiling
        const val MAX_LAG = 13 // 6.5 s -> 0.154 Hz floor
    }

    private val envelope = mutableListOf<Double>()
    private var envelopeSum = 0.0
    private var hopBuffer = 0.0
    private var hopSamples = 0
    private val hopSize = sampleRate / 2

    fun add(samples: ShortArray, length: Int) {
        var index = 0
        while (index < length) {
            val take = minOf(hopSize - hopSamples, length - index)
            var sum = 0.0
            for (i in 0 until take) {
                sum += abs(samples[index + i].toDouble() / Short.MAX_VALUE)
            }
            hopBuffer += sum
            hopSamples += take
            index += take
            if (hopSamples >= hopSize) {
                envelope.add(hopBuffer / hopSize)
                envelopeSum += envelope.last()
                hopBuffer = 0.0
                hopSamples = 0
            }
        }
    }

    /** Returns (regularity, rate_hz); (0.0, 0.0) on silence or insufficient data. */
    fun snapshot(): Pair<Double, Double> {
        if (envelope.size < MIN_LAG + 2) {
            reset()
            return 0.0 to 0.0
        }
        val count = envelope.size
        val mean = envelopeSum / count
        var variance = 0.0
        for (value in envelope) {
            val diff = value - mean
            variance += diff * diff
        }
        variance /= count
        if (variance < 1e-9) {
            reset()
            return 0.0 to 0.0
        }
        var bestRho = -1.0
        var bestLag = MIN_LAG
        for (lag in MIN_LAG..minOf(MAX_LAG, count - 1)) {
            var numerator = 0.0
            for (i in 0 until count - lag) {
                numerator += (envelope[i] - mean) * (envelope[i + lag] - mean)
            }
            val denominator = (count - lag) * variance
            val rho = if (denominator > 0.0) numerator / denominator else 0.0
            if (rho > bestRho) {
                bestRho = rho
                bestLag = lag
            }
        }
        val rateHz = 1.0 / (bestLag * hopSize / sampleRate.toDouble())
        val regularity = bestRho.coerceIn(0.0, 1.0)
        reset()
        return regularity to rateHz
    }

    private fun reset() {
        envelope.clear()
        envelopeSum = 0.0
        hopBuffer = 0.0
        hopSamples = 0
    }
}
