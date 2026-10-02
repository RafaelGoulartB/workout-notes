package com.workoutnotes.workout_notes.run

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.workoutnotes.workout_notes.MainActivity
import com.workoutnotes.workout_notes.common.PendingIntentFlags
import kotlin.math.max

/**
 * Voice coach for treadmill runs. Indoor sessions are timed in Dart without
 * GPS, but the coach must keep talking with the screen off, so this small
 * foreground service owns a moving clock and a [RunVoiceController] in indoor
 * mode (time-driven cues only). Dart drives it through [RunVoiceBridge]
 * (`indoorStart` / `indoorPause` / `indoorResume` / `indoorState` /
 * `indoorStop`) and reads the step snapshot back for the record screen.
 *
 * It lives in the app process: if the process dies the Dart session is gone
 * too, so there is nothing to restore (START_NOT_STICKY).
 */
class RunIndoorVoiceService : Service() {

    companion object {
        private const val ACTION_START = "com.workoutnotes.workout_notes.run.INDOOR_VOICE_START"
        private const val NOTIFICATION_ID = 1211
        private const val REQUEST_OPEN = 1212
        private const val WAKE_LOCK_WINDOW_MS = 4 * 60 * 60 * 1000L

        @Volatile private var instance: RunIndoorVoiceService? = null
        @Volatile private var pendingArgs: Map<String, Any?>? = null

        fun activeController(): RunVoiceController? = instance?.controller

        fun start(context: Context, args: Map<String, Any?>): Boolean {
            instance?.let {
                it.beginSession(args)
                return true
            }
            pendingArgs = args
            return try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, RunIndoorVoiceService::class.java).setAction(ACTION_START),
                )
                true
            } catch (e: Throwable) {
                Log.w("RunIndoorVoice", "start failed: ${e.message}")
                pendingArgs = null
                false
            }
        }

        fun pause() {
            instance?.pauseClock()
        }

        fun resume() {
            instance?.resumeClock()
        }

        fun skipStep(): Boolean = instance?.controller?.skipStep() ?: false

        fun state(): Map<String, Any?>? = instance?.stateMap()

        /** Ends the session and returns the per-step results of a structured workout. */
        fun stop(context: Context): List<Map<String, Any?>> {
            pendingArgs = null
            val service = instance ?: return emptyList()
            return service.stopSession()
        }
    }

    private lateinit var controller: RunVoiceController
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var startedAtMillis = 0L
    private var resumedAtMillis = 0L
    private var accumulatedMovingMillis = 0L
    private var paused = false
    private var running = false

    private val ticker = object : Runnable {
        override fun run() {
            if (!running) return
            tick()
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        controller = RunVoiceController(this)
        controller.indoor = true
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Always promote first: a service started with startForegroundService
        // must call startForeground even when it is about to stop.
        promoteToForeground()
        val args = pendingArgs
        pendingArgs = null
        if (intent?.action != ACTION_START || args == null) {
            if (!running) stopNow()
            return START_NOT_STICKY
        }
        instance = this
        beginSession(args)
        return START_NOT_STICKY
    }

    private fun beginSession(args: Map<String, Any?>) {
        @Suppress("UNCHECKED_CAST")
        controller.begin(
            args["settings"] as? Map<String, Any?>,
            args["goal"] as? Map<String, Any?>,
            false,
            args["plan"],
            args["workout"] as? Map<String, Any?>,
        )
        startedAtMillis = System.currentTimeMillis()
        resumedAtMillis = startedAtMillis
        accumulatedMovingMillis = 0L
        paused = false
        running = true
        acquireWakeLock()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    private fun movingSeconds(): Int {
        val live = if (paused || resumedAtMillis == 0L) 0L else System.currentTimeMillis() - resumedAtMillis
        return ((accumulatedMovingMillis + live) / 1000L).toInt()
    }

    private fun tick() {
        val elapsed = max(0, ((System.currentTimeMillis() - startedAtMillis) / 1000L).toInt())
        controller.onTrackingUpdate(
            distanceMeters = 0.0,
            durationSeconds = elapsed,
            movingTimeSeconds = movingSeconds(),
            currentPaceSecPerKm = null,
            lat = null,
            accuracyMeters = null,
            isRecording = !paused,
            isPaused = paused,
            splitsCount = 0,
            currentSplitPace = null,
            splits = emptyList(),
        )
    }

    private fun pauseClock() {
        if (!running || paused) return
        accumulatedMovingMillis += System.currentTimeMillis() - resumedAtMillis
        paused = true
        tick()
    }

    private fun resumeClock() {
        if (!running || !paused) return
        resumedAtMillis = System.currentTimeMillis()
        paused = false
        tick()
    }

    private fun stateMap(): Map<String, Any?> = mapOf(
        "moving_time_seconds" to movingSeconds(),
        "step_snapshot" to controller.stepSnapshotMap(),
        "interval_snapshot" to controller.intervalSnapshotMap(),
    )

    private fun stopSession(): List<Map<String, Any?>> {
        running = false
        handler.removeCallbacks(ticker)
        controller.end()
        val results = controller.stepResults()
        stopNow()
        return results
    }

    private fun stopNow() {
        running = false
        handler.removeCallbacks(ticker)
        releaseWakeLock()
        if (instance === this) instance = null
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Throwable) {}
        stopSelf()
    }

    private fun promoteToForeground() {
        RunTrackingNotification.ensureChannel(this)
        val pt = resources.configuration.locales[0].language == "pt"
        val openIntent = PendingIntent.getActivity(
            this,
            REQUEST_OPEN,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, RunTrackingNotification.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
            .setContentTitle(if (pt) "Corrida na esteira" else "Treadmill run")
            .setContentText(if (pt) "Treinador de voz ativo" else "Voice coach on")
            .setContentIntent(openIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Throwable) {
            Log.w("RunIndoorVoice", "startForeground refused: ${e.message}")
        }
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val power = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "workout_notes:run_indoor_voice",
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_WINDOW_MS)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {}
        wakeLock = null
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(ticker)
        releaseWakeLock()
        try { controller.shutdown() } catch (_: Throwable) {}
        if (instance === this) instance = null
        super.onDestroy()
    }
}
