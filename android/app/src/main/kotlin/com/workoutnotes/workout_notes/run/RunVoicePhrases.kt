package com.workoutnotes.workout_notes.run

import kotlin.math.abs
import kotlin.math.roundToInt

/** What a structured step is called out loud; picked from role and workout kind. */
enum class RunStepLabel {
    warmup, cooldown, recover, steady, effort, rep, hill, surge, stride, run, walk, timeTrial, race, easyBack, float, easy;

    /** Labels counted as "N of M" with a "last one" call. */
    val isCounted: Boolean get() = this == rep || this == hill || this == surge || this == stride || this == run
}

/** How a finished rep compares with its target. */
enum class RunRepVerdict { none, onTarget, fast, slow }

/**
 * Spoken run phrases. English is the primary voice; Portuguese mirrors it.
 *
 * Every phrase is kept short so it barely interrupts music or a podcast:
 * paces are said the way runners say them ("4:50", not "4 minutes and 50
 * seconds per kilometer"), amounts are rounded, and one cue carries one idea.
 */
class RunVoicePhrases(private val language: RunVoiceLanguage) {

    private val pt: Boolean get() = language == RunVoiceLanguage.pt

    // --- Structured steps ---------------------------------------------------

    fun stepIntro(
        label: RunStepLabel,
        rep: Int,
        total: Int,
        isLast: Boolean,
        metric: RunIntervalMetric,
        value: Int,
        targetPace: Double? = null,
    ): String {
        val amount = if (metric == RunIntervalMetric.time) length(value) else distance(value)
        val pace = if (validPace(targetPace)) (if (pt) " no pace " else " at ") + pace(targetPace!!) else ""
        val counted = label.isCounted && total > 1
        val head = if (pt) {
            when (label) {
                RunStepLabel.rep -> if (isLast && counted) "Último tiro." else if (counted) "Tiro $rep de $total." else "Tiro."
                RunStepLabel.hill -> if (isLast && counted) "Última subida." else if (counted) "Subida $rep de $total." else "Subida."
                RunStepLabel.surge -> if (isLast && counted) "Última aceleração." else if (counted) "Aceleração $rep de $total." else "Aceleração."
                RunStepLabel.stride -> if (isLast && counted) "Última aceleração curta." else if (counted) "Aceleração curta $rep de $total." else "Aceleração curta."
                RunStepLabel.run -> if (isLast && counted) "Última corrida," else "Corre,"
                RunStepLabel.walk -> "Caminha,"
                RunStepLabel.effort -> "Esforço,"
                RunStepLabel.steady -> "Ritmo contínuo,"
                RunStepLabel.timeTrial -> "Teste,"
                RunStepLabel.race -> "Prova,"
                RunStepLabel.warmup -> "Aquecimento,"
                RunStepLabel.cooldown -> "Desaquecimento,"
                RunStepLabel.recover -> "Recupera,"
                RunStepLabel.easyBack -> "Desce leve,"
                RunStepLabel.float -> "Solta,"
                RunStepLabel.easy -> "Leve,"
            }
        } else {
            when (label) {
                RunStepLabel.rep -> if (isLast && counted) "Last rep." else if (counted) "Rep $rep of $total." else "Rep."
                RunStepLabel.hill -> if (isLast && counted) "Last hill." else if (counted) "Hill $rep of $total." else "Hill."
                RunStepLabel.surge -> if (isLast && counted) "Last surge." else if (counted) "Surge $rep of $total." else "Surge."
                RunStepLabel.stride -> if (isLast && counted) "Last stride." else if (counted) "Stride $rep of $total." else "Stride."
                RunStepLabel.run -> if (isLast && counted) "Last run," else "Run,"
                RunStepLabel.walk -> "Walk,"
                RunStepLabel.effort -> "Effort,"
                RunStepLabel.steady -> "Steady,"
                RunStepLabel.timeTrial -> "Time trial,"
                RunStepLabel.race -> "Race,"
                RunStepLabel.warmup -> "Warm up,"
                RunStepLabel.cooldown -> "Cool down,"
                RunStepLabel.recover -> "Recover,"
                RunStepLabel.easyBack -> "Easy back down,"
                RunStepLabel.float -> "Float,"
                RunStepLabel.easy -> "Easy,"
            }
        }
        val go = if (label == RunStepLabel.timeTrial || label == RunStepLabel.race) (if (pt) " Vai!" else " Go!") else ""
        return "$head $amount$pace.$go"
    }

    /** "Rep 4", "Last hill", "Cool down": the name used in "… in 10 seconds". */
    fun stepName(label: RunStepLabel, rep: Int, isLast: Boolean): String = if (pt) {
        when (label) {
            RunStepLabel.rep -> if (isLast) "Último tiro" else "Tiro $rep"
            RunStepLabel.hill -> if (isLast) "Última subida" else "Subida $rep"
            RunStepLabel.surge -> if (isLast) "Última aceleração" else "Aceleração $rep"
            RunStepLabel.stride -> if (isLast) "Última aceleração curta" else "Aceleração curta $rep"
            RunStepLabel.run -> if (isLast) "Última corrida" else "Corrida"
            RunStepLabel.walk -> "Caminhada"
            RunStepLabel.effort -> "Esforço"
            RunStepLabel.steady -> "Ritmo contínuo"
            RunStepLabel.timeTrial -> "Teste"
            RunStepLabel.race -> "Prova"
            RunStepLabel.warmup -> "Aquecimento"
            RunStepLabel.cooldown -> "Desaquecimento"
            RunStepLabel.recover, RunStepLabel.easyBack -> "Recuperação"
            RunStepLabel.float -> "Trote"
            RunStepLabel.easy -> "Leve"
        }
    } else {
        when (label) {
            RunStepLabel.rep -> if (isLast) "Last rep" else "Rep $rep"
            RunStepLabel.hill -> if (isLast) "Last hill" else "Hill $rep"
            RunStepLabel.surge -> if (isLast) "Last surge" else "Surge $rep"
            RunStepLabel.stride -> if (isLast) "Last stride" else "Stride $rep"
            RunStepLabel.run -> if (isLast) "Last run" else "Run"
            RunStepLabel.walk -> "Walk"
            RunStepLabel.effort -> "Effort"
            RunStepLabel.steady -> "Steady"
            RunStepLabel.timeTrial -> "Time trial"
            RunStepLabel.race -> "Race"
            RunStepLabel.warmup -> "Warm up"
            RunStepLabel.cooldown -> "Cool down"
            RunStepLabel.recover, RunStepLabel.easyBack -> "Recovery"
            RunStepLabel.float -> "Float"
            RunStepLabel.easy -> "Easy"
        }
    }

    fun nextInSeconds(name: String, seconds: Int): String =
        if (pt) "$name em ${length(seconds)}." else "$name in ${length(seconds)}."

    fun nextInMeters(name: String, meters: Int): String =
        if (pt) "$name em ${distance(meters)}." else "$name in ${distance(meters)}."

    /** Result of a distance rep: its time, and how it compares with the target. */
    fun repTime(seconds: Int, verdict: RunRepVerdict, deltaSeconds: Int = 0): String {
        val head = clock(seconds)
        return "$head${verdictText(verdict, deltaSeconds)}."
    }

    /** Result of a timed rep: its pace, and how it compares with the target. */
    fun repPace(paceSecPerKm: Double, verdict: RunRepVerdict): String {
        val head = if (pt) "Pace ${pace(paceSecPerKm)}" else "Pace ${pace(paceSecPerKm)}"
        return "$head${verdictText(verdict, 0)}."
    }

    private fun verdictText(verdict: RunRepVerdict, deltaSeconds: Int): String {
        val delta = abs(deltaSeconds)
        return when (verdict) {
            RunRepVerdict.none -> ""
            RunRepVerdict.onTarget -> if (pt) ", no alvo" else ", on target"
            RunRepVerdict.fast -> if (delta > 0) {
                if (pt) ", ${seconds(delta)} rápido" else ", ${seconds(delta)} fast"
            } else if (pt) ", rápido" else ", a bit fast"
            RunRepVerdict.slow -> if (delta > 0) {
                if (pt) ", ${seconds(delta)} lento" else ", ${seconds(delta)} slow"
            } else if (pt) ", lento" else ", a bit slow"
        }
    }

    fun allRepsDone(label: RunStepLabel): String = if (pt) {
        when (label) {
            RunStepLabel.hill -> "Subidas concluídas."
            RunStepLabel.surge, RunStepLabel.stride -> "Acelerações concluídas."
            else -> "Tiros concluídos."
        }
    } else {
        when (label) {
            RunStepLabel.hill -> "All hills done."
            RunStepLabel.surge -> "All surges done."
            RunStepLabel.stride -> "Strides done."
            else -> "All reps done."
        }
    }

    fun testResult(meters: Int, seconds: Int): String =
        if (pt) "Teste concluído. ${distance(meters)} em ${clock(seconds)}."
        else "Time trial done. ${distance(meters)} in ${clock(seconds)}."

    fun timeLeft(seconds: Int): String = when {
        seconds <= 15 -> if (pt) "${seconds(seconds)}." else "${seconds(seconds)}."
        pt -> if (seconds == 60) "Falta 1 minuto." else "Faltam ${length(seconds)}."
        else -> "${length(seconds)} left."
    }

    fun distanceLeft(meters: Int): String =
        if (pt) (if (meters == 1000) "Falta 1 quilômetro." else "Faltam ${distance(meters)}.")
        else "${distance(meters)} left."

    fun halfway(): String = if (pt) "Metade." else "Halfway."

    // --- Pace ---------------------------------------------------------------

    fun paceTooSlow(current: Double? = null): String =
        (if (pt) "Acelera." else "Pick it up.") + paceSuffix(current)

    fun paceTooFast(current: Double? = null): String =
        (if (pt) "Segura." else "Ease off.") + paceSuffix(current)

    /** Easy days: the only mistake worth flagging is going too fast. */
    fun easyTooFast(current: Double? = null): String =
        (if (pt) "Mais leve." else "Keep it easy.") + paceSuffix(current)

    fun backOnPace(): String = if (pt) "Pace no alvo." else "Back on pace."

    fun onPaceShort(): String = if (pt) "No alvo." else "On pace."

    fun onPace(current: Double): String =
        if (pt) "No pace, ${pace(current)}." else "On pace, ${pace(current)}."

    private fun paceSuffix(current: Double?): String =
        if (validPace(current)) " ${pace(current!!)}." else ""

    // --- Free run -----------------------------------------------------------

    /** "Kilometer 3. Time 15:20. Pace 5:05. Average 5:10." — every part optional. */
    fun kilometer(
        km: Int,
        elapsedSeconds: Int? = null,
        splitPace: Double? = null,
        avgPace: Double? = null,
    ): String {
        val text = StringBuilder(if (pt) "Quilômetro $km." else "Kilometer $km.")
        if (elapsedSeconds != null && elapsedSeconds > 0) {
            text.append(if (pt) " Tempo ${elapsed(elapsedSeconds)}." else " Time ${elapsed(elapsedSeconds)}.")
        }
        if (validPace(splitPace)) text.append(" Pace ${pace(splitPace!!)}.")
        if (validPace(avgPace)) text.append(if (pt) " Média ${pace(avgPace!!)}." else " Average ${pace(avgPace!!)}.")
        return text.toString()
    }

    /** "On track for 49:30. 12 seconds ahead." */
    fun projection(finishSeconds: Int, deltaSeconds: Int?): String {
        val head = if (pt) "Projeção ${elapsed(finishSeconds)}." else "On track for ${elapsed(finishSeconds)}."
        if (deltaSeconds == null) return head
        val delta = abs(deltaSeconds)
        if (delta < 3) return head + if (pt) " No alvo." else " On target."
        val amount = if (delta >= 60) length(roundTo(delta, 5)) else seconds(delta)
        return head + when {
            deltaSeconds > 0 -> if (pt) " $amount adiantado." else " $amount ahead."
            else -> if (pt) " $amount atrasado." else " $amount behind."
        }
    }

    /** "20 minutes. 3.4 kilometers." */
    fun timeCue(minutes: Int, distanceMeters: Double?): String {
        val head = length(minutes * 60) + "."
        val meters = distanceMeters?.takeIf { it >= 100 } ?: return head
        return "$head ${distance(((meters / 100).toInt()) * 100)}."
    }

    fun goalHalfway(remaining: String): String =
        if (pt) "Metade. Faltam $remaining." else "Halfway. $remaining to go."

    fun goalToGo(remaining: String): String =
        if (pt) "Faltam $remaining." else "$remaining to go."

    fun goalComplete(metric: RunIntervalMetric, value: Int): String {
        val amount = if (metric == RunIntervalMetric.time) length(value) else distance(value)
        return if (pt) "Meta concluída. $amount." else "Goal complete. $amount."
    }

    fun plannedComplete(metric: RunIntervalMetric): String = if (metric == RunIntervalMetric.time) {
        if (pt) "Tempo planejado concluído." else "Planned time done."
    } else {
        if (pt) "Distância planejada concluída." else "Planned distance done."
    }

    /** Rounded amount left of a goal: "2.5 kilometers", "15 minutes". */
    fun remainingAmount(metric: RunIntervalMetric, remaining: Double): String =
        if (metric == RunIntervalMetric.time) {
            val seconds = remaining.roundToInt()
            length(if (seconds >= 120) roundTo(seconds, 60) else roundTo(seconds, 10).coerceAtLeast(10))
        } else {
            val meters = remaining.roundToInt()
            distance(if (meters >= 1000) roundTo(meters, 100) else roundTo(meters, 50).coerceAtLeast(50))
        }

    fun weakGps(): String = if (pt) "Sinal de GPS fraco." else "GPS signal weak."
    fun gpsRestored(): String = if (pt) "Sinal de GPS de volta." else "GPS signal back."

    // --- Session ------------------------------------------------------------

    fun paused(): String = if (pt) "Corrida pausada." else "Paused."
    fun resumed(): String = if (pt) "Corrida retomada." else "Resumed."

    /** "Resumed. Rep 3, 200 meters left." */
    fun resumedInStep(name: String, remaining: String): String =
        if (pt) "Retomado. $name, faltam $remaining." else "Resumed. $name, $remaining left."

    fun autoPaused(): String = if (pt) "Pausa automática." else "Auto paused."
    fun autoResumed(): String = if (pt) "Retomando." else "Resuming."

    fun workoutComplete(distanceMeters: Double? = null, movingSeconds: Int? = null): String {
        val head = if (pt) "Treino concluído." else "Workout complete."
        val meters = distanceMeters?.takeIf { it >= 100 }
        if (meters == null || movingSeconds == null || movingSeconds <= 0) return head
        val km = distance(((meters / 100).toInt()) * 100)
        return head + if (pt) " $km em ${elapsed(movingSeconds)}." else " $km in ${elapsed(movingSeconds)}."
    }

    fun intervalsComplete(): String = if (pt) "Intervalos concluídos." else "Intervals complete."

    /** "Lap 2. 1.2 kilometers in 6:12. Pace 5:10." */
    fun lapSummary(index: Int, distanceMeters: Int, durationSeconds: Int, paceSecPerKm: Double?): String {
        val head = if (pt) "Volta $index." else "Lap $index."
        val body = if (distanceMeters >= 10) {
            val rounded = if (distanceMeters >= 1000) roundTo(distanceMeters, 100) else roundTo(distanceMeters, 10)
            if (pt) " ${distance(rounded)} em ${clock(durationSeconds)}."
            else " ${distance(rounded)} in ${clock(durationSeconds)}."
        } else {
            " ${clock(durationSeconds)}."
        }
        val pace = if (validPace(paceSecPerKm) && distanceMeters >= 100) " Pace ${pace(paceSecPerKm!!)}." else ""
        return "$head$body$pace"
    }

    fun testAnnouncement(): String =
        if (pt) "Treinador de voz pronto. Pace ${pace(330.0)}." else "Voice coach ready. Pace ${pace(330.0)}."

    // --- Formatting ---------------------------------------------------------

    /** Pace the way runners say it: "4:50", "4:05", "5 flat" (pt: "4 e 50"). */
    fun pace(secPerKm: Double): String {
        val total = secPerKm.roundToInt().coerceIn(0, 99 * 60 + 59)
        val minutes = total / 60
        val seconds = total % 60
        return if (pt) {
            if (seconds == 0) "$minutes cravado" else "$minutes e $seconds"
        } else {
            if (seconds == 0) "$minutes flat" else "$minutes:${seconds.toString().padStart(2, '0')}"
        }
    }

    /** A measured duration: "45 seconds", "1:28", "1 hour 5 minutes". */
    fun clock(totalSeconds: Int): String {
        val safe = totalSeconds.coerceIn(0, 24 * 3600)
        if (safe < 60) return seconds(safe)
        if (safe >= 3600) return elapsed(safe)
        return clockMinutes(safe)
    }

    /** Total time of a run: "15:20" under an hour (pt: "15 minutos e 20"), else hours and minutes. */
    fun elapsed(totalSeconds: Int): String {
        val safe = totalSeconds.coerceIn(0, 24 * 3600)
        if (safe < 3600) return if (safe < 60) seconds(safe) else clockMinutes(safe)
        val hours = safe / 3600
        val minutes = (safe % 3600) / 60
        val hourWord = if (pt) (if (hours == 1) "hora" else "horas") else (if (hours == 1) "hour" else "hours")
        if (minutes == 0) return "$hours $hourWord"
        val minuteWord = if (pt) (if (minutes == 1) "minuto" else "minutos") else (if (minutes == 1) "minute" else "minutes")
        return if (pt) "$hours $hourWord e $minutes $minuteWord" else "$hours $hourWord $minutes $minuteWord"
    }

    /** "15:20"; whole minutes are words ("6 minutes"), as "6:00" reads as a clock time. */
    private fun clockMinutes(safe: Int): String {
        val minutes = safe / 60
        val seconds = safe % 60
        val unit = if (pt) (if (minutes == 1) "minuto" else "minutos") else (if (minutes == 1) "minute" else "minutes")
        if (seconds == 0) return "$minutes $unit"
        return if (pt) "$minutes $unit e $seconds" else "$minutes:${seconds.toString().padStart(2, '0')}"
    }

    /** A planned length: "90 seconds", "2 minutes 30", "20 minutes", "1 hour 15 minutes". */
    fun length(totalSeconds: Int): String {
        val safe = totalSeconds.coerceIn(0, 24 * 3600)
        if (safe < 60 || (safe < 120 && safe % 60 != 0)) return seconds(safe)
        if (safe >= 3600) return elapsed(safe)
        val minutes = if (safe >= 600) (safe + 30) / 60 else safe / 60
        val seconds = if (safe >= 600) 0 else safe % 60
        val unit = if (pt) (if (minutes == 1) "minuto" else "minutos") else (if (minutes == 1) "minute" else "minutes")
        if (seconds == 0) return "$minutes $unit"
        return if (pt) "$minutes $unit e $seconds" else "$minutes $unit $seconds"
    }

    private fun seconds(value: Int): String =
        if (pt) "$value ${if (value == 1) "segundo" else "segundos"}"
        else "$value ${if (value == 1) "second" else "seconds"}"

    /** "400 meters", "1 kilometer", "1.5 kilometers" (pt: "1,5 quilômetro"). */
    fun distance(meters: Int): String {
        if (meters < 1000) {
            val unit = if (pt) (if (meters == 1) "metro" else "metros") else (if (meters == 1) "meter" else "meters")
            return "$meters $unit"
        }
        val tenths = (meters + 50) / 100
        val whole = tenths / 10
        val decimal = tenths % 10
        val number = if (decimal == 0) "$whole" else "$whole${if (pt) "," else "."}$decimal"
        val plural = tenths != 10
        val unit = if (pt) (if (whole >= 2) "quilômetros" else "quilômetro")
        else (if (plural) "kilometers" else "kilometer")
        return "$number $unit"
    }

    private fun roundTo(value: Int, step: Int): Int = ((value + step / 2) / step) * step

    private fun validPace(pace: Double?): Boolean = pace != null && pace > 0 && pace.isFinite()
}
