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

    private fun noise(rate: Int, seconds: Double, dbfs: Double, random: java.util.Random): ShortArray {
        val amplitude = Math.pow(10.0, dbfs / 20.0) * Short.MAX_VALUE * 1.732 // uniform -> rms
        return ShortArray((rate * seconds).toInt()) { ((random.nextDouble() * 2 - 1) * amplitude).toInt().toShort() }
    }

    @Test fun countsDistinctNoisyEpisodesAcrossWindows() {
        val rate = 16_000
        val random = java.util.Random(3)
        val features = SleepAudioFeatures(rate)
        fun feed(seconds: Double, dbfs: Double) {
            val samples = noise(rate, seconds, dbfs, random)
            features.add(samples, samples.size)
        }
        // Window 1: floor, a 2 s burst, floor, a 1 s burst, then a burst that
        // runs into window 2.
        feed(15.0, -75.0); feed(2.0, -40.0); feed(3.0, -75.0); feed(1.0, -40.0)
        feed(7.0, -75.0); feed(2.0, -40.0)
        val first = features.snapshot()
        assertEquals(3, (first["noise_burst_count"] as Number).toInt())
        // Window 2 starts inside the same episode: no new burst.
        feed(2.0, -40.0); feed(10.0, -75.0); feed(3.0, -40.0); feed(15.0, -75.0)
        val second = features.snapshot()
        assertEquals(1, (second["noise_burst_count"] as Number).toInt())
        assertEquals(5.0, (second["noise_active_seconds"] as Number).toDouble(), 0.3)
        assertEquals(0, (features.snapshot()["noise_burst_count"] as? Number)?.toInt() ?: 0)
    }

    @Test fun detectsBriefBroadbandTurnWhileIgnoringNonSimultaneousAmbientBands() {
        val rate = 16_000
        val features = SleepAudioFeatures(rate)
        // Calibrate on 30 s of quiet room white noise (-78 dBFS).
        val quiet = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 10L)
        val quietPcm = SyntheticSleepAudio.mix(listOf(quiet))
        features.add(quietPcm, quietPcm.size)
        val calib = features.snapshot()
        assertEquals(0.0, (calib["broadband_active_seconds"] as Number).toDouble(), 0.25)

        // Window 2: birds (4-8 kHz) at 2-7 s, truck (0-180 Hz) at 12-18 s,
        // dove (600-1400 Hz) at 22-26 s — never broadband at the same instant.
        val room = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 11L)
        val birds = SyntheticSleepAudio.bandNoise(rate, 5.0, 4_500.0, 7_500.0, -48.0, seed = 12L)
        val truck = SyntheticSleepAudio.bandNoise(rate, 6.0, 20.0, 160.0, -40.0, seed = 13L)
        val dove = SyntheticSleepAudio.bandNoise(rate, 4.0, 700.0, 1_300.0, -48.0, seed = 14L)
        for (i in birds.indices) room[2 * rate + i] += birds[i]
        for (i in truck.indices) room[12 * rate + i] += truck[i]
        for (i in dove.indices) room[22 * rate + i] += dove[i]
        val ambientPcm = SyntheticSleepAudio.mix(listOf(room))
        features.add(ambientPcm, ambientPcm.size)
        val ambientSnap = features.snapshot()
        assertTrue(
            "non-simultaneous bands should not trigger broadband burst: ${ambientSnap["broadband_active_seconds"]}",
            (ambientSnap["broadband_active_seconds"] as Number).toDouble() < 0.5,
        )

        // Window 3: a brief 1.5 s broadband turn in bed (+12 dB above room).
        val turnRoom = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 15L)
        val turn = SyntheticSleepAudio.bandNoise(rate, 1.5, 0.0, rate / 2.0, -64.0, seed = 16L)
        for (i in turn.indices) turnRoom[10 * rate + i] += turn[i]
        val turnPcm = SyntheticSleepAudio.mix(listOf(turnRoom))
        features.add(turnPcm, turnPcm.size)
        val turnSnap = features.snapshot()
        assertTrue(
            "expected >= 1.0 s broadband burst, got ${turnSnap["broadband_active_seconds"]}",
            (turnSnap["broadband_active_seconds"] as Number).toDouble() >= 1.0,
        )
    }

    @Test fun quantizedQuietAudioDoesNotProduceFalseBroadbandBursts() {
        val rate = 16_000
        val random = java.util.Random(19)
        val features = SleepAudioFeatures(rate)
        // Two minutes of +-1 LSB quantization noise with occasional zero gaps.
        repeat(4) { window ->
            val pcm = ShortArray(rate * 30) { i ->
                if (i % 10 < 3) 0 else (random.nextInt(3) - 1).toShort()
            }
            features.add(pcm, pcm.size)
            val snap = features.snapshot()
            val bb = (snap["broadband_active_seconds"] as? Number)?.toDouble() ?: 0.0
            assertTrue("window $window had false broadband burst $bb", bb < 0.5)
        }
    }

    @Test fun overlappingBirdsAndTrafficWithQuietMidBandProduceZeroBroadbandBurst() {
        val rate = 16_000
        val features = SleepAudioFeatures(rate)
        // Calibrate on 2 minutes of quiet room noise.
        repeat(4) { i ->
            val quiet = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 20L + i)
            val pcm = SyntheticSleepAudio.mix(listOf(quiet))
            features.add(pcm, pcm.size)
            features.snapshot()
        }
        // Overlapping traffic (30-450 Hz) + birds (2000-7500 Hz) at the exact
        // same instants, while band 2 (600-1500 Hz) stays quiet.
        val room = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 30L)
        val traffic = SyntheticSleepAudio.bandNoise(rate, 8.0, 30.0, 400.0, -45.0, seed = 31L)
        val birds = SyntheticSleepAudio.bandNoise(rate, 8.0, 2_200.0, 7_500.0, -45.0, seed = 32L)
        for (i in traffic.indices) {
            room[5 * rate + i] += traffic[i] + birds[i]
            room[18 * rate + i] += traffic[i] + birds[i]
        }
        val pcm = SyntheticSleepAudio.mix(listOf(room))
        features.add(pcm, pcm.size)
        val snap = features.snapshot()
        assertTrue(
            "overlapping traffic+birds should not score broadband: ${snap["broadband_active_seconds"]}",
            (snap["broadband_active_seconds"] as Number).toDouble() < 0.5,
        )
    }

    @Test fun endToEndFanMaskedBriefTurnReachesMovementInNativeFilter() {
        val rate = 16_000
        val features = SleepAudioFeatures(rate)
        val filter = SleepWakeFilter("fan-night")
        var epochSec = 1_700_000_000L
        fun feedWindow(pcm: ShortArray): SleepWakeFilter.Decision {
            features.add(pcm, pcm.size)
            val snap = features.snapshot()
            val segment = snap + mapOf(
                "session_id" to "fan-night",
                "started_at" to java.time.Instant.ofEpochSecond(epochSec).toString(),
                "duration_seconds" to 30,
                "classification" to "quiet",
                "valid_fraction" to 1.0,
            )
            epochSec += 30
            return filter.add(segment)
        }
        // 5 minutes of steady low-frequency fan (-48 dBFS, 20-120 Hz) over room floor.
        repeat(10) { i ->
            val room = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 40L + i)
            val fan = SyntheticSleepAudio.bandNoise(rate, 30.0, 20.0, 120.0, -48.0, seed = 60L + i)
            feedWindow(SyntheticSleepAudio.mix(listOf(room, fan)))
        }
        // Brief 1.5 s turn in bed (-48 dBFS over a -48 dBFS low-frequency fan:
        // total RMS rises only ~3 dB, so noise_active_seconds == 0 and stddev < 2 dB,
        // completely masked from the full-band detector yet clear in bands 1-4).
        val room = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 80L)
        val fan = SyntheticSleepAudio.bandNoise(rate, 30.0, 20.0, 120.0, -48.0, seed = 81L)
        val turn = SyntheticSleepAudio.bandNoise(rate, 1.5, 200.0, rate / 2.0, -48.0, seed = 82L)
        for (i in turn.indices) room[12 * rate + i] += turn[i]
        val pcm = SyntheticSleepAudio.mix(listOf(room, fan))
        features.add(pcm, pcm.size)
        val snap = features.snapshot()
        assertEquals(0.0, (snap["noise_active_seconds"] as Number).toDouble(), 0.01)
        assertTrue((snap["audio_level_stddev_db"] as Number).toDouble() < 3.0)
        val segment = snap + mapOf(
            "session_id" to "fan-night",
            "started_at" to java.time.Instant.ofEpochSecond(epochSec).toString(),
            "duration_seconds" to 30,
            "classification" to "quiet",
            "valid_fraction" to 1.0,
        )
        val decision = filter.add(segment)
        assertTrue(
            "expected movement/strong_movement for fan-masked 1.5 s turn, got ${decision.reason}",
            decision.reason == "movement" || decision.reason == "strong_movement",
        )
    }

    @Test fun stepOnsetAtWindowTailAndSparseSilentFramesAreGuarded() {
        val rate = 16_000
        val features = SleepAudioFeatures(rate)
        repeat(4) { i ->
            val quiet = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 90L + i)
            val pcm = SyntheticSleepAudio.mix(listOf(quiet))
            features.add(pcm, pcm.size)
            features.snapshot()
        }
        // AC switches on at t=20 s and stays steady to window end: tailRunSeconds >= 9 s.
        val acRoom = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, rate / 2.0, -78.0, seed = 95L)
        val ac = SyntheticSleepAudio.bandNoise(rate, 10.0, 0.0, rate / 2.0, -64.0, seed = 96L)
        for (i in ac.indices) acRoom[20 * rate + i] += ac[i]
        val acPcm = SyntheticSleepAudio.mix(listOf(acRoom))
        features.add(acPcm, acPcm.size)
        val acSnap = features.snapshot()
        assertTrue(
            "expected broadband_tail_seconds >= 5.0, got ${acSnap["broadband_tail_seconds"]}",
            (acSnap["broadband_tail_seconds"] as Number).toDouble() >= 5.0,
        )

        // Almost-silent window (only 0.5 s non-zero out of 30 s): omits broadband_* keys.
        val sparse = ShortArray(rate * 30)
        val burst = SyntheticSleepAudio.mix(
            listOf(SyntheticSleepAudio.bandNoise(rate, 0.5, 0.0, rate / 2.0, -60.0, seed = 97L)),
        )
        burst.copyInto(sparse, 0)
        features.add(sparse, sparse.size)
        val sparseSnap = features.snapshot()
        assertFalse(sparseSnap.containsKey("broadband_active_seconds"))
    }

    @Test fun frameBroadbandTrackerWorksAt44100HzFallback() {
        val rate = 44_100
        val features = SleepAudioFeatures(rate)
        val quiet = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, 8_000.0, -78.0, seed = 100L)
        val quietPcm = SyntheticSleepAudio.mix(listOf(quiet))
        features.add(quietPcm, quietPcm.size)
        features.snapshot()

        val room = SyntheticSleepAudio.bandNoise(rate, 30.0, 0.0, 8_000.0, -78.0, seed = 101L)
        val turn = SyntheticSleepAudio.bandNoise(rate, 2.0, 0.0, 8_000.0, -62.0, seed = 102L)
        for (i in turn.indices) room[10 * rate + i] += turn[i]
        val pcm = SyntheticSleepAudio.mix(listOf(room))
        features.add(pcm, pcm.size)
        val snap = features.snapshot()
        assertTrue(
            "expected >= 1.0 s broadband burst at 44.1 kHz, got ${snap["broadband_active_seconds"]}",
            (snap["broadband_active_seconds"] as Number).toDouble() >= 1.0,
        )
    }
}
