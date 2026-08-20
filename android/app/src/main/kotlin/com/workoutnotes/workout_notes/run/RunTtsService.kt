package com.workoutnotes.workout_notes.run

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue
import android.util.Log

/**
 * Native TTS bound to the run foreground service lifecycle.
 * Survives screen-off because it lives inside RunTrackingService.
 * Uses STREAM_MUSIC with USAGE_ASSISTANCE_NAVIGATION_GUIDANCE equivalent.
 */
class RunTtsService(private val context: Context) : TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    @Volatile private var ready = false
    @Volatile private var initializing = false
    private val pendingQueue = LinkedBlockingQueue<String>()
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null

    fun ensureReady() {
        if (ready || initializing) return
        initializing = true
        try {
            tts = TextToSpeech(context.applicationContext, this)
        } catch (e: Throwable) {
            Log.w("RunTts", "TTS create failed: ${e.message}")
            initializing = false
        }
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Log.w("RunTts", "TTS init failed status=$status")
            initializing = false
            ready = false
            return
        }
        val engine = tts ?: return
        try {
            val locale = Locale("en", "US")
            val avail = engine.isLanguageAvailable(locale)
            if (avail >= TextToSpeech.LANG_AVAILABLE) {
                engine.language = locale
            } else {
                engine.language = Locale.US
            }
            engine.setSpeechRate(0.48f)
            engine.setPitch(1.0f)
            // Ensure we play on music stream and duck other audio briefly.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                engine.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
            }
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    abandonFocus()
                }
                override fun onError(utteranceId: String?) {
                    abandonFocus()
                }
            })
            ready = true
            initializing = false
            // Drain queued phrases
            while (pendingQueue.isNotEmpty()) {
                val text = pendingQueue.poll() ?: break
                speakInternal(text)
            }
            Log.i("RunTts", "TTS ready en-US")
        } catch (e: Throwable) {
            Log.w("RunTts", "TTS onInit config failed: ${e.message}")
            initializing = false
        }
    }

    fun speak(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        if (!ready) {
            pendingQueue.offer(trimmed)
            ensureReady()
            return
        }
        speakInternal(trimmed)
    }

    private fun speakInternal(text: String) {
        val engine = tts ?: return
        try {
            requestFocus()
            // QUEUE_FLUSH for run cues — each cue should be immediate.
            val params = Bundle().apply {
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
            }
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, "run_${System.currentTimeMillis()}")
            Log.i("RunTts", "speak: $text")
        } catch (e: Throwable) {
            Log.w("RunTts", "speak failed: ${e.message}")
        }
    }

    fun stop() {
        try {
            tts?.stop()
        } catch (_: Throwable) {}
        pendingQueue.clear()
        abandonFocus()
    }

    fun shutdown() {
        stop()
        try {
            tts?.shutdown()
        } catch (_: Throwable) {}
        tts = null
        ready = false
        initializing = false
    }

    private fun requestFocus() {
        try {
            val am = audioManager ?: (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).also { audioManager = it }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .setOnAudioFocusChangeListener {}
                    .build()
                focusRequest = req
                am.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            }
        } catch (_: Throwable) {}
    }

    private fun abandonFocus() {
        try {
            val am = audioManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { am.abandonAudioFocusRequest(it) }
                focusRequest = null
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(null)
            }
        } catch (_: Throwable) {}
    }
}
