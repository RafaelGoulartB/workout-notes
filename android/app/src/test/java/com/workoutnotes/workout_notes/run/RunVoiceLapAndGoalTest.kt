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
            "Volta 2. 1 quilômetro e 200 metros. 6 minutos e 12 segundos. " +
                "Pace 5 minutos e 10 segundos por quilômetro.",
            pt.lapSummary(2, 1200, 372, 310.0),
        )
        assertEquals(
            "Lap 1. 800 meters. 4 minutes. Pace 5 minutes per kilometer.",
            en.lapSummary(1, 800, 240, 300.0),
        )
        // No usable pace: the summary simply omits it.
        assertEquals("Lap 3. 500 meters. 2 minutes 30 seconds.", en.lapSummary(3, 500, 150, null))
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
}
