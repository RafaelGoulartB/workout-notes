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
    @Volatile private var desiredLanguage = RunVoiceLanguage.en
    private val pendingQueue = LinkedBlockingQueue<String>()
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null

    fun ensureReady(language: RunVoiceLanguage = desiredLanguage) {
        desiredLanguage = language
        if (ready) {
            applyLanguage(tts ?: return)
            return
        }
        if (initializing) return
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
            applyLanguage(engine)
            // flutter_tts normalizes its 0.48 setting to 0.96 on Android
            // (the plugin multiplies the Dart value by 2). This native path
            // must use the Android TextToSpeech scale directly, where 1.0 is
            // the normal rate, so both execution paths sound the same.
            engine.setSpeechRate(0.96f)
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
            Log.i("RunTts", "TTS ready ${localeFor(desiredLanguage).toLanguageTag()}")
        } catch (e: Throwable) {
            Log.w("RunTts", "TTS onInit config failed: ${e.message}")
            initializing = false
        }
    }

    fun setLanguage(language: RunVoiceLanguage) {
        desiredLanguage = language
        val engine = tts
        if (ready && engine != null) applyLanguage(engine)
    }

    private fun localeFor(language: RunVoiceLanguage): Locale = when (language) {
        RunVoiceLanguage.pt -> Locale.forLanguageTag("pt-BR")
        RunVoiceLanguage.app, RunVoiceLanguage.en -> Locale.US
    }

    private fun applyLanguage(engine: TextToSpeech) {
        val locale = localeFor(desiredLanguage)
        val availability = engine.isLanguageAvailable(locale)
        if (availability >= TextToSpeech.LANG_AVAILABLE) {
            engine.language = locale
        } else {
            Log.w("RunTts", "TTS language unavailable: ${locale.toLanguageTag()} status=$availability")
            // Keep the requested locale. The engine reports the synthesis error
            // instead of reading Portuguese phrases with an English voice.
            engine.language = locale
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
            engine.speak(text, TextToSpeech.QUEUE_ADD, params, "run_${System.currentTimeMillis()}")
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
