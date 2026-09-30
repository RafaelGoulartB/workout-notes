package com.workoutnotes.workout_notes.common

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Looping alarm sound (default alarm ringtone, falling back to the default
 * notification tone) plus a repeating vibration. Shared by the sleep,
 * traditional and medication alarm services, which all ring identically.
 */
class AlarmRinger(private val context: Context) {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    /** True once a media player exists; false if sound never started or failed. */
    val hasPlayer: Boolean get() = player != null

    fun start() {
        startSound()
        startVibration()
    }

    fun startSound() {
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
                prepare()
                start()
            }
        } catch (_: Throwable) {
            player?.release()
            player = null
        }
    }

    @Suppress("DEPRECATION")
    fun startVibration() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
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
        try {
            if (player?.isPlaying == true) player?.pause()
        } catch (_: Throwable) {
        }
        vibrator?.cancel()
    }

    fun resume() {
        if (player == null) {
            startSound()
        } else {
            try {
                if (player?.isPlaying != true) player?.start()
            } catch (_: Throwable) {
                player?.release()
                player = null
                startSound()
            }
        }
        startVibration()
    }

    fun stop() {
        try {
            player?.stop()
        } catch (_: Throwable) {
        }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
    }

    private companion object {
        val VIBRATION_PATTERN = longArrayOf(0, 700, 300, 700, 1200)
    }
}
