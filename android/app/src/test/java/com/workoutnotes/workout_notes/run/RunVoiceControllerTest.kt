package com.workoutnotes.workout_notes.run

import android.content.ContextWrapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The native controller is the only voice engine, so its cue selection is
 * pinned here with a fake speech output and a fake clock. The Android context
 * is an empty wrapper: audio-route and locale lookups fail and fall back to
 * "no headset", "not in a call" and English.
 */
class RunVoiceControllerTest {

    private class FakeSpeech : RunSpeechOutput {
        val spoken = mutableListOf<String>()
        val earcons = mutableListOf<RunEarcon>()
        override fun ensureReady(language: RunVoiceLanguage) {}
        override fun setLanguage(language: RunVoiceLanguage) {}
        override fun speak(text: String) { spoken.add(text) }
        override fun stop() {}
        override fun shutdown() {}
        override fun playEarcon(earcon: RunEarcon, then: String?) {
            earcons.add(earcon)
            then?.let { spoken.add(it) }
        }
    }

    private class FakeHaptics : RunHaptics {
        val patterns = mutableListOf<RunHapticPattern>()
        override fun vibrate(pattern: RunHapticPattern) { patterns.add(pattern) }
    }

    private var now = 1_000_000L
    private val speech = FakeSpeech()
    private val haptics = FakeHaptics()
    private val controller = RunVoiceController(ContextWrapper(null), speech, haptics) { now }

    private fun settings(vararg overrides: Pair<String, Any?>): Map<String, Any?> =
        mapOf(
            "enabled" to true,
            "language" to "en",
            "headphonesOnly" to false,
            "announceGpsStatus" to false,
        ) + overrides

    private fun begin(
        settings: Map<String, Any?> = settings(),
        goal: Map<String, Any?>? = null,
        intervalsOn: Boolean = false,
        plan: List<Map<String, Any?>>? = null,
        workout: Map<String, Any?>? = null,
    ) = controller.begin(settings, goal, intervalsOn, plan, workout)

    /** One tracking update; the clock follows the moving time. */
    private fun tick(
        distance: Double,
        moving: Int,
        splits: List<Map<String, Any?>> = emptyList(),
        recording: Boolean = true,
        autoPaused: Boolean = false,
        paused: Boolean = false,
    ) {
        now = 1_000_000L + moving * 1000L
        controller.onTrackingUpdate(
            distanceMeters = distance,
            durationSeconds = moving,
            movingTimeSeconds = moving,
            currentPaceSecPerKm = if (distance > 0) moving / (distance / 1000.0) else null,
            lat = -23.5,
            accuracyMeters = 8f,
            isRecording = recording,
            isPaused = paused,
            splitsCount = splits.size,
            currentSplitPace = null,
            splits = splits,
            autoPaused = autoPaused,
        )
    }

    /** Runs at a steady [paceSecPerKm] from [fromSecond] to [toSecond], one update per second. */
    private fun run(fromSecond: Int, toSecond: Int, startMeters: Double, paceSecPerKm: Double): Double {
        var meters = startMeters
        for (second in fromSecond + 1..toSecond) {
            meters += 1000.0 / paceSecPerKm
            tick(meters, second)
        }
        return meters
    }

    private fun kmSplits(count: Int, pace: Double) =
        (1..count).map { mapOf("km" to it, "pace_sec_per_km" to pace) }

    private fun step(
        role: String,
        value: Int,
        metric: String = "distance",
        group: Int? = null,
        count: Int = 1,
        min: Double? = null,
        max: Double? = null,
    ) = mapOf(
        "role" to role,
        "metric" to metric,
        "value" to value,
        "repeatGroup" to group,
        "repeatCount" to count,
        "targetPaceMinSecPerKm" to min,
        "targetPaceMaxSecPerKm" to max,
    )

    @Test
    fun continuousPlanAnnouncesAndCompletes() {
        begin(
            settings("announceDistance" to false),
            plan = listOf(step("steady", 2800, min = 360.0, max = 360.0)),
        )

        tick(0.0, 0)
        assertEquals(listOf("Steady, 2.8 kilometers at 6 flat."), speech.spoken)
        assertEquals(listOf(RunEarcon.go), speech.earcons)
        assertEquals(listOf(RunHapticPattern.go), haptics.patterns)

        run(0, 960, 0.0, 360.0)
        assertTrue(speech.spoken.contains("Halfway."))
        assertTrue(speech.spoken.contains("200 meters left."))

        run(960, 1010, 2666.6, 360.0)
        assertTrue(speech.spoken.last().startsWith("Workout complete. 2.8 kilometers"))
        assertEquals(RunEarcon.done, speech.earcons.last())
    }

    @Test
    fun intervalSessionSpeaksResultsCountdownAndLastRep() {
        begin(
            plan = listOf(
                step("warmup", 1000),
                step("work", 400, group = 1, count = 3, min = 230.0, max = 250.0),
                step("recovery", 60, "time", group = 1, count = 3),
                step("cooldown", 500),
            ),
            workout = mapOf("kind" to "interval"),
        )
        tick(0.0, 0)
        assertEquals("Warm up, 1 kilometer.", speech.spoken.last())

        var meters = run(0, 360, 0.0, 360.0)
        assertEquals("Rep 1 of 3. 400 meters at 4 flat.", speech.spoken.last())

        // 400 m in 96 s: inside the 92–100 s window of the band.
        meters = run(360, 456, meters, 240.0)
        assertEquals("1:36, on target. Recover, 1 minute.", speech.spoken.last())

        // Recovery: a heads-up naming the next rep, then the 3-2-1 beeps.
        run(456, 516, meters, 600.0)
        assertTrue(speech.spoken.contains("Rep 2 in 10 seconds."))
        assertEquals(3, speech.earcons.count { it == RunEarcon.countdown })
        // The target pace is not repeated on later reps.
        assertEquals("Rep 2 of 3. 400 meters.", speech.spoken.last())
        assertFalse(speech.spoken.any { it.startsWith("Kilometer") })
    }

    @Test
    fun lastRepAndAllRepsDoneAreCalledOut() {
        begin(
            plan = listOf(
                step("work", 400, group = 1, count = 2),
                step("recovery", 60, "time", group = 1, count = 2),
                step("cooldown", 500),
            ),
            workout = mapOf("kind" to "interval"),
        )
        tick(0.0, 0)
        var meters = run(0, 100, 0.0, 250.0)
        meters = run(100, 160, meters, 900.0)
        assertEquals("Last rep. 400 meters.", speech.spoken.last())
        run(160, 260, meters, 250.0)
        assertTrue(speech.spoken.last().contains("All reps done. Recover, 1 minute."))
    }

    @Test
    fun hillAndStrideSessionsUseTheirOwnWords() {
        begin(
            plan = listOf(
                step("work", 60, "time", group = 1, count = 6),
                step("recovery", 96, "time", group = 1, count = 6),
            ),
            workout = mapOf("kind" to "hills"),
        )
        tick(0.0, 0)
        assertEquals("Hill 1 of 6. 1 minute.", speech.spoken.last())
        run(0, 60, 0.0, 400.0)
        assertEquals("Easy back down, 96 seconds.", speech.spoken.last())

        speech.spoken.clear()
        begin(
            plan = listOf(
                step("steady", 3000, min = 330.0, max = 360.0),
                step("work", 20, "time", group = 1, count = 4, min = 210.0),
                step("recovery", 60, "time", group = 1, count = 4),
            ),
            workout = mapOf("kind" to "easy"),
        )
        tick(0.0, 0)
        run(0, 1040, 0.0, 345.0)
        assertTrue(speech.spoken.contains("Stride 1 of 4. 20 seconds."))
        // Strides are too short for a GPS pace check or a voiced "10 seconds".
        assertFalse(speech.spoken.any { it.startsWith("Pick it up") || it.startsWith("Ease off") })
        run(1040, 1060, 3000.0, 200.0)
        assertTrue(speech.spoken.last().startsWith("Easy, 1 minute"))
    }

    @Test
    fun paceWarningsReArmDuringALongTempo() {
        begin(
            plan = listOf(step("steady", 1200, "time", min = 290.0, max = 310.0)),
            workout = mapOf("kind" to "tempo"),
        )
        tick(0.0, 0)
        var meters = run(0, 100, 0.0, 340.0)
        assertTrue(speech.spoken.any { it.startsWith("Pick it up.") })
        meters = run(100, 160, meters, 300.0)
        assertTrue(speech.spoken.contains("Back on pace."))
        run(160, 300, meters, 340.0)
        assertEquals(2, speech.spoken.count { it.startsWith("Pick it up.") })
    }

    @Test
    fun easyRunsOnlyWarnWhenTooFast() {
        begin(
            workout = mapOf("kind" to "easy", "targetDistanceMeters" to 8000, "targetPaceSecPerKm" to 360.0),
            settings = settings("announceDistance" to false),
        )
        tick(0.0, 0)
        var meters = run(0, 200, 0.0, 450.0)
        assertTrue(speech.spoken.isEmpty())
        meters = run(200, 260, meters, 310.0)
        assertTrue(speech.spoken.toString(), speech.spoken.single().startsWith("Keep it easy."))
        // Back inside the easy range; the planned distance acts as the goal.
        run(260, 2900, meters, 345.0)
        assertTrue(speech.spoken.toString(), speech.spoken.contains("Back on pace."))
        assertTrue(speech.spoken.toString(), speech.spoken.any { it.contains("Halfway. 4") })
        assertTrue(speech.spoken.toString(), speech.spoken.any { it.contains("Planned distance done.") })
        assertEquals(1, speech.spoken.count { it.startsWith("Keep it easy.") })
    }

    @Test
    fun persistentPaceDriftIsRepeatedWithBackoff() {
        begin(
            settings("announceDistance" to false),
            goal = mapOf("enabled" to false, "pace_target_sec_per_km" to 300, "pace_tolerance_percent" to 5),
        )
        tick(0.0, 0)
        run(0, 1200, 0.0, 360.0)
        // Warned at ~0:25, then after 2 and 4 more minutes, then every 8.
        assertEquals(speech.spoken.toString(), 4, speech.spoken.count { it.startsWith("Pick it up.") })
    }

    @Test
    fun kilometerCueRespectsItsSettings() {
        begin()
        tick(1000.0, 360, kmSplits(1, 360.0))
        assertEquals(listOf("Kilometer 1. Time 6 minutes. Pace 6 flat."), speech.spoken)

        speech.spoken.clear()
        begin(settings("kmIncludeTime" to false, "announceSplit" to false, "kmIncludeAvgPace" to true))
        tick(1000.0, 300, kmSplits(1, 300.0))
        assertEquals(listOf("Kilometer 1. Average 5 flat."), speech.spoken)
    }

    @Test
    fun goalProgressMergesWithTheKilometerCueInsteadOfReplacingIt() {
        begin(goal = mapOf("enabled" to true, "metric" to "distance", "value" to 10000))
        tick(5000.0, 1500, kmSplits(5, 300.0))
        assertEquals(
            listOf("Kilometer 5. Time 25 minutes. Pace 5 flat. Halfway. 5 kilometers to go."),
            speech.spoken,
        )
    }

    @Test
    fun aCueThatCollidesWaitsInsteadOfBeingLost() {
        begin(goal = mapOf("enabled" to true, "metric" to "distance", "value" to 1000))
        tick(1000.0, 360, kmSplits(1, 360.0))
        assertEquals(listOf("Goal complete. 1 kilometer."), speech.spoken)

        tick(1040.0, 375, kmSplits(1, 360.0))
        assertEquals("Kilometer 1. Time 6 minutes. Pace 6 flat.", speech.spoken.last())
    }

    @Test
    fun minimalVerbositySkipsProgressCues() {
        begin(settings("verbosity" to "minimal"))
        tick(1000.0, 300, kmSplits(1, 300.0))
        tick(2000.0, 600, kmSplits(2, 300.0))
        assertTrue(speech.spoken.isEmpty())
    }

    @Test
    fun raceGetsAProjectionAgainstItsTarget() {
        begin(workout = mapOf("kind" to "race", "targetDistanceMeters" to 10000, "targetPaceSecPerKm" to 300.0))
        tick(1000.0, 295, kmSplits(1, 295.0))
        assertEquals(
            "Kilometer 1. Time 4:55. Pace 4:55. On track for 49:10. 50 seconds ahead.",
            speech.spoken.single(),
        )
    }

    @Test
    fun timeCuesFollowTheSetting() {
        begin(settings("announceDistance" to false, "announceTimeEveryMin" to 5))
        tick(1500.0, 299)
        tick(1505.0, 300)
        assertEquals(listOf("5 minutes. 1.5 kilometers."), speech.spoken)
    }

    @Test
    fun treadmillUsesTimeCuesOnly() {
        controller.indoor = true
        begin()
        tick(0.0, 299)
        tick(0.0, 300)
        assertEquals(listOf("5 minutes."), speech.spoken)
    }

    @Test
    fun headphonesOnlyStaysSilentButStillVibrates() {
        begin(settings("headphonesOnly" to true), plan = listOf(step("work", 400)))
        tick(0.0, 0)
        assertTrue(speech.spoken.isEmpty())
        assertEquals(listOf(RunHapticPattern.go), haptics.patterns)
    }

    @Test
    fun disabledVoiceNeverSpeaks() {
        begin(settings("enabled" to false))
        tick(1000.0, 300, kmSplits(1, 300.0))
        controller.speakWorkoutComplete()
        assertTrue(speech.spoken.isEmpty())
    }

    @Test
    fun announcesAutoPauseAndResumeOnceEach() {
        begin(settings("announceDistance" to false))
        tick(500.0, 200)
        assertTrue(speech.spoken.isEmpty())

        tick(500.0, 200, autoPaused = true)
        assertEquals(listOf("Auto paused."), speech.spoken)

        // Still standing: no repeated cue.
        tick(500.0, 201, autoPaused = true)
        assertEquals(1, speech.spoken.size)

        tick(510.0, 210)
        assertEquals("Resuming.", speech.spoken.last())
    }

    @Test
    fun autoPauseCanBeABeepOrOff() {
        begin(settings("autoPauseStyle" to "beep", "announceDistance" to false))
        tick(500.0, 200)
        tick(500.0, 201, autoPaused = true)
        assertTrue(speech.spoken.isEmpty())
        assertEquals(listOf(RunEarcon.pause), speech.earcons)

        begin(settings("announceAutoPause" to false, "announceDistance" to false))
        tick(500.0, 200)
        tick(500.0, 201, autoPaused = true)
        assertTrue(speech.spoken.isEmpty())
    }

    @Test
    fun resumingAStructuredStepSaysWhatIsLeft() {
        begin(plan = listOf(step("work", 1000, group = 1, count = 2), step("recovery", 60, "time", group = 1, count = 2)))
        tick(0.0, 0)
        tick(300.0, 80)
        tick(300.0, 80, recording = false, paused = true)
        assertEquals("Paused.", speech.spoken.last())
        tick(300.0, 90)
        assertEquals("Resumed. Rep 1, 700 meters left.", speech.spoken.last())
    }

    @Test
    fun lapSummaryFollowsTheAnnounceLapsSetting() {
        val lap = mapOf(
            "lap_index" to 2,
            "distance_meters" to 1200.0,
            "duration_seconds" to 372,
            "pace_sec_per_km" to 310.0,
        )
        begin()
        controller.announceLap(lap)
        assertEquals(listOf("Lap 2. 1.2 kilometers in 6:12. Pace 5:10."), speech.spoken)

        speech.spoken.clear()
        begin(settings("announceLaps" to false))
        controller.announceLap(lap)
        assertTrue(speech.spoken.isEmpty())
    }

    @Test
    fun skippingTheQuickIntervalSetMovesToTheNextPhase() {
        begin(intervalsOn = true)
        tick(0.0, 0)
        assertEquals(listOf("Rep 1 of 8. 400 meters."), speech.spoken)

        assertTrue(controller.skipStep())
        assertEquals("Recover, 90 seconds.", speech.spoken.last())
        assertEquals("rest", controller.intervalSnapshotMap()?.get("phase"))
    }

    @Test
    fun quickIntervalsReportTheRepTime() {
        begin(intervalsOn = true)
        tick(0.0, 0)
        run(0, 90, 0.0, 225.0)
        assertEquals("1:30. Recover, 90 seconds.", speech.spoken.last())
    }

    @Test
    fun intervalSnapshotIsOnlyPublishedForARunningQuickSet() {
        begin(intervalsOn = true)
        assertNull(controller.intervalSnapshotMap())

        tick(0.0, 0)
        val snapshot = controller.intervalSnapshotMap()!!
        assertEquals("work", snapshot["phase"])
        assertEquals(1, snapshot["workIndex"])
        assertEquals(8, snapshot["totalWorks"])
        assertEquals("rest", snapshot["nextPhase"])

        controller.end()
        assertNull(controller.intervalSnapshotMap())
    }

    @Test
    fun workoutCompleteAcknowledgementRespectsTheVoiceGates() {
        begin(settings("headphonesOnly" to true))
        controller.speakWorkoutComplete()
        assertFalse(speech.spoken.contains("Workout complete."))

        controller.syncFromFlutter(settings(), null, null)
        controller.speakWorkoutComplete()
        assertEquals(listOf("Workout complete."), speech.spoken)
    }

    @Test
    fun portugueseLanguageUsesPortuguesePhrases() {
        begin(settings("language" to "pt"))
        tick(1000.0, 360, kmSplits(1, 360.0))
        assertEquals("Quilômetro 1. Tempo 6 minutos. Pace 6 cravado.", speech.spoken.single())
    }

    @Test
    fun plannedEasyRunAsOneContinuousStepOnlyWarnsWhenTooFast() {
        // What Dart sends for a step-less easy run: one steady step, ±5% band.
        begin(
            settings("announceDistance" to false),
            plan = listOf(step("steady", 6000, min = 342.0, max = 378.0)),
            workout = mapOf("kind" to "easy", "targetDistanceMeters" to 6000, "targetPaceSecPerKm" to 360.0),
        )
        tick(0.0, 0)
        assertEquals("Steady, 6 kilometers at 6 flat.", speech.spoken.last())
        var meters = run(0, 400, 0.0, 450.0)
        assertFalse(speech.spoken.any { it.startsWith("Pick it up") })
        meters = run(400, 500, meters, 300.0)
        assertTrue(speech.spoken.toString(), speech.spoken.any { it.startsWith("Keep it easy.") })
    }

    @Test
    fun plannedRaceGetsItsOwnWordsAndProjections() {
        begin(
            plan = listOf(step("work", 10000, min = 291.0, max = 309.0)),
            workout = mapOf("kind" to "race", "targetDistanceMeters" to 10000, "targetPaceSecPerKm" to 300.0),
        )
        tick(0.0, 0)
        assertEquals("Race, 10 kilometers at 5 flat. Go!", speech.spoken.last())
        tick(1000.0, 295, kmSplits(1, 295.0))
        assertEquals(
            "Kilometer 1. Time 4:55. Pace 4:55. On track for 49:10. 50 seconds ahead.",
            speech.spoken.last(),
        )
    }

    @Test
    fun detailedModeAddsAverageAndOnPaceConfirmation() {
        begin(
            settings("verbosity" to "detailed", "kmIncludeTime" to false),
            goal = mapOf("enabled" to false, "pace_target_sec_per_km" to 300, "pace_tolerance_percent" to 5),
        )
        tick(1000.0, 302, kmSplits(1, 302.0))
        assertEquals("Kilometer 1. Pace 5:02. Average 5:02. On pace.", speech.spoken.single())
    }

    @Test
    fun settingsSyncMidRunKeepsTheWorkoutWhereItIs() {
        val plan = listOf(step("warmup", 1000), step("work", 400, group = 1, count = 2))
        begin(plan = plan)
        tick(0.0, 0)
        run(0, 380, 0.0, 360.0)
        assertEquals("work", controller.stepSnapshotMap()?.get("role"))

        controller.syncFromFlutter(settings("verbosity" to "minimal"), null, false, plan)
        tick(1060.0, 381)
        assertEquals("work", controller.stepSnapshotMap()?.get("role"))
        assertFalse(speech.spoken.last().startsWith("Warm up"))
    }
}
