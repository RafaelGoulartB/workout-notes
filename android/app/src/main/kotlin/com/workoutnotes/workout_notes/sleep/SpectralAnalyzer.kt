package com.workoutnotes.workout_notes.sleep

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin

/**
 * Privacy-preserving spectral aggregates for one 30-second window.
 *
 * Computes band energies, spectral flatness and spectral centroid from short
 * FFT frames. Only aggregate statistics leave this class; raw samples and
 * spectrograms are never persisted.
 */
class SpectralAnalyzer(
    private val sampleRate: Int = 16_000,
    /**
     * Called once per hop (every ~125 ms) with the power in the breath band
     * ([BREATH_BAND_LOW_HZ], [BREATH_BAND_HIGH_HZ]). All-zero frames skip the
     * FFT but still report 0.0 so a consumer's timeline stays continuous.
     */
    private val onFrame: ((bandPower: Double) -> Unit)? = null,
) {
    companion object {
        const val FFT_SIZE = 1024
        const val MAX_FRAMES_PER_SECOND = 8
        /** Excludes mains hum / rumble below and microphone hiss above. */
        const val BREATH_BAND_LOW_HZ = 150.0
        const val BREATH_BAND_HIGH_HZ = 2000.0

        /** Samples between frame starts; bounds FFT work at any sample rate. */
        fun hopSizeFor(sampleRate: Int): Int =
            maxOf(FFT_SIZE, (sampleRate + MAX_FRAMES_PER_SECOND - 1) / MAX_FRAMES_PER_SECOND)

        private const val POWER_FLOOR = 1e-24
        val BANDS = listOf(
            0.0 to 200.0, // snore fundamental, HVAC rumble
            200.0 to 600.0, // snore harmonics, low speech formants
            600.0 to 1500.0, // speech
            1500.0 to 4000.0, // sibilants, alarms, movement noise
            4000.0 to 8000.0, // electronics, birds, sharp noise
        )
        private val WINDOW = FloatArray(FFT_SIZE) { index ->
            (0.5 * (1.0 - cos(2.0 * PI * index / (FFT_SIZE - 1)))).toFloat()
        }
    }

    private val re = DoubleArray(FFT_SIZE)
    private val im = DoubleArray(FFT_SIZE)
    private val bandSum = DoubleArray(BANDS.size)
    private var flatnessLogSum = 0.0
    private var powerSum = 0.0
    private var centroidSum = 0.0
    private var binCount = 0
    private var frameCount = 0
    private var pendingSamples = 0
    private var pendingHasSignal = false
    private var skipSamples = 0
    // Bound FFT work to the same cadence at 16 kHz and the 44.1 kHz fallback.
    private val hopSize = hopSizeFor(sampleRate)
    private var framePower = 0.0
    internal var processedFrames = 0L
        private set

    fun add(samples: ShortArray, length: Int) {
        var offset = 0
        while (offset < length) {
            if (skipSamples > 0) {
                val skip = minOf(skipSamples, length - offset)
                skipSamples -= skip
                offset += skip
                continue
            }
            val take = minOf(FFT_SIZE - pendingSamples, length - offset)
            for (index in 0 until take) {
                val target = pendingSamples + index
                if (samples[offset + index].toInt() != 0) pendingHasSignal = true
                re[target] = (samples[offset + index].toDouble() / Short.MAX_VALUE) * WINDOW[target]
                im[target] = 0.0
            }
            offset += take
            pendingSamples += take
            if (pendingSamples < FFT_SIZE) continue
            if (pendingHasSignal) {
                fftRadix2()
                accumulate()
                frameCount++
                processedFrames++
                onFrame?.invoke(framePower)
            } else {
                onFrame?.invoke(0.0)
            }
            pendingSamples = 0
            pendingHasSignal = false
            skipSamples = hopSize - FFT_SIZE
        }
    }

    /** Returns per-window aggregates, or an empty map if no complete frame ran. */
    fun snapshot(): Map<String, Double> {
        if (frameCount == 0 || powerSum <= 0.0) {
            resetAggregates()
            return emptyMap()
        }
        val result = mutableMapOf<String, Double>()
        for (band in BANDS.indices) {
            result["spectral_band_energy_$band"] = bandSum[band]
        }
        val meanLog = if (binCount > 0) flatnessLogSum / binCount else 0.0
        val meanPower = if (binCount > 0) powerSum / binCount else 0.0
        // Geometric/arithmetic mean ratio is bounded to [0, 1]; the clamp only
        // absorbs floating-point error.
        result["spectral_flatness"] = if (meanPower > 0.0 && binCount > 0) {
            (exp(meanLog) / meanPower).coerceIn(0.0, 1.0)
        } else {
            1.0
        }
        result["spectral_centroid_hz"] = if (powerSum > 0.0) {
            centroidSum / powerSum
        } else {
            0.0
        }
        resetAggregates()
        return result
    }

    private fun accumulate() {
        framePower = 0.0
        for (k in 1 until FFT_SIZE / 2) {
            val power = (re[k] * re[k] + im[k] * im[k]) / (FFT_SIZE.toDouble() * FFT_SIZE)
            val freq = k * sampleRate.toDouble() / FFT_SIZE
            if (freq >= 8_000.0) continue
            if (freq >= BREATH_BAND_LOW_HZ && freq < BREATH_BAND_HIGH_HZ) framePower += power
            for (band in BANDS.indices) {
                if (freq >= BANDS[band].first && freq < BANDS[band].second) {
                    bandSum[band] += power
                }
            }
            // The floor must stay far below real bin power. Quiet 16-bit capture
            // near 1 LSB yields ~1e-13 per bin; a 1e-12 floor inflated the
            // geometric mean and produced flatness values above 1.
            flatnessLogSum += ln(power + POWER_FLOOR)
            powerSum += power
            centroidSum += freq * power
            binCount++
        }
    }

    /**
     * Clears the window aggregates only. Frame alignment (partial frame and
     * hop skip) is kept so the frame timeline is continuous across snapshots.
     */
    private fun resetAggregates() {
        bandSum.fill(0.0)
        flatnessLogSum = 0.0
        powerSum = 0.0
        centroidSum = 0.0
        binCount = 0
        frameCount = 0
    }

    /** Iterative radix-2 FFT, in-place on [re]/[im]. */
    private fun fftRadix2() {
        var j = 0
        for (i in 1 until FFT_SIZE) {
            var bit = FFT_SIZE shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                val tempRe = re[i]
                re[i] = re[j]
                re[j] = tempRe
                val tempIm = im[i]
                im[i] = im[j]
                im[j] = tempIm
            }
        }
        var size = 2
        while (size <= FFT_SIZE) {
            val angle = -2.0 * PI / size
            val wRe = cos(angle)
            val wIm = sin(angle)
            var half = 0
            while (half < FFT_SIZE) {
                var curRe = 1.0
                var curIm = 0.0
                for (k in 0 until size / 2) {
                    val uRe = re[half + k]
                    val uIm = im[half + k]
                    val vRe =
                        re[half + k + size / 2] * curRe - im[half + k + size / 2] * curIm
                    val vIm =
                        re[half + k + size / 2] * curIm + im[half + k + size / 2] * curRe
                    re[half + k] = uRe + vRe
                    im[half + k] = uIm + vIm
                    re[half + k + size / 2] = uRe - vRe
                    im[half + k + size / 2] = uIm - vIm
                    val nextRe = curRe * wRe - curIm * wIm
                    curIm = curRe * wIm + curIm * wRe
                    curRe = nextRe
                }
                half += size
            }
            size *= 2
        }
    }
}
