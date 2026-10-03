package com.workoutnotes.workout_notes.sleep

import java.util.Random
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Deterministic bedroom-like test signals: band-limited noise built from
 * random-phase tones (rotating phasors, so generation stays fast), optionally
 * amplitude modulated like breathing, mixed at chosen dBFS levels.
 */
internal object SyntheticSleepAudio {
    /** Direct-form biquad (RBJ cookbook, Q = 1/sqrt(2)), applied in place. */
    private fun biquad(x: DoubleArray, cutoffHz: Double, rate: Int, highPass: Boolean) {
        val w = 2.0 * PI * cutoffHz / rate
        val cosW = cos(w)
        val alpha = sin(w) / (2.0 * 0.7071)
        val b0: Double
        val b1: Double
        if (highPass) {
            b0 = (1 + cosW) / 2
            b1 = -(1 + cosW)
        } else {
            b0 = (1 - cosW) / 2
            b1 = 1 - cosW
        }
        val b2 = b0
        val a0 = 1 + alpha
        val a1 = -2 * cosW / a0
        val a2 = (1 - alpha) / a0
        val nb0 = b0 / a0
        val nb1 = b1 / a0
        val nb2 = b2 / a0
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for (i in x.indices) {
            val y = nb0 * x[i] + nb1 * x1 + nb2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = y
            x[i] = y
        }
    }

    private fun scaleToRms(x: DoubleArray, rmsDbfs: Double) {
        var sum = 0.0
        for (v in x) sum += v * v
        val gain = 10.0.pow(rmsDbfs / 20.0) / sqrt(sum / x.size)
        for (i in x.indices) x[i] *= gain
    }

    /**
     * Gaussian white noise shaped by 4th-order high/low-pass edges (0 / Nyquist
     * disable an edge), scaled to [rmsDbfs]; full scale = 1.0. An optional
     * sinusoidal amplitude modulation keeps the same average power.
     */
    fun bandNoise(
        rate: Int,
        seconds: Double,
        lowHz: Double,
        highHz: Double,
        rmsDbfs: Double,
        seed: Long,
        modulationHz: Double = 0.0,
        modulationDepth: Double = 0.0,
    ): DoubleArray {
        val random = Random(seed)
        val out = DoubleArray((rate * seconds).toInt()) { random.nextGaussian() }
        if (lowHz > 0.0) repeat(2) { biquad(out, lowHz, rate, highPass = true) }
        if (highHz < rate / 2.0) repeat(2) { biquad(out, highHz, rate, highPass = false) }
        if (modulationDepth > 0.0) {
            for (i in out.indices) {
                out[i] *= 1.0 + modulationDepth * sin(2.0 * PI * modulationHz * i / rate)
            }
        }
        scaleToRms(out, rmsDbfs)
        return out
    }

    /** Sum of steady tones, e.g. 50 Hz mains hum and its harmonics. */
    fun hum(rate: Int, seconds: Double, rmsDbfs: Double, fundamentalHz: Double = 50.0): DoubleArray {
        val count = (rate * seconds).toInt()
        val rms = 10.0.pow(rmsDbfs / 20.0)
        val harmonics = 3
        val amplitude = rms * sqrt(2.0 / harmonics)
        return DoubleArray(count) { i ->
            var sum = 0.0
            for (h in 1..harmonics) sum += sin(2.0 * PI * fundamentalHz * h * i / rate + h)
            amplitude * sum
        }
    }

    /** A breath: modulated 300-1500 Hz noise, plus 4-8 kHz hiss and hum. */
    fun night(
        rate: Int,
        seconds: Double,
        breathHz: Double?,
        breathDbfs: Double = -70.0,
        hissDbfs: Double = -66.0,
        humDbfs: Double = -58.0,
        humHz: Double = 50.0,
        micDbfs: Double = -85.0,
        depth: Double = 0.8,
        seed: Long = 1L,
    ): ShortArray {
        val parts = mutableListOf(
            bandNoise(rate, seconds, 4_000.0, rate / 2.0, hissDbfs, seed + 1),
            hum(rate, seconds, humDbfs, humHz),
            // The microphone's own broadband self-noise, also inside the breath band.
            bandNoise(rate, seconds, 0.0, rate / 2.0, micDbfs, seed + 3),
        )
        if (breathHz != null) {
            parts += bandNoise(
                rate, seconds, 300.0, 1_500.0, breathDbfs, seed + 2,
                modulationHz = breathHz, modulationDepth = depth,
            )
        }
        return mix(parts)
    }

    fun mix(parts: List<DoubleArray>): ShortArray {
        val count = parts.minOf { it.size }
        return ShortArray(count) { i ->
            var sum = 0.0
            for (part in parts) sum += part[i]
            (sum * Short.MAX_VALUE).roundToInt().coerceIn(-32768, 32767).toShort()
        }
    }

    /** Runs the whole native feature pipeline, snapshotting every 30 s. */
    fun snapshots(samples: ShortArray, rate: Int, chunk: Int = 1_000): List<Map<String, Any?>> {
        val features = SleepAudioFeatures(rate)
        val window = rate * 30
        val result = mutableListOf<Map<String, Any?>>()
        var offset = 0
        var inWindow = 0
        while (offset < samples.size) {
            val take = minOf(chunk, samples.size - offset, window - inWindow)
            features.add(samples.copyOfRange(offset, offset + take), take)
            offset += take
            inWindow += take
            if (inWindow == window) {
                result += features.snapshot()
                inWindow = 0
            }
        }
        return result
    }

    fun regularity(snapshot: Map<String, Any?>) = (snapshot["breathing_regularity"] as Number).toDouble()
    fun rate(snapshot: Map<String, Any?>) = (snapshot["breathing_rate_hz"] as Number).toDouble()
}
