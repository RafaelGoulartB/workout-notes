package com.workoutnotes.workout_notes.run

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * Synthesizes the coach's short tones. A beep says "step change" in a fraction
 * of a second, so it interrupts music far less than words would.
 */
object RunEarconSynth {
    const val SAMPLE_RATE = 22_050

    data class Tone(val frequencyHz: Double, val millis: Int)

    private const val GAP_MS = 60

    fun tones(earcon: RunEarcon): List<Tone> = when (earcon) {
        RunEarcon.countdown -> listOf(Tone(880.0, 110))
        RunEarcon.go -> listOf(Tone(1318.5, 320))
        RunEarcon.ease -> listOf(Tone(784.0, 150), Tone(523.3, 220))
        RunEarcon.done -> listOf(Tone(523.3, 120), Tone(659.3, 120), Tone(784.0, 260))
        RunEarcon.pause -> listOf(Tone(440.0, 180))
        RunEarcon.resume -> listOf(Tone(659.3, 180))
    }

    fun durationMillis(earcon: RunEarcon): Int {
        val tones = tones(earcon)
        return tones.sumOf { it.millis } + GAP_MS * (tones.size - 1)
    }

    /** 16-bit mono PCM with short fades so the tones never click. */
    fun pcm(earcon: RunEarcon, amplitude: Double = 0.45): ShortArray {
        val out = ArrayList<Short>()
        val tones = tones(earcon)
        val fade = SAMPLE_RATE * 6 / 1000
        tones.forEachIndexed { index, tone ->
            val samples = SAMPLE_RATE * tone.millis / 1000
            for (i in 0 until samples) {
                val envelope = min(1.0, min(i.toDouble() / fade, (samples - 1 - i).toDouble() / fade))
                val value = sin(2 * PI * tone.frequencyHz * i / SAMPLE_RATE) * amplitude * envelope
                out.add((value * Short.MAX_VALUE).toInt().toShort())
            }
            if (index < tones.lastIndex) repeat(SAMPLE_RATE * GAP_MS / 1000) { out.add(0) }
        }
        return out.toShortArray()
    }
}

/** Vibration sink used by [RunVoiceController]; faked in unit tests. */
interface RunHaptics {
    fun vibrate(pattern: RunHapticPattern)
}

class AndroidRunHaptics(private val context: Context) : RunHaptics {
    private var vibrator: Vibrator? = null

    @Suppress("DEPRECATION")
    override fun vibrate(pattern: RunHapticPattern) {
        try {
            val vibrator = this.vibrator ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            this.vibrator = vibrator
            val timings = when (pattern) {
                RunHapticPattern.tick -> longArrayOf(0, 40)
                RunHapticPattern.go -> longArrayOf(0, 350)
                RunHapticPattern.ease -> longArrayOf(0, 120, 100, 120)
                RunHapticPattern.done -> longArrayOf(0, 120, 90, 120, 90, 260)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(timings, -1))
            } else {
                vibrator.vibrate(timings, -1)
            }
        } catch (e: Throwable) {
            Log.w("RunHaptics", "vibrate failed: ${e.message}")
        }
    }
}
