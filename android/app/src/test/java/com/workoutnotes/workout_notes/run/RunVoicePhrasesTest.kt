package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RunVoicePhrasesTest {
    private val en = RunVoicePhrases(RunVoiceLanguage.en)
    private val pt = RunVoicePhrases(RunVoiceLanguage.pt)

    @Test
    fun distanceMilestoneIncludesPaceWhenPresent() {
        val text = en.distanceMilestone(2, 724, 362.0)
        assertTrue(text.contains("2 kilometers"))
        assertTrue(text.contains("Average"))
        assertTrue(text.length < 70)
    }

    @Test
    fun splitAndIntervalPhrasesAreEnglish() {
        assertTrue(en.splitComplete(3, 348.0).startsWith("Kilometer 3"))
        assertEquals("Rep 1 of 8. Go.", en.workIntervalStart(1, 8))
        assertTrue(en.restIntervalStart(RunIntervalMetric.time, 90).contains("Recover."))
    }

    @Test
    fun portugueseUsesNaturalRunningVocabulary() {
        assertEquals(
            "Quilômetro 3. Pace 5 minutos e 48 segundos por quilômetro.",
            pt.splitComplete(3, 348.0),
        )
        assertEquals("Tiro 2 de 6. Vai!", pt.workIntervalStart(2, 6))
        assertEquals(
            "Recuperação. 1 minuto e 30 segundos.",
            pt.restIntervalStart(RunIntervalMetric.time, 90),
        )
        assertEquals("Pace dentro da meta.", pt.paceOnTarget())
    }

    @Test
    fun workoutCompleteAndTestAnnouncement() {
        assertEquals("Workout complete.", en.workoutComplete())
        assertEquals("Treino concluído.", pt.workoutComplete())
        assertTrue(en.testAnnouncement().isNotBlank())
    }
}
