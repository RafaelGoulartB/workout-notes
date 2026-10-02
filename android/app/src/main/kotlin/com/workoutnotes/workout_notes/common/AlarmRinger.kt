package com.workoutnotes.workout_notes.common

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Looping alarm sound plus a repeating vibration. Shared by the sleep,
 * traditional and medication alarm services, which all ring identically.
 *
 * The sound is never silent: the default alarm tone is tried first, then the
 * default notification and ringtone tones (a tone that cannot be opened, for
 * instance because it lives on storage that is still locked after a reboot,
 * is skipped), and as a last resort a [ToneGenerator] beeps on the alarm
 * stream. The vibration carries alarm attributes, so "Do Not Disturb" with
 * alarms allowed does not suppress it.
 *
 * With a gradual [AlarmVolumeRamp] the sound starts soft and rises, the
 * vibration joins halfway and, optionally, the alarm volume is raised to its
 * maximum at the end. [stop] restores that volume.
 */
class AlarmRinger(private val context: Context) {
    private var player: MediaPlayer? = null
    private var tone: ToneGenerator? = null
    private val failedUris = mutableSetOf<Uri>()
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var ramp = AlarmVolumeRamp.NONE
    private var rampStartedAt = 0L
    private var boosted = false

    private val rampTick = object : Runnable {
        override fun run() {
            val elapsed = SystemClock.elapsedRealtime() - rampStartedAt
            setGain(ramp.gainAt(elapsed))
            if (elapsed < ramp.rampMillis) {
                handler.postDelayed(this, AlarmVolumeRamp.TICK_MILLIS)
            } else {
                finishRamp()
            }
        }
    }
    private val vibrationStart = Runnable { startVibration() }
    private val toneLoop = object : Runnable {
        override fun run() {
            val generator = tone ?: return
            try {
                generator.startTone(FALLBACK_TONE, FALLBACK_BURST_MILLIS)
            } catch (_: Throwable) {
                // A failed beep is retried on the next tick.
            }
            handler.postDelayed(this, FALLBACK_PERIOD_MILLIS)
        }
    }

    /**
     * True once a sound is playing (a media player or the fallback tone);
     * false if no sound started.
     */
    val hasPlayer: Boolean get() = player != null || tone != null

    fun start(ramp: AlarmVolumeRamp = AlarmVolumeRamp.NONE) {
        cancelRamp()
        this.ramp = ramp
        if (!ramp.isGradual) {
            startSound(1f)
            startVibration()
            if (ramp.boostToMax) boost()
            return
        }
        rampStartedAt = SystemClock.elapsedRealtime()
        startSound(ramp.gainAt(0L))
        handler.postDelayed(rampTick, AlarmVolumeRamp.TICK_MILLIS)
        handler.postDelayed(vibrationStart, ramp.vibrationDelayMillis)
    }

    private fun startSound(gain: Float) {
        for (uri in candidateUris()) {
            if (uri in failedUris) continue
            if (play(uri, gain)) return
        }
        startFallbackTone()
    }

    /** Default alarm tone first, then the notification and ringtone defaults. */
    private fun candidateUris(): List<Uri> {
        val types = intArrayOf(
            RingtoneManager.TYPE_ALARM,
            RingtoneManager.TYPE_NOTIFICATION,
            RingtoneManager.TYPE_RINGTONE,
        )
        val uris = mutableListOf<Uri>()
        for (type in types) {
            try {
                RingtoneManager.getActualDefaultRingtoneUri(context, type)?.let(uris::add)
            } catch (_: Throwable) {
                // Falls back to the settings URI below.
            }
            RingtoneManager.getDefaultUri(type)?.let(uris::add)
        }
        return uris.distinct()
    }

    private fun play(uri: Uri, gain: Float): Boolean {
        val candidate = MediaPlayer()
        try {
            candidate.apply {
                setAudioAttributes(ALARM_AUDIO_ATTRIBUTES)
                setDataSource(context, uri)
                isLooping = true
                setVolume(gain, gain)
                setOnErrorListener { failed, _, _ ->
                    handler.post { onPlayerError(failed, uri) }
                    true
                }
                prepare()
                start()
            }
        } catch (error: Throwable) {
            Log.w(TAG, "Alarm tone $uri could not be played", error)
            failedUris += uri
            try {
                candidate.release()
            } catch (_: Throwable) {
            }
            return false
        }
        player = candidate
        return true
    }

    /** The player broke while ringing: move on to the next tone, then the beep. */
    private fun onPlayerError(failed: MediaPlayer, uri: Uri) {
        if (player !== failed) return
        Log.w(TAG, "Alarm tone $uri failed while playing")
        failedUris += uri
        try {
            failed.release()
        } catch (_: Throwable) {
        }
        player = null
        startSound(1f)
    }

    private fun startFallbackTone() {
        if (tone != null) return
        try {
            tone = ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
            handler.post(toneLoop)
        } catch (error: Throwable) {
            Log.w(TAG, "The fallback alarm tone is unavailable", error)
            tone?.release()
            tone = null
        }
    }

    private fun stopFallbackTone() {
        handler.removeCallbacks(toneLoop)
        try {
            tone?.stopTone()
            tone?.release()
        } catch (_: Throwable) {
        }
        tone = null
    }

    @Suppress("DEPRECATION")
    private fun startVibration() {
        val vibrator = this.vibrator ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        this.vibrator = vibrator
        // Alarm usage keeps the vibration alive under "Do Not Disturb" with
        // alarms allowed, like the alarm sound.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(
                VibrationEffect.createWaveform(VIBRATION_PATTERN, 0),
                VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM),
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createWaveform(VIBRATION_PATTERN, 0),
                ALARM_AUDIO_ATTRIBUTES,
            )
        } else {
            vibrator.vibrate(VIBRATION_PATTERN, 0, ALARM_AUDIO_ATTRIBUTES)
        }
    }

    /** Silences sound and vibration but keeps the player so [resume] can continue it. */
    fun pause() {
        cancelRamp()
        try {
            if (player?.isPlaying == true) player?.pause()
        } catch (_: Throwable) {
        }
        handler.removeCallbacks(toneLoop)
        try {
            tone?.stopTone()
        } catch (_: Throwable) {
        }
        vibrator?.cancel()
    }

    /**
     * Continues after a pause (a mission attempt ran out). The person is
     * awake by then, so it resumes at full volume without another rise.
     */
    fun resume() {
        if (tone != null) {
            handler.removeCallbacks(toneLoop)
            handler.post(toneLoop)
        } else if (player == null) {
            startSound(1f)
        } else {
            try {
                setGain(1f)
                if (player?.isPlaying != true) player?.start()
            } catch (_: Throwable) {
                player?.release()
                player = null
                startSound(1f)
            }
        }
        startVibration()
        if (ramp.boostToMax) boost()
    }

    fun stop() {
        cancelRamp()
        try {
            player?.stop()
        } catch (_: Throwable) {
        }
        player?.release()
        player = null
        stopFallbackTone()
        failedUris.clear()
        vibrator?.cancel()
        vibrator = null
        if (boosted) {
            AlarmWakePrefs.restoreVolume(context)
            boosted = false
        }
    }

    private fun finishRamp() {
        setGain(1f)
        if (ramp.boostToMax) boost()
    }

    private fun boost() {
        AlarmWakePrefs.boost(context)
        boosted = true
    }

    private fun setGain(gain: Float) {
        try {
            player?.setVolume(gain, gain)
        } catch (_: Throwable) {
        }
    }

    private fun cancelRamp() {
        handler.removeCallbacks(rampTick)
        handler.removeCallbacks(vibrationStart)
    }

    private companion object {
        const val TAG = "AlarmRinger"
        val VIBRATION_PATTERN = longArrayOf(0, 700, 300, 700, 1200)
        const val FALLBACK_TONE = ToneGenerator.TONE_CDMA_ABBR_ALERT
        const val FALLBACK_BURST_MILLIS = 1_000
        const val FALLBACK_PERIOD_MILLIS = 1_500L

        val ALARM_AUDIO_ATTRIBUTES: AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }
}
