package com.workoutnotes.workout_notes.sleep

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Estimates breathing regularity and rate from the slow modulation of the
 * breath-band energy.
 *
 * Input is one power value per spectral frame ([SpectralAnalyzer.onFrame],
 * 150-2000 Hz, ~8 frames/s), so mains hum below and microphone hiss above the
 * band cannot drown the airflow sound the way a broadband mean |sample| did.
 * The last [HISTORY_SECONDS] of frames are kept across 30-second snapshots
 * (a window alone holds only 6-8 breaths). On snapshot the power series is
 * averaged over [SMOOTHING_SECONDS] (a boxcar that nulls frame-locked
 * artefacts such as mains-hum harmonics beating in the FFT at 2 and 4 Hz),
 * converted to the log domain, linearly detrended, outliers are clipped robustly, and the normalized
 * autocorrelation is searched for the highest true local peak at breath
 * periods of [MIN_PERIOD_SECONDS]..[MAX_PERIOD_SECONDS]. The peak lag is
 * refined with a parabola for sub-frame rate resolution.
 *
 * Cost is one sort plus ~60 lags x 480 frames per 30 s; nothing per sample.
 */
class BreathingAnalyzer(sampleRate: Int = 16_000) {
    companion object {
        const val HISTORY_SECONDS = 60.0
        const val MIN_HISTORY_SECONDS = 20.0
        const val MIN_PERIOD_SECONDS = 1.5 // 0.667 Hz ceiling
        const val MAX_PERIOD_SECONDS = 8.0 // 0.125 Hz floor
        const val SMOOTHING_SECONDS = 0.5
        private const val POWER_FLOOR = 1e-15
        private const val MIN_VARIANCE = 1e-6
        private const val CLIP_SIGMAS = 4.0
        private val NONE = 0.0 to 0.0
    }

    /** Seconds between frames; also the lag resolution. */
    val framePeriodSeconds: Double =
        SpectralAnalyzer.hopSizeFor(sampleRate) / sampleRate.toDouble()
    private val capacity = ceil(HISTORY_SECONDS / framePeriodSeconds).toInt()
    private val smoothingFrames = max(1, (SMOOTHING_SECONDS / framePeriodSeconds).roundToInt())
    // Linear band power per frame; the log is taken after smoothing.
    private val history = DoubleArray(capacity)
    private var head = 0
    private var size = 0

    /** Appends one frame of breath-band power (0.0 for silent frames). */
    fun addFrame(bandPower: Double) {
        val power = if (bandPower.isFinite() && bandPower > 0.0) bandPower else 0.0
        history[head] = power
        head = (head + 1) % capacity
        if (size < capacity) size++
    }

    /** Returns (regularity, rate_hz); (0.0, 0.0) on silence, insufficient data or no periodic peak. */
    fun snapshot(): Pair<Double, Double> {
        if (size * framePeriodSeconds < MIN_HISTORY_SECONDS) return NONE
        val minLag = ceil(MIN_PERIOD_SECONDS / framePeriodSeconds).toInt()
        val maxLag = floor(MAX_PERIOD_SECONDS / framePeriodSeconds).toInt()
        // Lags minLag - 1 .. maxLag + 1 are needed to recognise a peak.
        val n = size - smoothingFrames + 1
        if (maxLag + 1 >= n - 8) return NONE

        val x = detrendedSeries(n)
        var variance = 0.0
        for (value in x) variance += value * value
        if (variance / n < MIN_VARIANCE) return NONE
        clipOutliers(x)

        // prefix[i] = sum of x[0 until i]^2, for the overlap energies.
        val prefix = DoubleArray(n + 1)
        for (i in 0 until n) prefix[i + 1] = prefix[i] + x[i] * x[i]
        val total = prefix[n]
        if (total <= 0.0) return NONE

        // biased: lag-penalised, used to choose among peaks (prefers the
        // fundamental over its multiples); pearson: unpenalised, reported.
        val biased = DoubleArray(maxLag + 2)
        val pearson = DoubleArray(maxLag + 2)
        for (lag in minLag - 1..maxLag + 1) {
            var dot = 0.0
            for (i in 0 until n - lag) dot += x[i] * x[i + lag]
            biased[lag] = dot / total
            val headEnergy = prefix[n - lag]
            val tailEnergy = total - prefix[lag]
            val denominator = sqrt(headEnergy * tailEnergy)
            pearson[lag] = if (denominator > 0.0) dot / denominator else 0.0
        }

        var bestLag = 0
        var bestBiased = 0.0
        for (lag in minLag..maxLag) {
            val isPeak = biased[lag] > biased[lag - 1] && biased[lag] >= biased[lag + 1]
            if (isPeak && biased[lag] > bestBiased) {
                bestBiased = biased[lag]
                bestLag = lag
            }
        }
        if (bestLag == 0) return NONE

        val left = pearson[bestLag - 1]
        val mid = pearson[bestLag]
        val right = pearson[bestLag + 1]
        val curvature = left - 2.0 * mid + right
        val offset = if (curvature < -1e-12) {
            (0.5 * (left - right) / curvature).coerceIn(-0.5, 0.5)
        } else {
            0.0
        }
        val periodSeconds = (bestLag + offset) * framePeriodSeconds
        if (periodSeconds <= 0.0) return NONE
        return mid.coerceIn(0.0, 1.0) to 1.0 / periodSeconds
    }

    /** Smoothed log energies of the last frames minus a linear trend. */
    private fun detrendedSeries(n: Int): DoubleArray {
        val start = (head - size + capacity) % capacity
        var window = 0.0
        for (i in 0 until smoothingFrames - 1) window += history[(start + i) % capacity]
        val x = DoubleArray(n)
        for (i in 0 until n) {
            window += history[(start + i + smoothingFrames - 1) % capacity]
            x[i] = ln(window / smoothingFrames + POWER_FLOOR)
            window -= history[(start + i) % capacity]
        }
        val xMean = (n - 1) / 2.0
        val yMean = x.average()
        var sxy = 0.0
        var sxx = 0.0
        for (i in 0 until n) {
            sxy += (i - xMean) * (x[i] - yMean)
            sxx += (i - xMean) * (i - xMean)
        }
        val slope = if (sxx > 0.0) sxy / sxx else 0.0
        for (i in 0 until n) x[i] = x[i] - yMean - slope * (i - xMean)
        return x
    }

    /**
     * A door slam is tens of dB above the breath modulation; in the log domain
     * it would still dominate the variance. Clip at a few robust (median
     * absolute deviation) sigmas, which leaves a sinusoid untouched.
     */
    private fun clipOutliers(x: DoubleArray) {
        val magnitudes = DoubleArray(x.size) { abs(x[it]) }
        magnitudes.sort()
        val sigma = 1.4826 * magnitudes[magnitudes.size / 2]
        if (sigma <= 1e-9) return
        val limit = CLIP_SIGMAS * sigma
        for (i in x.indices) x[i] = min(limit, max(-limit, x[i]))
    }
}
