package com.workoutnotes.workout_notes.run

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.util.Log
import org.json.JSONObject

private data class RunVoicePacePoint(
    val atMillis: Long,
    val distanceMeters: Double,
    val movingSeconds: Int,
)

/**
 * Native voice coach — mirrors Dart RunVoiceCoach logic but runs inside
 * RunTrackingService so announcements survive screen-off / Flutter engine death.
 */
class RunVoiceController(private val context: Context) {

    private val tts = RunTtsService(context)
    private val intervalEngine = RunIntervalEngineNative()

    /** Structured plan session. Takes precedence over [intervalEngine]. */
    private val stepEngine = RunWorkoutStepEngineNative()
    private var planSteps: List<RunWorkoutStepNative> = emptyList()
    private var settings: RunVoiceSettings = RunVoiceSettings.defaults()
    private var goal: RunSessionGoal = RunSessionGoal.disabled()
    private var intervalsOn: Boolean = false
    private var bypassHeadphonesGate: Boolean = false
    private var active: Boolean = false
    private var goalCompleted: Boolean = false

    // Free-run dedup
    private var lastAnnouncedKm: Int = 0
    private var lastSplitCount: Int = 0
    private var lastWeakGps: Boolean? = null
    private var lastGpsAnnounceAt: Long = 0L
    private var lastPaceAnnounceAt: Long = 0L
    private val goalProgressCues = mutableSetOf<Int>()
    private val paceSamples = ArrayDeque<RunVoicePacePoint>()
    private var paceDeviationSince: Long = 0L
    private var paceDeviationDirection: Int = 0
    private var paceCorrectionSpoken: Boolean = false
    private var wasPaused: Boolean? = null

    // Persisted settings cache
    @Volatile private var settingsLoaded = false

    fun loadSettingsFromDb(): RunVoiceSettings {
        // Try SharedPreferences mirror first (fast), then SQLite app_settings
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            // Flutter SharedPreferences stores as flutter.<key>
            val raw = prefs.getString("flutter.${RunVoiceSettings.STORAGE_KEY}", null)
                ?: prefs.getString(RunVoiceSettings.STORAGE_KEY, null)
            if (!raw.isNullOrBlank()) {
                val parsed = RunVoiceSettings.fromJsonString(raw)
                settings = parsed
                intervalEngine.configure(parsed.interval)
                settingsLoaded = true
                return parsed
            }
        } catch (_: Throwable) {}

        // Fallback: read SQLite directly
        try {
            val dbPath = context.getDatabasePath("workout_notes.db")
            if (dbPath.exists()) {
                val db = SQLiteDatabase.openDatabase(dbPath.path, null, SQLiteDatabase.OPEN_READONLY)
                try {
                    val cursor = db.rawQuery("SELECT value FROM app_settings WHERE key = ?", arrayOf(RunVoiceSettings.STORAGE_KEY))
                    if (cursor.moveToFirst()) {
                        val raw = cursor.getString(0)
                        val parsed = RunVoiceSettings.fromJsonString(raw)
                        settings = parsed
                        intervalEngine.configure(parsed.interval)
                        settingsLoaded = true
                        return parsed
                    }
                    cursor.close()
                } finally {
                    db.close()
                }
            }
        } catch (e: Throwable) {
            Log.w("RunVoice", "DB read failed: ${e.message}")
        }
        val defaults = RunVoiceSettings.defaults()
        settings = defaults
        intervalEngine.configure(defaults.interval)
        return defaults
    }

    fun configure(
        settings: RunVoiceSettings,
        goal: RunSessionGoal,
        intervalsOn: Boolean,
        bypassHeadphonesGate: Boolean = false,
        planSteps: List<RunWorkoutStepNative> = emptyList(),
    ) {
        this.settings = settings
        this.goal = goal
        this.intervalsOn = intervalsOn
        this.bypassHeadphonesGate = bypassHeadphonesGate
        intervalEngine.configure(settings.interval)
        setPlanSteps(planSteps)
    }

    /** Loads a structured session. Empty clears it and falls back to presets. */
    fun setPlanSteps(steps: List<RunWorkoutStepNative>) {
        planSteps = steps
        stepEngine.configure(steps)
    }

    /** Serialized plan for the run spool, so a killed process resumes cueing. */
    fun planStepsJson(): String? =
        if (planSteps.isEmpty()) null else RunWorkoutStepNative.listToJsonString(planSteps)

    /** Per-step results collected during the session, for Dart to persist. */
    fun stepResults(): List<Map<String, Any?>> = stepEngine.results.map { it.toMap() }

    val hasPlan: Boolean get() = stepEngine.hasPlan
    val intervalsEnabled: Boolean get() = intervalsOn

    fun goalJson(): String = goal.toJson().toString()

    fun restoreGoalJson(raw: String?) {
        if (raw.isNullOrBlank()) return
        try {
            goal = RunSessionGoal.fromJson(JSONObject(raw))
        } catch (_: Throwable) {}
    }

    fun syncFromFlutter(
        settingsMap: Map<String, Any?>?,
        goalMap: Map<String, Any?>?,
        intervalsOn: Boolean?,
        bypassGate: Boolean?,
        plan: Any? = null,
    ) {
        if (plan != null) setPlanSteps(RunWorkoutStepNative.listFromAny(plan))
        if (settingsMap != null) {
            val parsed = RunVoiceSettings.fromMap(settingsMap)
            this.settings = parsed
            intervalEngine.configure(parsed.interval)
        }
        if (goalMap != null) {
            this.goal = RunSessionGoal.fromMap(goalMap)
        }
        if (intervalsOn != null) this.intervalsOn = intervalsOn
        if (bypassGate != null) this.bypassHeadphonesGate = bypassGate
        Log.i("RunVoice", "sync intervalsOn=$intervalsOn goal=${goal.enabled} enabled=${settings.enabled}")
    }

    fun begin(
        settingsMap: Map<String, Any?>?,
        goalMap: Map<String, Any?>?,
        intervalsOn: Boolean?,
        bypassGate: Boolean?,
        plan: Any? = null,
    ) {
        // If flutter didn't push settings, load from storage
        if (settingsMap == null && !settingsLoaded) {
            loadSettingsFromDb()
        } else if (settingsMap != null) {
            val parsed = RunVoiceSettings.fromMap(settingsMap)
            settings = parsed
            intervalEngine.configure(parsed.interval)
        }
        if (goalMap != null) goal = RunSessionGoal.fromMap(goalMap)
        // If caller didn't specify intervalsOn, respect default
        this.intervalsOn = intervalsOn ?: settings.intervalsEnabledByDefault
        this.bypassHeadphonesGate = bypassGate ?: false
        active = true
        goalCompleted = false
        lastAnnouncedKm = 0
        lastSplitCount = 0
        lastWeakGps = null
        lastGpsAnnounceAt = 0L
        lastPaceAnnounceAt = 0L
        goalProgressCues.clear()
        paceSamples.clear()
        paceDeviationSince = 0L
        paceDeviationDirection = 0
        paceCorrectionSpoken = false
        wasPaused = null
        intervalEngine.reset()
        if (plan != null) setPlanSteps(RunWorkoutStepNative.listFromAny(plan))
        stepEngine.reset()
        tts.ensureReady()
        Log.i(
            "RunVoice",
            "begin intervalsOn=${this.intervalsOn} goal=${goal.enabled} ${goal.metric} ${goal.value} planSteps=${stepEngine.totalSteps}",
        )
    }

    fun end() {
        active = false
        goalCompleted = false
        intervalEngine.reset()
        // Keep the step results — Dart reads them after stop() to persist
        // planned-vs-actual. finish() closes a partial step.
        stepEngine.finish()
        tts.stop()
        Log.i("RunVoice", "end")
    }

    fun shutdown() {
        end()
        tts.shutdown()
    }

    fun speakTest() {
        if (!settings.enabled) {
            loadSettingsFromDb()
        }
        tts.ensureReady()
        // Queue a short test phrase even if queueing before init
        tts.speak("Voice cues ready. Pace 5 30 per kilometer.")
    }

    // Called from RunTrackingService on each publishState / location update
    fun onTrackingUpdate(
        distanceMeters: Double,
        durationSeconds: Int,
        movingTimeSeconds: Int,
        currentPaceSecPerKm: Double?,
        lat: Double?,
        accuracyMeters: Float?,
        isRecording: Boolean,
        isPaused: Boolean,
        splitsCount: Int,
        currentSplitPace: Double?,
        splits: List<Map<String, Any?>>,
    ) {
        if (!active) return
        if (!settings.enabled) return

        val phrases = mutableListOf<String>()

        if (isRecording || isPaused) {
            val previousPaused = wasPaused
            wasPaused = isPaused
            if (previousPaused != null && previousPaused != isPaused) {
                phrases.add(if (isPaused) RunVoicePhrases.paused() else RunVoicePhrases.resumed())
            }
        }

        // Goal completion wins
        val goalJustCompleted = checkGoalCompletion(distanceMeters, movingTimeSeconds, isRecording, isPaused)
        if (goalJustCompleted) {
            phrases.add(RunVoicePhrases.goalComplete(goal.metric, goal.value))
            // keep the structured/preset counters in sync
            if (stepEngine.hasPlan) {
                advanceStepEngine(isRecording, distanceMeters, movingTimeSeconds, speak = false)
            } else {
                if (intervalsOn && intervalEngine.snapshot.phase == RunIntervalPhase.idle && isRecording) {
                    intervalEngine.start()
                }
                intervalEngine.tick(isRecording, distanceMeters, movingTimeSeconds)
            }
            phrases.addAll(collectFreeRunPhrases(distanceMeters, durationSeconds, movingTimeSeconds, currentPaceSecPerKm, lat, accuracyMeters, isRecording, splitsCount, splits))
        } else if (stepEngine.hasPlan) {
            // A planned session takes over from the quick interval preset.
            phrases.addAll(
                advanceStepEngine(
                    isRecording,
                    distanceMeters,
                    movingTimeSeconds,
                    speak = true,
                )
            )
            if (isRecording || isPaused) {
                phrases.addAll(collectFreeRunPhrases(distanceMeters, durationSeconds, movingTimeSeconds, currentPaceSecPerKm, lat, accuracyMeters, isRecording, splitsCount, splits))
            }
        } else {
            if (intervalsOn && settings.announceIntervals && isRecording && intervalEngine.snapshot.phase == RunIntervalPhase.idle) {
                val startEvents = intervalEngine.start()
                for (event in startEvents) {
                    phraseForInterval(event)?.let { phrases.add(it) }
                }
            }
            if (intervalsOn && settings.announceIntervals) {
                val intervalEvents = intervalEngine.tick(isRecording, distanceMeters, movingTimeSeconds)
                for (event in intervalEvents) {
                    phraseForInterval(event)?.let { phrases.add(it) }
                }
            }
            if (isRecording || isPaused) {
                phrases.addAll(collectFreeRunPhrases(distanceMeters, durationSeconds, movingTimeSeconds, currentPaceSecPerKm, lat, accuracyMeters, isRecording, splitsCount, splits))
            }
        }

        // One concise cue per update. Ordering above expresses priority:
        // transitions/achievements first, background metrics last.
        phrases.firstOrNull()?.let { speakIfAllowed(it) }
    }

    private fun checkGoalCompletion(distanceMeters: Double, movingTimeSeconds: Int, isRecording: Boolean, isPaused: Boolean): Boolean {
        if (goalCompleted || !goal.enabled) return false
        if (!isRecording && !isPaused) return false
        if (!goal.isComplete(distanceMeters, movingTimeSeconds)) return false
        goalCompleted = true
        return true
    }

    private fun collectFreeRunPhrases(
        distanceMeters: Double,
        durationSeconds: Int,
        movingTimeSeconds: Int,
        currentPaceSecPerKm: Double?,
        lat: Double?,
        accuracyMeters: Float?,
        isRecording: Boolean,
        splitsCount: Int,
        splits: List<Map<String, Any?>>,
    ): List<String> {
        val out = mutableListOf<String>()

        goalProgressPhrase(distanceMeters, movingTimeSeconds, isRecording)?.let { out.add(it) }

        val every = settings.distanceEveryKm.coerceIn(1, 5)
        val milestone = (((distanceMeters / 1000.0).toInt()) / every) * every
        val newMilestone = settings.announceDistance && milestone > 0 && milestone > lastAnnouncedKm
        val newSplit = settings.announceSplit && splitsCount > lastSplitCount
        val avgPace = if (distanceMeters > 0) movingTimeSeconds / (distanceMeters / 1000.0) else null
        if (newSplit) {
            val lastSplit = splits.lastOrNull()
            if (lastSplit != null) {
                val km = (lastSplit["km"] as? Number)?.toInt() ?: splitsCount
                val pace = (lastSplit["pace_sec_per_km"] as? Number)?.toDouble()
                lastSplitCount = splitsCount
                if (newMilestone) lastAnnouncedKm = milestone
                out.add(
                    if (newMilestone) RunVoicePhrases.splitSummary(km, pace, avgPace)
                    else RunVoicePhrases.splitComplete(km, pace)
                )
            }
        } else if (newMilestone) {
            lastAnnouncedKm = milestone
            out.add(RunVoicePhrases.distanceMilestone(milestone, durationSeconds, avgPace))
        }

        if (settings.announceGpsStatus && isRecording) {
            val weak = (accuracyMeters != null && accuracyMeters > 30) || lat == null
            if (lastWeakGps == null) {
                lastWeakGps = weak
            } else if (weak != lastWeakGps) {
                val now = System.currentTimeMillis()
                val cooled = lastGpsAnnounceAt == 0L || now - lastGpsAnnounceAt >= 30_000
                if (cooled) {
                    lastWeakGps = weak
                    lastGpsAnnounceAt = now
                    out.add(if (weak) RunVoicePhrases.weakGps() else RunVoicePhrases.gpsRestored())
                }
            }
        }

        if (!stepEngine.hasPlan && settings.announcePaceWarning && settings.targetPaceSecPerKm != null && isRecording) {
            stablePacePhrase(distanceMeters, movingTimeSeconds)?.let { out.add(it) }
        }

        return out
    }

    private fun goalProgressPhrase(distanceMeters: Double, movingTimeSeconds: Int, recording: Boolean): String? {
        if (!recording || !goal.enabled || goalCompleted || goal.value <= 0) return null
        val current = if (goal.metric == RunIntervalMetric.distance) distanceMeters else movingTimeSeconds.toDouble()
        val progress = (current / goal.value).coerceIn(0.0, 1.0)
        val threshold = if (progress >= .8) 80 else if (progress >= .5) 50 else 0
        if (threshold == 0 || goalProgressCues.contains(threshold)) return null
        if (threshold == 50 && ((goal.metric == RunIntervalMetric.distance && goal.value < 5000) ||
                (goal.metric == RunIntervalMetric.time && goal.value < 1800))) return null
        goalProgressCues.add(threshold)
        val remaining = (goal.value - current).coerceAtLeast(0.0).toInt()
        return RunVoicePhrases.goalRemaining(goal.metric, remaining)
    }

    private fun stablePacePhrase(distanceMeters: Double, movingTimeSeconds: Int): String? {
        val now = System.currentTimeMillis()
        paceSamples.addLast(RunVoicePacePoint(now, distanceMeters, movingTimeSeconds))
        while (paceSamples.isNotEmpty() && now - paceSamples.first().atMillis > 25_000) paceSamples.removeFirst()
        if (paceSamples.size < 2 || distanceMeters < 200) return null
        val first = paceSamples.first()
        val elapsed = movingTimeSeconds - first.movingSeconds
        val distance = distanceMeters - first.distanceMeters
        if (elapsed < 12 || distance < 40) return null
        val pace = elapsed / (distance / 1000.0)
        val target = settings.targetPaceSecPerKm ?: return null
        val tolerance = settings.paceTolerancePercent / 100.0
        val direction = if (pace < target * (1 - tolerance)) -1 else if (pace > target * (1 + tolerance)) 1 else 0
        if (direction == 0) {
            paceDeviationSince = 0L
            paceDeviationDirection = 0
            if (paceCorrectionSpoken) {
                paceCorrectionSpoken = false
                return RunVoicePhrases.paceOnTarget()
            }
            return null
        }
        if (paceDeviationDirection != direction) {
            paceDeviationDirection = direction
            paceDeviationSince = now
            return null
        }
        if (paceDeviationSince == 0L || now - paceDeviationSince < 10_000) return null
        if (paceCorrectionSpoken || (lastPaceAnnounceAt != 0L && now - lastPaceAnnounceAt < 60_000)) return null
        lastPaceAnnounceAt = now
        paceCorrectionSpoken = true
        return if (direction < 0) RunVoicePhrases.paceTooFast() else RunVoicePhrases.paceTooSlow()
    }

    /**
     * Starts the plan on the first recording tick and drains its events.
     * Returns the phrases to speak (empty when [speak] is false).
     */
    private fun advanceStepEngine(
        isRecording: Boolean,
        distanceMeters: Double,
        movingTimeSeconds: Int,
        speak: Boolean,
    ): List<String> {
        val out = mutableListOf<String>()
        val events = mutableListOf<RunStepEventNative>()
        if (isRecording && stepEngine.snapshot.phase == RunStepEnginePhase.idle) {
            events.addAll(stepEngine.start())
        }
        events.addAll(stepEngine.tick(isRecording, distanceMeters, movingTimeSeconds))
        if (!speak) return out
        for (event in events) {
            phraseForStep(event)?.let { out.add(it) }
        }
        return out
    }

    private fun phraseForStep(event: RunStepEventNative): String? = when (event.kind) {
        RunStepEventKind.stepStarted -> RunVoicePhrases.stepStart(
            event.role,
            event.repIndex,
            event.repTotal,
            event.metric,
            event.target,
            stepEngine.snapshot.let { snapshot ->
                if (snapshot.stepIndex == event.stepIndex) targetPaceForCurrentStep() else null
            },
        )
        RunStepEventKind.timeRemainingCue -> RunVoicePhrases.timeRemaining(event.remainingSeconds ?: 30)
        RunStepEventKind.distanceRemainingCue -> RunVoicePhrases.distanceRemaining(event.remainingMeters ?: 100)
        RunStepEventKind.paceTooSlow -> RunVoicePhrases.stepPaceTooSlow(event.paceSecPerKm)
        RunStepEventKind.paceTooFast -> RunVoicePhrases.stepPaceTooFast(event.paceSecPerKm)
        RunStepEventKind.workoutCompleted -> RunVoicePhrases.workoutComplete()
        // Completion is implied by the next step's start cue.
        RunStepEventKind.stepCompleted -> null
    }

    private fun targetPaceForCurrentStep(): Double? {
        val snapshot = stepEngine.snapshot
        if (!snapshot.isActive) return null
        return planStepsForSnapshot(snapshot)
    }

    private fun planStepsForSnapshot(snapshot: RunStepSnapshotNative): Double? {
        val step = RunWorkoutStepEngineNative.expand(planSteps)
            .getOrNull(snapshot.stepIndex)
            ?.step ?: return null
        val min = step.targetPaceMinSecPerKm
        val max = step.targetPaceMaxSecPerKm
        return if (min != null && max != null) (min + max) / 2.0 else min ?: max
    }

    private fun phraseForInterval(event: RunIntervalEvent): String? {
        return when (event.kind) {
            RunIntervalEventKind.workStarted -> RunVoicePhrases.workIntervalStart(event.workIndex, event.totalWorks)
            RunIntervalEventKind.restStarted -> RunVoicePhrases.restIntervalStart(settings.interval.restMetric, settings.interval.restValue)
            RunIntervalEventKind.completed -> RunVoicePhrases.intervalsComplete()
            RunIntervalEventKind.timeRemainingCue -> RunVoicePhrases.timeRemaining(event.remainingSeconds ?: 30)
        }
    }

    private fun speakIfAllowed(phrase: String): Boolean {
        if (!settings.enabled) {
            Log.d("RunVoice", "skipped disabled")
            return false
        }
        if (settings.muteDuringCall && isInCall()) {
            Log.d("RunVoice", "skipped in call")
            return false
        }
        if (settings.headphonesOnly && !bypassHeadphonesGate && !isHeadsetConnected()) {
            Log.d("RunVoice", "skipped no headset")
            return false
        }
        Log.i("RunVoice", "speak \"$phrase\"")
        tts.speak(phrase)
        return true
    }

    private fun isInCall(): Boolean {
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (am.mode) {
                AudioManager.MODE_IN_CALL, AudioManager.MODE_IN_COMMUNICATION -> true
                else -> false
            }
        } catch (_: Throwable) { false }
    }

    private fun isHeadsetConnected(): Boolean {
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                for (device in devices) {
                    when (device.type) {
                        AudioDeviceInfo.TYPE_WIRED_HEADSET,
                        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                        AudioDeviceInfo.TYPE_USB_HEADSET,
                        AudioDeviceInfo.TYPE_HEARING_AID,
                        -> return true
                        else -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                if (device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                    device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                                ) return true
                            }
                        }
                    }
                }
                false
            } else {
                @Suppress("DEPRECATION")
                am.isWiredHeadsetOn || am.isBluetoothA2dpOn || am.isBluetoothScoOn
            }
        } catch (_: Throwable) { false }
    }
}
