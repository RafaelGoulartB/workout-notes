package com.workoutnotes.workout_notes.sleep

import kotlin.math.abs
import kotlin.math.ln

/**
 * Estimates breathing regularity and rate from the slow amplitude envelope.
 *
 * A 0.5-second hop boxcar mean low-passes the audio to ~1 Hz, isolating the
 * breathing/snore amplitude modulation (0.15-1.0 Hz) from speech energy. The
 * envelope is taken in the log domain (a single loud sound must not dominate
 * the variance) and linearly detrended. Regularity is the normalized
 * autocorrelation at a true local peak inside the plausible breath-period
 * lags; a slowly drifting envelope decays monotonically with lag and has no
 * such peak, so it no longer reads as regular 1 Hz "breathing".
 */
class BreathingAnalyzer(private val sampleRate: Int = 16_000) {
    companion object {
        const val MIN_LAG = 2 // 1.0 s -> 1.0 Hz ceiling
        const val MAX_LAG = 13 // 6.5 s -> 0.154 Hz floor
        private const val LOG_FLOOR = 1e-6
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

    /** Returns (regularity, rate_hz); (0.0, 0.0) on silence, insufficient data or no periodic peak. */
    fun snapshot(): Pair<Double, Double> {
        val count = envelope.size
        // A peak at lag L needs L + 1 to be evaluated as its right neighbour.
        if (count < MIN_LAG + 3) {
            reset()
            return 0.0 to 0.0
        }
        val linearMean = envelopeSum / count
        var linearVariance = 0.0
        for (value in envelope) {
            val diff = value - linearMean
            linearVariance += diff * diff
        }
        if (linearVariance / count < 1e-9) {
            reset()
            return 0.0 to 0.0
        }
        val residual = detrendedLog(envelope)
        var variance = 0.0
        for (value in residual) variance += value * value
        variance /= count
        if (variance <= 0.0) {
            reset()
            return 0.0 to 0.0
        }
        val maxLag = minOf(MAX_LAG + 1, count - 1)
        val rho = DoubleArray(maxLag + 1)
        for (lag in MIN_LAG - 1..maxLag) {
            var numerator = 0.0
            for (i in 0 until count - lag) numerator += residual[i] * residual[i + lag]
            rho[lag] = numerator / ((count - lag) * variance)
        }
        var bestRho = 0.0
        var bestLag = 0
        for (lag in MIN_LAG..minOf(MAX_LAG, maxLag - 1)) {
            val isPeak = rho[lag] > rho[lag - 1] && rho[lag] >= rho[lag + 1]
            if (isPeak && rho[lag] > bestRho) {
                bestRho = rho[lag]
                bestLag = lag
            }
        }
        reset()
        if (bestLag == 0) return 0.0 to 0.0
        val rateHz = 1.0 / (bestLag * hopSize / sampleRate.toDouble())
        return bestRho.coerceIn(0.0, 1.0) to rateHz
    }

    private fun detrendedLog(values: List<Double>): DoubleArray {
        val n = values.size
        val logs = DoubleArray(n) { ln(values[it] + LOG_FLOOR) }
        val xMean = (n - 1) / 2.0
        val yMean = logs.average()
        var sxy = 0.0
        var sxx = 0.0
        for (i in 0 until n) {
            sxy += (i - xMean) * (logs[i] - yMean)
            sxx += (i - xMean) * (i - xMean)
        }
        val slope = if (sxx > 0.0) sxy / sxx else 0.0
        return DoubleArray(n) { logs[it] - yMean - slope * (it - xMean) }
    }

    private fun reset() {
        envelope.clear()
        envelopeSum = 0.0
        hopBuffer = 0.0
        hopSamples = 0
    }
}
