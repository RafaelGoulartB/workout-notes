package com.workoutnotes.workout_notes.run

object RunVoicePhrases {

    fun distanceMilestone(km: Int, durationSeconds: Int, avgPaceSecPerKm: Double?): String {
        val buf = StringBuilder()
        buf.append("$km ${kilometersWord(km)}.")
        if (avgPaceSecPerKm != null && avgPaceSecPerKm > 0 && avgPaceSecPerKm.isFinite()) {
            buf.append(" Average ${paceSpeech(avgPaceSecPerKm)}.")
        }
        return buf.toString()
    }

    fun splitComplete(km: Int, paceSecPerKm: Double?): String {
        val pace = if (paceSecPerKm != null && paceSecPerKm > 0 && paceSecPerKm.isFinite()) {
            " ${paceSpeech(paceSecPerKm)}."
        } else ""
        return "Kilometer $km.$pace"
    }

    fun splitSummary(km: Int, splitPace: Double?, avgPace: Double?): String {
        val split = if (splitPace != null && splitPace > 0 && splitPace.isFinite()) " ${paceSpeech(splitPace)}." else ""
        val average = if (avgPace != null && avgPace > 0 && avgPace.isFinite()) " Average ${paceSpeech(avgPace)}." else ""
        return "Kilometer $km.$split$average"
    }

    fun paceTooFast(): String = "Ease off."
    fun paceTooSlow(): String = "Pick it up."
    fun paceOnTarget(): String = "Pace on target."
    fun weakGps(): String = "Weak GPS signal."
    fun gpsRestored(): String = "GPS signal restored."

    fun workIntervalStart(index: Int, total: Int): String = "Rep $index of $total. Go."

    fun restIntervalStart(metric: RunIntervalMetric, value: Int): String {
        return if (metric == RunIntervalMetric.time) {
            "Recover. ${durationSpeech(value)}."
        } else {
            "Recover. ${distanceSpeech(value)}."
        }
    }

    fun intervalsComplete(): String = "Intervals complete."
    fun timeRemaining(seconds: Int): String = "$seconds seconds."
    fun distanceRemaining(meters: Int): String = "$meters meters."

    // ---- Structured plan sessions (RunWorkoutStepEngineNative) ----

    /** Announces the step that just started, e.g. "Rep 3 of 6. 800 meters. Target pace 3 minutes 50 seconds." */
    fun stepStart(
        role: RunStepRole,
        repIndex: Int,
        repTotal: Int,
        metric: RunIntervalMetric,
        value: Int,
        targetPaceSecPerKm: Double?,
    ): String {
        val amount = if (metric == RunIntervalMetric.time) durationSpeech(value) else distanceSpeech(value)
        val head = when (role) {
            RunStepRole.warmup -> "Warm up. $amount."
            RunStepRole.cooldown -> "Cool down. $amount."
            RunStepRole.recovery -> "Recover. $amount."
            RunStepRole.steady -> "Steady. $amount."
            RunStepRole.work -> if (repTotal > 1) "Rep $repIndex of $repTotal. $amount." else "Effort. $amount."
        }
        if (targetPaceSecPerKm != null && targetPaceSecPerKm > 0 && targetPaceSecPerKm.isFinite() && role.isEffort) {
            return "$head Target ${paceSpeech(targetPaceSecPerKm)}."
        }
        return head
    }

    fun stepPaceTooSlow(paceSecPerKm: Double?): String {
        if (paceSecPerKm == null || paceSecPerKm <= 0 || !paceSecPerKm.isFinite()) return "Pick it up."
        return "Pick it up. ${paceSpeech(paceSecPerKm)}."
    }

    fun stepPaceTooFast(paceSecPerKm: Double?): String {
        if (paceSecPerKm == null || paceSecPerKm <= 0 || !paceSecPerKm.isFinite()) return "Ease off."
        return "Ease off. ${paceSpeech(paceSecPerKm)}."
    }

    fun workoutComplete(): String = "Workout complete."

    fun goalComplete(metric: RunIntervalMetric, value: Int): String {
        return if (metric == RunIntervalMetric.time) {
            "Goal complete. ${durationSpeech(value)}."
        } else {
            "Goal complete. ${distanceSpeech(value)}."
        }
    }

    fun goalRemaining(metric: RunIntervalMetric, value: Int): String =
        if (metric == RunIntervalMetric.time) "${durationSpeech(value)} left."
        else "${distanceSpeech(value)} left."

    fun paused(): String = "Paused."
    fun resumed(): String = "Resumed."

    private fun kilometersWord(km: Int): String = if (km == 1) "kilometer" else "kilometers"

    private fun durationSpeech(totalSeconds: Int): String {
        val safe = totalSeconds.coerceIn(0, 24 * 3600)
        val hours = safe / 3600
        val minutes = (safe % 3600) / 60
        val seconds = safe % 60
        val parts = mutableListOf<String>()
        if (hours > 0) parts.add("$hours ${if (hours == 1) "hour" else "hours"}")
        if (minutes > 0 || hours > 0) parts.add("$minutes ${if (minutes == 1) "minute" else "minutes"}")
        if (hours == 0) parts.add("$seconds ${if (seconds == 1) "second" else "seconds"}")
        if (parts.isEmpty()) return "0 seconds"
        return parts.joinToString(" ")
    }

    private fun paceSpeech(secPerKm: Double): String {
        val total = secPerKm.toInt().coerceIn(0, 99 * 60 + 59)
        val minutes = total / 60
        val seconds = total % 60
        return "$minutes ${seconds.toString().padStart(2, '0')} per kilometer"
    }

    private fun distanceSpeech(meters: Int): String {
        if (meters >= 1000) {
            if (meters % 1000 == 0) {
                val km = meters / 1000
                return "$km ${kilometersWord(km)}"
            }
            val tenths = (meters + 50) / 100
            return "${tenths / 10}.${tenths % 10} kilometers"
        }
        return "$meters meters"
    }
}
