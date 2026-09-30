package com.workoutnotes.workout_notes.sleep

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/** Fixed-duration analysis blocks, independent of AudioRecord callback sizes.
 * Buffers are reused; only aggregates survive a 30-second snapshot.
 */
internal class SleepAudioFeatures(val sampleRate: Int) {
    private val block = ShortArray(sampleRate / 8)
    private var blockSize = 0
    private val baseline = AdaptiveNoiseBaseline()
    // Breathing reads the per-frame breath-band energy of the spectral FFT, so
    // it must exist first and never sees raw samples.
    private val breathing = BreathingAnalyzer(sampleRate)
    private val spectral = SpectralAnalyzer(sampleRate, onFrame = breathing::addFrame)
    private var samples = 0L
    private var squares = 0.0
    private var peak = 0.0
    private var noisySeconds = 0.0
    private var noiseBursts = 0
    // Carried across snapshots so an episode straddling two windows counts once.
    private var previousBlockNoisy = false
    private var digitalSilenceSamples = 0L
    private var levelCount = 0
    private var levelMean = 0.0
    private var levelM2 = 0.0
    // Read from the platform thread by the live waveform; never persisted.
    @Volatile private var liveDbfs = Double.NaN
    @Volatile private var liveBaselineDbfs = baseline.value

    internal val processedFrames get() = spectral.processedFrames

    /** Level of the latest analysis block and the room baseline, for the
     * monitor screen's waveform only. Null before the first block. */
    fun liveLevel(): Map<String, Any?>? {
        val level = liveDbfs
        if (level.isNaN()) return null
        return mapOf(
            "level_dbfs" to level,
            "baseline_dbfs" to liveBaselineDbfs,
        )
    }

    fun add(buffer: ShortArray, length: Int) {
        var offset = 0
        while (offset < length) {
            val take = minOf(block.size - blockSize, length - offset)
            buffer.copyInto(block, blockSize, offset, offset + take)
            offset += take
            blockSize += take
            if (blockSize == block.size) processBlock()
        }
    }

    private fun processBlock() {
        if (blockSize == 0) return
        var blockSquares = 0.0
        for (i in 0 until blockSize) {
            val value = block[i].toDouble() / Short.MAX_VALUE
            blockSquares += value * value
            peak = max(peak, abs(value))
            if (block[i].toInt() == 0) digitalSilenceSamples++
        }
        samples += blockSize
        squares += blockSquares
        val db = AudioSignalProcessor.dbfs(sqrt(blockSquares / blockSize))
        levelCount++
        val delta = db - levelMean
        levelMean += delta / levelCount
        levelM2 += delta * (db - levelMean)
        baseline.observe(db)
        liveBaselineDbfs = baseline.value
        liveDbfs = db
        val noisy = baseline.isCalibrated &&
            db > baseline.value + AudioSignalProcessor.NOISE_DELTA_DB
        if (noisy) {
            noisySeconds += blockSize / sampleRate.toDouble()
            if (!previousBlockNoisy) noiseBursts++
        }
        previousBlockNoisy = noisy
        // Keep zero samples in the timeline rather than compressing pauses.
        spectral.add(block, blockSize)
        blockSize = 0
    }

    fun snapshot(): Map<String, Any?> {
        processBlock()
        if (samples == 0L) return emptyMap()
        val rmsDb = AudioSignalProcessor.dbfs(sqrt(squares / samples))
        val result = mutableMapOf<String, Any?>(
            "audio_rms_dbfs" to rmsDb,
            "audio_peak_dbfs" to AudioSignalProcessor.dbfs(peak),
            "noise_score" to baseline.noiseScore(rmsDb),
            // Distinct noisy episodes (quiet -> noisy transitions), not buffers.
            "noise_burst_count" to noiseBursts,
            "noise_active_seconds" to noisySeconds,
            "audio_sample_rate" to sampleRate,
            "audio_sample_count" to samples,
            "audio_baseline_dbfs" to baseline.value,
            "audio_calibrated" to baseline.isCalibrated,
            "digital_silence_fraction" to digitalSilenceSamples.toDouble() / samples,
            "audio_level_stddev_db" to if (levelCount == 0) 0.0 else sqrt(levelM2 / levelCount),
        )
        result.putAll(spectral.snapshot())
        val (regularity, rate) = breathing.snapshot()
        result["breathing_regularity"] = regularity
        result["breathing_rate_hz"] = rate
        samples = 0
        squares = 0.0
        peak = 0.0
        noisySeconds = 0.0
        noiseBursts = 0
        digitalSilenceSamples = 0
        levelCount = 0
        levelMean = 0.0
        levelM2 = 0.0
        return result
    }
}
