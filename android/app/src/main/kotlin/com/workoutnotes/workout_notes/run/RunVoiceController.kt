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
 * The run voice coach. It is the only voice engine: it runs inside
 * RunTrackingService (or RunIndoorVoiceService on the treadmill) so
 * announcements survive screen-off / Flutter engine death.
 *
 * Every update collects the cues worth saying (step changes, rep results, pace,
 * distance/time, goal progress, GPS) and hands them to a [RunCueScheduler],
 * which decides what is actually spoken and when. What gets offered depends on
 * [RunVoiceSettings.verbosity]:
 *
 * - minimal: step changes, pace corrections, goal/workout complete;
 * - standard: + rep results, time/distance left, "next rep in…", distance and
 *   time cues, goal progress, GPS, "back on pace", race projections;
 * - detailed: + target pace on every rep and projections for any pace goal.
 */
class RunVoiceController(
    private val context: Context,
    private val tts: RunSpeechOutput = RunTtsService(context),
    private val haptics: RunHaptics = AndroidRunHaptics(context),
    private val clock: () -> Long = { System.currentTimeMillis() },
) {

    private var phrases = RunVoicePhrases(RunVoiceLanguage.en)
    private val intervalEngine = RunIntervalEngineNative()

    /** Structured plan session. Takes precedence over [intervalEngine]. */
    private val stepEngine = RunWorkoutStepEngineNative()
    private val scheduler = RunCueScheduler()
    private var planSteps: List<RunWorkoutStepNative> = emptyList()
    private var settings: RunVoiceSettings = RunVoiceSettings.defaults()
    private var goal: RunSessionGoal = RunSessionGoal.disabled()
    private var workout: RunWorkoutProfile = RunWorkoutProfile.none()
    private var intervalsOn: Boolean = false
    private var active: Boolean = false
    private var goalCompleted: Boolean = false

    /** Treadmill session: no GPS, no distance, time-driven cues only. */
    var indoor: Boolean = false

    // Free-run state
    private var lastSplitCount: Int = 0
    private var lastTimeCueIndex: Int = 0
    private var gpsWeakSince: Long = 0L
    private var gpsGoodSince: Long = 0L
    private var gpsWeakAnnounced: Boolean = false
    private var lastPaceAnnounceAt: Long = 0L
    private val goalProgressCues = mutableSetOf<String>()
    private val paceSamples = ArrayDeque<RunVoicePacePoint>()
    private var paceDeviationSince: Long = 0L
    private var paceDeviationDirection: Int = 0
    private var paceCorrectionSpoken: Boolean = false
    private var paceRepeats: Int = 0
    private var wasPaused: Boolean? = null
    private var wasAutoPaused: Boolean? = null
    private var lastAnnouncedTargetPace: Double? = null

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
                applySettings(RunVoiceSettings.fromJsonString(raw))
                settingsLoaded = true
                return settings
            }
        } catch (_: Throwable) {}

        // Fallback: read SQLite directly
        try {
            val dbPath = context.getDatabasePath("workout_notes.db")
            if (dbPath.exists()) {
                val db = SQLiteDatabase.openDatabase(dbPath.path, null, SQLiteDatabase.OPEN_READONLY)
                try {
                    db.rawQuery("SELECT value FROM app_settings WHERE key = ?", arrayOf(RunVoiceSettings.STORAGE_KEY)).use { cursor ->
                        if (cursor.moveToFirst()) {
                            applySettings(RunVoiceSettings.fromJsonString(cursor.getString(0)))
                            settingsLoaded = true
                            return settings
                        }
                    }
                } finally {
                    db.close()
                }
            }
        } catch (e: Throwable) {
            Log.w("RunVoice", "DB read failed: ${e.message}")
        }
        applySettings(RunVoiceSettings.defaults())
        return settings
    }

    private fun applySettings(parsed: RunVoiceSettings) {
        settings = parsed
        refreshVoiceLanguage()
        intervalEngine.configure(parsed.interval)
        scheduler.speechRate = parsed.speechRate
        scheduler.budgetPerWindow = when (parsed.verbosity) {
            RunVoiceVerbosity.minimal -> 2
            RunVoiceVerbosity.standard -> 4
            RunVoiceVerbosity.detailed -> 6
        }
        tts.configure(parsed.speechRate, parsed.voiceVolume, parsed.pauseMedia)
    }

    /** Loads a structured session. Empty clears it and falls back to presets. */
    fun setPlanSteps(steps: List<RunWorkoutStepNative>) {
        planSteps = steps
        stepEngine.configure(steps, easyEffort = workout.kind.isEasy)
    }

    /** Serialized plan for the run spool, so a killed process resumes cueing. */
    fun planStepsJson(): String? =
        if (planSteps.isEmpty()) null else RunWorkoutStepNative.listToJsonString(planSteps)

    /** Per-step results collected during the session, for Dart to persist. */
    fun stepResults(): List<Map<String, Any?>> = stepEngine.results.map { it.toMap() }

    /** Durable execution snapshot mirrored into the run spool. */
    fun engineSnapshotJson(): String? =
        if (stepEngine.hasPlan) stepEngine.stateJson() else null

    /** Live quick-interval progress, or null while no interval set is running. */
    fun intervalSnapshotMap(): Map<String, Any?>? =
        if (intervalsOn && !stepEngine.hasPlan && intervalEngine.snapshot.phase != RunIntervalPhase.idle) {
            intervalEngine.snapshot.toMap()
        } else null

    /** Live structured-workout progress for a reattached Flutter screen. */
    fun stepSnapshotMap(): Map<String, Any?>? =
        if (stepEngine.hasPlan) stepEngine.snapshotMap() else null

    fun restoreEngineSnapshot(raw: String?): Boolean =
        stepEngine.restoreStateJson(raw)

    val hasPlan: Boolean get() = stepEngine.hasPlan
    val intervalsEnabled: Boolean get() = intervalsOn

    /** Auto-pause is a user setting, but structured sessions own their clock. */
    val autoPauseEnabled: Boolean get() = settings.autoPause

    fun goalJson(): String = goal.toJson().toString()

    fun restoreGoalJson(raw: String?) {
        if (raw.isNullOrBlank()) return
        try {
            goal = RunSessionGoal.fromJson(JSONObject(raw))
        } catch (_: Throwable) {}
    }

    fun workoutJson(): String = workout.toJson().toString()

    fun restoreWorkoutJson(raw: String?) {
        workout = RunWorkoutProfile.fromJsonString(raw)
    }

    fun syncFromFlutter(
        settingsMap: Map<String, Any?>?,
        goalMap: Map<String, Any?>?,
        intervalsOn: Boolean?,
        plan: Any? = null,
        workoutMap: Map<String, Any?>? = null,
    ) {
        if (workoutMap != null) workout = RunWorkoutProfile.fromMap(workoutMap)
        // A settings sync mid-run resends the same plan: reloading it would
        // reset the engine and restart the workout from its first step.
        if (plan != null) {
            val steps = RunWorkoutStepNative.listFromAny(plan)
            if (steps != planSteps) setPlanSteps(steps)
        }
        if (settingsMap != null) applySettings(RunVoiceSettings.fromMap(settingsMap))
        if (goalMap != null) {
            this.goal = RunSessionGoal.fromMap(goalMap)
        }
        if (intervalsOn != null) this.intervalsOn = intervalsOn
        Log.i("RunVoice", "sync intervalsOn=$intervalsOn goal=${goal.enabled} enabled=${settings.enabled}")
    }

    fun begin(
        settingsMap: Map<String, Any?>?,
        goalMap: Map<String, Any?>?,
        intervalsOn: Boolean?,
        plan: Any? = null,
        workoutMap: Map<String, Any?>? = null,
    ) {
        // If flutter didn't push settings, load from storage
        if (settingsMap == null && !settingsLoaded) {
            loadSettingsFromDb()
        } else if (settingsMap != null) {
            applySettings(RunVoiceSettings.fromMap(settingsMap))
        }
        if (goalMap != null) goal = RunSessionGoal.fromMap(goalMap)
        if (workoutMap != null) workout = RunWorkoutProfile.fromMap(workoutMap)
        // If caller didn't specify intervalsOn, respect default
        this.intervalsOn = intervalsOn ?: settings.intervalsEnabledByDefault
        active = true
        goalCompleted = false
        lastSplitCount = 0
        lastTimeCueIndex = 0
        gpsWeakSince = 0L
        gpsGoodSince = 0L
        gpsWeakAnnounced = false
        lastPaceAnnounceAt = 0L
        goalProgressCues.clear()
        paceSamples.clear()
        paceDeviationSince = 0L
        paceDeviationDirection = 0
        paceCorrectionSpoken = false
        paceRepeats = 0
        wasPaused = null
        wasAutoPaused = null
        lastAnnouncedTargetPace = null
        scheduler.reset()
        intervalEngine.reset()
        if (plan != null) {
            setPlanSteps(RunWorkoutStepNative.listFromAny(plan))
        } else {
            // Re-apply the workout kind to an already loaded plan.
            stepEngine.configure(planSteps, easyEffort = workout.kind.isEasy)
        }
        stepEngine.reset()
        tts.ensureReady(effectiveLanguage())
        Log.i(
            "RunVoice",
            "begin intervalsOn=${this.intervalsOn} goal=${goal.enabled} ${goal.metric} ${goal.value} " +
                "planSteps=${stepEngine.totalSteps} kind=${workout.kind} indoor=$indoor",
        )
    }

    fun end() {
        active = false
        goalCompleted = false
        intervalEngine.reset()
        scheduler.reset()
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

    /**
     * Moves the structured session (or the quick interval set) to its next
     * step and speaks it. Returns false when there is nothing to skip.
     */
    fun skipStep(): Boolean {
        if (!active) return false
        val now = clock()
        if (stepEngine.hasPlan) {
            if (stepEngine.snapshot.phase != RunStepEnginePhase.running) return false
            stepCues(stepEngine.skip(), now, 0.0, 0, skipped = true).forEach(scheduler::offer)
        } else if (intervalsOn) {
            val phase = intervalEngine.snapshot.phase
            if (phase != RunIntervalPhase.work && phase != RunIntervalPhase.rest) return false
            val events = intervalEngine.skip()
            if (settings.announceIntervals) intervalCues(events, now, skipped = true).forEach(scheduler::offer)
        } else {
            return false
        }
        drain(now)
        return true
    }

    /** Spoken summary of a manual lap that was just marked. */
    fun announceLap(lap: Map<String, Any?>) {
        if (!active || !settings.enabled || !settings.announceLaps) return
        val index = (lap["lap_index"] as? Number)?.toInt() ?: return
        val distance = (lap["distance_meters"] as? Number)?.toDouble() ?: 0.0
        val duration = (lap["duration_seconds"] as? Number)?.toInt() ?: 0
        val pace = (lap["pace_sec_per_km"] as? Number)?.toDouble()
        val now = clock()
        scheduler.offer(
            RunCue(phrases.lapSummary(index, distance.toInt(), duration, pace), RunCuePriority.critical, "lap", now),
        )
        drain(now)
    }

    /** Short acknowledgement after a free run was stopped (planned sessions announce their own end). */
    fun speakWorkoutComplete() {
        if (!settings.enabled) return
        tts.ensureReady(effectiveLanguage())
        if (speechAllowed()) tts.speak(phrases.workoutComplete())
    }

    fun speakTest() {
        if (!settings.enabled) {
            loadSettingsFromDb()
        }
        tts.ensureReady(effectiveLanguage())
        // Queue a short test phrase even if queueing before init
        tts.speak(phrases.testAnnouncement())
    }

    private fun effectiveLanguage(): RunVoiceLanguage {
        if (settings.language != RunVoiceLanguage.app) return settings.language
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val appLocale = prefs.getString("flutter.app_locale", null)
                ?: prefs.getString("app_locale", null)
                ?: "en"
            if (appLocale.lowercase().startsWith("pt")) RunVoiceLanguage.pt else RunVoiceLanguage.en
        } catch (_: Throwable) {
            RunVoiceLanguage.en
        }
    }

    private fun refreshVoiceLanguage() {
        val language = effectiveLanguage()
        phrases = RunVoicePhrases(language)
        tts.setLanguage(language)
    }

    private val verbosity: RunVoiceVerbosity get() = settings.verbosity
    private val standard: Boolean get() = verbosity != RunVoiceVerbosity.minimal
    private val detailed: Boolean get() = verbosity == RunVoiceVerbosity.detailed

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
        autoPaused: Boolean = false,
    ) {
        if (!active) return
        if (!settings.enabled) return
        val now = clock()
        val cues = mutableListOf<RunCue>()

        if (isRecording || isPaused || autoPaused) {
            val previousAuto = wasAutoPaused
            wasAutoPaused = autoPaused
            if (previousAuto != null && previousAuto != autoPaused && settings.announceAutoPause) {
                if (settings.autoPauseBeep) {
                    playEarcon(if (autoPaused) RunEarcon.pause else RunEarcon.resume)
                } else {
                    cues.add(
                        RunCue(
                            if (autoPaused) phrases.autoPaused() else phrases.autoResumed(),
                            RunCuePriority.high,
                            "autopause",
                            now,
                            ttlMillis = 5_000,
                        ),
                    )
                }
            }
        }

        if (isRecording || isPaused) {
            val previousPaused = wasPaused
            wasPaused = isPaused
            if (previousPaused != null && previousPaused != isPaused) {
                scheduler.cancel("pace")
                cues.add(
                    RunCue(
                        if (isPaused) phrases.paused() else resumePhrase(),
                        RunCuePriority.high,
                        "pause",
                        now,
                        ttlMillis = 5_000,
                    ),
                )
            }
        }

        val activeGoal = goalForCues()
        if (activeGoal != null && !goalCompleted && (isRecording || isPaused) &&
            activeGoal.isComplete(distanceMeters, movingTimeSeconds)
        ) {
            goalCompleted = true
            val text = if (goalIsImplicit()) phrases.plannedComplete(activeGoal.metric)
            else phrases.goalComplete(activeGoal.metric, activeGoal.value)
            cues.add(goalCue(text, now))
        }

        var structuredAllowsProgress = true
        if (stepEngine.hasPlan) {
            val events = mutableListOf<RunStepEventNative>()
            if (isRecording && stepEngine.snapshot.phase == RunStepEnginePhase.idle) {
                events.addAll(stepEngine.start())
            }
            events.addAll(stepEngine.tick(isRecording, distanceMeters, movingTimeSeconds))
            cues.addAll(stepCues(events, now, distanceMeters, movingTimeSeconds))
            structuredAllowsProgress = stepAllowsProgressCues()
        } else {
            if (intervalsOn && isRecording && intervalEngine.snapshot.phase == RunIntervalPhase.idle) {
                val startEvents = intervalEngine.start()
                if (settings.announceIntervals) cues.addAll(intervalCues(startEvents, now))
            }
            if (intervalsOn) {
                val intervalEvents = intervalEngine.tick(isRecording, distanceMeters, movingTimeSeconds)
                if (settings.announceIntervals) cues.addAll(intervalCues(intervalEvents, now))
                structuredAllowsProgress = !intervalEngine.snapshot.isActive
            }
        }

        if (isRecording || isPaused) {
            cues.addAll(
                progressCues(
                    now,
                    distanceMeters,
                    movingTimeSeconds,
                    lat,
                    accuracyMeters,
                    isRecording,
                    splitsCount,
                    splits,
                    structuredAllowsProgress,
                ),
            )
        }

        cues.forEach(scheduler::offer)
        drain(now)
    }

    private fun drain(now: Long) {
        val transition = if (stepEngine.hasPlan) stepEngine.secondsToTransition()
        else if (intervalsOn) intervalEngine.secondsToTransition() else null
        val cue = scheduler.next(now, transition) ?: return
        deliver(cue)
    }

    private fun deliver(cue: RunCue) {
        if (settings.haptics) cue.haptic?.let { haptics.vibrate(it) }
        if (!speechAllowed()) return
        Log.i("RunVoice", "speak [${cue.priority}] \"${cue.text}\"")
        val earcon = cue.earcon
        if (earcon != null && settings.earcons) tts.playEarcon(earcon, cue.text) else tts.speak(cue.text)
    }

    private fun playEarcon(earcon: RunEarcon) {
        if (!settings.earcons || !speechAllowed()) return
        tts.playEarcon(earcon, null)
    }

    /** The 3-2-1 before a step change: beeps, or a vibration tick when no audio can be heard. */
    private fun countdownTick() {
        if (settings.earcons && speechAllowed()) {
            tts.playEarcon(RunEarcon.countdown, null)
        } else if (settings.haptics) {
            haptics.vibrate(RunHapticPattern.tick)
        }
    }

    private fun goalCue(text: String, now: Long) = RunCue(
        text,
        RunCuePriority.critical,
        "goal",
        now,
        earcon = RunEarcon.done,
        haptic = RunHapticPattern.done,
    )

    // --- Goal & pace targets -------------------------------------------------

    /** The session goal, or the planned distance/time of a step-less planned run. */
    private fun goalForCues(): RunSessionGoal? = when {
        goal.enabled && goal.value > 0 -> goal
        !stepEngine.hasPlan -> workout.implicitGoal()
        else -> null
    }

    private fun goalIsImplicit(): Boolean = !(goal.enabled && goal.value > 0)

    /** Pace enforced in a run without structured steps. */
    private fun freeRunPaceTarget(): RunPaceTarget? {
        goal.paceTargetSecPerKm?.let {
            return RunPaceTarget(it.toDouble(), goal.paceTolerancePercent, RunPaceMode.band)
        }
        if (!stepEngine.hasPlan) workout.implicitPace()?.let { return it }
        val global = settings.targetPaceSecPerKm?.takeIf { settings.announcePaceWarning } ?: return null
        return RunPaceTarget(global.toDouble(), settings.paceTolerancePercent, RunPaceMode.band)
    }

    // --- Structured sessions --------------------------------------------------

    /** What a step is called out loud. */
    private fun labelFor(expanded: RunExpandedStepNative): RunStepLabel {
        val step = expanded.step
        val kind = workout.kind
        val noPace = step.targetPaceMinSecPerKm == null && step.targetPaceMaxSecPerKm == null
        return when (step.role) {
            RunStepRole.warmup -> RunStepLabel.warmup
            RunStepRole.cooldown -> RunStepLabel.cooldown
            RunStepRole.work -> when {
                kind == RunWorkoutKindNative.hills -> RunStepLabel.hill
                kind == RunWorkoutKindNative.fartlek -> RunStepLabel.surge
                kind == RunWorkoutKindNative.test -> RunStepLabel.timeTrial
                kind == RunWorkoutKindNative.race && expanded.repTotal == 1 -> RunStepLabel.race
                step.metric == RunIntervalMetric.time && step.value <= 30 -> RunStepLabel.stride
                kind == RunWorkoutKindNative.easy && noPace -> RunStepLabel.run
                expanded.repTotal > 1 -> RunStepLabel.rep
                else -> RunStepLabel.effort
            }
            RunStepRole.steady ->
                if (kind == RunWorkoutKindNative.easy && noPace && planHasRunWalk()) RunStepLabel.run
                else RunStepLabel.steady
            RunStepRole.recovery -> when {
                kind == RunWorkoutKindNative.hills -> RunStepLabel.easyBack
                kind == RunWorkoutKindNative.fartlek -> RunStepLabel.float
                kind == RunWorkoutKindNative.easy && planHasStrides() -> RunStepLabel.easy
                kind == RunWorkoutKindNative.easy -> RunStepLabel.walk
                else -> RunStepLabel.recover
            }
        }
    }

    private fun planHasStrides(): Boolean = planSteps.any {
        it.role == RunStepRole.work && it.metric == RunIntervalMetric.time && it.value <= 30
    }

    /** Beginner run/walk plans: warm-up walks and untargeted run steps. */
    private fun planHasRunWalk(): Boolean = planSteps.any { it.role == RunStepRole.warmup } &&
        planSteps.none { it.targetPaceMinSecPerKm != null || it.targetPaceMaxSecPerKm != null }

    private fun isEffortLabel(label: RunStepLabel): Boolean = when (label) {
        RunStepLabel.rep, RunStepLabel.hill, RunStepLabel.surge, RunStepLabel.stride, RunStepLabel.run,
        RunStepLabel.effort, RunStepLabel.steady, RunStepLabel.timeTrial, RunStepLabel.race -> true
        else -> false
    }

    private fun isLastCounted(expanded: RunExpandedStepNative, label: RunStepLabel): Boolean =
        label.isCounted && expanded.repTotal > 1 && expanded.repIndex == expanded.repTotal

    private fun targetPace(step: RunWorkoutStepNative): Double? {
        val min = step.targetPaceMinSecPerKm
        val max = step.targetPaceMaxSecPerKm
        return if (min != null && max != null) (min + max) / 2.0 else min ?: max
    }

    private fun introFor(expanded: RunExpandedStepNative): String {
        val label = labelFor(expanded)
        // Strides and hills are run by feel; a pace would only distract.
        val pace = targetPace(expanded.step)?.takeIf {
            isEffortLabel(label) && standard && label != RunStepLabel.stride && label != RunStepLabel.hill
        }
        val sayPace = pace != null && (
            detailed || expanded.repIndex <= 1 ||
                lastAnnouncedTargetPace == null || kotlin.math.abs(lastAnnouncedTargetPace!! - pace) > 2
            )
        if (sayPace) lastAnnouncedTargetPace = pace
        return phrases.stepIntro(
            label,
            expanded.repIndex,
            expanded.repTotal,
            isLastCounted(expanded, label),
            expanded.step.metric,
            expanded.step.value,
            if (sayPace) pace else null,
        )
    }

    /** Result of a finished work step, or null when it is not worth saying. */
    private fun resultFor(event: RunStepEventNative, skipped: Boolean): String? {
        if (skipped || !standard) return null
        val expanded = stepEngine.stepAt(event.stepIndex) ?: return null
        val label = labelFor(expanded)
        val seconds = event.stepDurationSeconds ?: return null
        val meters = event.stepDistanceMeters ?: 0.0
        val step = expanded.step
        val completedShare = if (step.metric == RunIntervalMetric.time) seconds / step.value.toDouble()
        else meters / step.value.toDouble()
        if (completedShare < 0.9) return null
        if (label == RunStepLabel.timeTrial) {
            return if (step.metric == RunIntervalMetric.distance) phrases.testResult(step.value, seconds) else null
        }
        if (label != RunStepLabel.rep && label != RunStepLabel.effort && label != RunStepLabel.surge) return null
        val band = RunWorkoutStepEngineNative.paceBand(step)
        if (step.metric == RunIntervalMetric.distance) {
            if (band == null) return phrases.repTime(seconds, RunRepVerdict.none)
            val fastest = step.value / 1000.0 * band.first
            val slowest = step.value / 1000.0 * band.second
            return when {
                seconds < fastest - 1 -> phrases.repTime(seconds, RunRepVerdict.fast, (fastest - seconds).toInt().coerceAtLeast(1))
                seconds > slowest + 1 -> phrases.repTime(seconds, RunRepVerdict.slow, (seconds - slowest).toInt().coerceAtLeast(1))
                else -> phrases.repTime(seconds, RunRepVerdict.onTarget)
            }
        }
        if (indoor || meters < 50) return null
        val pace = seconds / (meters / 1000.0)
        val verdict = when {
            band == null -> RunRepVerdict.none
            pace < band.first -> RunRepVerdict.fast
            pace > band.second -> RunRepVerdict.slow
            else -> RunRepVerdict.onTarget
        }
        return phrases.repPace(pace, verdict)
    }

    private fun stepCues(
        events: List<RunStepEventNative>,
        now: Long,
        distanceMeters: Double,
        movingSeconds: Int,
        skipped: Boolean = false,
    ): List<RunCue> {
        val out = mutableListOf<RunCue>()
        var completed: RunStepEventNative? = null
        for (event in events) {
            when (event.kind) {
                RunStepEventKind.stepCompleted -> completed = event
                RunStepEventKind.stepStarted -> {
                    val expanded = stepEngine.stepAt(event.stepIndex) ?: continue
                    val parts = mutableListOf<String>()
                    completed?.let { done ->
                        resultFor(done, skipped)?.let(parts::add)
                        stepEngine.stepAt(done.stepIndex)?.let { prev ->
                            val prevLabel = labelFor(prev)
                            if (isLastCounted(prev, prevLabel) && prevLabel != RunStepLabel.run) {
                                parts.add(phrases.allRepsDone(prevLabel))
                            }
                        }
                    }
                    completed = null
                    parts.add(introFor(expanded))
                    val effort = isEffortLabel(labelFor(expanded))
                    scheduler.cancel("pace")
                    scheduler.cancel("stepProgress")
                    out.add(
                        RunCue(
                            parts.joinToString(" "),
                            RunCuePriority.critical,
                            "step",
                            now,
                            earcon = if (effort) RunEarcon.go else RunEarcon.ease,
                            haptic = if (effort) RunHapticPattern.go else RunHapticPattern.ease,
                        ),
                    )
                }
                RunStepEventKind.workoutCompleted -> {
                    val parts = mutableListOf<String>()
                    completed?.let { done -> resultFor(done, skipped)?.let(parts::add) }
                    completed = null
                    parts.add(
                        if (indoor) phrases.workoutComplete()
                        else phrases.workoutComplete(distanceMeters, movingSeconds.takeIf { it > 0 }),
                    )
                    scheduler.cancel("pace")
                    scheduler.cancel("stepProgress")
                    out.add(
                        RunCue(
                            parts.joinToString(" "),
                            RunCuePriority.critical,
                            "step",
                            now,
                            earcon = RunEarcon.done,
                            haptic = RunHapticPattern.done,
                        ),
                    )
                }
                RunStepEventKind.halfway -> if (standard) {
                    out.add(RunCue(phrases.halfway(), RunCuePriority.normal, "stepProgress", now, ttlMillis = 10_000))
                }
                RunStepEventKind.timeRemainingCue -> timeLeftCue(event, now)?.let(out::add)
                RunStepEventKind.distanceRemainingCue -> distanceLeftCue(event, now)?.let(out::add)
                RunStepEventKind.countdown -> countdownTick()
                RunStepEventKind.paceTooSlow, RunStepEventKind.paceTooFast -> {
                    val pace = event.paceSecPerKm?.takeIf { standard }
                    val easyCeiling = workout.kind.isEasy && event.role == RunStepRole.steady
                    val text = when {
                        event.kind == RunStepEventKind.paceTooSlow -> phrases.paceTooSlow(pace)
                        easyCeiling -> phrases.easyTooFast(pace)
                        else -> phrases.paceTooFast(pace)
                    }
                    out.add(RunCue(text, RunCuePriority.high, "pace", now))
                }
                RunStepEventKind.paceBackInRange -> if (standard) {
                    out.add(RunCue(phrases.backOnPace(), RunCuePriority.normal, "pace", now, ttlMillis = 6_000))
                }
            }
        }
        return out
    }

    /**
     * "1 minute left" in an effort; "Rep 4 in 10 seconds" in a recovery. The
     * last 10 seconds of a short effort are left to the countdown beeps.
     */
    private fun timeLeftCue(event: RunStepEventNative, now: Long): RunCue? {
        val seconds = event.remainingSeconds ?: return null
        val expanded = stepEngine.stepAt(event.stepIndex) ?: return null
        val label = labelFor(expanded)
        val effort = isEffortLabel(label)
        val beepsCover = settings.earcons && seconds <= 10
        if (!standard && beepsCover) return null
        if (effort && beepsCover) return null
        val next = stepEngine.stepsAfter(event.stepIndex).firstOrNull()
        val text = if (!effort && next != null) {
            val nextLabel = labelFor(next)
            phrases.nextInSeconds(phrases.stepName(nextLabel, next.repIndex, isLastCounted(next, nextLabel)), seconds)
        } else {
            phrases.timeLeft(seconds)
        }
        return RunCue(text, RunCuePriority.high, "stepProgress", now, ttlMillis = 6_000)
    }

    private fun distanceLeftCue(event: RunStepEventNative, now: Long): RunCue? {
        if (!standard) return null
        val meters = event.remainingMeters ?: return null
        val expanded = stepEngine.stepAt(event.stepIndex) ?: return null
        val label = labelFor(expanded)
        val next = stepEngine.stepsAfter(event.stepIndex).firstOrNull()
        val text = if (!isEffortLabel(label) && next != null && label != RunStepLabel.warmup) {
            val nextLabel = labelFor(next)
            phrases.nextInMeters(phrases.stepName(nextLabel, next.repIndex, isLastCounted(next, nextLabel)), meters)
        } else {
            phrases.distanceLeft(meters)
        }
        return RunCue(text, RunCuePriority.high, "stepProgress", now, ttlMillis = 10_000)
    }

    /**
     * Distance and time cues make sense in long continuous steps only: inside a
     * block of reps they would mix rep and recovery paces.
     */
    private fun stepAllowsProgressCues(): Boolean {
        val current = stepEngine.current() ?: return !stepEngine.snapshot.isActive
        if (current.repTotal > 1) return false
        val step = current.step
        return if (step.metric == RunIntervalMetric.time) step.value >= 600 else step.value >= 2000
    }

    private fun resumePhrase(): String {
        val current = stepEngine.current() ?: return phrases.resumed()
        if (!standard) return phrases.resumed()
        val label = labelFor(current)
        val remaining = stepEngine.snapshot.remaining
        if (remaining <= 0) return phrases.resumed()
        val amount = phrases.remainingAmount(current.step.metric, remaining)
        return phrases.resumedInStep(phrases.stepName(label, current.repIndex, isLastCounted(current, label)), amount)
    }

    // --- Quick interval preset ----------------------------------------------

    private fun intervalCues(events: List<RunIntervalEvent>, now: Long, skipped: Boolean = false): List<RunCue> {
        val out = mutableListOf<RunCue>()
        val preset = intervalEngine.currentPreset
        for (event in events) {
            val result = if (skipped || !standard) null else intervalResult(event, preset)
            when (event.kind) {
                RunIntervalEventKind.workStarted -> {
                    val isLast = event.totalWorks > 1 && event.workIndex == event.totalWorks
                    val intro = phrases.stepIntro(
                        RunStepLabel.rep,
                        event.workIndex,
                        event.totalWorks,
                        isLast,
                        preset.workMetric,
                        preset.workValue,
                    )
                    out.add(transitionCue(listOfNotNull(result, intro), now, effort = true))
                }
                RunIntervalEventKind.restStarted -> {
                    val intro = phrases.stepIntro(RunStepLabel.recover, 0, 0, false, preset.restMetric, preset.restValue)
                    out.add(transitionCue(listOfNotNull(result, intro), now, effort = false))
                }
                RunIntervalEventKind.completed -> {
                    out.add(
                        RunCue(
                            listOfNotNull(result, phrases.intervalsComplete()).joinToString(" "),
                            RunCuePriority.critical,
                            "step",
                            now,
                            earcon = RunEarcon.done,
                            haptic = RunHapticPattern.done,
                        ),
                    )
                }
                RunIntervalEventKind.timeRemainingCue -> {
                    val seconds = event.remainingSeconds ?: continue
                    val working = intervalEngine.snapshot.phase == RunIntervalPhase.work
                    val beepsCover = settings.earcons && seconds <= 10
                    if (beepsCover && (working || !standard)) continue
                    val text = if (!working) {
                        val next = event.workIndex + 1
                        phrases.nextInSeconds(phrases.stepName(RunStepLabel.rep, next, next == event.totalWorks), seconds)
                    } else {
                        phrases.timeLeft(seconds)
                    }
                    out.add(RunCue(text, RunCuePriority.high, "stepProgress", now, ttlMillis = 6_000))
                }
                RunIntervalEventKind.distanceRemainingCue -> {
                    if (!standard) continue
                    val meters = event.remainingMeters ?: continue
                    val working = intervalEngine.snapshot.phase == RunIntervalPhase.work
                    val text = if (!working) {
                        val next = event.workIndex + 1
                        phrases.nextInMeters(phrases.stepName(RunStepLabel.rep, next, next == event.totalWorks), meters)
                    } else {
                        phrases.distanceLeft(meters)
                    }
                    out.add(RunCue(text, RunCuePriority.high, "stepProgress", now, ttlMillis = 10_000))
                }
                RunIntervalEventKind.countdown -> countdownTick()
            }
        }
        return out
    }

    private fun intervalResult(event: RunIntervalEvent, preset: RunIntervalPreset): String? {
        val seconds = event.lastWorkSeconds ?: return null
        val meters = event.lastWorkMeters ?: 0.0
        return if (preset.workMetric == RunIntervalMetric.distance) {
            if (meters < preset.workValue * 0.9) null else phrases.repTime(seconds, RunRepVerdict.none)
        } else {
            if (indoor || meters < 50 || seconds < preset.workValue * 0.9) null
            else phrases.repPace(seconds / (meters / 1000.0), RunRepVerdict.none)
        }
    }

    private fun transitionCue(parts: List<String>, now: Long, effort: Boolean): RunCue {
        scheduler.cancel("pace")
        scheduler.cancel("stepProgress")
        return RunCue(
            parts.joinToString(" "),
            RunCuePriority.critical,
            "step",
            now,
            earcon = if (effort) RunEarcon.go else RunEarcon.ease,
            haptic = if (effort) RunHapticPattern.go else RunHapticPattern.ease,
        )
    }

    // --- Progress: distance, time, goal, GPS, pace ---------------------------

    private fun progressCues(
        now: Long,
        distanceMeters: Double,
        movingTimeSeconds: Int,
        lat: Double?,
        accuracyMeters: Float?,
        isRecording: Boolean,
        splitsCount: Int,
        splits: List<Map<String, Any?>>,
        structuredAllowsProgress: Boolean,
    ): List<RunCue> {
        val out = mutableListOf<RunCue>()
        val goalText = goalProgressPhrase(distanceMeters, movingTimeSeconds, isRecording)
        val kmText = kilometerPhrase(distanceMeters, movingTimeSeconds, splitsCount, splits, structuredAllowsProgress)
        val timeText = if (kmText == null) timePhrase(distanceMeters, movingTimeSeconds, isRecording, structuredAllowsProgress) else null
        val progress = listOfNotNull(kmText ?: timeText, goalText)
        if (progress.isNotEmpty()) {
            out.add(RunCue(progress.joinToString(" "), RunCuePriority.normal, if (kmText != null) "km" else "progress", now))
        }

        gpsPhrase(now, lat, accuracyMeters, isRecording)?.let {
            out.add(RunCue(it, RunCuePriority.low, "gps", now))
        }

        if (!stepEngine.hasPlan && !indoor && isRecording) {
            freeRunPaceTarget()?.let { target ->
                stablePaceCue(now, distanceMeters, movingTimeSeconds, target)?.let(out::add)
            }
        }
        return out
    }

    private fun goalProgressPhrase(distanceMeters: Double, movingTimeSeconds: Int, recording: Boolean): String? {
        if (!recording || !standard || goalCompleted) return null
        val active = goalForCues() ?: return null
        if (indoor && active.metric == RunIntervalMetric.distance) return null
        val target = active.value.toDouble()
        val current = if (active.metric == RunIntervalMetric.distance) distanceMeters else movingTimeSeconds.toDouble()
        val remaining = target - current
        if (remaining <= 0) return null
        val (bigEnough, lastMark) = if (active.metric == RunIntervalMetric.distance) {
            (target >= 3000) to 1000.0
        } else {
            (target >= 1200) to 300.0
        }
        if (!bigEnough) return null
        if (remaining <= lastMark && goalProgressCues.add("last")) {
            goalProgressCues.add("half")
            return phrases.goalToGo(phrases.remainingAmount(active.metric, remaining))
        }
        if (current * 2 >= target && goalProgressCues.add("half")) {
            return phrases.goalHalfway(phrases.remainingAmount(active.metric, remaining))
        }
        return null
    }

    private fun kilometerPhrase(
        distanceMeters: Double,
        movingTimeSeconds: Int,
        splitsCount: Int,
        splits: List<Map<String, Any?>>,
        structuredAllowsProgress: Boolean,
    ): String? {
        if (splitsCount <= lastSplitCount) return null
        lastSplitCount = splitsCount
        if (indoor || !standard || !settings.announceDistance || !structuredAllowsProgress) return null
        val lastSplit = splits.lastOrNull() ?: return null
        val km = (lastSplit["km"] as? Number)?.toInt() ?: splitsCount
        val race = workout.kind == RunWorkoutKindNative.race
        var every = settings.distanceEveryKm.coerceIn(1, 5)
        if (workout.kind == RunWorkoutKindNative.long && every < 2) every = 2
        if (race) every = 1
        if (km % every != 0) return null
        val structured = stepEngine.hasPlan
        val avgPace = if (distanceMeters > 0) movingTimeSeconds / (distanceMeters / 1000.0) else null
        val splitPace = (lastSplit["pace_sec_per_km"] as? Number)?.toDouble()
        val text = phrases.kilometer(
            km,
            elapsedSeconds = movingTimeSeconds.takeIf { settings.kmIncludeTime },
            splitPace = splitPace.takeIf { settings.announceSplit },
            avgPace = avgPace.takeIf { (settings.kmIncludeAvgPace || detailed) && !structured },
        )
        val extras = listOfNotNull(
            projectionPhrase(distanceMeters, movingTimeSeconds, avgPace),
            onPaceConfirmation(splitPace),
        )
        return (listOf(text) + extras).joinToString(" ")
    }

    /** Detailed mode: "On pace." when the kilometer just run sat inside the target. */
    private fun onPaceConfirmation(splitPace: Double?): String? {
        if (!detailed || splitPace == null || splitPace <= 0) return null
        val inRange = if (stepEngine.hasPlan) {
            val step = stepEngine.current()?.step?.takeIf { it.role.isEffort } ?: return null
            val (fast, slow) = RunWorkoutStepEngineNative.paceBand(step) ?: return null
            splitPace in fast..slow
        } else {
            val target = freeRunPaceTarget() ?: return null
            target.direction(splitPace) == 0
        }
        return if (inRange) phrases.onPaceShort() else null
    }

    /**
     * Finish-time projection toward the session's distance goal or the planned
     * distance: always for a race, for any pace goal in detailed mode.
     */
    private fun projectionPhrase(distanceMeters: Double, movingTimeSeconds: Int, avgPace: Double?): String? {
        val race = workout.kind == RunWorkoutKindNative.race
        if (!(race || detailed)) return null
        if (avgPace == null || !avgPace.isFinite() || avgPace <= 0) return null
        val sessionDistance = goal.value.takeIf { goal.enabled && goal.metric == RunIntervalMetric.distance }
        val targetMeters = sessionDistance ?: workout.targetDistanceMeters ?: return null
        val remaining = targetMeters - distanceMeters
        if (remaining <= 200) return null
        val targetPace = goal.paceTargetSecPerKm?.toDouble() ?: workout.targetPaceSecPerKm
        if (targetPace == null && !race) return null
        val finish = (movingTimeSeconds + remaining / 1000.0 * avgPace).toInt()
        val delta = targetPace?.let { (targetMeters / 1000.0 * it - finish).toInt() }
        return phrases.projection(finish, delta)
    }

    private fun timePhrase(
        distanceMeters: Double,
        movingTimeSeconds: Int,
        recording: Boolean,
        structuredAllowsProgress: Boolean,
    ): String? {
        if (!recording) return null
        var every = settings.announceTimeEveryMin
        // On the treadmill time is all there is: fall back to 5 minutes.
        if (every == 0 && indoor && settings.announceDistance && !stepEngine.hasPlan) every = 5
        if (every <= 0) return null
        val index = movingTimeSeconds / (every * 60)
        if (index <= lastTimeCueIndex) return null
        lastTimeCueIndex = index
        if (!standard || !structuredAllowsProgress) return null
        return phrases.timeCue(index * every, if (indoor) null else distanceMeters)
    }

    /** Weak GPS only after 20 s of it; "back" only if "weak" was said. */
    private fun gpsPhrase(now: Long, lat: Double?, accuracyMeters: Float?, recording: Boolean): String? {
        if (indoor || !recording || !settings.announceGpsStatus || !standard) return null
        val weak = (accuracyMeters != null && accuracyMeters > 30) || lat == null
        if (weak) {
            gpsGoodSince = 0L
            if (gpsWeakSince == 0L) gpsWeakSince = now
            if (!gpsWeakAnnounced && now - gpsWeakSince >= 20_000) {
                gpsWeakAnnounced = true
                return phrases.weakGps()
            }
        } else {
            gpsWeakSince = 0L
            if (gpsGoodSince == 0L) gpsGoodSince = now
            if (gpsWeakAnnounced && now - gpsGoodSince >= 10_000) {
                gpsWeakAnnounced = false
                return phrases.gpsRestored()
            }
        }
        return null
    }

    private fun stablePaceCue(
        now: Long,
        distanceMeters: Double,
        movingTimeSeconds: Int,
        target: RunPaceTarget,
    ): RunCue? {
        paceSamples.addLast(RunVoicePacePoint(now, distanceMeters, movingTimeSeconds))
        while (paceSamples.isNotEmpty() && now - paceSamples.first().atMillis > 25_000) paceSamples.removeFirst()
        if (paceSamples.size < 2 || distanceMeters < 200) return null
        val first = paceSamples.first()
        val elapsed = movingTimeSeconds - first.movingSeconds
        val distance = distanceMeters - first.distanceMeters
        if (elapsed < 12 || distance < 40) return null
        val pace = elapsed / (distance / 1000.0)
        val direction = target.direction(pace)
        if (direction == 0) {
            paceDeviationSince = 0L
            paceDeviationDirection = 0
            paceRepeats = 0
            if (paceCorrectionSpoken) {
                paceCorrectionSpoken = false
                if (standard) return RunCue(phrases.backOnPace(), RunCuePriority.normal, "pace", now, ttlMillis = 6_000)
            }
            return null
        }
        if (paceDeviationDirection != direction) {
            paceDeviationDirection = direction
            paceDeviationSince = now
            return null
        }
        if (paceDeviationSince == 0L || now - paceDeviationSince < 10_000) return null
        // Still off: say it again after 2, then 4, then 8 minutes.
        val repeatAfter = 120_000L shl paceRepeats.coerceAtMost(2)
        if (paceCorrectionSpoken && now - lastPaceAnnounceAt >= repeatAfter) {
            paceCorrectionSpoken = false
            paceRepeats++
        }
        if (paceCorrectionSpoken || (lastPaceAnnounceAt != 0L && now - lastPaceAnnounceAt < 60_000)) return null
        lastPaceAnnounceAt = now
        paceCorrectionSpoken = true
        val shown = pace.takeIf { standard }
        val text = when {
            direction > 0 -> phrases.paceTooSlow(shown)
            target.mode == RunPaceMode.ceiling -> phrases.easyTooFast(shown)
            else -> phrases.paceTooFast(shown)
        }
        return RunCue(text, RunCuePriority.high, "pace", now)
    }

    // --- Audio gates ----------------------------------------------------------

    private fun speechAllowed(): Boolean {
        if (!settings.enabled) return false
        if (settings.muteDuringCall && isInCall()) {
            Log.d("RunVoice", "skipped in call")
            return false
        }
        if (settings.headphonesOnly && !isHeadsetConnected()) {
            Log.d("RunVoice", "skipped no headset")
            return false
        }
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
        } catch (_: Throwable) { false }
    }
}
