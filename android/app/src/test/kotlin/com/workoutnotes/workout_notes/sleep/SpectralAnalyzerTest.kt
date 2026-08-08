package com.workoutnotes.workout_notes.sleep

import kotlin.math.PI
import kotlin.math.sin
import org.junit.Assert.assertTrue
import org.junit.Test

class SpectralAnalyzerTest {
    private fun tone(freqHz: Double, seconds: Double, amplitude: Double = 0.5): ShortArray {
        val count = (16_000 * seconds).toInt()
        return ShortArray(count) { index ->
            val sample = sin(2.0 * PI * freqHz * index / 16_000.0) * Short.MAX_VALUE * amplitude
            sample.toInt().toShort()
        }
    }

    @Test
    fun concentratesLowToneInTheSnoreBand() {
        val analyzer = SpectralAnalyzer()
        val samples = tone(100.0, 1.0)
        analyzer.add(samples, samples.size)
        val result = analyzer.snapshot()
        val band0 = result.getValue("spectral_band_energy_0")
        val band1 = result.getValue("spectral_band_energy_1")
        assertTrue("expected band0 to dominate, got $band0 vs $band1", band0 > band1 * 10)
    }

    @Test
    fun whiteNoiseYieldsNearFlatSpectrum() {
        val analyzer = SpectralAnalyzer()
        val random = java.util.Random(42)
        val samples = ShortArray(4096) { (random.nextInt(65536) - 32768).toShort() }
        analyzer.add(samples, samples.size)
        val result = analyzer.snapshot()
        val flatness = result.getValue("spectral_flatness")
        assertTrue("expected noise-like flatness ~1, got $flatness", flatness > 0.5)
    }

    @Test
    fun highToneCentroidLandsInItsBand() {
        val analyzer = SpectralAnalyzer()
        val samples = tone(6000.0, 1.0)
        analyzer.add(samples, samples.size)
        val result = analyzer.snapshot()
        val centroid = result.getValue("spectral_centroid_hz")
        assertTrue("expected ~6000Hz centroid, got $centroid", centroid > 5500 && centroid < 6500)
    }
}
