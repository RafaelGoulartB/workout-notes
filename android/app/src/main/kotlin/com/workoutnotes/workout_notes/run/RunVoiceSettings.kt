package com.workoutnotes.workout_notes.run

import org.json.JSONObject

enum class RunIntervalMetric { distance, time }

data class RunIntervalPreset(
    val workMetric: RunIntervalMetric = RunIntervalMetric.distance,
    val workValue: Int = 400,
    val restMetric: RunIntervalMetric = RunIntervalMetric.time,
    val restValue: Int = 90,
    val repeats: Int = 8,
) {
    companion object {
        fun fromJson(json: JSONObject?): RunIntervalPreset {
            if (json == null) return RunIntervalPreset()
            val workMetric = if (json.optString("workMetric") == "time") RunIntervalMetric.time else RunIntervalMetric.distance
            val restMetric = if (json.optString("restMetric") == "time") RunIntervalMetric.time else RunIntervalMetric.distance
            val workValue = json.optInt("workValue", 400).coerceAtLeast(1)
            val restValue = json.optInt("restValue", 90).coerceAtLeast(0)
            val repeats = json.optInt("repeats", 8).coerceIn(1, 99)
            return RunIntervalPreset(workMetric, workValue, restMetric, restValue, repeats)
        }

        fun fromMap(map: Map<String, Any?>?): RunIntervalPreset {
            if (map == null) return RunIntervalPreset()
            val workMetric = if (map["workMetric"] == "time") RunIntervalMetric.time else RunIntervalMetric.distance
            val restMetric = if (map["restMetric"] == "time") RunIntervalMetric.time else RunIntervalMetric.distance
            val workValue = (map["workValue"] as? Number)?.toInt()?.coerceAtLeast(1) ?: 400
            val restValue = (map["restValue"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 90
            val repeats = (map["repeats"] as? Number)?.toInt()?.coerceIn(1, 99) ?: 8
            return RunIntervalPreset(workMetric, workValue, restMetric, restValue, repeats)
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("workMetric", workMetric.name)
        put("workValue", workValue)
        put("restMetric", restMetric.name)
        put("restValue", restValue)
        put("repeats", repeats)
    }
}

data class RunVoiceSettings(
    val enabled: Boolean = true,
    val headphonesOnly: Boolean = true,
    val muteDuringCall: Boolean = true,
    val announceDistance: Boolean = true,
    val distanceEveryKm: Int = 1,
    val announceSplit: Boolean = true,
    val announcePaceWarning: Boolean = false,
    val targetPaceSecPerKm: Int? = null,
    val paceTolerancePercent: Int = 10,
    val announceGpsStatus: Boolean = true,
    val announceIntervals: Boolean = true,
    val intervalsEnabledByDefault: Boolean = false,
    val interval: RunIntervalPreset = RunIntervalPreset(),
) {
    companion object {
        const val STORAGE_KEY = "run_voice_settings_v1"

        fun defaults() = RunVoiceSettings()

        fun fromJsonString(raw: String?): RunVoiceSettings {
            if (raw.isNullOrBlank()) return defaults()
            return try {
                val json = JSONObject(raw)
                fromJson(json)
            } catch (_: Throwable) {
                defaults()
            }
        }

        fun fromJson(json: JSONObject?): RunVoiceSettings {
            if (json == null) return defaults()
            val everyRaw = json.optInt("distanceEveryKm", 1)
            val every = if (everyRaw == 2 || everyRaw == 5) everyRaw else 1
            val tolerance = json.optInt("paceTolerancePercent", 10).coerceIn(5, 50)
            val target = if (json.isNull("targetPaceSecPerKm")) null else json.optInt("targetPaceSecPerKm").takeIf { it > 0 }
            val intervalObj = if (json.has("interval") && !json.isNull("interval")) {
                try { json.getJSONObject("interval") } catch (_: Throwable) { null }
            } else null
            return RunVoiceSettings(
                enabled = json.optBoolean("enabled", true),
                headphonesOnly = json.optBoolean("headphonesOnly", true),
                muteDuringCall = json.optBoolean("muteDuringCall", true),
                announceDistance = json.optBoolean("announceDistance", true),
                distanceEveryKm = every,
                announceSplit = json.optBoolean("announceSplit", true),
                announcePaceWarning = json.optBoolean("announcePaceWarning", false),
                targetPaceSecPerKm = target,
                paceTolerancePercent = tolerance,
                announceGpsStatus = json.optBoolean("announceGpsStatus", true),
                announceIntervals = json.optBoolean("announceIntervals", true),
                intervalsEnabledByDefault = json.optBoolean("intervalsEnabledByDefault", false),
                interval = RunIntervalPreset.fromJson(intervalObj),
            )
        }

        fun fromMap(map: Map<String, Any?>?): RunVoiceSettings {
            if (map == null) return defaults()
            val everyRaw = (map["distanceEveryKm"] as? Number)?.toInt() ?: 1
            val every = if (everyRaw == 2 || everyRaw == 5) everyRaw else 1
            val tolerance = (map["paceTolerancePercent"] as? Number)?.toInt()?.coerceIn(5, 50) ?: 10
            val target = (map["targetPaceSecPerKm"] as? Number)?.toInt()?.takeIf { it > 0 }
            @Suppress("UNCHECKED_CAST")
            val intervalRaw = map["interval"] as? Map<String, Any?>
            return RunVoiceSettings(
                enabled = map["enabled"] as? Boolean ?: true,
                headphonesOnly = map["headphonesOnly"] as? Boolean ?: true,
                muteDuringCall = map["muteDuringCall"] as? Boolean ?: true,
                announceDistance = map["announceDistance"] as? Boolean ?: true,
                distanceEveryKm = every,
                announceSplit = map["announceSplit"] as? Boolean ?: true,
                announcePaceWarning = map["announcePaceWarning"] as? Boolean ?: false,
                targetPaceSecPerKm = target,
                paceTolerancePercent = tolerance,
                announceGpsStatus = map["announceGpsStatus"] as? Boolean ?: true,
                announceIntervals = map["announceIntervals"] as? Boolean ?: true,
                intervalsEnabledByDefault = map["intervalsEnabledByDefault"] as? Boolean ?: false,
                interval = RunIntervalPreset.fromMap(intervalRaw),
            )
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("enabled", enabled)
        put("headphonesOnly", headphonesOnly)
        put("muteDuringCall", muteDuringCall)
        put("announceDistance", announceDistance)
        put("distanceEveryKm", distanceEveryKm)
        put("announceSplit", announceSplit)
        put("announcePaceWarning", announcePaceWarning)
        if (targetPaceSecPerKm != null) put("targetPaceSecPerKm", targetPaceSecPerKm) else put("targetPaceSecPerKm", JSONObject.NULL)
        put("paceTolerancePercent", paceTolerancePercent)
        put("announceGpsStatus", announceGpsStatus)
        put("announceIntervals", announceIntervals)
        put("intervalsEnabledByDefault", intervalsEnabledByDefault)
        put("interval", interval.toJson())
    }
}

data class RunSessionGoal(
    val enabled: Boolean = false,
    val metric: RunIntervalMetric = RunIntervalMetric.distance,
    val value: Int = 5000,
) {
    companion object {
        fun disabled() = RunSessionGoal(enabled = false)
        fun fromMap(map: Map<String, Any?>?): RunSessionGoal {
            if (map == null) return disabled()
            val enabled = map["enabled"] as? Boolean ?: false
            val metric = if (map["metric"] == "time") RunIntervalMetric.time else RunIntervalMetric.distance
            val value = (map["value"] as? Number)?.toInt() ?: 5000
            return RunSessionGoal(enabled, metric, value)
        }

        fun fromJson(json: JSONObject?): RunSessionGoal {
            if (json == null) return disabled()
            val enabled = json.optBoolean("enabled", false)
            val metric = if (json.optString("metric") == "time") RunIntervalMetric.time else RunIntervalMetric.distance
            val value = json.optInt("value", 5000)
            return RunSessionGoal(enabled, metric, value)
        }
    }

    fun isComplete(distanceMeters: Double, movingTimeSeconds: Int): Boolean {
        if (!enabled || value <= 0) return false
        return if (metric == RunIntervalMetric.distance) {
            distanceMeters + 1e-6 >= value
        } else {
            movingTimeSeconds >= value
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("enabled", enabled)
        put("metric", metric.name)
        put("value", value)
    }
}
