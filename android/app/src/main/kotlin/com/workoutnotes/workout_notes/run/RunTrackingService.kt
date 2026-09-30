package com.workoutnotes.workout_notes.run

import android.Manifest
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.content.ContextCompat
import java.time.Instant
import java.util.UUID
import kotlin.math.max

class RunTrackingService : Service(), LocationListener {
    companion object {
        const val EXTRA_ACTIVITY_ID = "activity_id"
        const val ACTION_START = "com.workoutnotes.workout_notes.run.START"
        const val ACTION_PAUSE = "com.workoutnotes.workout_notes.run.PAUSE"
        const val ACTION_RESUME = "com.workoutnotes.workout_notes.run.RESUME"
        const val ACTION_RESTORE = "com.workoutnotes.workout_notes.run.RESTORE"
        const val ACTION_STOP = "com.workoutnotes.workout_notes.run.STOP"
        const val ACTION_DISCARD = "com.workoutnotes.workout_notes.run.DISCARD"
        const val ACTION_LAP = "com.workoutnotes.workout_notes.run.LAP"

        private const val WAKE_LOCK_WINDOW_MS = 6 * 60 * 60 * 1000L
        private const val MAX_ACCURACY_METERS = 40f

        private var activeInstance: RunTrackingService? = null
        @Volatile private var lastState: Map<String, Any?>? = null
        @Volatile var eventSink: ((Map<String, Any?>) -> Unit)? = null

        fun activeInstanceForVoice(): RunTrackingService? = activeInstance

        fun currentState(context: Context): Map<String, Any?> {
            val service = activeInstance
            if (service != null) return service.stateMap()
            return lastState ?: idleState(context)
        }

        fun pauseCurrent(): Map<String, Any?> {
            val service = activeInstance ?: return lastState ?: mapOf("status" to "idle")
            service.pauseRun()
            return service.stateMap()
        }

        fun resumeCurrent(): Map<String, Any?> {
            val service = activeInstance ?: return lastState ?: mapOf("status" to "idle")
            service.resumeRun()
            return service.stateMap()
        }

        fun lapCurrent(): Map<String, Any?> {
            val service = activeInstance ?: return lastState ?: mapOf("status" to "idle")
            service.lapRun()
            return service.stateMap()
        }

        fun stopCurrent(context: Context): Map<String, Any?> {
            val service = activeInstance
            if (service != null) {
                service.finishRun("completed")
                return lastState ?: mapOf("status" to "completed")
            }
            return finalizeOrphanActiveSpool(context, "completed")
        }

        fun discardCurrent(context: Context): Map<String, Any?> {
            val service = activeInstance
            if (service != null) {
                service.finishRun("discarded")
                return lastState ?: mapOf("status" to "discarded")
            }
            return finalizeOrphanActiveSpool(context, "discarded")
        }

        fun idleState(context: Context): Map<String, Any?> = mapOf(
            "supported" to true,
            "location_granted" to locationGranted(context),
            "status" to "idle",
            "updated_at" to Instant.now().toString(),
            "distance_meters" to 0.0,
            "duration_seconds" to 0,
            "moving_time_seconds" to 0,
        )

        /** Precise (fine) location only — coarse is not enough for distance. */
        fun locationGranted(context: Context): Boolean =
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

        private fun isActiveSpoolStatus(status: String?): Boolean =
            status == "starting" ||
                status == "recording" ||
                status == "paused" ||
                status == "stopping"

        /**
         * When stop/discard races ahead of [startRun], finalize the spool on disk
         * so Flutter can still import (or delete) a consistent activity.
         */
        private fun finalizeOrphanActiveSpool(
            context: Context,
            finalStatus: String,
        ): Map<String, Any?> {
            val spool = RunActivitySpool(context.applicationContext)
            // Rare recovery path (stop/discard racing ahead of start, or no
            // location permission on restore): waits on the sequential spool
            // worker so it stays ordered after any queued writes.
            val pending = spool.blocking { listPending() }
            val orphan = pending.firstOrNull { isActiveSpoolStatus(it["status"] as? String) }
            val id = orphan?.get("id")?.toString()
            if (id == null) {
                return lastState ?: idleState(context)
            }
            return try {
                val data = spool.blocking { read(id) }
                @Suppress("UNCHECKED_CAST")
                val session = (data["activity"] as Map<String, Any?>).toMutableMap()
                val endedAt = System.currentTimeMillis()
                val startedAt = parseMillis(session["started_at"]) ?: endedAt
                val durationSeconds = max(
                    (session["duration_seconds"] as? Number)?.toInt() ?: 0,
                    ((endedAt - startedAt) / 1000L).toInt(),
                )
                val movingTimeSeconds = (session["moving_time_seconds"] as? Number)?.toInt()
                    ?: durationSeconds
                val distanceMeters = (session["distance_meters"] as? Number)?.toDouble() ?: 0.0
                session["status"] = finalStatus
                session["ended_at"] = Instant.ofEpochMilli(endedAt).toString()
                session["duration_seconds"] = durationSeconds
                session["moving_time_seconds"] = movingTimeSeconds.coerceAtMost(durationSeconds)
                session["avg_pace_sec_per_km"] =
                    RunGeoMath.paceSecPerKm(distanceMeters, movingTimeSeconds)
                session["calories"] = RunGeoMath.estimateCalories(distanceMeters)

                if (finalStatus == "discarded") {
                    spool.blocking { delete(id) }
                } else {
                    spool.blocking { updateActivity(session) }
                }

                val state = mapOf(
                    "supported" to true,
                    "location_granted" to locationGranted(context),
                    "status" to finalStatus,
                    "activity_id" to id,
                    "started_at" to session["started_at"],
                    "updated_at" to Instant.now().toString(),
                    "distance_meters" to distanceMeters,
                    "duration_seconds" to durationSeconds,
                    "moving_time_seconds" to movingTimeSeconds,
                    "avg_pace_sec_per_km" to session["avg_pace_sec_per_km"],
                )
                lastState = state
                eventSink?.invoke(state)
                state
            } catch (_: Throwable) {
                lastState ?: idleState(context)
            }
        }

        private fun parseMillis(value: Any?): Long? {
            val text = value as? String ?: return null
            return try {
                Instant.parse(text).toEpochMilli()
            } catch (_: Throwable) {
                null
            }
        }
    }

    private lateinit var spool: RunActivitySpool
    private lateinit var locationManager: LocationManager
    private var wakeLock: PowerManager.WakeLock? = null
    lateinit var voiceController: RunVoiceController
        private set
    private var activity: MutableMap<String, Any?>? = null
    private var status: String = "idle"
    private var startedAtMillis: Long = 0L
    private var pausedAtMillis: Long = 0L
    private var totalPausedMillis: Long = 0L
    private var distanceMeters: Double = 0.0
    private var pointSeq: Int = 0
    private var lastLocation: Location? = null
    private var currentLat: Double? = null
    private var currentLng: Double? = null
    private var currentAccuracy: Float? = null
    private var currentPaceSecPerKm: Double? = null
    private var maxPaceSecPerKm: Double? = null
    private var finished = false
    private var tickCount = 0
    private val completedSplits = mutableListOf<Map<String, Any?>>()
    private var nextSplitAtMeters = 1000.0
    private var lastSplitMovingSeconds = 0

    // Auto-pause: the run stays "recording" but its clock and distance stop
    // while the detector reports stillness. Reported to Dart as `auto_paused`.
    private val autoPauseDetector = RunAutoPauseDetector()
    private var autoPaused = false
    private var autoPausedAtMillis = 0L
    private var totalAutoPausedMillis = 0L
    private val lapTracker = RunLapTracker()

    private val mainHandler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() {
            if (finished) return
            if (status == "recording" || status == "paused") {
                renewWakeLockIfNeeded()
                tickCount += 1
                if (status == "recording") reconcileAutoPauseSetting()
                // Persist duration periodically so recovery after kill is accurate.
                if (tickCount % 5 == 0) {
                    persistLiveTotals()
                }
                publishState()
                updateNotification()
            }
            mainHandler.postDelayed(this, 1000L)
        }
    }

    /** Writes IDs and per-session options without resetting the live tracker. */
    fun persistSessionContext(context: Map<String, Any?>) {
        val session = activity ?: return
        session["plan_workout_id"] = context["plan_workout_id"]
        session["scheduled_run_id"] = context["scheduled_run_id"]
        session["session_goal"] = context["goal"]
        session["session_intervals_on"] = context["intervals_on"] as? Boolean ?: false
        val plan = RunWorkoutStepNative.listFromAny(context["plan_steps"])
        if (plan.isNotEmpty()) {
            session["voice_plan_json"] = RunWorkoutStepNative.listToJsonString(plan)
        }
        spool.updateActivityAsync(session)
        publishState()
    }

    private fun applyPendingSessionContext(session: MutableMap<String, Any?>) {
        val context = RunTrackingBridge.pendingSessionContext ?: return
        session["plan_workout_id"] = context["plan_workout_id"]
        session["scheduled_run_id"] = context["scheduled_run_id"]
        session["session_goal"] = context["goal"]
        session["session_intervals_on"] = context["intervals_on"] as? Boolean ?: false
        val plan = RunWorkoutStepNative.listFromAny(context["plan_steps"])
        if (plan.isNotEmpty()) {
            session["voice_plan_json"] = RunWorkoutStepNative.listToJsonString(plan)
        }
    }

    private fun sessionContextMap(): Map<String, Any?>? {
        val session = activity ?: return null
        val planId = session["plan_workout_id"] as? String
        val scheduledId = session["scheduled_run_id"] as? String
        @Suppress("UNCHECKED_CAST")
        val goal = session["session_goal"] as? Map<String, Any?>
        val intervalsOn = session["session_intervals_on"] as? Boolean ?: false
        if (planId == null && scheduledId == null && goal == null && !intervalsOn) return null
        return mapOf(
            "plan_workout_id" to planId,
            "scheduled_run_id" to scheduledId,
            "goal" to (goal ?: mapOf(
                "enabled" to false,
                "metric" to "distance",
                "value" to 5000,
            )),
            "intervals_on" to intervalsOn,
        )
    }

    override fun onCreate() {
        super.onCreate()
        spool = RunActivitySpool(this)
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        voiceController = RunVoiceController(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRun(intent.getStringExtra(EXTRA_ACTIVITY_ID))
            ACTION_PAUSE -> pauseRun()
            ACTION_RESUME -> resumeRun()
            ACTION_LAP -> lapRun()
            ACTION_RESTORE -> {
                if (activeInstance == null || status == "idle") {
                    restoreActiveSessionIfNeeded()
                }
            }
            ACTION_STOP -> finishRun("completed")
            ACTION_DISCARD -> finishRun("discarded")
            else -> {
                // START_STICKY restart (null/unknown action): reattach live spool.
                if (activeInstance == null || status == "idle") {
                    restoreActiveSessionIfNeeded()
                }
            }
        }
        return START_STICKY
    }

    private fun startRun(requestedId: String?) {
        if (activeInstance != null && status != "idle") {
            publishState()
            return
        }
        if (!locationGranted(this)) {
            lastState = idleState(this) + mapOf(
                "error_code" to "location_denied",
                "error_message" to "Precise location permission denied",
            )
            eventSink?.invoke(lastState!!)
            stopSelf()
            return
        }

        activeInstance = this
        finished = false
        status = "starting"
        val id = requestedId ?: UUID.randomUUID().toString()
        startedAtMillis = System.currentTimeMillis()
        pausedAtMillis = 0L
        totalPausedMillis = 0L
        distanceMeters = 0.0
        pointSeq = 0
        lastLocation = null
        currentPaceSecPerKm = null
        maxPaceSecPerKm = null
        completedSplits.clear()
        nextSplitAtMeters = 1000.0
        lastSplitMovingSeconds = 0
        resetAutoPauseAndLaps()
        tickCount = 0

        val session = mutableMapOf<String, Any?>(
            "id" to id,
            "status" to "recording",
            "started_at" to Instant.ofEpochMilli(startedAtMillis).toString(),
            "ended_at" to null,
            "duration_seconds" to 0,
            "moving_time_seconds" to 0,
            "distance_meters" to 0.0,
            "avg_pace_sec_per_km" to null,
            "max_pace_sec_per_km" to null,
            "calories" to 0,
            "title" to null,
            "notes" to null,
        )
        applyPendingSessionContext(session)
        activity = session
        spool.createAsync(session)

        promoteToForeground("recording")
        acquireWakeLock()
        status = "recording"
        session["status"] = "recording"
        spool.updateActivityAsync(session)
        // Native TTS: consume pending settings from bridge or DB
        try {
            val pendingS = RunVoiceBridge.pendingSettings
            val pendingG = RunVoiceBridge.pendingGoal
            val pendingI = RunVoiceBridge.pendingIntervalsOn
            voiceController.begin(pendingS, pendingG, pendingI, RunVoiceBridge.pendingPlan)
            persistVoicePlan()
        } catch (_: Throwable) {
            voiceController.begin(null, null, null)
        }
        startLocationUpdates()
        mainHandler.removeCallbacks(tickRunnable)
        mainHandler.post(tickRunnable)
        publishState()
    }

    /**
     * After process death + START_STICKY, reload the in-progress spool and
     * continue GPS (or stay paused). Next fix is treated as a fresh anchor so
     * the kill gap does not inflate distance.
     */
    private fun restoreActiveSessionIfNeeded() {
        // Process-death recovery: one blocking read on the sequential worker.
        val pending = spool.blocking { listPending() }
        val orphan = pending.firstOrNull {
            isActiveSpoolStatus(it["status"] as? String)
        }
        val id = orphan?.get("id")?.toString()
        if (id == null) {
            stopSelf()
            return
        }
        if (!locationGranted(this)) {
            finalizeOrphanActiveSpool(this, "completed")
            stopSelf()
            return
        }

        val data = try {
            spool.blocking { read(id) }
        } catch (_: Throwable) {
            stopSelf()
            return
        }

        @Suppress("UNCHECKED_CAST")
        val session = (data["activity"] as Map<String, Any?>).toMutableMap()
        @Suppress("UNCHECKED_CAST")
        val points = (data["points"] as? List<Map<String, Any?>>) ?: emptyList()

        activeInstance = this
        finished = false
        activity = session
        startedAtMillis = parseMillis(session["started_at"]) ?: System.currentTimeMillis()
        distanceMeters = (session["distance_meters"] as? Number)?.toDouble() ?: 0.0
        pointSeq = points.maxOfOrNull { (it["seq"] as? Number)?.toInt() ?: 0 }?.plus(1) ?: 0
        lastLocation = null
        currentPaceSecPerKm = null
        maxPaceSecPerKm = (session["max_pace_sec_per_km"] as? Number)?.toDouble()
        currentLat = points.lastOrNull()?.let { (it["lat"] as? Number)?.toDouble() }
        currentLng = points.lastOrNull()?.let { (it["lng"] as? Number)?.toDouble() }

        completedSplits.clear()
        val rawSplits = session["splits"]
        if (rawSplits is List<*>) {
            for (row in rawSplits) {
                if (row is Map<*, *>) {
                    @Suppress("UNCHECKED_CAST")
                    completedSplits.add(row as Map<String, Any?>)
                }
            }
        }
        val recovery = RunTrackingRecovery.restore(
            session,
            completedSplits,
            System.currentTimeMillis(),
        )
        nextSplitAtMeters = recovery.nextSplitAtMeters
        lastSplitMovingSeconds = recovery.lastSplitMovingSeconds
        totalPausedMillis = recovery.totalPausedMillis
        pausedAtMillis = recovery.pausedAtMillis
        tickCount = 0

        val restoredStatus = when (session["status"] as? String) {
            "paused" -> "paused"
            else -> "recording"
        }
        totalAutoPausedMillis = recovery.totalAutoPausedMillis
        autoPaused = restoredStatus == "recording" && recovery.autoPausedAtMillis > 0L
        autoPausedAtMillis = if (autoPaused) recovery.autoPausedAtMillis else 0L
        autoPauseDetector.reset(startPaused = autoPaused)
        restoreLaps(session)
        status = restoredStatus
        session["status"] = restoredStatus
        spool.updateActivityAsync(session)

        promoteToForeground(restoredStatus)
        acquireWakeLock()
        // Restore voice: reload settings from DB and resume active flag
        try {
            voiceController.loadSettingsFromDb()
            // Resume as active if was recording/paused — next tick will drive intervals
            @Suppress("UNCHECKED_CAST")
            val hasIntervals = (session["voice_intervals_on"] as? Boolean) ?: voiceController.let {
                // Fallback: check bridge pending or defaults
                RunVoiceBridge.pendingIntervalsOn
            }
            // Rehydrate the goal, structured plan and execution cursor so a
            // killed process keeps cueing the remaining reps.
            voiceController.restoreGoalJson(session["voice_goal_json"] as? String)
            val restoredPlan = session["voice_plan_json"] as? String
            voiceController.begin(
                null,
                null,
                hasIntervals,
                restoredPlan,
            )
            voiceController.restoreEngineSnapshot(
                session["voice_engine_snapshot_json"] as? String,
            )
            if (restoredStatus == "paused") {
                // voice pauses naturally via tick(recording=false)
            }
        } catch (_: Throwable) {}
        if (restoredStatus == "recording") {
            startLocationUpdates()
        }
        mainHandler.removeCallbacks(tickRunnable)
        mainHandler.post(tickRunnable)
        publishState()
    }

    private fun pauseRun() {
        if (status != "recording") return
        closeAutoPauseInterval()
        status = "paused"
        pausedAtMillis = System.currentTimeMillis()
        // Drop anchor so resume does not credit distance moved while paused.
        lastLocation = null
        activity?.let {
            it["status"] = "paused"
            spool.updateActivityAsync(it)
        }
        persistLiveTotals()
        // Make the paused state durable before it is reported (waits for the
        // queued writes only; the queue is normally empty or a single write).
        spool.flush()
        stopLocationUpdates()
        updateNotification()
        publishState()
    }

    private fun resumeRun() {
        // "Resume" while auto-paused means "I'm moving, carry on".
        if (status == "recording" && autoPaused) {
            endAutoPause()
            return
        }
        if (status != "paused") return
        if (pausedAtMillis > 0L) {
            totalPausedMillis += System.currentTimeMillis() - pausedAtMillis
            pausedAtMillis = 0L
        }
        status = "recording"
        lastLocation = null
        autoPauseDetector.reset()
        activity?.let {
            it["status"] = "recording"
        }
        persistLiveTotals()
        startLocationUpdates()
        updateNotification()
        publishState()
    }

    private fun finishRun(finalStatus: String) {
        if (finished) return
        finished = true
        status = "stopping"
        stopLocationUpdates()
        mainHandler.removeCallbacks(tickRunnable)
        try { voiceController.end() } catch (_: Throwable) {}

        val session = activity
        if (session == null) {
            cleanupAndStop()
            return
        }

        if (pausedAtMillis > 0L) {
            totalPausedMillis += System.currentTimeMillis() - pausedAtMillis
            pausedAtMillis = 0L
        }
        closeAutoPauseInterval()

        val endedAt = System.currentTimeMillis()
        val durationSeconds = max(0, ((endedAt - startedAtMillis) / 1000L).toInt())
        val movingTimeSeconds = max(
            0,
            durationSeconds - ((totalPausedMillis + totalAutoPausedMillis) / 1000L).toInt(),
        )
        val avgPace = RunGeoMath.paceSecPerKm(distanceMeters, movingTimeSeconds)
        val calories = RunGeoMath.estimateCalories(distanceMeters)

        session["status"] = finalStatus
        session["ended_at"] = Instant.ofEpochMilli(endedAt).toString()
        session["duration_seconds"] = durationSeconds
        session["moving_time_seconds"] = movingTimeSeconds
        session["distance_meters"] = distanceMeters
        session["avg_pace_sec_per_km"] = avgPace
        session["max_pace_sec_per_km"] = maxPaceSecPerKm
        session["calories"] = calories
        session["splits"] = completedSplits.toList()
        // Manual laps: the remainder after the last lap closes the set.
        lapTracker.closeFinal(distanceMeters, movingTimeSeconds)
        persistRuntimeSnapshot(session)
        spool.updateActivityAsync(session)
        if (finalStatus == "discarded") {
            spool.deleteAsync(session["id"].toString())
        }
        // Durable stop: everything queued (points, checkpoints, the final
        // activity) must be on disk before the stop is reported, so the Dart
        // side never imports a spool that is still being written.
        spool.flush()

        status = finalStatus
        val state = stateMap()
        lastState = state
        eventSink?.invoke(state)

        cleanupAndStop()
    }

    private fun cleanupAndStop() {
        releaseWakeLock()
        activeInstance = null
        RunTrackingBridge.pendingSessionContext = null
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    private fun promoteToForeground(runStatus: String) {
        RunTrackingNotification.ensureChannel(this)
        val notification = buildNotification(runStatus)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val types = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            startForeground(
                RunTrackingNotification.NOTIFICATION_ID,
                notification,
                types,
            )
        } else {
            startForeground(RunTrackingNotification.NOTIFICATION_ID, notification)
        }
    }

    private fun startLocationUpdates() {
        if (!locationGranted(this)) return
        try {
            val criteria = android.location.Criteria().apply {
                accuracy = android.location.Criteria.ACCURACY_FINE
                powerRequirement = android.location.Criteria.POWER_HIGH
                isAltitudeRequired = false
                isBearingRequired = false
                isSpeedRequired = false
            }
            val best = locationManager.getBestProvider(criteria, true)
            val provider = when {
                // Prefer raw GPS when available — more stable distance than network.
                locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                    LocationManager.GPS_PROVIDER
                best != null -> best
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                    LocationManager.NETWORK_PROVIDER
                else -> LocationManager.GPS_PROVIDER
            }
            locationManager.requestLocationUpdates(
                provider,
                1000L,
                0f,
                this,
                Looper.getMainLooper(),
            )
        } catch (_: SecurityException) {
            lastState = stateMap() + mapOf(
                "error_code" to "location_denied",
                "error_message" to "Precise location permission denied",
            )
            eventSink?.invoke(lastState!!)
        }
    }

    private fun stopLocationUpdates() {
        try {
            locationManager.removeUpdates(this)
        } catch (_: Throwable) {
        }
    }

    override fun onLocationChanged(location: Location) {
        if (status != "recording" || finished) return
        currentLat = location.latitude
        currentLng = location.longitude
        currentAccuracy = if (location.hasAccuracy()) location.accuracy else null

        if (autoPauseActive()) {
            val event = autoPauseDetector.onFix(
                location.time,
                location.latitude,
                location.longitude,
                if (location.hasSpeed()) location.speed.toDouble() else null,
                currentAccuracy,
            )
            when (event) {
                RunAutoPauseDetector.Event.PAUSE -> beginAutoPause()
                RunAutoPauseDetector.Event.RESUME -> endAutoPause()
                RunAutoPauseDetector.Event.NONE -> Unit
            }
        }
        if (autoPaused) {
            // Standing still: keep the map dot alive, but no distance or route.
            publishState()
            return
        }

        val previous = lastLocation
        if (previous == null) {
            // Need a usable fix before anchoring; otherwise distance stays wrong.
            val accuracy = currentAccuracy
            if (accuracy == null || accuracy > MAX_ACCURACY_METERS) {
                publishState()
                return
            }
            acceptPoint(location, distanceDelta = 0.0)
            return
        }

        val delta = RunGeoMath.haversineMeters(
            previous.latitude,
            previous.longitude,
            location.latitude,
            location.longitude,
        )
        val timeDeltaSec = ((location.time - previous.time) / 1000.0).coerceAtLeast(0.1)
        if (!RunGeoMath.shouldAcceptPoint(currentAccuracy, delta, timeDeltaSec)) {
            publishState()
            return
        }

        val instantPace = RunGeoMath.paceSecPerKm(delta, timeDeltaSec.toInt().coerceAtLeast(1))
        if (instantPace != null && instantPace in 120.0..1200.0) {
            currentPaceSecPerKm = instantPace
            maxPaceSecPerKm = when (val existing = maxPaceSecPerKm) {
                null -> instantPace
                else -> minOf(existing, instantPace) // lower sec/km = faster
            }
        }

        distanceMeters += delta
        acceptPoint(location, distanceDelta = delta)
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    override fun onProviderEnabled(provider: String) {}

    override fun onProviderDisabled(provider: String) {}

    private fun recordCompletedSplits() {
        val moving = movingSeconds()
        while (distanceMeters >= nextSplitAtMeters) {
            val splitDuration = max(0, moving - lastSplitMovingSeconds)
            val km = (nextSplitAtMeters / 1000.0).toInt()
            completedSplits.add(
                mapOf(
                    "km" to km,
                    "distance_meters" to 1000.0,
                    "duration_seconds" to splitDuration,
                    "pace_sec_per_km" to splitDuration.toDouble(),
                    "is_partial" to false,
                ),
            )
            lastSplitMovingSeconds = moving
            nextSplitAtMeters += 1000.0
        }
    }

    private fun currentPartialSplit(): Map<String, Any?>? {
        if (distanceMeters < 1.0 && completedSplits.isEmpty()) return null
        val partialMeters = distanceMeters % 1000.0
        // Exactly on a km boundary with no leftover.
        if (partialMeters < 0.5 && distanceMeters >= 1000.0) return null
        val moving = movingSeconds()
        val duration = max(0, moving - lastSplitMovingSeconds)
        val km = completedSplits.size + 1
        val pace = if (partialMeters >= 1.0) {
            duration / (partialMeters / 1000.0)
        } else {
            null
        }
        return mapOf(
            "km" to km,
            "distance_meters" to partialMeters,
            "duration_seconds" to duration,
            "pace_sec_per_km" to pace,
            "is_partial" to true,
        )
    }

    private fun acceptPoint(location: Location, distanceDelta: Double) {
        lastLocation = location
        val session = activity ?: return
        val id = session["id"].toString()
        val point = mapOf(
            "id" to UUID.randomUUID().toString(),
            "activity_id" to id,
            "seq" to pointSeq,
            "lat" to location.latitude,
            "lng" to location.longitude,
            "altitude" to if (location.hasAltitude()) location.altitude else null,
            "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
            "speed" to if (location.hasSpeed()) location.speed.toDouble() else null,
            "recorded_at" to Instant.ofEpochMilli(location.time).toString(),
            "distance_delta_meters" to distanceDelta,
        )
        pointSeq += 1
        spool.appendPointAsync(point)

        if (distanceDelta > 0) {
            recordCompletedSplits()
        }

        persistLiveTotals()
        publishState()
    }

    /**
     * Mirrors the structured plan (and the intervals flag) into the spool so a
     * process death mid-session resumes cueing the remaining reps instead of
     * silently degrading to a plain run.
     */
    fun persistVoicePlan() {
        val session = activity ?: return
        try {
            session["voice_plan_json"] = voiceController.planStepsJson()
            session["voice_goal_json"] = voiceController.goalJson()
            session["voice_intervals_on"] = voiceController.intervalsEnabled
            session["voice_engine_snapshot_json"] = voiceController.engineSnapshotJson()
            session["voice_step_results"] = voiceController.stepResults()
            spool.updateActivityAsync(session)
        } catch (_: Throwable) {
            // Best-effort: a spool write failure must never abort the run.
        }
    }

    private fun autoPauseActive(): Boolean =
        voiceController.autoPauseEnabled &&
            // A structured session or interval set owns its own clock: standing
            // still during a timed recovery must not freeze it.
            !voiceController.hasPlan &&
            !voiceController.intervalsEnabled

    /** The setting can change mid-run (voice settings, intervals armed). */
    private fun reconcileAutoPauseSetting() {
        if (autoPauseActive()) return
        if (autoPaused) endAutoPause() else autoPauseDetector.reset()
    }

    private fun beginAutoPause() {
        if (autoPaused || status != "recording") return
        autoPaused = true
        autoPausedAtMillis = System.currentTimeMillis()
        lastLocation = null
        currentPaceSecPerKm = null
        persistLiveTotals()
        updateNotification()
        publishState()
    }

    private fun endAutoPause() {
        if (!autoPaused) return
        closeAutoPauseInterval()
        autoPauseDetector.reset()
        // The next fix re-anchors, so the stop credits no distance.
        lastLocation = null
        persistLiveTotals()
        updateNotification()
        publishState()
    }

    /** Folds an open auto-pause into the total (no notification/publish). */
    private fun closeAutoPauseInterval() {
        if (autoPausedAtMillis > 0L) {
            totalAutoPausedMillis += System.currentTimeMillis() - autoPausedAtMillis
        }
        autoPaused = false
        autoPausedAtMillis = 0L
    }

    private fun resetAutoPauseAndLaps() {
        autoPaused = false
        autoPausedAtMillis = 0L
        totalAutoPausedMillis = 0L
        autoPauseDetector.reset()
        lapTracker.reset()
    }

    private fun restoreLaps(session: Map<String, Any?>) {
        val laps = mutableListOf<Map<String, Any?>>()
        (session["laps"] as? List<*>)?.forEach { row ->
            if (row is Map<*, *>) {
                @Suppress("UNCHECKED_CAST")
                laps.add(row as Map<String, Any?>)
            }
        }
        lapTracker.restore(
            laps,
            (session["lap_start_distance_meters"] as? Number)?.toDouble() ?: 0.0,
            (session["lap_start_moving_seconds"] as? Number)?.toInt() ?: 0,
        )
    }

    /** Marks a manual lap at the current distance / moving time. */
    fun lapRun(): Map<String, Any?>? {
        if (finished || status != "recording") return null
        val lap = lapTracker.mark(distanceMeters, movingSeconds()) ?: return null
        persistLiveTotals()
        try {
            voiceController.announceLap(lap)
        } catch (_: Throwable) {
        }
        publishState()
        return lap
    }

    /** Skips the current structured step / interval phase. */
    fun skipStep(): Boolean {
        val skipped = try {
            voiceController.skipStep()
        } catch (_: Throwable) {
            false
        }
        if (skipped) {
            persistVoicePlan()
            publishState()
        }
        return skipped
    }

    private fun persistLiveTotals() {
        val session = activity ?: return
        val durationSeconds = elapsedSeconds()
        val movingTimeSeconds = movingSeconds()
        session["distance_meters"] = distanceMeters
        session["duration_seconds"] = durationSeconds
        session["moving_time_seconds"] = movingTimeSeconds
        session["avg_pace_sec_per_km"] =
            RunGeoMath.paceSecPerKm(distanceMeters, movingTimeSeconds)
        session["max_pace_sec_per_km"] = maxPaceSecPerKm
        session["calories"] = RunGeoMath.estimateCalories(distanceMeters)
        session["splits"] = completedSplits.toList()
        persistRuntimeSnapshot(session)
        spool.updateActivityAsync(session)
    }

    private fun persistRuntimeSnapshot(session: MutableMap<String, Any?>) {
        session["paused_at_millis"] = pausedAtMillis.takeIf { it > 0L }
        session["total_paused_millis"] = totalPausedMillis
        session["auto_paused_at_millis"] = autoPausedAtMillis.takeIf { it > 0L }
        session["total_auto_paused_millis"] = totalAutoPausedMillis
        session["laps"] = lapTracker.completedLaps()
        session["lap_start_distance_meters"] = lapTracker.startDistanceMeters
        session["lap_start_moving_seconds"] = lapTracker.startMovingSeconds
        session["last_split_moving_seconds"] = lastSplitMovingSeconds
        session["next_split_at_meters"] = nextSplitAtMeters
        session["voice_engine_snapshot_json"] = voiceController.engineSnapshotJson()
        session["voice_step_results"] = voiceController.stepResults()
    }

    private fun elapsedSeconds(): Int {
        val now = System.currentTimeMillis()
        return max(0, ((now - startedAtMillis) / 1000L).toInt())
    }

    private fun movingSeconds(): Int {
        val pausedExtra = if (status == "paused" && pausedAtMillis > 0L) {
            System.currentTimeMillis() - pausedAtMillis
        } else {
            0L
        }
        val autoExtra = if (autoPaused && autoPausedAtMillis > 0L) {
            System.currentTimeMillis() - autoPausedAtMillis
        } else {
            0L
        }
        val pausedTotal = totalPausedMillis + pausedExtra + totalAutoPausedMillis + autoExtra
        return max(0, elapsedSeconds() - (pausedTotal / 1000L).toInt())
    }

    private fun stateMap(): Map<String, Any?> {
        val session = activity
        val splits = completedSplits.toList()
        val partial = currentPartialSplit()
        return mapOf(
            "supported" to true,
            "location_granted" to locationGranted(this),
            "status" to status,
            "activity_id" to session?.get("id"),
            "started_at" to session?.get("started_at"),
            "updated_at" to Instant.now().toString(),
            "distance_meters" to distanceMeters,
            "duration_seconds" to elapsedSeconds(),
            "moving_time_seconds" to movingSeconds(),
            "current_pace_sec_per_km" to currentPaceSecPerKm,
            "avg_pace_sec_per_km" to RunGeoMath.paceSecPerKm(distanceMeters, movingSeconds()),
            "lat" to currentLat,
            "lng" to currentLng,
            "accuracy_meters" to currentAccuracy?.toDouble(),
            "point_count" to pointSeq,
            "splits" to splits,
            "current_split" to partial,
            "auto_paused" to (autoPaused && status == "recording"),
            "laps" to lapTracker.completedLaps(),
            "current_lap" to lapTracker.current(distanceMeters, movingSeconds()),
            "session_context" to sessionContextMap(),
            "step_snapshot" to voiceController.stepSnapshotMap(),
            "interval_snapshot" to voiceController.intervalSnapshotMap(),
        )
    }

    private fun publishState() {
        val state = stateMap()
        lastState = state
        eventSink?.invoke(state)
        // Drive native voice while screen off — no Flutter needed.
        try {
            voiceController.onTrackingUpdate(
                distanceMeters = distanceMeters,
                durationSeconds = elapsedSeconds(),
                movingTimeSeconds = movingSeconds(),
                currentPaceSecPerKm = currentPaceSecPerKm,
                lat = currentLat,
                accuracyMeters = currentAccuracy,
                isRecording = status == "recording" && !autoPaused,
                isPaused = status == "paused",
                splitsCount = completedSplits.size,
                currentSplitPace = null,
                splits = completedSplits.toList(),
                autoPaused = autoPaused && status == "recording",
            )
        } catch (_: Throwable) {}
    }

    private fun buildNotification(runStatus: String) = RunTrackingNotification.build(
        this,
        startedAtMillis,
        distanceMeters,
        movingSeconds(),
        currentPaceSecPerKm,
        runStatus,
        autoPaused = autoPaused && runStatus == "recording",
    )

    private fun updateNotification() {
        val notification = buildNotification(status)
        val manager = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
        manager.notify(RunTrackingNotification.NOTIFICATION_ID, notification)
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val power = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "workout_notes:run_tracking",
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_WINDOW_MS)
        }
    }

    private fun renewWakeLockIfNeeded() {
        if (wakeLock?.isHeld == true) return
        acquireWakeLock()
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {
        }
        wakeLock = null
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(tickRunnable)
        stopLocationUpdates()
        releaseWakeLock()
        try { voiceController.shutdown() } catch (_: Throwable) {}
        if (activeInstance === this) activeInstance = null
        super.onDestroy()
    }
}
