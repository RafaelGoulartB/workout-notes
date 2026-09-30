package com.workoutnotes.workout_notes.run

import android.content.Context
import com.workoutnotes.workout_notes.common.JsonMaps
import org.json.JSONObject
import java.io.File

/**
 * Private JSON spool for GPS runs. Survives Flutter process death.
 *
 * The plain methods do blocking disk I/O and are safe to call from any thread,
 * but must not run on the main thread. Callers on the main thread use the
 * `*Async` writers (queued, in order, on [io]) and the `*Blocking`/[submit]
 * helpers for reads. Writes are serialized as JSON on the calling thread, so
 * a queued write captures the state at the moment it was enqueued.
 */
class RunActivitySpool(
    private val root: File,
    val io: RunSpoolExecutor = RunSpoolExecutor.shared,
) {
    constructor(context: Context) : this(File(context.filesDir, "run_tracking"))

    init {
        root.mkdirs()
    }

    // --- Main-thread-safe API: queue the work on the sequential executor. ---

    fun createAsync(activity: Map<String, Any?>) {
        val id = activity["id"].toString()
        val json = encode(activity)
        io.execute { createJson(id, json) }
    }

    fun updateActivityAsync(activity: Map<String, Any?>) {
        val id = activity["id"].toString()
        val json = encode(activity)
        io.execute { updateActivityJson(id, json) }
    }

    fun appendPointAsync(point: Map<String, Any?>) {
        val id = point["activity_id"].toString()
        val line = encode(point) + "\n"
        io.execute { appendPointLine(id, line) }
    }

    fun deleteAsync(id: String) {
        io.execute { delete(id) }
    }

    /**
     * Waits until every queued write has hit the disk. Call after the last
     * write of a pause/stop so the state is durable before it is reported.
     */
    fun flush(timeoutMillis: Long = RunSpoolExecutor.DEFAULT_FLUSH_TIMEOUT_MS): Boolean =
        io.flush(timeoutMillis)

    /** Runs [work] on the spool worker (after queued writes); the result goes to [deliver] on that worker. */
    fun <T> submit(work: RunActivitySpool.() -> T, deliver: (Result<T>) -> Unit) {
        io.submit({ work() }, deliver)
    }

    /** Synchronous read ordered after all queued writes. For rare recovery paths only. */
    fun <T> blocking(work: RunActivitySpool.() -> T): T = io.call { work() }

    // --- Blocking disk operations (run on the spool worker or in tests). ---

    @Synchronized
    fun create(activity: Map<String, Any?>) {
        createJson(activity["id"].toString(), encode(activity))
    }

    @Synchronized
    fun updateActivity(activity: Map<String, Any?>) {
        updateActivityJson(activity["id"].toString(), encode(activity))
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

    @Synchronized
    private fun createJson(id: String, json: String) {
        val directory = File(root, id)
        directory.mkdirs()
        writeText(File(directory, "activity.json"), json)
        File(directory, "points.ndjson").createNewFile()
    }

    @Synchronized
    private fun updateActivityJson(id: String, json: String) {
        val directory = File(root, id)
        directory.mkdirs()
        writeText(File(directory, "activity.json"), json)
    }

    @Synchronized
    private fun appendPointLine(id: String, line: String) {
        val directory = File(root, id)
        directory.mkdirs()
        File(directory, "points.ndjson").appendText(line)
    }

    /** Atomic replace: write a temp file, then rename over the target. */
    private fun writeText(file: File, json: String) {
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(json)
        if (!temporary.renameTo(file)) {
            file.writeText(json)
            temporary.delete()
        }
    }

    private fun encode(value: Map<String, Any?>): String = JSONObject(value).toString()

    private fun decode(value: String): Map<String, Any?> = JsonMaps.toMap(JSONObject(value))
}
