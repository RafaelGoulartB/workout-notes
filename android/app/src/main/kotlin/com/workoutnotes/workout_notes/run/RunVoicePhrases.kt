package com.workoutnotes.workout_notes.run

import kotlin.math.roundToInt

/** Native mirror of the Dart voice phrases used while the screen is off. */
class RunVoicePhrases(private val language: RunVoiceLanguage) {

    private val pt: Boolean get() = language == RunVoiceLanguage.pt

    fun distanceMilestone(km: Int, durationSeconds: Int, avgPaceSecPerKm: Double?): String {
        val text = StringBuilder("$km ${kilometersWord(km)}.")
        if (validPace(avgPaceSecPerKm)) {
            text.append(if (pt) " Pace médio ${paceSpeech(avgPaceSecPerKm!!)}." else " Average pace ${paceSpeech(avgPaceSecPerKm!!)}.")
        }
        return text.toString()
    }

    fun splitComplete(km: Int, paceSecPerKm: Double?): String {
        val pace = if (validPace(paceSecPerKm)) " Pace ${paceSpeech(paceSecPerKm!!)}." else ""
        return "${if (pt) "Quilômetro" else "Kilometer"} $km.$pace"
    }

    fun splitSummary(km: Int, splitPace: Double?, avgPace: Double?): String {
        val split = if (validPace(splitPace)) " Pace ${paceSpeech(splitPace!!)}." else ""
        val average = if (validPace(avgPace)) {
            if (pt) " Pace médio ${paceSpeech(avgPace!!)}." else " Average pace ${paceSpeech(avgPace!!)}."
        } else ""
        return "${if (pt) "Quilômetro" else "Kilometer"} $km.$split$average"
    }

    fun paceTooFast(): String = if (pt) "Segura um pouco o ritmo." else "Ease off."
    fun paceTooSlow(): String = if (pt) "Aumente um pouco o ritmo." else "Pick it up."
    fun paceOnTarget(): String = if (pt) "Pace dentro da meta." else "Pace on target."
    fun weakGps(): String = if (pt) "Sinal de GPS fraco." else "Weak GPS signal."
    fun gpsRestored(): String = if (pt) "Sinal de GPS recuperado." else "GPS signal restored."

    fun workIntervalStart(index: Int, total: Int): String =
        if (pt) "Tiro $index de $total. Vai!" else "Rep $index of $total. Go."

    fun restIntervalStart(metric: RunIntervalMetric, value: Int): String {
        val amount = if (metric == RunIntervalMetric.time) durationSpeech(value) else distanceSpeech(value)
        return if (pt) "Recuperação. $amount." else "Recover. $amount."
    }

    fun intervalsComplete(): String = if (pt) "Intervalos concluídos." else "Intervals complete."
    fun timeRemaining(seconds: Int): String =
        if (pt) "Faltam ${durationSpeech(seconds)}." else "${durationSpeech(seconds)} left."
    fun distanceRemaining(meters: Int): String =
        if (pt) "Faltam ${distanceSpeech(meters)}." else "${distanceSpeech(meters)} left."

    fun stepStart(
        role: RunStepRole,
        repIndex: Int,
        repTotal: Int,
        metric: RunIntervalMetric,
        value: Int,
        targetPaceSecPerKm: Double?,
    ): String {
        val amount = if (metric == RunIntervalMetric.time) durationSpeech(value) else distanceSpeech(value)
        val head = if (pt) {
            when (role) {
                RunStepRole.warmup -> "Aquecimento. $amount."
                RunStepRole.cooldown -> "Desaquecimento. $amount."
                RunStepRole.recovery -> "Recuperação. $amount."
                RunStepRole.steady -> "Ritmo contínuo. $amount."
                RunStepRole.work -> if (repTotal > 1) "Tiro $repIndex de $repTotal. $amount." else "Esforço. $amount."
            }
        } else {
            when (role) {
                RunStepRole.warmup -> "Warm up. $amount."
                RunStepRole.cooldown -> "Cool down. $amount."
                RunStepRole.recovery -> "Recover. $amount."
                RunStepRole.steady -> "Steady. $amount."
                RunStepRole.work -> if (repTotal > 1) "Rep $repIndex of $repTotal. $amount." else "Effort. $amount."
            }
        }
        return if (role.isEffort && validPace(targetPaceSecPerKm)) {
            "$head ${if (pt) "Pace alvo" else "Target pace"} ${paceSpeech(targetPaceSecPerKm!!)}."
        } else head
    }

    fun stepPaceTooSlow(paceSecPerKm: Double?): String {
        if (!validPace(paceSecPerKm)) return paceTooSlow()
        return if (pt) "Aumente o ritmo. Pace atual ${paceSpeech(paceSecPerKm!!)}."
        else "Pick it up. Current pace ${paceSpeech(paceSecPerKm!!)}."
    }

    fun stepPaceTooFast(paceSecPerKm: Double?): String {
        if (!validPace(paceSecPerKm)) return paceTooFast()
        return if (pt) "Segura o ritmo. Pace atual ${paceSpeech(paceSecPerKm!!)}."
        else "Ease off. Current pace ${paceSpeech(paceSecPerKm!!)}."
    }

    fun workoutComplete(): String = if (pt) "Treino concluído." else "Workout complete."

    fun goalComplete(metric: RunIntervalMetric, value: Int): String {
        val amount = if (metric == RunIntervalMetric.time) durationSpeech(value) else distanceSpeech(value)
        return if (pt) "Meta concluída. $amount." else "Goal complete. $amount."
    }

    fun goalRemaining(metric: RunIntervalMetric, value: Int): String {
        val amount = if (metric == RunIntervalMetric.time) durationSpeech(value) else distanceSpeech(value)
        return if (pt) "Faltam $amount." else "$amount left."
    }

    fun paused(): String = if (pt) "Corrida pausada." else "Paused."
    fun resumed(): String = if (pt) "Corrida retomada." else "Resumed."
    fun testAnnouncement(): String = if (pt) {
        "Áudio do treinador pronto. Pace de 5 minutos e 30 segundos por quilômetro."
    } else {
        "Voice coach ready. Pace 5 minutes 30 seconds per kilometer."
    }

    private fun kilometersWord(km: Int): String = if (pt) {
        if (km == 1) "quilômetro" else "quilômetros"
    } else if (km == 1) "kilometer" else "kilometers"

    private fun durationSpeech(totalSeconds: Int): String {
        val safe = totalSeconds.coerceIn(0, 24 * 3600)
        val hours = safe / 3600
        val minutes = (safe % 3600) / 60
        val seconds = safe % 60
        val parts = mutableListOf<String>()
        if (hours > 0) parts.add("$hours ${if (pt) if (hours == 1) "hora" else "horas" else if (hours == 1) "hour" else "hours"}")
        if (minutes > 0) parts.add("$minutes ${if (pt) if (minutes == 1) "minuto" else "minutos" else if (minutes == 1) "minute" else "minutes"}")
        if (seconds > 0 || parts.isEmpty()) parts.add("$seconds ${if (pt) if (seconds == 1) "segundo" else "segundos" else if (seconds == 1) "second" else "seconds"}")
        return parts.joinToString(if (pt) " e " else " ")
    }

    private fun paceSpeech(secPerKm: Double): String {
        val total = secPerKm.roundToInt().coerceIn(0, 99 * 60 + 59)
        val minutes = total / 60
        val seconds = total % 60
        val minutePart = if (pt) "$minutes ${if (minutes == 1) "minuto" else "minutos"}"
        else "$minutes ${if (minutes == 1) "minute" else "minutes"}"
        val secondPart = if (seconds == 0) "" else if (pt) " e $seconds ${if (seconds == 1) "segundo" else "segundos"}"
        else " $seconds ${if (seconds == 1) "second" else "seconds"}"
        return "$minutePart$secondPart ${if (pt) "por quilômetro" else "per kilometer"}"
    }

    private fun validPace(pace: Double?): Boolean = pace != null && pace > 0 && pace.isFinite()

    private fun distanceSpeech(meters: Int): String {
        if (meters < 1000) {
            val unit = if (pt) if (meters == 1) "metro" else "metros" else if (meters == 1) "meter" else "meters"
            return "$meters $unit"
        }
        val kilometers = meters / 1000
        val remainder = meters % 1000
        if (remainder == 0) return "$kilometers ${kilometersWord(kilometers)}"
        return "$kilometers ${kilometersWord(kilometers)} ${if (pt) "e" else "and"} $remainder ${if (pt) "metros" else "meters"}"
    }
}
