package com.workoutnotes.workout_notes.sleep

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sqrt

/** Fixed-duration analysis blocks, independent of AudioRecord callback sizes.
 * Buffers are reused; only aggregates survive a 30-second snapshot.
 */
internal class SleepAudioFeatures(val sampleRate: Int) {
    private val block = ShortArray(sampleRate / 8)
    private var blockSize = 0
    private val baseline = AdaptiveNoiseBaseline()
    // Breathing and broadband tracking read per-frame spectral power from the
    // FFT, so they must exist first and never see raw samples.
    private val breathing = BreathingAnalyzer(sampleRate)
    private val broadband = FrameBroadbandTracker(
        SpectralAnalyzer.hopSizeFor(sampleRate) / sampleRate.toDouble(),
    )
    private val spectral = SpectralAnalyzer(
        sampleRate,
        onBands = broadband::observe,
        onFrame = { bandPower ->
            breathing.addFrame(bandPower)
            broadband.recordHop(silent = bandPower == 0.0)
        },
    )
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
        result.putAll(broadband.snapshot())
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

/**
 * Per-frame (125 ms) simultaneous broadband burst detector.
 *
 * Unlike 30-second band averages — which dilute a 1.5 s bed turn by ~13 dB and
 * merge a bird chirp at t=3 s with a truck at t=22 s into the same window —
 * this tracker maintains a lightweight 5-minute 20th-percentile floor per band
 * and counts exact seconds where at least four of the five bands rose together
 * on the **same** 125 ms frame (excluding steep low-frequency rumble).
 *
 * Allocation-free per frame: 5 fixed histograms + short ring buffers (~25 KB).
 */
internal class FrameBroadbandTracker(private val framePeriodSeconds: Double) {
    companion object {
        private const val BANDS = 5
        private const val MIN_CALIBRATED_BANDS = 4
        private const val MIN_EVALUATED_FRAMES = 20
        private const val MIN_EVALUATED_COVERAGE = 0.5
        private const val MIN_FRAME_TOTAL_POWER = 1e-11
        private const val MIN_BAND_POWER = 1e-17
        private const val MOVEMENT_EXCESS_DB = 8.0
        private const val STRONG_EXCESS_DB = 14.0
        private const val RUMBLE_TILT_DB = 15.0
        private const val RUMBLE_HIGH_SHARE = 0.03
        private const val SPLIT_NOTCH_DB = 7.0
        private const val WINDOW_FRAMES = 2_400 // 5 min at 8 frames/s
        private const val CALIBRATION_FRAMES = 80 // 10 s
        private const val FLOOR_PERCENTILE = 0.20
    }

    private val floors = Array(BANDS) {
        BandFloorHistogram(WINDOW_FRAMES, FLOOR_PERCENTILE, CALIBRATION_FRAMES)
    }
    private val frameDb = DoubleArray(BANDS)
    private val rawExcess = DoubleArray(BANDS)
    private val sortedExcess = DoubleArray(BANDS)
    private val bandValid = BooleanArray(BANDS)

    private var activeSeconds = 0.0
    private var strongSeconds = 0.0
    private var peakDb = 0.0
    private var tailRunSeconds = 0.0
    private var evaluatedFrames = 0
    private var totalFrames = 0

    /** Called once per FFT hop (including silent all-zero frames). */
    fun recordHop(silent: Boolean) {
        totalFrames++
        if (silent) tailRunSeconds = 0.0
    }

    fun observe(bandPowers: DoubleArray) {
        if (bandPowers.size < BANDS) {
            tailRunSeconds = 0.0
            return
        }
        var total = 0.0
        for (b in 0 until BANDS) {
            val p = bandPowers[b]
            if (p.isFinite() && p > 0.0) total += p
        }
        // Skip near-silent glitch frames (e.g. a few +-1 LSB samples) so they
        // never drag down the per-band floor histogram.
        if (total < MIN_FRAME_TOTAL_POWER) {
            tailRunSeconds = 0.0
            return
        }

        var validCount = 0
        for (b in 0 until BANDS) {
            val p = bandPowers[b]
            val db = if (p.isFinite() && p > MIN_BAND_POWER) {
                10.0 * ln(p) / ln(10.0)
            } else {
                Double.NaN
            }
            frameDb[b] = db
            if (!db.isNaN() && floors[b].isCalibrated) {
                val ex = db - floors[b].value
                rawExcess[b] = ex
                sortedExcess[validCount] = ex
                bandValid[b] = true
                validCount++
            } else {
                bandValid[b] = false
            }
        }

        var frameActive = false
        if (validCount >= MIN_CALIBRATED_BANDS) {
            evaluatedFrames++
            // Insertion sort on <=5 elements: zero allocations.
            for (i in 1 until validCount) {
                val key = sortedExcess[i]
                var j = i - 1
                while (j >= 0 && sortedExcess[j] > key) {
                    sortedExcess[j + 1] = sortedExcess[j]
                    j--
                }
                sortedExcess[j + 1] = key
            }
            // Require band 2 (600-1500 Hz, the acoustic bridge of movement/voice)
            // alongside four-band excess so overlapping traffic (0-600 Hz) and
            // birdsong (1500-8000 Hz) with a quiet mid-band never score as human
            // movement.
            val midExcess = if (bandValid[2]) rawExcess[2] else Double.NEGATIVE_INFINITY
            val score = minOf(sortedExcess[1], midExcess)
            if (score.isFinite() && !isLowRumble(bandPowers) && !isSplitBandNotch()) {
                if (score > peakDb) peakDb = score
                if (score >= MOVEMENT_EXCESS_DB) {
                    activeSeconds += framePeriodSeconds
                    tailRunSeconds += framePeriodSeconds
                    frameActive = true
                    if (score >= STRONG_EXCESS_DB) {
                        strongSeconds += framePeriodSeconds
                    }
                }
            }
        }
        if (!frameActive) tailRunSeconds = 0.0

        for (b in 0 until BANDS) {
            val db = frameDb[b]
            if (!db.isNaN()) floors[b].observe(db)
        }
    }

    /**
     * Rejects overlapping band-limited ambient sources (traffic below 600 Hz +
     * birdsong above 1.5 kHz) whose filter skirts leak into band 2 while
     * leaving a >= [SPLIT_NOTCH_DB] U-shaped spectral valley in the middle.
     */
    private fun isSplitBandNotch(): Boolean {
        if (!bandValid[2]) return false
        val low = maxOf(
            if (bandValid[0]) rawExcess[0] else Double.NEGATIVE_INFINITY,
            if (bandValid[1]) rawExcess[1] else Double.NEGATIVE_INFINITY,
        )
        val high = maxOf(
            if (bandValid[3]) rawExcess[3] else Double.NEGATIVE_INFINITY,
            if (bandValid[4]) rawExcess[4] else Double.NEGATIVE_INFINITY,
        )
        if (!low.isFinite() || !high.isFinite()) return false
        val mid = rawExcess[2]
        return low - mid >= SPLIT_NOTCH_DB && high - mid >= SPLIT_NOTCH_DB
    }

    private fun isLowRumble(bandPowers: DoubleArray): Boolean {
        if (!bandValid[0]) return false
        var high = Double.NEGATIVE_INFINITY
        if (bandValid[3] && rawExcess[3] > high) high = rawExcess[3]
        if (bandValid[4] && rawExcess[4] > high) high = rawExcess[4]
        if (!high.isFinite() || rawExcess[0] - high < RUMBLE_TILT_DB) return false
        var addedHigh = 0.0
        var addedAll = 0.0
        for (b in 0 until BANDS) {
            if (!bandValid[b]) continue
            val floorPower = Math.pow(10.0, floors[b].value / 10.0)
            val added = max(0.0, bandPowers[b] - floorPower)
            addedAll += added
            if (b >= 3) addedHigh += added
        }
        return addedAll > 0.0 && addedHigh / addedAll < RUMBLE_HIGH_SHARE
    }

    fun snapshot(): Map<String, Double> {
        val sufficientCoverage = totalFrames > 0 &&
            evaluatedFrames >= MIN_EVALUATED_FRAMES &&
            evaluatedFrames.toDouble() / totalFrames >= MIN_EVALUATED_COVERAGE
        val result = if (sufficientCoverage) {
            mapOf(
                "broadband_active_seconds" to activeSeconds,
                "broadband_strong_seconds" to strongSeconds,
                "broadband_peak_db" to peakDb,
                "broadband_tail_seconds" to tailRunSeconds,
            )
        } else {
            emptyMap()
        }
        activeSeconds = 0.0
        strongSeconds = 0.0
        peakDb = 0.0
        tailRunSeconds = 0.0
        evaluatedFrames = 0
        totalFrames = 0
        return result
    }
}

/** O(bins) allocation-free rolling percentile floor for one FFT band (1 dB bins). */
internal class BandFloorHistogram(
    private val windowFrames: Int,
    private val percentile: Double,
    private val calibrationFrames: Int,
) {
    companion object {
        private const val MIN_DB = -180.0
        private const val MAX_DB = 0.0
        private const val BINS = 180
    }

    private val histogram = IntArray(BINS)
    private val ring = ShortArray(windowFrames)
    private var head = 0
    private var filled = 0
    private var observed = 0
    var value: Double = MIN_DB
        private set
    var isCalibrated: Boolean = false
        private set

    fun observe(db: Double) {
        if (!db.isFinite()) return
        val bin = (db.coerceIn(MIN_DB, MAX_DB) - MIN_DB).toInt().coerceIn(0, BINS - 1)
        if (filled == windowFrames) {
            histogram[ring[head].toInt()]--
        } else {
            filled++
        }
        ring[head] = bin.toShort()
        histogram[bin]++
        head = (head + 1) % windowFrames
        if (observed < calibrationFrames) observed++
        if (!isCalibrated && observed >= calibrationFrames) isCalibrated = true
        if (isCalibrated) value = percentileValue()
    }

    private fun percentileValue(): Double {
        val rank = max(1, ceil(percentile * filled).toInt())
        var cumulative = 0
        for (bin in 0 until BINS) {
            cumulative += histogram[bin]
            if (cumulative >= rank) return MIN_DB + bin + 0.5
        }
        return MIN_DB
    }
}
