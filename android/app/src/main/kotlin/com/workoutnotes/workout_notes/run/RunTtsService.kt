package com.workoutnotes.workout_notes.run

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue

/** Speech sink used by [RunVoiceController]; faked in unit tests. */
interface RunSpeechOutput {
    fun ensureReady(language: RunVoiceLanguage)
    fun setLanguage(language: RunVoiceLanguage)
    fun speak(text: String)
    fun stop()
    fun shutdown()

    /** Voice speed, volume (0–1) and whether other media is paused rather than ducked. */
    fun configure(rate: Float, volume: Float, pauseMedia: Boolean) {}

    /** Plays [earcon]; [then], when given, is spoken right after the tone. */
    fun playEarcon(earcon: RunEarcon, then: String?) {
        then?.let { speak(it) }
    }
}

/**
 * Native TTS bound to the run foreground service lifecycle.
 * Survives screen-off because it lives inside the run services.
 *
 * Audio focus is held per burst, not per utterance: it is requested when the
 * first tone or phrase starts and released only once everything queued has
 * finished, so music is ducked once instead of pumping between two cues.
 * With "pause media" speech asks for exclusive transient focus (podcasts
 * pause), while beeps always only duck.
 */
class RunTtsService(private val context: Context) : RunSpeechOutput, TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    @Volatile private var ready = false
    @Volatile private var initializing = false
    // Terminal: once shut down, late callbacks must not recreate the engine.
    @Volatile private var isShutDown = false
    @Volatile private var desiredLanguage = RunVoiceLanguage.en
    private val pendingQueue = LinkedBlockingQueue<String>()
    private var audioManager: AudioManager? = null
    private val handler = Handler(Looper.getMainLooper())
    // Tones still playing; released by their own callback or by shutdown().
    private val playingTracks = java.util.Collections.synchronizedSet(mutableSetOf<AudioTrack>())

    @Volatile private var rate = 1.0f
    @Volatile private var volume = 1.0f
    @Volatile private var pauseMedia = false

    // Focus bookkeeping, only touched on the main thread.
    private var activeOutputs = 0
    private var focusRequest: AudioFocusRequest? = null
    private var focusExclusive = false
    private val focusListener = AudioManager.OnAudioFocusChangeListener {}
    private val releaseFocus = Runnable { abandonFocus() }

    override fun configure(rate: Float, volume: Float, pauseMedia: Boolean) {
        this.rate = rate.coerceIn(0.5f, 2.0f)
        this.volume = volume.coerceIn(0.1f, 1.0f)
        this.pauseMedia = pauseMedia
        val engine = tts
        if (ready && engine != null) engine.setSpeechRate(this.rate)
    }

    override fun ensureReady(language: RunVoiceLanguage) {
        if (isShutDown) return
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
            // Android TextToSpeech scale: 1.0 is the normal rate.
            engine.setSpeechRate(rate)
            engine.setPitch(1.0f)
            engine.setAudioAttributes(attributes())
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) = outputFinished()
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = outputFinished()
                override fun onError(utteranceId: String?, errorCode: Int) = outputFinished()
                override fun onStop(utteranceId: String?, interrupted: Boolean) = outputFinished()
            })
            ready = true
            initializing = false
            // Drain queued phrases
            while (pendingQueue.isNotEmpty()) {
                val text = pendingQueue.poll() ?: break
                onMain { speakInternal(text) }
            }
            Log.i("RunTts", "TTS ready ${localeFor(desiredLanguage).toLanguageTag()}")
        } catch (e: Throwable) {
            Log.w("RunTts", "TTS onInit config failed: ${e.message}")
            initializing = false
        }
    }

    private fun attributes(): AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    override fun setLanguage(language: RunVoiceLanguage) {
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
        if (availability < TextToSpeech.LANG_AVAILABLE) {
            Log.w("RunTts", "TTS language unavailable: ${locale.toLanguageTag()} status=$availability")
        }
        // Keep the requested locale even when unavailable: the engine reports
        // the synthesis error instead of reading the phrase with a foreign voice.
        engine.language = locale
    }

    override fun speak(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || isShutDown) return
        if (!ready) {
            pendingQueue.offer(trimmed)
            ensureReady(desiredLanguage)
            return
        }
        onMain { speakInternal(trimmed) }
    }

    private fun speakInternal(text: String) {
        if (isShutDown) return
        val engine = tts ?: return
        try {
            outputStarted(speech = true)
            val params = Bundle().apply {
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
            }
            // QUEUE_ADD: the scheduler already decides what is worth saying,
            // so nothing it lets through should cut a previous cue short.
            val result = engine.speak(text, TextToSpeech.QUEUE_ADD, params, "run_${System.nanoTime()}")
            if (result != TextToSpeech.SUCCESS) outputFinished()
            Log.i("RunTts", "speak: $text")
        } catch (e: Throwable) {
            outputFinished()
            Log.w("RunTts", "speak failed: ${e.message}")
        }
    }

    override fun playEarcon(earcon: RunEarcon, then: String?) {
        if (isShutDown) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            then?.let { speak(it) }
            return
        }
        onMain {
            if (isShutDown) return@onMain
            val track = try {
                val pcm = RunEarconSynth.pcm(earcon)
                AudioTrack.Builder()
                    .setAudioAttributes(attributes())
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(RunEarconSynth.SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build(),
                    )
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(pcm.size * 2)
                    .build()
                    .also {
                        it.write(pcm, 0, pcm.size)
                        it.setVolume(volume)
                    }
            } catch (e: Throwable) {
                Log.w("RunTts", "earcon failed: ${e.message}")
                null
            }
            if (track == null) {
                then?.let { speak(it) }
                return@onMain
            }
            outputStarted(speech = false)
            playingTracks.add(track)
            try {
                track.play()
            } catch (e: Throwable) {
                Log.w("RunTts", "earcon play failed: ${e.message}")
            }
            handler.postDelayed({
                playingTracks.remove(track)
                try { track.release() } catch (_: Throwable) {}
                if (isShutDown) return@postDelayed
                // Speak before releasing the tone's share of focus, so the
                // music is not un-ducked between the beep and the words.
                then?.let { speak(it) }
                outputFinished()
            }, RunEarconSynth.durationMillis(earcon) + 60L)
        }
    }

    override fun stop() {
        try {
            tts?.stop()
        } catch (_: Throwable) {}
        pendingQueue.clear()
        onMain {
            activeOutputs = 0
            abandonFocus()
        }
    }

    override fun shutdown() {
        isShutDown = true
        // Drop pending earcon/focus callbacks: one of them could otherwise call
        // speak() after shutdown and recreate an engine nobody shuts down.
        handler.removeCallbacksAndMessages(null)
        val tracks = synchronized(playingTracks) { playingTracks.toList().also { playingTracks.clear() } }
        tracks.forEach { try { it.release() } catch (_: Throwable) {} }
        stop()
        try {
            tts?.shutdown()
        } catch (_: Throwable) {}
        tts = null
        ready = false
        initializing = false
    }

    private fun outputStarted(speech: Boolean) {
        handler.removeCallbacks(releaseFocus)
        activeOutputs += 1
        val exclusive = speech && pauseMedia
        if (focusRequest == null || (exclusive && !focusExclusive)) requestFocus(exclusive)
    }

    private fun outputFinished() {
        onMain {
            activeOutputs = (activeOutputs - 1).coerceAtLeast(0)
            if (activeOutputs == 0) {
                handler.removeCallbacks(releaseFocus)
                handler.postDelayed(releaseFocus, FOCUS_RELEASE_DELAY_MS)
            }
        }
    }

    private fun requestFocus(exclusive: Boolean) {
        try {
            val am = audioManager ?: (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).also { audioManager = it }
            val gain = if (exclusive) AudioManager.AUDIOFOCUS_GAIN_TRANSIENT else AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { am.abandonAudioFocusRequest(it) }
                val req = AudioFocusRequest.Builder(gain)
                    .setAudioAttributes(attributes())
                    .setOnAudioFocusChangeListener(focusListener, handler)
                    .build()
                focusRequest = req
                am.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, gain)
                focusRequest = null
            }
            focusExclusive = exclusive
            legacyFocusHeld = true
        } catch (_: Throwable) {}
    }

    private var legacyFocusHeld = false

    private fun abandonFocus() {
        if (activeOutputs > 0) return
        try {
            val am = audioManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else if (legacyFocusHeld) {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(focusListener)
            }
        } catch (_: Throwable) {}
        focusRequest = null
        focusExclusive = false
        legacyFocusHeld = false
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else handler.post(block)
    }

    private companion object {
        /** Bridges the gap between back-to-back cues so the music does not bounce. */
        const val FOCUS_RELEASE_DELAY_MS = 400L
    }
}
