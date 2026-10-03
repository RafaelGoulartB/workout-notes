package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RunVoicePhrasesTest {
    private val en = RunVoicePhrases(RunVoiceLanguage.en)
    private val pt = RunVoicePhrases(RunVoiceLanguage.pt)

    @Test
    fun paceIsSaidTheWayRunnersSayIt() {
        assertEquals("4:50", en.pace(290.0))
        assertEquals("4:05", en.pace(245.0))
        assertEquals("5 flat", en.pace(300.0))
        assertEquals("4 e 50", pt.pace(290.0))
    }

    @Test
    fun durationsAvoidClockTimeReadings() {
        assertEquals("45 seconds", en.clock(45))
        assertEquals("1:28", en.clock(88))
        // "6:00" would be read as a time of day.
        assertEquals("6 minutes", en.clock(360))
        assertEquals("1 hour 5 minutes", en.elapsed(3_925))
        assertEquals("90 seconds", en.length(90))
        assertEquals("2 minutes 30", en.length(150))
        assertEquals("20 minutes", en.length(1_210))
        assertEquals("1 minuto e 28", pt.clock(88))
    }

    @Test
    fun distancesAreRoundedToWhatCanBeSaid() {
        assertEquals("400 meters", en.distance(400))
        assertEquals("1 kilometer", en.distance(1_000))
        assertEquals("1.5 kilometers", en.distance(1_500))
        assertEquals("2.8 kilometers", en.distance(2_800))
        assertEquals("1,5 quilômetro", pt.distance(1_500))
        assertEquals("2.5 kilometers", en.remainingAmount(RunIntervalMetric.distance, 2_487.0))
        assertEquals("15 minutes", en.remainingAmount(RunIntervalMetric.time, 877.0))
    }

    @Test
    fun stepIntrosAreShort() {
        assertEquals(
            "Rep 1 of 6. 800 meters at 3:50.",
            en.stepIntro(RunStepLabel.rep, 1, 6, false, RunIntervalMetric.distance, 800, 230.0),
        )
        assertEquals("Last rep. 800 meters.", en.stepIntro(RunStepLabel.rep, 6, 6, true, RunIntervalMetric.distance, 800))
        assertEquals("Recover, 90 seconds.", en.stepIntro(RunStepLabel.recover, 1, 6, false, RunIntervalMetric.time, 90))
        assertEquals("Hill 3 of 8. 1 minute.", en.stepIntro(RunStepLabel.hill, 3, 8, false, RunIntervalMetric.time, 60))
        assertEquals("Time trial, 3 kilometers. Go!", en.stepIntro(RunStepLabel.timeTrial, 1, 1, false, RunIntervalMetric.distance, 3_000))
        assertEquals("Tiro 2 de 6. 400 metros.", pt.stepIntro(RunStepLabel.rep, 2, 6, false, RunIntervalMetric.distance, 400))
        // Every phrase the coach says at a step change stays under ~8 words.
        val longest = en.stepIntro(RunStepLabel.rep, 10, 12, false, RunIntervalMetric.distance, 1_200, 245.0)
        assertTrue(longest.split(" ").size <= 9)
    }

    @Test
    fun repResultsCompareWithTheTarget() {
        assertEquals("1:28, on target.", en.repTime(88, RunRepVerdict.onTarget))
        assertEquals("1:28, 3 seconds fast.", en.repTime(88, RunRepVerdict.fast, 3))
        assertEquals("Pace 3:40, a bit slow.", en.repPace(220.0, RunRepVerdict.slow))
        assertEquals("Rep 4 in 10 seconds.", en.nextInSeconds(en.stepName(RunStepLabel.rep, 4, false), 10))
        assertEquals("Last hill in 100 meters.", en.nextInMeters(en.stepName(RunStepLabel.hill, 8, true), 100))
    }

    @Test
    fun kilometerCueCarriesOnlyTheChosenParts() {
        assertEquals("Kilometer 3. Time 15:20. Pace 5:05.", en.kilometer(3, 920, 305.0, null))
        assertEquals("Kilometer 3. Average 5:10.", en.kilometer(3, null, null, 310.0))
        assertEquals("Quilômetro 3. Pace 5 e 5.", pt.kilometer(3, null, 305.0, null))
    }

    @Test
    fun projectionsSayAheadOrBehind() {
        assertEquals("On track for 49:30. 12 seconds ahead.", en.projection(2_970, 12))
        assertEquals("On track for 49:30. 20 seconds behind.", en.projection(2_970, -20))
        assertEquals("On track for 49:30. On target.", en.projection(2_970, 1))
    }

    @Test
    fun workoutCompleteAndTestAnnouncement() {
        assertEquals("Workout complete.", en.workoutComplete())
        assertEquals("Workout complete. 8.2 kilometers in 45 minutes.", en.workoutComplete(8_240.0, 2_700))
        assertEquals("Treino concluído.", pt.workoutComplete())
        assertEquals("Voice coach ready. Pace 5:30.", en.testAnnouncement())
    }
}
