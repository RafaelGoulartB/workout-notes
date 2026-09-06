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
    private val spectral = SpectralAnalyzer(sampleRate)
    private val breathing = BreathingAnalyzer(sampleRate)
    private var samples = 0L
    private var squares = 0.0
    private var peak = 0.0
    private var noisySeconds = 0.0
    private var digitalSilenceSamples = 0L
    private var levelCount = 0
    private var levelMean = 0.0
    private var levelM2 = 0.0

    internal val processedFrames get() = spectral.processedFrames

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
        if (baseline.isCalibrated && db > baseline.value + AudioSignalProcessor.NOISE_DELTA_DB) {
            noisySeconds += blockSize / sampleRate.toDouble()
        }
        // Keep zero samples in the timeline rather than compressing pauses.
        spectral.add(block, blockSize)
        breathing.add(block, blockSize)
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
            // v3 uses a duration, not a count of device-dependent buffers.
            "noise_burst_count" to 0,
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
        digitalSilenceSamples = 0
        levelCount = 0
        levelMean = 0.0
        levelM2 = 0.0
        return result
    }
}
