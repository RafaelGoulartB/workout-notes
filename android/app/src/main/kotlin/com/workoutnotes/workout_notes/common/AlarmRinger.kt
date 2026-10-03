package com.workoutnotes.workout_notes.common

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Looping alarm sound (default alarm ringtone, falling back to the default
 * notification tone) plus a repeating vibration. Shared by the sleep,
 * traditional and medication alarm services, which all ring identically.
 *
 * With a gradual [AlarmVolumeRamp] the sound starts soft and rises, the
 * vibration joins halfway and, optionally, the alarm volume is raised to its
 * maximum at the end. [stop] restores that volume.
 */
class AlarmRinger(private val context: Context) {
    private var player: MediaPlayer? = null
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

    /** True once a media player exists; false if sound never started or failed. */
    val hasPlayer: Boolean get() = player != null

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
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(context, uri)
                isLooping = true
                setVolume(gain, gain)
                prepare()
                start()
            }
        } catch (_: Throwable) {
            player?.release()
            player = null
        }
    }

    @Suppress("DEPRECATION")
    private fun startVibration() {
        val vibrator = this.vibrator ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        this.vibrator = vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(VIBRATION_PATTERN, 0))
        } else {
            vibrator.vibrate(VIBRATION_PATTERN, 0)
        }
    }

    /** Silences sound and vibration but keeps the player so [resume] can continue it. */
    fun pause() {
        cancelRamp()
        try {
            if (player?.isPlaying == true) player?.pause()
        } catch (_: Throwable) {
        }
        vibrator?.cancel()
    }

    /**
     * Continues after a pause (a mission attempt ran out). The person is
     * awake by then, so it resumes at full volume without another rise.
     */
    fun resume() {
        if (player == null) {
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
        val VIBRATION_PATTERN = longArrayOf(0, 700, 300, 700, 1200)
    }
}
