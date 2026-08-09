package com.workoutnotes.workout_notes.sleep

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.sin

/**
 * Privacy-preserving spectral aggregates for one 30-second window.
 *
 * Computes band energies, spectral flatness and spectral centroid from short
 * FFT frames. Only aggregate statistics leave this class; raw samples and
 * spectrograms are never persisted.
 */
class SpectralAnalyzer(private val sampleRate: Int = 16_000) {
    companion object {
        const val FFT_SIZE = 1024
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

    fun add(samples: ShortArray, length: Int) {
        var offset = 0
        while (offset + FFT_SIZE <= length) {
            for (index in 0 until FFT_SIZE) {
                re[index] =
                    (samples[offset + index].toDouble() / Short.MAX_VALUE) * WINDOW[index]
                im[index] = 0.0
            }
            offset += FFT_SIZE
            fftRadix2()
            accumulate()
            frameCount++
        }
    }

    /** Returns per-window aggregates, or an empty map if no complete frame ran. */
    fun snapshot(): Map<String, Double> {
        if (frameCount == 0) return emptyMap()
        val result = mutableMapOf<String, Double>()
        for (band in BANDS.indices) {
            result["spectral_band_energy_$band"] = bandSum[band]
        }
        val meanLog = if (binCount > 0) flatnessLogSum / binCount else 0.0
        val meanPower = if (binCount > 0) powerSum / binCount else 0.0
        result["spectral_flatness"] = if (meanPower > 0.0 && binCount > 0) {
            exp(meanLog) / meanPower
        } else {
            1.0
        }
        result["spectral_centroid_hz"] = if (powerSum > 0.0) {
            centroidSum / powerSum
        } else {
            0.0
        }
        reset()
        return result
    }

    private fun accumulate() {
        for (k in 1 until FFT_SIZE / 2) {
            val magnitude = hypot(re[k], im[k]) / FFT_SIZE
            val power = magnitude * magnitude
            val freq = k * sampleRate.toDouble() / FFT_SIZE
            for (band in BANDS.indices) {
                if (freq >= BANDS[band].first && freq < BANDS[band].second) {
                    bandSum[band] += power
                }
            }
            flatnessLogSum += ln(power + 1e-12)
            powerSum += power
            centroidSum += freq * power
            binCount++
        }
    }

    private fun reset() {
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
