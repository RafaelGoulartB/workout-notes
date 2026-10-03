package com.workoutnotes.workout_notes.sleep

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Captures short-lived buffers and emits only 30-second aggregate metrics. */
class AudioSignalProcessor(
    private val sessionId: String,
    private val onSegment: (Map<String, Any?>) -> Unit,
    private val onError: (Throwable) -> Unit,
) {
    companion object {
        const val SAMPLE_RATE = 16_000
        const val WINDOW_SECONDS = 30
        const val INVALID_VALID_FRACTION = 0.5
        const val NOISE_DELTA_DB = 10.0
        const val MAX_CONSECUTIVE_READ_ERRORS = 3
        const val NO_DATA_TIMEOUT_MILLIS = 5_000L

        fun rms(samples: ShortArray, length: Int = samples.size): Double {
            if (length <= 0) return 0.0
            var sum = 0.0
            for (index in 0 until length) {
                val normalized = samples[index].toDouble() / Short.MAX_VALUE
                sum += normalized * normalized
            }
            return sqrt(sum / length)
        }

        fun dbfs(rms: Double): Double {
            if (rms <= 0.0) return -120.0
            return 20.0 * (ln(rms) / ln(10.0))
        }

        fun classify(validFraction: Double, noiseScore: Double): String {
            if (validFraction < INVALID_VALID_FRACTION) return "invalid"
            return if (noiseScore >= NOISE_DELTA_DB) "noise" else "quiet"
        }
    }

    private var audioRecord: AudioRecord? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    private var windowStartedAt = System.currentTimeMillis()
    private var windowStartedElapsed = 0L
    private var recordingStartedElapsed = 0L
    private var recordingStartedAt = 0L
    private var windowSamples = 0
    @Volatile private var features = SleepAudioFeatures(SAMPLE_RATE)
    private var activeSampleRate = SAMPLE_RATE

    @Synchronized
    fun start() {
        if (running) return
        val started = openStartedRecorder()
        audioRecord = started.record
        activeSampleRate = started.sampleRate
        features = SleepAudioFeatures(activeSampleRate)
        running = true
        windowStartedAt = System.currentTimeMillis()
        recordingStartedAt = windowStartedAt
        windowStartedElapsed = SystemClock.elapsedRealtime()
        recordingStartedElapsed = windowStartedElapsed
        worker = Thread(
            { captureLoop(started.record, started.bufferSizeBytes / 2) },
            "sleep-audio",
        )
        worker?.start()
    }

    /**
     * Some Android devices initialize UNPROCESSED successfully and only fail
     * when recording starts. Treat startRecording as part of the probe and
     * retry with the broadly supported MIC source/sample rates.
     */
    private fun openStartedRecorder(): StartedRecorder {
        val candidates = buildList {
            add(MediaRecorder.AudioSource.UNPROCESSED to SAMPLE_RATE)
            add(MediaRecorder.AudioSource.MIC to SAMPLE_RATE)
            add(MediaRecorder.AudioSource.MIC to 44_100)
        }.distinct()
        var lastError: Throwable? = null
        for ((source, sampleRate) in candidates) {
            var candidate: AudioRecord? = null
            try {
                val minimumBuffer = AudioRecord.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                if (minimumBuffer <= 0) continue
                val bufferSize = max(minimumBuffer, sampleRate / 2)
                candidate = AudioRecord(
                    source,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize,
                )
                if (candidate.state != AudioRecord.STATE_INITIALIZED) {
                    throw IllegalStateException("audio_record_uninitialized")
                }
                candidate.startRecording()
                if (candidate.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    throw IllegalStateException("audio_record_not_recording")
                }
                return StartedRecorder(candidate, sampleRate, bufferSize)
            } catch (error: Throwable) {
                lastError = error
                try { candidate?.stop() } catch (_: Throwable) {}
                candidate?.release()
            }
        }
        throw IllegalStateException("audio_record_unavailable", lastError)
    }

    /** Latest block level for the live waveform (see [SleepAudioFeatures.liveLevel]). */
    fun liveLevel(): Map<String, Any?>? = features.liveLevel()

    @Synchronized
    fun stop() {
        running = false
        try { audioRecord?.stop() } catch (_: Throwable) {}
        if (Thread.currentThread() != worker) {
            try { worker?.join(2_000) } catch (_: InterruptedException) {}
        }
        audioRecord?.release()
        audioRecord = null
        worker = null
        if (windowSamples > 0) emitSegment()
    }

    private fun captureLoop(record: AudioRecord, bufferLength: Int) {
        val buffer = ShortArray(max(bufferLength, 256))
        var consecutiveReadErrors = 0
        var lastSuccessfulReadAt = SystemClock.elapsedRealtime()
        try {
            while (running) {
                val read = record.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (read == 0) {
                    if (SystemClock.elapsedRealtime() - lastSuccessfulReadAt >= NO_DATA_TIMEOUT_MILLIS) {
                        throw IllegalStateException("audio_record_no_data")
                    }
                    continue
                }
                if (read < 0) {
                    consecutiveReadErrors++
                    if (
                        read == AudioRecord.ERROR_DEAD_OBJECT ||
                        consecutiveReadErrors >= MAX_CONSECUTIVE_READ_ERRORS
                    ) {
                        throw IllegalStateException("audio_record_read_error_$read")
                    }
                    continue
                }
                consecutiveReadErrors = 0
                lastSuccessfulReadAt = SystemClock.elapsedRealtime()
                addBuffer(buffer, read)
                if (SystemClock.elapsedRealtime() - windowStartedElapsed >= WINDOW_SECONDS * 1_000L) {
                    emitSegment()
                }
            }
        } catch (error: Throwable) {
            if (running) onError(error)
        }
    }

    private fun addBuffer(buffer: ShortArray, length: Int) {
        windowSamples += length
        features.add(buffer, length)
    }

    private fun emitSegment() {
        if (windowSamples <= 0) return
        val elapsed = SystemClock.elapsedRealtime()
        val now = recordingStartedAt + elapsed - recordingStartedElapsed
        val elapsedMillis = max(1L, elapsed - windowStartedElapsed)
        val expectedSamples = max(1.0, activeSampleRate * elapsedMillis / 1_000.0)
        val validFraction = min(1.0, windowSamples.toDouble() / expectedSamples)
        val snapshot = features.snapshot()
        val noiseScore = (snapshot["noise_score"] as Number).toDouble()
        val classification = classify(validFraction, noiseScore)
        val startedAt = windowStartedAt
        val segment = mutableMapOf<String, Any?>(
            "id" to UUID.randomUUID().toString(),
            "session_id" to sessionId,
            "started_at" to java.time.Instant.ofEpochSecond(startedAt / 1_000L).toString(),
            "duration_seconds" to max(1L, (now / 1_000L) - (startedAt / 1_000L)).toInt(),
            "classification" to classification,
            "valid_fraction" to validFraction,
        )
        segment.putAll(snapshot)
        onSegment(segment)
        windowStartedAt = now
        windowStartedElapsed = elapsed
        windowSamples = 0
    }

    private data class StartedRecorder(
        val record: AudioRecord,
        val sampleRate: Int,
        val bufferSizeBytes: Int,
    )
}

/**
 * Device-relative ambient floor: a low percentile of the last few minutes of
 * block levels.
 *
 * A percentile of a rolling window (instead of an EMA gated to "near the
 * floor") has properties the wake evidence depends on:
 * - a burst or an episode of talking shorter than (1 - percentile) of the
 *   window cannot raise the floor at all, because loud blocks only occupy the
 *   top of the ordering;
 * - a quiet dip has to outlast `percentile * window` (30 s by default) before
 *   it lowers the floor;
 * - a sustained level change (fan or AC turning on, rain) is absorbed once it
 *   fills `(1 - percentile)` of the window (about 4.5 min), instead of
 *   staying "activity" for the rest of the night.
 *
 * Levels are kept in a fixed 0.5 dB histogram plus a ring of the bin indexes,
 * so an update is O(bins) and allocation free. Blocks are sampleRate / 8
 * samples, so one block is always 125 ms.
 */
internal class AdaptiveNoiseBaseline(
    private val windowBlocks: Int = DEFAULT_WINDOW_BLOCKS,
    private val percentile: Double = DEFAULT_PERCENTILE,
    private val calibrationBlocks: Int = DEFAULT_CALIBRATION_BLOCKS,
    private val initialValue: Double = -55.0,
) {
    companion object {
        const val DEFAULT_WINDOW_BLOCKS = 2_400 // 5 min of 125 ms blocks
        const val DEFAULT_PERCENTILE = 0.10
        const val DEFAULT_CALIBRATION_BLOCKS = 80 // 10 s
        private const val MIN_DBFS = -120.0
        private const val MAX_DBFS = 0.0
        private const val BIN_DB = 0.5
        private const val BINS = ((MAX_DBFS - MIN_DBFS) / BIN_DB).toInt()
        // Codec noise floor / digital silence: not real ambient noise.
        private const val SILENCE_DBFS = -118.0
    }

    init {
        require(windowBlocks > 0 && calibrationBlocks > 0)
        require(percentile > 0.0 && percentile < 1.0)
    }

    private val histogram = IntArray(BINS)
    private val ring = IntArray(windowBlocks)
    private var head = 0
    private var filled = 0
    private var validBlocks = 0
    var value: Double = initialValue
        private set
    var isCalibrated: Boolean = false
        private set

    fun observe(dbfs: Double) {
        if (!dbfs.isFinite() || dbfs <= SILENCE_DBFS) return
        val bin = ((dbfs.coerceIn(MIN_DBFS, MAX_DBFS) - MIN_DBFS) / BIN_DB).toInt()
            .coerceIn(0, BINS - 1)
        if (filled == windowBlocks) histogram[ring[head]]-- else filled++
        ring[head] = bin
        histogram[bin]++
        head = (head + 1) % windowBlocks
        if (validBlocks < calibrationBlocks) validBlocks++
        if (!isCalibrated && validBlocks >= calibrationBlocks) isCalibrated = true
        if (isCalibrated) value = percentileValue()
    }

    private fun percentileValue(): Double {
        val rank = max(1, ceil(percentile * filled).toInt())
        var cumulative = 0
        for (bin in 0 until BINS) {
            cumulative += histogram[bin]
            if (cumulative >= rank) return MIN_DBFS + (bin + 0.5) * BIN_DB
        }
        return initialValue
    }

    fun noiseScore(dbfs: Double): Double =
        if (isCalibrated) max(0.0, dbfs - value) else 0.0
}
