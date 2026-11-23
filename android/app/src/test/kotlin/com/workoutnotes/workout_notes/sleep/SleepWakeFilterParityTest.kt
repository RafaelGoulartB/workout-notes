package com.workoutnotes.workout_notes.sleep

import java.io.File
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The native filter must see the night exactly as the Dart engine does.
 * `test/fixtures/sleep_wake_parity.json` is produced by
 * `test/sleep_wake_parity_test.dart` from the real fixture nights; see there
 * how to regenerate it after an engine change.
 */
class SleepWakeFilterParityTest {
    private val fixtures = File("../../test/fixtures")

    @Test
    fun `native filter and smart policy reproduce the Dart results`() {
        val golden = JSONObject(File(fixtures, "sleep_wake_parity.json").readText())
        val sessionId = golden.getString("session_id")
        val start = Instant.parse(golden.getString("start")).toEpochMilli()
        val runs = golden.getJSONArray("runs")
        for (r in 0 until runs.length()) {
            val run = runs.getJSONObject(r)
            val label = run.getString("fixture")
            // Recorded nights live in their own file; the synthetic run carries its table.
            val table = run.optJSONObject("table")
                ?: JSONObject(File(fixtures, run.getString("fixture")).readText())
            val segments = segments(table, sessionId, start)
            val expectedP = run.getJSONArray("p")
            val expectedReason = run.getJSONArray("reason")
            val expectedValid = run.getJSONArray("valid")
            val expectedInformative = run.getJSONArray("informative")
            val expectedFresh = run.getJSONArray("fresh")
            val expectedMovement = run.getJSONArray("movement")
            val expectedAmbient = run.getJSONArray("ambient")
            assertEquals(label, expectedP.length(), segments.size)

            val filter = SleepWakeFilter(sessionId)
            val decisions = segments.map { filter.add(it) }
            decisions.forEachIndexed { i, decision ->
                assertEquals("$label reason $i", expectedReason.getString(i), decision.reason)
                assertEquals("$label valid $i", expectedValid.getBoolean(i), decision.validSignal)
                assertEquals("$label informative $i", expectedInformative.getBoolean(i), decision.informative)
                assertEquals("$label fresh $i", expectedFresh.getBoolean(i), decision.evidenceFresh)
                assertEquals("$label movement $i", expectedMovement.getDouble(i), decision.movementSeconds, 1e-9)
                assertEquals("$label ambient $i", expectedAmbient.getDouble(i), decision.ambientSeconds, 1e-9)
                assertEquals(
                    "$label p $i",
                    expectedP.getDouble(i),
                    decision.sleepProbability,
                    1e-9,
                )
            }

            val smart = run.getJSONArray("smart")
            for (s in 0 until smart.length()) {
                val case = smart.getJSONObject(s)
                val deadline = start + case.getLong("deadline_offset_seconds") * 1_000L
                val windowStart = deadline - case.getInt("window_minutes") * 60_000L
                val policy = SmartWakePolicy(case.getDouble("threshold"))
                var fired: Int? = null
                var trigger: String? = null
                for (i in segments.indices) {
                    val segment = segments[i]
                    val seconds = (segment["duration_seconds"] as Number).toInt()
                    val end = Instant.parse(segment["started_at"].toString()).toEpochMilli() +
                        seconds * 1_000L
                    val result = policy.onWindow(decisions[i], seconds, end, windowStart, deadline)
                    if (result != null) {
                        fired = i
                        trigger = result
                        break
                    }
                }
                val caseLabel = "$label smart ${case.getDouble("threshold")} at ${case.getLong("deadline_offset_seconds")}"
                assertEquals(caseLabel, case.opt("fired_index").takeUnless { it == JSONObject.NULL }, fired)
                assertEquals(caseLabel, case.opt("trigger").takeUnless { it == JSONObject.NULL }, trigger)
            }
        }
    }

    /** Same maps the Dart loader and the native recorder produce. */
    private fun segments(fixture: JSONObject, sessionId: String, start: Long): List<Map<String, Any?>> {
        val columns = fixture.getJSONArray("columns")
        val rows = fixture.getJSONArray("rows")
        return (0 until rows.length()).map { index ->
            val row: JSONArray = rows.getJSONArray(index)
            val map = mutableMapOf<String, Any?>(
                "id" to "recorded-$index",
                "session_id" to sessionId,
                "started_at" to Instant.ofEpochMilli(start + row.getLong(0) * 1_000L).toString(),
            )
            for (c in 1 until columns.length()) {
                val value = row.get(c)
                map[columns.getString(c)] = if (value == JSONObject.NULL) null else value
            }
            map
        }
    }
}
