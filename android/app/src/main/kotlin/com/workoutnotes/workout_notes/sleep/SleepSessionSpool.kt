package com.workoutnotes.workout_notes.sleep

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Private JSON spool. It stores aggregates only, never audio samples. */
interface SleepSpoolCodec {
    fun encode(value: Map<String, Any?>): String
    fun decode(value: String): Map<String, Any?>
}

class SleepSessionSpool(
    private val root: File,
    private val codec: SleepSpoolCodec = AndroidJsonSpoolCodec,
) {
    constructor(context: Context) : this(File(context.filesDir, "sleep_monitor"))

    init { root.mkdirs() }

    @Synchronized
    fun create(session: MutableMap<String, Any?>) {
        val directory = File(root, session["id"].toString())
        directory.mkdirs()
        writeJson(File(directory, "session.json"), session)
        File(directory, "segments.ndjson").createNewFile()
    }

    @Synchronized
    fun updateSession(session: Map<String, Any?>) {
        val directory = File(root, session["id"].toString())
        directory.mkdirs()
        writeJson(File(directory, "session.json"), session)
    }

    @Synchronized
    fun appendSegment(segment: Map<String, Any?>) {
        val directory = File(root, segment["session_id"].toString())
        directory.mkdirs()
        File(directory, "segments.ndjson").appendText(codec.encode(segment) + "\n")
    }

    @Synchronized
    fun read(id: String): Map<String, Any?> {
        val directory = File(root, id)
        val sessionFile = File(directory, "session.json")
        if (!sessionFile.exists()) throw IllegalStateException("missing_session_spool")
        val session = codec.decode(sessionFile.readText())
        val segments = mutableListOf<Map<String, Any?>>()
        val segmentFile = File(directory, "segments.ndjson")
        if (segmentFile.exists()) {
            segmentFile.forEachLine { line ->
                if (line.isBlank()) return@forEachLine
                try {
                    segments += codec.decode(line)
                } catch (_: Throwable) {
                    // A partially flushed last line is ignored; prior segments
                    // remain recoverable and the session remains in the spool.
                }
            }
        }
        return mapOf("session" to session, "segments" to segments)
    }

    @Synchronized
    fun listPending(): List<Map<String, Any?>> {
        val directories = root.listFiles()?.filter { it.isDirectory } ?: return emptyList()
        return directories.mapNotNull { directory ->
            val file = File(directory, "session.json")
            if (!file.exists()) return@mapNotNull null
            try {
                val session = codec.decode(file.readText())
                mapOf(
                    "id" to session["id"],
                    "status" to session["status"],
                    "started_at" to session["started_at"],
                    "ended_at" to session["ended_at"],
                )
            } catch (_: Throwable) {
                // Surface a corrupt directory to Flutter instead of silently
                // dropping a session that may still be recoverable manually.
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
        temporary.writeText(codec.encode(value))
        if (!temporary.renameTo(file)) {
            file.writeText(codec.encode(value))
            temporary.delete()
        }
    }

    companion object {
        private object AndroidJsonSpoolCodec : SleepSpoolCodec {
            override fun encode(value: Map<String, Any?>): String = JSONObject(value).toString()

            override fun decode(value: String): Map<String, Any?> =
                jsonObjectToMap(JSONObject(value))
        }

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
}
