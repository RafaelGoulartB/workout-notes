package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RunVoiceLapAndGoalTest {
    @Test
    fun lapAndAutoPausePhrasesFollowTheLanguage() {
        val pt = RunVoicePhrases(RunVoiceLanguage.pt)
        val en = RunVoicePhrases(RunVoiceLanguage.en)
        assertEquals("Pausa automática.", pt.autoPaused())
        assertEquals("Retomando.", pt.autoResumed())
        assertEquals("Auto paused.", en.autoPaused())
        assertEquals("Resuming.", en.autoResumed())

        assertEquals(
            "Volta 2. 1,2 quilômetro em 6 minutos e 12. Pace 5 e 10.",
            pt.lapSummary(2, 1200, 372, 310.0),
        )
        assertEquals(
            "Lap 1. 800 meters in 4 minutes. Pace 5 flat.",
            en.lapSummary(1, 800, 240, 300.0),
        )
        // No usable pace: the summary simply omits it.
        assertEquals("Lap 3. 500 meters in 2:30.", en.lapSummary(3, 500, 150, null))
    }

    @Test
    fun sessionGoalCarriesAnIndependentPaceTarget() {
        val goal = RunSessionGoal.fromMap(
            mapOf(
                "enabled" to false,
                "metric" to "distance",
                "value" to 5000,
                "pace_target_sec_per_km" to 330,
                "pace_tolerance_percent" to 10,
            ),
        )
        assertFalse(goal.enabled)
        assertEquals(330, goal.paceTargetSecPerKm)
        assertEquals(10, goal.paceTolerancePercent)
        // A pace goal never completes the distance/time goal.
        assertFalse(goal.isComplete(99_999.0, 99_999))
    }

    @Test
    fun legacyGoalMapsHaveNoPaceTarget() {
        val goal = RunSessionGoal.fromMap(mapOf("enabled" to true, "metric" to "time", "value" to 1800))
        assertNull(goal.paceTargetSecPerKm)
        assertEquals(5, goal.paceTolerancePercent)
        assertTrue(goal.isComplete(0.0, 1800))
    }

    @Test
    fun voiceSettingsDefaultsKeepAutoPauseOn() {
        val defaults = RunVoiceSettings.fromMap(mapOf("enabled" to true))
        assertTrue(defaults.autoPause)
        assertTrue(defaults.announceAutoPause)
        assertTrue(defaults.announceLaps)

        val off = RunVoiceSettings.fromMap(mapOf("autoPause" to false, "announceLaps" to false))
        assertFalse(off.autoPause)
        assertFalse(off.announceLaps)
    }

    @Test
    fun newVoiceSettingsDecodeWithSafeFallbacks() {
        val defaults = RunVoiceSettings.fromMap(mapOf("enabled" to true))
        assertEquals(RunVoiceVerbosity.standard, defaults.verbosity)
        assertFalse(defaults.pauseMedia)
        assertTrue(defaults.earcons)
        assertEquals(1.0f, defaults.speechRate)
        assertEquals(0, defaults.announceTimeEveryMin)

        val custom = RunVoiceSettings.fromMap(
            mapOf(
                "verbosity" to "minimal",
                "mediaBehavior" to "pause",
                "speechRate" to 1.2,
                "voiceVolume" to 0.6,
                "announceTimeEveryMin" to 7,
                "autoPauseStyle" to "beep",
            ),
        )
        assertEquals(RunVoiceVerbosity.minimal, custom.verbosity)
        assertTrue(custom.pauseMedia)
        assertEquals(1.25f, custom.speechRate)
        assertEquals(0.5f, custom.voiceVolume)
        assertEquals(0, custom.announceTimeEveryMin)
        assertTrue(custom.autoPauseBeep)

        val roundTrip = RunVoiceSettings.fromJson(custom.toJson())
        assertEquals(custom, roundTrip)
    }

    @Test
    fun workoutProfileGivesStepLessPlansAGoalAndPace() {
        val easy = RunWorkoutProfile.fromMap(
            mapOf("kind" to "easy", "targetDistanceMeters" to 8000, "targetPaceSecPerKm" to 360.0),
        )
        assertEquals(8000, easy.implicitGoal()!!.value)
        val pace = easy.implicitPace()!!
        assertEquals(RunPaceMode.ceiling, pace.mode)
        // Easy days never get "pick it up".
        assertEquals(0, pace.direction(420.0))
        assertEquals(-1, pace.direction(320.0))

        val race = RunWorkoutProfile.fromMap(mapOf("kind" to "race", "targetDistanceMeters" to 10000, "targetPaceSecPerKm" to 300.0))
        assertEquals(1, race.implicitPace()!!.direction(320.0))

        val test = RunWorkoutProfile.fromMap(mapOf("kind" to "test", "targetPaceSecPerKm" to 280.0))
        assertNull(test.implicitPace())

        assertEquals(easy, RunWorkoutProfile.fromJsonString(easy.toJson().toString()))
    }
}
