package com.workoutnotes.workout_notes.sleep

import kotlin.math.PI
import kotlin.math.sin
import org.junit.Assert.*
import org.junit.Test

class SleepAudioFeaturesTest {
    private fun signal(rate: Int, seconds: Int = 30) = ShortArray(rate * seconds) { i ->
        val t = i.toDouble() / rate
        val amplitude = (0.35 + 0.25 * sin(2 * PI * 0.25 * t)) * if (t in 12.0..14.0) 1.4 else 1.0
        (sin(2 * PI * 300 * t) * amplitude * Short.MAX_VALUE).toInt().toShort()
    }

    private fun analyze(samples: ShortArray, rate: Int, block: Int): Map<String, Any?> {
        val features = SleepAudioFeatures(rate)
        var offset = 0
        while (offset < samples.size) {
            val next = samples.copyOfRange(offset, minOf(offset + block, samples.size))
            features.add(next, next.size)
            offset += next.size
        }
        return features.snapshot()
    }

    @Test fun featuresDoNotDependOnRecorderBufferBoundaries() {
        val samples = signal(16_000)
        val expected = analyze(samples, 16_000, samples.size)
        for (block in listOf(137, 1024, 4000, 8192)) {
            val actual = analyze(samples, 16_000, block)
            for ((key, value) in expected) {
                if (value is Number) assertEquals(key, value.toDouble(), (actual[key] as Number).toDouble(), 1e-9)
                else assertEquals(key, value, actual[key])
            }
        }
    }

    @Test fun fallbackKeepsPhysicalFrequenciesAndBoundedFftWork() {
        for (rate in listOf(16_000, 44_100)) {
            val features = SleepAudioFeatures(rate)
            val samples = signal(rate)
            features.add(samples, samples.size)
            val result = features.snapshot()
            assertEquals(300.0, (result["spectral_centroid_hz"] as Number).toDouble(), 45.0)
            assertEquals(0.25, (result["breathing_rate_hz"] as Number).toDouble(), 0.05)
            assertTrue("FFT budget exceeded at $rate Hz: ${features.processedFrames}", features.processedFrames <= 30 * 8)
            assertTrue(features.processedFrames > 30 * 7)
        }
    }

    @Test fun silenceHasNoSpectralEvidenceAndSnapshotsReset() {
        val features = SleepAudioFeatures(16_000)
        val samples = ShortArray(16_000 * 30)
        features.add(samples, samples.size)
        val result = features.snapshot()
        assertFalse(result.containsKey("spectral_flatness"))
        assertEquals(1.0, result["digital_silence_fraction"])
        assertEquals(0.0, result["breathing_regularity"])
        assertTrue(features.snapshot().isEmpty())
    }

    @Test fun spectralFramesSurviveSmallBuffers() {
        val samples = signal(16_000, 1)
        val analyzer = SpectralAnalyzer()
        for (sample in samples) analyzer.add(shortArrayOf(sample), 1)
        assertTrue(analyzer.snapshot().containsKey("spectral_centroid_hz"))
        assertEquals(8L, analyzer.processedFrames)
    }
}
