package com.workoutnotes.workout_notes.run

object RunVoicePhrases {

    fun distanceMilestone(km: Int, durationSeconds: Int, avgPaceSecPerKm: Double?): String {
        val buf = StringBuilder()
        buf.append("$km ${kilometersWord(km)}. ")
        buf.append("Time ${durationSpeech(durationSeconds)}.")
        if (avgPaceSecPerKm != null && avgPaceSecPerKm > 0 && avgPaceSecPerKm.isFinite()) {
            buf.append(" Average pace ${paceSpeech(avgPaceSecPerKm)} per kilometer.")
        }
        return buf.toString()
    }

    fun splitComplete(km: Int, paceSecPerKm: Double?): String {
        val pace = if (paceSecPerKm != null && paceSecPerKm > 0 && paceSecPerKm.isFinite()) {
            " Pace ${paceSpeech(paceSecPerKm)}."
        } else ""
        return "Kilometer $km.$pace"
    }

    fun paceTooFast(): String = "Pace too fast."
    fun paceTooSlow(): String = "Pace too slow."
    fun weakGps(): String = "Weak GPS signal."
    fun gpsRestored(): String = "GPS signal restored."

    fun workIntervalStart(index: Int, total: Int): String = "Work interval $index of $total. Go."

    fun restIntervalStart(metric: RunIntervalMetric, value: Int): String {
        return if (metric == RunIntervalMetric.time) {
            "Rest. ${durationSpeech(value)}."
        } else {
            "Rest. ${distanceSpeech(value)}."
        }
    }

    fun intervalsComplete(): String = "Intervals complete."
    fun timeRemaining(seconds: Int): String = "${durationSpeech(seconds)} remaining."

    fun goalComplete(metric: RunIntervalMetric, value: Int): String {
        return if (metric == RunIntervalMetric.time) {
            "Goal complete. ${durationSpeech(value)}."
        } else {
            "Goal complete. ${distanceSpeech(value)}."
        }
    }

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
        return "$minutes minutes $seconds seconds"
    }

    private fun distanceSpeech(meters: Int): String {
        if (meters >= 1000 && meters % 1000 == 0) {
            val km = meters / 1000
            return "$km ${kilometersWord(km)}"
        }
        return "$meters meters"
    }
}
