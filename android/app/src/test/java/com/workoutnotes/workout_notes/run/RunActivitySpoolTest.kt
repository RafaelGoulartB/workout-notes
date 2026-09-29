package com.workoutnotes.workout_notes.run

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RunActivitySpoolTest {
    private fun withSpool(block: (RunActivitySpool, File, RunSpoolExecutor) -> Unit) {
        val root = Files.createTempDirectory("run-spool-test").toFile()
        val io = RunSpoolExecutor(onError = { throw AssertionError("spool task failed", it) })
        try {
            block(RunActivitySpool(root, io), root, io)
        } finally {
            root.deleteRecursively()
        }
    }

    private fun activity(status: String, distance: Double = 0.0) = mutableMapOf<String, Any?>(
        "id" to "run-1",
        "status" to status,
        "started_at" to "2026-07-26T22:00:00Z",
        "distance_meters" to distance,
    )

    private fun point(seq: Int) = mapOf<String, Any?>(
        "id" to "p$seq",
        "activity_id" to "run-1",
        "seq" to seq,
        "lat" to -23.5 + seq * 0.0001,
        "lng" to -46.6,
    )

    @Test
    fun asyncAppendsKeepOrderAndFlushMakesThemDurable() = withSpool { spool, root, _ ->
        spool.createAsync(activity("recording"))
        repeat(200) { spool.appendPointAsync(point(it)) }
        assertTrue(spool.flush())

        val lines = File(root, "run-1/points.ndjson").readLines().filter { it.isNotBlank() }
        assertEquals(200, lines.size)
        val restored = spool.read("run-1")
        val seqs = (restored["points"] as List<*>).map { ((it as Map<*, *>)["seq"] as Number).toInt() }
        assertEquals((0 until 200).toList(), seqs)
    }

    @Test
    fun lastActivityUpdateWinsAndLeavesNoTempFile() = withSpool { spool, root, _ ->
        spool.createAsync(activity("recording"))
        spool.updateActivityAsync(activity("recording", distance = 100.0))
        spool.updateActivityAsync(activity("paused", distance = 250.0))
        assertTrue(spool.flush())

        val stored = spool.read("run-1")["activity"] as Map<*, *>
        assertEquals("paused", stored["status"])
        assertEquals(250.0, (stored["distance_meters"] as Number).toDouble(), 0.0)
        assertFalse(File(root, "run-1/activity.json.tmp").exists())
    }

    @Test
    fun queuedWriteCapturesStateAtEnqueueTime() = withSpool { spool, _, _ ->
        val live = activity("recording", distance = 10.0)
        spool.createAsync(live)
        spool.updateActivityAsync(live)
        // Mutating the live map afterwards must not leak into the queued write.
        live["distance_meters"] = 9999.0
        live["status"] = "completed"
        assertTrue(spool.flush())

        val stored = spool.read("run-1")["activity"] as Map<*, *>
        assertEquals("recording", stored["status"])
        assertEquals(10.0, (stored["distance_meters"] as Number).toDouble(), 0.0)
    }

    @Test
    fun readsAreOrderedAfterQueuedWrites() = withSpool { spool, _, io ->
        val gate = CountDownLatch(1)
        // Hold the worker so the writes below pile up behind it.
        io.execute { gate.await(5, TimeUnit.SECONDS) }
        spool.createAsync(activity("recording"))
        repeat(5) { spool.appendPointAsync(point(it)) }
        gate.countDown()

        val data = spool.blocking { read("run-1") }
        assertEquals(5, (data["points"] as List<*>).size)
    }

    @Test
    fun flushWaitsForSlowWriter() = withSpool { spool, root, io ->
        spool.createAsync(activity("recording"))
        io.execute { Thread.sleep(150) }
        spool.appendPointAsync(point(1))
        assertTrue(spool.flush())
        assertEquals(1, File(root, "run-1/points.ndjson").readLines().count { it.isNotBlank() })
    }

    @Test
    fun flushTimesOutInsteadOfBlockingForever() = withSpool { spool, _, io ->
        val gate = CountDownLatch(1)
        io.execute { gate.await(5, TimeUnit.SECONDS) }
        assertFalse(spool.flush(timeoutMillis = 50))
        gate.countDown()
        assertTrue(spool.flush())
    }

    @Test
    fun deleteAsyncRemovesSpoolAfterEarlierWrites() = withSpool { spool, root, _ ->
        spool.createAsync(activity("recording"))
        spool.appendPointAsync(point(0))
        spool.deleteAsync("run-1")
        spool.appendPointAsync(point(1)) // recreates the directory like the old sync code did
        assertTrue(spool.flush())
        // The delete ran between the two appends: only the later point survives.
        val points = File(root, "run-1/points.ndjson")
        assertEquals(1, points.readLines().count { it.isNotBlank() })
        assertNotEquals(0L, points.length())
    }

    @Test
    fun partialLastPointLineIsIgnoredOnRecovery() = withSpool { spool, root, _ ->
        spool.createAsync(activity("recording"))
        spool.appendPointAsync(point(0))
        assertTrue(spool.flush())
        File(root, "run-1/points.ndjson").appendText("{\"partial\":")

        val restored = spool.blocking { read("run-1") }
        assertEquals(1, (restored["points"] as List<*>).size)
        assertTrue(spool.blocking { listPending() }.any { it["id"] == "run-1" })
    }
}
