package com.workoutnotes.workout_notes.run

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Private JSON spool for GPS runs. Survives Flutter process death. */
class RunActivitySpool(private val root: File) {
    constructor(context: Context) : this(File(context.filesDir, "run_tracking"))

    init {
        root.mkdirs()
    }

    @Synchronized
    fun create(activity: MutableMap<String, Any?>) {
        val directory = File(root, activity["id"].toString())
        directory.mkdirs()
        writeJson(File(directory, "activity.json"), activity)
        File(directory, "points.ndjson").createNewFile()
    }

    @Synchronized
    fun updateActivity(activity: Map<String, Any?>) {
        val directory = File(root, activity["id"].toString())
        directory.mkdirs()
        writeJson(File(directory, "activity.json"), activity)
    }

    @Synchronized
    fun appendPoint(point: Map<String, Any?>) {
        val directory = File(root, point["activity_id"].toString())
        directory.mkdirs()
        File(directory, "points.ndjson").appendText(encode(point) + "\n")
    }

    @Synchronized
    fun read(id: String): Map<String, Any?> {
        val directory = File(root, id)
        val activityFile = File(directory, "activity.json")
        if (!activityFile.exists()) throw IllegalStateException("missing_run_spool")
        val activity = decode(activityFile.readText())
        val points = mutableListOf<Map<String, Any?>>()
        val pointsFile = File(directory, "points.ndjson")
        if (pointsFile.exists()) {
            pointsFile.forEachLine { line ->
                if (line.isBlank()) return@forEachLine
                try {
                    points += decode(line)
                } catch (_: Throwable) {
                    // Ignore a partial last line; prior points remain recoverable.
                }
            }
        }
        return mapOf(
            "activity" to activity,
            "points" to points,
        )
    }

    @Synchronized
    fun listPending(): List<Map<String, Any?>> {
        val directories = root.listFiles()?.filter { it.isDirectory } ?: return emptyList()
        return directories.mapNotNull { directory ->
            val file = File(directory, "activity.json")
            if (!file.exists()) return@mapNotNull null
            try {
                val activity = decode(file.readText())
                mapOf(
                    "id" to activity["id"],
                    "status" to activity["status"],
                    "started_at" to activity["started_at"],
                    "ended_at" to activity["ended_at"],
                )
            } catch (_: Throwable) {
                mapOf("id" to directory.name, "corrupt" to true)
            }
        }
    }

    @Synchronized
    fun delete(id: String) {
        File(root, id).deleteRecursively()
    }

    private fun writeJson(file: File, value: Map<String, Any?>) {
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(encode(value))
        if (!temporary.renameTo(file)) {
            file.writeText(encode(value))
            temporary.delete()
        }
    }

    private fun encode(value: Map<String, Any?>): String = JSONObject(value).toString()

    private fun decode(value: String): Map<String, Any?> =
        jsonObjectToMap(JSONObject(value))

    private fun jsonObjectToMap(value: JSONObject): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val keys = value.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = jsonValue(value.get(key))
        }
        return result
    }

    private fun jsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> jsonObjectToMap(value)
        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        else -> value
    }
}
