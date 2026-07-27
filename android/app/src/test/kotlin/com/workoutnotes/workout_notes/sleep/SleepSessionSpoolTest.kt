package com.workoutnotes.workout_notes.sleep

import java.io.File
import java.nio.file.Files
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepSessionSpoolTest {
    @Test
    fun serializesAggregatesAndRecoversPartialLastLine() {
        val root = Files.createTempDirectory("sleep-spool-test").toFile()
        try {
            val spool = SleepSessionSpool(root, TestSpoolCodec)
            val session = mutableMapOf<String, Any?>(
                "id" to "session-1",
                "status" to "running",
                "started_at" to "2026-07-26T22:00:00Z",
                "ended_at" to null,
            )
            spool.create(session)
            spool.appendSegment(
                mapOf(
                    "id" to "segment-1",
                    "session_id" to "session-1",
                    "classification" to "quiet",
                    "duration_seconds" to 30,
                ),
            )
            File(root, "session-1/segments.ndjson").appendText("{\"partial\":")

            val restored = spool.read("session-1")
            assertEquals("running", (restored["session"] as Map<*, *>) ["status"])
            assertEquals(1, (restored["segments"] as List<*>).size)
            assertTrue(spool.listPending().any { it["id"] == "session-1" })
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun finalizationUpdateIsIdempotent() {
        val root = Files.createTempDirectory("sleep-spool-idempotent").toFile()
        try {
            val spool = SleepSessionSpool(root, TestSpoolCodec)
            val session = mutableMapOf<String, Any?>(
                "id" to "session-2",
                "status" to "starting",
                "started_at" to "2026-07-26T22:00:00Z",
            )
            spool.create(session)
            session["status"] = "completed"
            session["end_reason"] = "user"
            spool.updateSession(session)
            spool.updateSession(session)
            assertEquals(
                "completed",
                ((spool.read("session-2")["session"] as Map<*, *>) ["status"]),
            )
        } finally {
            root.deleteRecursively()
        }
    }
}

private object TestSpoolCodec : SleepSpoolCodec {
    override fun encode(value: Map<String, Any?>): String = value.entries.joinToString(";") { entry ->
        val raw = entry.value?.toString() ?: "<null>"
        "${entry.key}=${Base64.getEncoder().encodeToString(raw.toByteArray())}"
    }

    override fun decode(value: String): Map<String, Any?> {
        if (!value.contains('=')) error("partial")
        return value.split(';')
        .filter { it.contains('=') }
        .associate { part ->
            val separator = part.indexOf('=')
            val key = part.substring(0, separator)
            val decoded = String(Base64.getDecoder().decode(part.substring(separator + 1)))
            key to if (decoded == "<null>") null else decoded
        }
    }
}
