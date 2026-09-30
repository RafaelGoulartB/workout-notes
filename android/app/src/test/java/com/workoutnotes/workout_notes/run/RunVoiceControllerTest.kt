package com.workoutnotes.workout_notes.run

import android.content.ContextWrapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The native controller is the only voice engine, so its cue selection is
 * pinned here with a fake speech output. The Android context is an empty
 * wrapper: audio-route and locale lookups fail and fall back to "no headset",
 * "not in a call" and English.
 */
class RunVoiceControllerTest {

    private class FakeSpeech : RunSpeechOutput {
        val spoken = mutableListOf<String>()
        override fun ensureReady(language: RunVoiceLanguage) {}
        override fun setLanguage(language: RunVoiceLanguage) {}
        override fun speak(text: String) { spoken.add(text) }
        override fun stop() {}
        override fun shutdown() {}
    }

    private val speech = FakeSpeech()
    private val controller = RunVoiceController(ContextWrapper(null), speech)

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
    ) = controller.begin(settings, goal, intervalsOn, plan)

    private fun tick(
        distance: Double,
        moving: Int,
        splits: List<Map<String, Any?>> = emptyList(),
        recording: Boolean = true,
        autoPaused: Boolean = false,
    ) = controller.onTrackingUpdate(
        distanceMeters = distance,
        durationSeconds = moving,
        movingTimeSeconds = moving,
        currentPaceSecPerKm = if (distance > 0) moving / (distance / 1000.0) else null,
        lat = -23.5,
        accuracyMeters = 8f,
        isRecording = recording,
        isPaused = false,
        splitsCount = splits.size,
        currentSplitPace = null,
        splits = splits,
        autoPaused = autoPaused,
    )

    private fun kmSplit(km: Int, pace: Double) =
        mapOf("km" to km, "pace_sec_per_km" to pace)

    @Test
    fun continuousPlanAnnouncesAndCompletesEvenWhenQuickIntervalsAreMuted() {
        begin(
            settings(
                "announceIntervals" to false,
                "announceDistance" to false,
                "announceSplit" to false,
            ),
            plan = listOf(
                mapOf(
                    "role" to "steady",
                    "metric" to "distance",
                    "value" to 2800,
                    "targetPaceMinSecPerKm" to 360.0,
                    "targetPaceMaxSecPerKm" to 360.0,
                ),
            ),
        )

        tick(0.0, 0)
        assertEquals(
            listOf("Steady. 2 kilometers and 800 meters. Target pace 6 minutes per kilometer."),
            speech.spoken,
        )

        tick(2700.0, 972)
        assertEquals("100 meters left.", speech.spoken.last())

        tick(2800.0, 1008)
        assertEquals("Workout complete.", speech.spoken.last())
    }

    @Test
    fun kilometerSplitAndMilestoneMergeIntoOneCue() {
        begin()
        tick(1000.0, 360, listOf(kmSplit(1, 360.0)))

        assertEquals(1, speech.spoken.size)
        assertTrue(speech.spoken.single().startsWith("Kilometer 1. Pace 6 minutes"))
        assertTrue(speech.spoken.single().contains("Average"))
    }

    @Test
    fun portugueseLanguageUsesPortuguesePhrases() {
        begin(settings("language" to "pt"))
        tick(1000.0, 360, listOf(kmSplit(1, 360.0)))

        assertTrue(speech.spoken.single().startsWith("Quilômetro 1. Pace 6 minutos"))
        assertTrue(speech.spoken.single().contains("Pace médio"))
    }

    @Test
    fun headphonesOnlyStaysSilentWithoutAHeadset() {
        begin(settings("headphonesOnly" to true))
        tick(1000.0, 300)
        assertTrue(speech.spoken.isEmpty())
    }

    @Test
    fun disabledVoiceNeverSpeaks() {
        begin(settings("enabled" to false))
        tick(1000.0, 300, listOf(kmSplit(1, 300.0)))
        controller.speakWorkoutComplete()
        assertTrue(speech.spoken.isEmpty())
    }

    @Test
    fun goalCompletionPreemptsOtherCuesInTheSameTick() {
        begin(
            goal = mapOf("enabled" to true, "metric" to "distance", "value" to 1000),
        )
        tick(1000.0, 360, listOf(kmSplit(1, 360.0)))

        assertEquals(1, speech.spoken.size)
        assertTrue(speech.spoken.single().startsWith("Goal complete"))
    }

    @Test
    fun announcesAutoPauseAndResumeOnceEach() {
        begin(settings("announceDistance" to false, "announceSplit" to false))
        tick(500.0, 200)
        assertTrue(speech.spoken.isEmpty())

        tick(500.0, 200, autoPaused = true)
        assertEquals(listOf("Auto paused."), speech.spoken)

        // Still standing: no repeated cue.
        tick(500.0, 200, autoPaused = true)
        assertEquals(1, speech.spoken.size)

        tick(510.0, 205)
        assertEquals("Resuming.", speech.spoken.last())
    }

    @Test
    fun autoPauseCuesCanBeSwitchedOff() {
        begin(
            settings(
                "announceAutoPause" to false,
                "announceDistance" to false,
                "announceSplit" to false,
            ),
        )
        tick(500.0, 200)
        tick(500.0, 200, autoPaused = true)
        assertTrue(speech.spoken.isEmpty())
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
        assertEquals(
            listOf("Lap 2. 1 kilometer and 200 meters. 6 minutes 12 seconds. Pace 5 minutes 10 seconds per kilometer."),
            speech.spoken,
        )

        speech.spoken.clear()
        begin(settings("announceLaps" to false))
        controller.announceLap(lap)
        assertTrue(speech.spoken.isEmpty())
    }

    @Test
    fun skippingTheQuickIntervalSetMovesToTheNextPhase() {
        begin(intervalsOn = true)
        tick(0.0, 0)
        assertEquals(listOf("Rep 1 of 8. Go."), speech.spoken)

        assertTrue(controller.skipStep())
        assertTrue(speech.spoken.last().startsWith("Recover."))
        assertEquals("rest", controller.intervalSnapshotMap()?.get("phase"))
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
}
