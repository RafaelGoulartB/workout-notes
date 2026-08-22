package com.workoutnotes.workout_notes.run

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.util.Log

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
        tts.speak("Voice alerts are working. One kilometer. Pace 5 minutes 30 seconds.")
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
                    speak = settings.announceIntervals,
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

        for (phrase in phrases) {
            if (!speakIfAllowed(phrase)) break
        }
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

        if (settings.announceDistance) {
            val every = settings.distanceEveryKm.coerceIn(1, 5)
            val kmFloor = (distanceMeters / 1000.0).toInt()
            val milestone = (kmFloor / every) * every
            if (milestone > 0 && milestone > lastAnnouncedKm) {
                lastAnnouncedKm = milestone
                val avgPace = if (distanceMeters > 0) movingTimeSeconds / (distanceMeters / 1000.0) else null
                out.add(RunVoicePhrases.distanceMilestone(milestone, durationSeconds, avgPace?.takeIf { it.isFinite() && it > 0 }))
            }
        }

        if (settings.announceSplit) {
            if (splitsCount > lastSplitCount) {
                val lastSplit = splits.lastOrNull()
                if (lastSplit != null) {
                    val km = (lastSplit["km"] as? Number)?.toInt() ?: splitsCount
                    val pace = (lastSplit["pace_sec_per_km"] as? Number)?.toDouble()
                    lastSplitCount = splitsCount
                    out.add(RunVoicePhrases.splitComplete(km, pace))
                }
            }
        }

        if (settings.announceGpsStatus && isRecording) {
            val weak = (accuracyMeters != null && accuracyMeters > 30) || lat == null
            if (lastWeakGps == null) {
                lastWeakGps = weak
            } else if (weak != lastWeakGps) {
                val now = System.currentTimeMillis()
                val cooled = lastGpsAnnounceAt == 0L || now - lastGpsAnnounceAt >= 20_000
                if (cooled) {
                    lastWeakGps = weak
                    lastGpsAnnounceAt = now
                    out.add(if (weak) RunVoicePhrases.weakGps() else RunVoicePhrases.gpsRestored())
                }
            }
        }

        if (settings.announcePaceWarning && settings.targetPaceSecPerKm != null && isRecording) {
            val pace = currentPaceSecPerKm
            val target = settings.targetPaceSecPerKm
            if (pace != null && pace > 0 && pace.isFinite() && distanceMeters >= 200 && target != null) {
                val tol = settings.paceTolerancePercent / 100.0
                val fastLimit = target * (1 - tol)
                val slowLimit = target * (1 + tol)
                var warning: String? = null
                if (pace < fastLimit) warning = RunVoicePhrases.paceTooFast()
                else if (pace > slowLimit) warning = RunVoicePhrases.paceTooSlow()
                if (warning != null) {
                    val now = System.currentTimeMillis()
                    val cooled = lastPaceAnnounceAt == 0L || now - lastPaceAnnounceAt >= 45_000
                    if (cooled) {
                        lastPaceAnnounceAt = now
                        out.add(warning)
                    }
                }
            }
        }

        return out
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

    private fun planStepsForSnapshot(snapshot: RunStepSnapshotNative): Double? =
        RunWorkoutStepEngineNative.expand(planSteps)
            .getOrNull(snapshot.stepIndex)
            ?.step
            ?.targetPaceMinSecPerKm

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
