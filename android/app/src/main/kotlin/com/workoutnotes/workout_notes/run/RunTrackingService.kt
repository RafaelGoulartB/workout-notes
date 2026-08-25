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
            val pending = spool.listPending()
            val orphan = pending.firstOrNull { isActiveSpoolStatus(it["status"] as? String) }
            val id = orphan?.get("id")?.toString()
            if (id == null) {
                return lastState ?: idleState(context)
            }
            return try {
                val data = spool.read(id)
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
                    spool.delete(id)
                } else {
                    spool.updateActivity(session)
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
    // Native debug simulation (emulator background survives like real GPS)
    private var isNativeDebugSim: Boolean = false
    private var debugTick: Int = 0
    private var debugLat: Double = -23.5505
    private var debugLng: Double = -46.6333
    private val mainHandler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() {
            if (finished) return
            if (status == "recording" || status == "paused") {
                renewWakeLockIfNeeded()
                tickCount += 1
                // Native debug sim synthesizes movement even with no GPS.
                if (isNativeDebugSim && status == "recording") {
                    synthesizeDebugTick()
                }
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
        spool.updateActivity(session)
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

    private fun speedForDebugTick(tick: Int): Double {
        val slowWave = 3.5 * kotlin.math.sin(tick * 0.14)
        val fastWave = 1.8 * kotlin.math.sin(tick * 0.37 + 0.6)
        val surge = if (tick % 28 < 4) 2.8 else 0.0
        val dip = if (tick % 55 > 40) -2.2 else 0.0
        return (14.0 + slowWave + fastWave + surge + dip).coerceIn(8.0, 22.0)
    }

    private fun synthesizeDebugTick() {
        debugTick += 1
        val step = speedForDebugTick(debugTick)
        val headingRad = (debugTick * 0.035) % (2 * Math.PI)
        val dLat = (step * kotlin.math.cos(headingRad)) / 111320.0
        val dLng = (step * kotlin.math.sin(headingRad)) / (111320.0 * kotlin.math.cos(Math.toRadians(debugLat)))
        debugLat += dLat
        debugLng += dLng
        // Update map state and spool as if a real fix arrived.
        currentLat = debugLat
        currentLng = debugLng
        currentAccuracy = 5f
        val instantPace = 1000.0 / step
        if (instantPace in 60.0..1800.0) {
            currentPaceSecPerKm = instantPace
            maxPaceSecPerKm = maxPaceSecPerKm?.let { minOf(it, instantPace) } ?: instantPace
        }
        distanceMeters += step
        // Synthesize a Location for spool persistence
        val loc = Location("debug").apply {
            latitude = debugLat
            longitude = debugLng
            time = System.currentTimeMillis()
            accuracy = 5f
            speed = step.toFloat()
        }
        acceptPoint(loc, distanceDelta = step)
        // acceptPoint already calls persist + publish; avoid double publish
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
            "com.workoutnotes.workout_notes.run.START_DEBUG" -> {
                val lat = intent.getDoubleExtra("debug_start_lat", -23.5505)
                val lng = intent.getDoubleExtra("debug_start_lng", -46.6333)
                startNativeDebugSimulation(lat, lng)
            }
            ACTION_PAUSE -> pauseRun()
            ACTION_RESUME -> resumeRun()
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
        isNativeDebugSim = false
        debugTick = 0
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
        spool.create(session)

        promoteToForeground("recording")
        acquireWakeLock()
        status = "recording"
        session["status"] = "recording"
        spool.updateActivity(session)
        // Native TTS: consume pending settings from bridge or DB
        try {
            val pendingS = RunVoiceBridge.pendingSettings
            val pendingG = RunVoiceBridge.pendingGoal
            val pendingI = RunVoiceBridge.pendingIntervalsOn
            val pendingB = RunVoiceBridge.pendingBypassGate
            voiceController.begin(pendingS, pendingG, pendingI, pendingB, RunVoiceBridge.pendingPlan)
            persistVoicePlan()
        } catch (_: Throwable) {
            voiceController.begin(null, null, null, null)
        }
        startLocationUpdates()
        mainHandler.removeCallbacks(tickRunnable)
        mainHandler.post(tickRunnable)
        publishState()
    }

    fun startNativeDebugSimulation(startLat: Double, startLng: Double): Boolean {
        if (activeInstance != null && status != "idle") {
            publishState()
            return false
        }
        // Debug sim does not require location permission — it's synthetic.
        activeInstance = this
        finished = false
        isNativeDebugSim = true
        debugLat = startLat
        debugLng = startLng
        debugTick = 0
        status = "starting"
        val id = UUID.randomUUID().toString()
        startedAtMillis = System.currentTimeMillis()
        pausedAtMillis = 0L
        totalPausedMillis = 0L
        distanceMeters = 0.0
        pointSeq = 0
        lastLocation = null
        currentLat = startLat
        currentLng = startLng
        currentAccuracy = 5f
        currentPaceSecPerKm = 1000.0 / 14.0
        maxPaceSecPerKm = currentPaceSecPerKm
        completedSplits.clear()
        nextSplitAtMeters = 1000.0
        lastSplitMovingSeconds = 0
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
            "title" to "Debug Run",
            "notes" to "Simulated debug run (native - background capable)",
        )
        applyPendingSessionContext(session)
        activity = session
        spool.create(session)

        promoteToForeground("recording")
        acquireWakeLock()
        status = "recording"
        session["status"] = "recording"
        spool.updateActivity(session)
        try {
            val pendingS = RunVoiceBridge.pendingSettings
            val pendingG = RunVoiceBridge.pendingGoal
            val pendingI = RunVoiceBridge.pendingIntervalsOn
            val pendingB = RunVoiceBridge.pendingBypassGate
            // For debug sim we force bypass headset gate so emulator without headset still speaks
            voiceController.begin(pendingS, pendingG, pendingI, true, RunVoiceBridge.pendingPlan)
            persistVoicePlan()
        } catch (_: Throwable) {
            voiceController.begin(null, null, null, true)
        }
        // No real GPS — synthesized ticks drive everything
        mainHandler.removeCallbacks(tickRunnable)
        mainHandler.post(tickRunnable)
        publishState()
        return true
    }

    /**
     * After process death + START_STICKY, reload the in-progress spool and
     * continue GPS (or stay paused). Next fix is treated as a fresh anchor so
     * the kill gap does not inflate distance.
     */
    private fun restoreActiveSessionIfNeeded() {
        val pending = spool.listPending()
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
            spool.read(id)
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
        status = restoredStatus
        session["status"] = restoredStatus
        spool.updateActivity(session)

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
                RunVoiceBridge.pendingBypassGate,
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
        status = "paused"
        pausedAtMillis = System.currentTimeMillis()
        // Drop anchor so resume does not credit distance moved while paused.
        lastLocation = null
        activity?.let {
            it["status"] = "paused"
            spool.updateActivity(it)
        }
        persistLiveTotals()
        stopLocationUpdates()
        updateNotification()
        publishState()
    }

    private fun resumeRun() {
        if (status != "paused") return
        if (pausedAtMillis > 0L) {
            totalPausedMillis += System.currentTimeMillis() - pausedAtMillis
            pausedAtMillis = 0L
        }
        status = "recording"
        lastLocation = null
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

        val endedAt = System.currentTimeMillis()
        val durationSeconds = max(0, ((endedAt - startedAtMillis) / 1000L).toInt())
        val movingTimeSeconds = max(0, durationSeconds - (totalPausedMillis / 1000L).toInt())
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
        persistRuntimeSnapshot(session)
        spool.updateActivity(session)

        status = finalStatus
        val state = stateMap()
        lastState = state
        eventSink?.invoke(state)

        if (finalStatus == "discarded") {
            spool.delete(session["id"].toString())
        }

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
        val notification = RunTrackingNotification.build(
            this,
            startedAtMillis,
            distanceMeters,
            elapsedSeconds(),
            runStatus,
        )
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
        spool.appendPoint(point)

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
            spool.updateActivity(session)
        } catch (_: Throwable) {
            // Best-effort: a spool write failure must never abort the run.
        }
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
        spool.updateActivity(session)
    }

    private fun persistRuntimeSnapshot(session: MutableMap<String, Any?>) {
        session["paused_at_millis"] = pausedAtMillis.takeIf { it > 0L }
        session["total_paused_millis"] = totalPausedMillis
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
        val pausedTotal = totalPausedMillis + pausedExtra
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
            "session_context" to sessionContextMap(),
            "step_snapshot" to voiceController.stepSnapshotMap(),
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
                isRecording = status == "recording",
                isPaused = status == "paused",
                splitsCount = completedSplits.size,
                currentSplitPace = null,
                splits = completedSplits.toList(),
            )
        } catch (_: Throwable) {}
    }

    private fun updateNotification() {
        val notification = RunTrackingNotification.build(
            this,
            startedAtMillis,
            distanceMeters,
            elapsedSeconds(),
            status,
        )
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
